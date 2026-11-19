class_name ApexMonster
extends Node3D
## The apex: huge, blind, hunts by sound. Lives under the world root, so its
## transform is in world space. The host runs the brain and steering;
## clients receive pose and state through a MultiplayerSynchronizer.
##
## Behaviour by state (see [SuspicionModel]):
##   UNAWARE   slow wandering
##   PATROL    faster wandering, biased toward where it last heard something
##   CURIOUS   drifts toward the noise, stops short
##   HUNTING   circles the last-heard area
##   COMMITTED charges the last-heard position; the last chance to break contact
## Contact happens only if its jaws actually reach the sub.

signal state_changed(new_state: int)
## Host only: the monster reached the sub.
signal contact
## Host only: passed close at speed without contact.
signal near_miss(distance: float)

const LENGTH_M: float = 30.0
const CONTACT_RADIUS: float = 9.0
const NEAR_MISS_RADIUS: float = 28.0
const NEAR_MISS_MIN_SPEED: float = 6.0
const LAYER_EXTERIOR: int = 1 << 3
const AVOID_RANGE: float = 45.0

## Calls, by kind. Levels are at 1 m.
enum Call { MOAN, GRUNT, PULSE, ROAR }
const CALL_DB: Dictionary = {Call.MOAN: 135.0, Call.GRUNT: 128.0, Call.PULSE: 130.0, Call.ROAR: 140.0}
## Seconds between calls by state: [min, max]. Empty = no routine calls.
const CALL_INTERVALS: Dictionary = {
	SuspicionModel.State.UNAWARE: Vector2(40.0, 80.0),
	SuspicionModel.State.PATROL: Vector2(25.0, 45.0),
	SuspicionModel.State.CURIOUS: Vector2(9.0, 15.0),
	SuspicionModel.State.HUNTING: Vector2(5.0, 8.0),
	SuspicionModel.State.COMMITTED: Vector2(2.0, 2.5),
}
## Swimming noise at 1 m: this at 2 m/s, +20 dB per tenfold speed.
const SWIM_DB_AT_2MS: float = 100.0

@export var tuning: SuspicionTuning
## Where the monster lives; it never leaves this box (world space).
@export var territory: AABB = AABB(Vector3(-300, -120, -300), Vector3(600, 100, 600))
@export var spawn_position: Vector3 = Vector3(150, -60, -200)
@export_group("Speeds (m/s)")
@export var speed_unaware: float = 2.0
@export var speed_patrol: float = 4.5
@export var speed_curious: float = 3.0
@export var speed_hunting: float = 5.5
@export var speed_committed: float = 13.0
@export var turn_rate_deg: float = 25.0
@export var accel: float = 1.5

## Developer switch: when false the apex is gone from the dive (no body, no
## sound, no hearing, no contact). Replicated; only the host changes it.
var active: bool = true

# Replicated (written by the host).
var sync_state: int = SuspicionModel.State.UNAWARE
var speed: float = 0.0
var sync_position: Vector3 = Vector3.ZERO
var sync_rotation: Quaternion = Quaternion.IDENTITY
# Brain readouts for the developer overlay.
var sync_suspicion: float = 0.0
var sync_snr: float = -100.0
var sync_alertness: float = 0.0

var brain: SuspicionModel
## Host can disable the brain (tests drive it directly).
var brain_enabled: bool = true

var _sub_frame: SubFrame
var _target: Vector3 = Vector3.ZERO
var _retarget_timer: float = 0.0
var _search_angle: float = 0.0
var _near_miss_cooldown: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _call_timer: float = 20.0


func _ready() -> void:
	if tuning == null:
		tuning = SuspicionTuning.new()
	brain = SuspicionModel.new(tuning)
	_rng.randomize()
	add_to_group(&"apex")
	add_to_group(&"outside_sources")
	_build_body()
	reset_to_spawn()


func reset_to_spawn() -> void:
	position = spawn_position
	basis = Basis.looking_at(Vector3(-1, 0, 1).normalized())
	sync_position = position
	sync_rotation = basis.get_rotation_quaternion()
	sync_suspicion = brain.suspicion
	sync_snr = maxf(brain.last_snr_db, -100.0)
	sync_alertness = brain.alertness
	speed = 0.0
	brain.reset()
	sync_state = brain.state
	_target = spawn_position
	_retarget_timer = 0.0


## Forward direction (world space). The head points along -Z.
func forward() -> Vector3:
	return -basis.z


func head_position() -> Vector3:
	return position + forward() * LENGTH_M * 0.5


func state() -> int:
	return sync_state


## Host: turns the apex on or off for everyone. Turning it off also calms it
## and sends it home, so turning it back on starts it fresh.
func set_active(on: bool) -> void:
	if not multiplayer.is_server() or on == active:
		return
	active = on
	reset_to_spawn()
	print("[apex] %s by developer" % ("enabled" if on else "disabled"))


## Any peer: ask the host to switch the apex. Used by the developer overlay.
func request_active(on: bool) -> void:
	if multiplayer.is_server():
		set_active(on)
	else:
		_rpc_request_active.rpc_id(1, on)


@rpc("any_peer", "reliable")
func _rpc_request_active(on: bool) -> void:
	if multiplayer.is_server() and DevOverlay.allowed():
		set_active(on)


func _process(delta: float) -> void:
	visible = active
	if multiplayer.is_server():
		return
	# Clients smooth toward the replicated pose.
	var w: float = 1.0 - exp(-6.0 * delta)
	position = position.lerp(sync_position, w)
	basis = Basis(basis.get_rotation_quaternion().slerp(sync_rotation, w))


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if _sub_frame == null:
		_sub_frame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
		if _sub_frame == null:
			return
	if not active:
		speed = 0.0
		return
	var sub_pos: Vector3 = _sub_frame.sub_transform.origin
	if brain_enabled:
		var heard: float = Acoustics.heard_at(position, _sub_frame)
		var background: float = Acoustics.ambient_at(position)
		brain.update(delta, brain.snr_db(heard, background), sub_pos, position)
	if brain.state != sync_state:
		var previous: int = sync_state
		sync_state = brain.state
		state_changed.emit(sync_state)
		_on_state_entered(previous)
	_update_calls(delta)
	if sync_state == SuspicionModel.State.CONTACT:
		speed = 0.0
		return
	_choose_target(delta, sub_pos)
	_steer(delta)
	_check_sub(delta, sub_pos)
	sync_position = position
	sync_rotation = basis.get_rotation_quaternion()
	sync_suspicion = brain.suspicion
	sync_snr = maxf(brain.last_snr_db, -100.0)
	sync_alertness = brain.alertness


# --- Sound -------------------------------------------------------------------

## Outside-audio hook: swimming noise, louder the faster it goes.
func outside_db() -> float:
	if not active:
		return -INF
	return SWIM_DB_AT_2MS + 20.0 * log(maxf(speed, 0.3) / 2.0) / log(10.0)


func outside_stream() -> AudioStream:
	return ProceduralSounds.swim()


func _on_state_entered(previous: int) -> void:
	if sync_state == SuspicionModel.State.COMMITTED:
		_rpc_call.rpc(Call.ROAR)
		_call_timer = 3.0
	elif sync_state > previous:
		# Escalating: call soon so the crew can hear the change.
		_call_timer = minf(_call_timer, 1.5)


func _update_calls(delta: float) -> void:
	_call_timer -= delta
	if _call_timer > 0.0 or not CALL_INTERVALS.has(sync_state):
		return
	var range_s: Vector2 = CALL_INTERVALS[sync_state]
	_call_timer = _rng.randf_range(range_s.x, range_s.y)
	var kind: int = Call.MOAN
	match sync_state:
		SuspicionModel.State.CURIOUS:
			kind = Call.GRUNT
		SuspicionModel.State.HUNTING, SuspicionModel.State.COMMITTED:
			kind = Call.PULSE
	_rpc_call.rpc(kind)


@rpc("authority", "call_local", "reliable")
func _rpc_call(kind: int) -> void:
	if not active:
		return
	var outside: OutsideAudio = get_tree().get_first_node_in_group(&"outside_audio") as OutsideAudio
	if outside == null:
		return
	var stream: AudioStream = ProceduralSounds.moan()
	match kind:
		Call.GRUNT:
			stream = ProceduralSounds.grunt()
		Call.PULSE:
			stream = ProceduralSounds.pulse()
		Call.ROAR:
			stream = ProceduralSounds.roar()
	outside.play_at(stream, self, float(CALL_DB[kind]))


func _choose_target(delta: float, sub_pos: Vector3) -> void:
	_retarget_timer -= delta
	match sync_state:
		SuspicionModel.State.UNAWARE:
			if _retarget_timer <= 0.0 or position.distance_to(_target) < 15.0:
				_target = _random_point_in_territory()
				_retarget_timer = _rng.randf_range(30.0, 60.0)
		SuspicionModel.State.PATROL:
			if _retarget_timer <= 0.0 or position.distance_to(_target) < 15.0:
				var centre: Vector3 = brain.last_heard if brain.has_heard else position
				_target = _clamp_to_territory(centre + _random_flat(120.0))
				_retarget_timer = _rng.randf_range(12.0, 25.0)
		SuspicionModel.State.CURIOUS:
			if brain.has_heard:
				var to_noise: Vector3 = brain.last_heard - position
				# Drift toward the noise, but stop short of it.
				_target = brain.last_heard - to_noise.normalized() * minf(30.0, to_noise.length())
		SuspicionModel.State.HUNTING:
			_search_angle += delta * 0.25
			var r: float = 40.0
			_target = _clamp_to_territory(brain.last_heard + Vector3(cos(_search_angle) * r, 0.0, sin(_search_angle) * r))
		SuspicionModel.State.COMMITTED:
			# Charge through the last-heard point, not at the sub's true position.
			_target = brain.last_heard + forward() * 10.0
	_target.y = clampf(_target.y, territory.position.y + 8.0, territory.end.y - 8.0)


func _steer(delta: float) -> void:
	var want_speed: float = _speed_for_state()
	speed = move_toward(speed, want_speed, accel * delta * (3.0 if sync_state == SuspicionModel.State.COMMITTED else 1.0))
	var desired: Vector3 = (_target - position)
	if desired.length_squared() < 1.0:
		desired = forward()
	desired = desired.normalized()
	desired = _avoid_terrain(desired)
	var current: Quaternion = basis.get_rotation_quaternion()
	var wanted: Quaternion = Basis.looking_at(desired, Vector3.UP).get_rotation_quaternion()
	var angle: float = current.angle_to(wanted)
	var max_step: float = deg_to_rad(turn_rate_deg) * delta
	var t: float = 1.0 if angle <= max_step else max_step / angle
	basis = Basis(current.slerp(wanted, t)).orthonormalized()
	position += forward() * speed * delta
	position = _clamp_to_territory(position)


## Raycasts ahead in render space and bends away from terrain.
func _avoid_terrain(desired: Vector3) -> Vector3:
	if _sub_frame == null:
		return desired
	var space: PhysicsDirectSpaceState3D = get_viewport().world_3d.direct_space_state
	if space == null:
		return desired
	var to_render: Transform3D = _sub_frame.sub_transform.affine_inverse()
	var from: Vector3 = to_render * position
	var to: Vector3 = to_render * (position + desired * AVOID_RANGE)
	var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, LAYER_EXTERIOR))
	if hit.is_empty():
		return desired
	var normal_world: Vector3 = _sub_frame.sub_transform.basis * (hit["normal"] as Vector3)
	return (desired + normal_world * 1.5 + Vector3.UP * 0.5).normalized()


func _check_sub(delta: float, sub_pos: Vector3) -> void:
	var head_dist: float = head_position().distance_to(sub_pos)
	if head_dist <= CONTACT_RADIUS:
		brain.make_contact()
		sync_state = brain.state
		state_changed.emit(sync_state)
		contact.emit()
		return
	_near_miss_cooldown = maxf(_near_miss_cooldown - delta, 0.0)
	var body_dist: float = _distance_to_body(sub_pos)
	if body_dist < NEAR_MISS_RADIUS and speed > NEAR_MISS_MIN_SPEED and _near_miss_cooldown <= 0.0:
		_near_miss_cooldown = 6.0
		near_miss.emit(body_dist)


func _distance_to_body(p: Vector3) -> float:
	var half: Vector3 = forward() * LENGTH_M * 0.5
	var a: Vector3 = position - half
	var b: Vector3 = position + half
	var ab: Vector3 = b - a
	var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _speed_for_state() -> float:
	match sync_state:
		SuspicionModel.State.PATROL:
			return speed_patrol
		SuspicionModel.State.CURIOUS:
			return speed_curious
		SuspicionModel.State.HUNTING:
			return speed_hunting
		SuspicionModel.State.COMMITTED:
			return speed_committed
	return speed_unaware


func _random_point_in_territory() -> Vector3:
	return territory.position + Vector3(_rng.randf(), _rng.randf(), _rng.randf()) * territory.size


func _random_flat(radius: float) -> Vector3:
	var a: float = _rng.randf() * TAU
	var r: float = sqrt(_rng.randf()) * radius
	return Vector3(cos(a) * r, _rng.randf_range(-10.0, 10.0), sin(a) * r)


func _clamp_to_territory(p: Vector3) -> Vector3:
	return p.clamp(territory.position, territory.end)


## Low-poly coelacanth-like silhouette from primitives: shape over texture.
func _build_body() -> void:
	var skin: StandardMaterial3D = StandardMaterial3D.new()
	skin.albedo_color = Color(0.16, 0.17, 0.16)
	skin.roughness = 0.8
	var fin_mat: StandardMaterial3D = StandardMaterial3D.new()
	fin_mat.albedo_color = Color(0.12, 0.13, 0.13)
	fin_mat.roughness = 0.9
	fin_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var body: MeshInstance3D = MeshInstance3D.new()
	var capsule: CapsuleMesh = CapsuleMesh.new()
	capsule.radius = 3.6
	capsule.height = LENGTH_M * 0.8
	capsule.radial_segments = 10
	capsule.rings = 4
	capsule.material = skin
	body.mesh = capsule
	body.rotation.x = PI / 2.0
	body.scale = Vector3(1.0, 1.0, 1.25)  # Deeper than wide.
	add_child(body)

	var head: MeshInstance3D = MeshInstance3D.new()
	var head_mesh: SphereMesh = SphereMesh.new()
	head_mesh.radius = 3.4
	head_mesh.height = 6.0
	head_mesh.radial_segments = 10
	head_mesh.rings = 5
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position = Vector3(0, 0.4, -LENGTH_M * 0.38)
	head.scale = Vector3(1.0, 0.9, 1.4)
	add_child(head)

	var fins: Array[Array] = [
		# [position, size, rotation]
		[Vector3(0, 0, LENGTH_M * 0.5), Vector3(0.4, 9.0, 5.0), Vector3.ZERO],      # tail
		[Vector3(0, 4.5, 2.0), Vector3(0.3, 4.0, 5.0), Vector3(-0.3, 0, 0)],         # dorsal
		[Vector3(0, -4.2, 4.0), Vector3(0.3, 3.5, 4.0), Vector3(0.3, 0, 0)],         # anal
		[Vector3(3.6, -1.5, -5.0), Vector3(5.0, 0.3, 2.5), Vector3(0, 0, -0.5)],     # pectoral R
		[Vector3(-3.6, -1.5, -5.0), Vector3(5.0, 0.3, 2.5), Vector3(0, 0, 0.5)],     # pectoral L
		[Vector3(2.5, -3.0, 4.0), Vector3(3.5, 0.3, 2.0), Vector3(0, 0, -0.8)],      # pelvic R
		[Vector3(-2.5, -3.0, 4.0), Vector3(3.5, 0.3, 2.0), Vector3(0, 0, 0.8)],      # pelvic L
	]
	for f: Array in fins:
		var fin: MeshInstance3D = MeshInstance3D.new()
		var box: PrismMesh = PrismMesh.new()
		box.size = f[1] as Vector3
		box.material = fin_mat
		fin.mesh = box
		fin.position = f[0] as Vector3
		fin.rotation = f[2] as Vector3
		add_child(fin)
