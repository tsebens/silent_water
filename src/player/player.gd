class_name Player
extends CharacterBody3D
## First-person crew member. Lives in the still interior, so every position
## here is sub-local. The owning peer simulates its own movement (responsive
## walking); everything that affects the game world is still decided by the
## host. Remote copies interpolate toward the replicated pose.
##
## Gravity comes from [method SubFrame.gravity_in_sub]: when the sub pitches or
## rolls, walking uphill is slower and downhill faster; past
## [constant SLIDE_ANGLE_DEG] the crew loses grip and slides.

signal footstep(loudness: float)

const WALK_SPEED: float = 2.6
const SNEAK_SPEED: float = 1.1
const ACCEL: float = 12.0
const MOUSE_SENSITIVITY: float = 0.0025
const STRIDE_M: float = 0.7
const INTERACT_RANGE_M: float = 2.0
const REMOTE_SMOOTHING: float = 15.0
## Footstep noise at walking speed (~75 dB); scales with speed cubed, so
## sneaking (~1.1 m/s) is ~11 dB quieter.
const FOOTSTEP_INTENSITY: float = 3e-3
## Faster than anyone can walk: movement this quick is a teleport.
const TELEPORT_SPEED: float = 8.0
const STANDING_EYE_HEIGHT: float = 1.6
const LAYER_INTERACTABLE: int = 1 << 1
## Deck tilt past which boots lose grip and the crew slides.
const SLIDE_ANGLE_DEG: float = 30.0
## How strongly tilt slows walking uphill and speeds walking downhill.
const SLOPE_SPEED_EFFECT: float = 1.5
## Interior bounds (sub-local). A player outside them is put back inside;
## this guards against physics glitches pushing someone through the hull.
const INTERIOR_BOUNDS: AABB = AABB(Vector3(-2.0, -0.8, -5.0), Vector3(4.0, 3.8, 10.0))
## Landing noise: louder than a walking step (a thud, not a footfall), fading
## over [constant LANDING_NOISE_S].
const LANDING_INTENSITY: float = 1.2e-2
const LANDING_NOISE_S: float = 0.25
const RESCUE_POINT: Vector3 = Vector3(0.0, 0.1, -0.8)

## Replicated pose (sub-local). Written by the owning peer.
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_pitch: float = 0.0
## Counts landings after a jump; every peer turns a change into landing noise.
@export var sync_landings: int = 0
## Jump height in metres, sub-local. Low enough to clear a step or seat edge
## and nothing out of bounds.
@export var jump_height: float = 0.3

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var _body_mesh: MeshInstance3D = $Body

## Scripted input for automated tests; overrides the keyboard when set.
var bot_move: Vector2 = Vector2.ZERO
var bot_planes: float = 0.0
var bot_ballast: float = 0.0
## Scripted jump press; consumed by the next physics step.
var bot_jump: bool = false

var _sub_frame: SubFrame
var _held: Interactable = null
## True while the interact button is down: the view holds still.
var _interact_down: bool = false
var _seat: StationSeat = null
var _worn: Wearable = null
var _stride: float = 0.0
## Smoothed movement speed, measured the same way on every peer.
var _speed: float = 0.0
## Camera shake amplitude (radians), set by threat cues.
var _shake: float = 0.0
var _last_position: Vector3 = Vector3.ZERO
var _airborne: bool = false
var _seen_landings: int = 0
## Seconds of landing noise left.
var _landing_left: float = 0.0


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	InputSetup.ensure_actions()
	_sub_frame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
	_ray.target_position = Vector3(0, 0, -INTERACT_RANGE_M)
	_ray.collision_mask = LAYER_INTERACTABLE
	var local: bool = is_multiplayer_authority()
	_camera.current = local
	_body_mesh.visible = not local
	_tint_from_id(name.to_int())
	if local:
		sync_position = position
	else:
		position = sync_position
	_last_position = position
	add_to_group(&"noise_sources")


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed(&"release_mouse"):
		_interact_down = false
		_release_held()
		stand_up()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if _seat != null and _seat.has_table_view():
		# The table handles its own mouse and keys; only E leaves it.
		if event.is_action_pressed(&"activate"):
			_activate()
			get_viewport().set_input_as_handled()
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed(&"activate"):
		_activate()
		return
	if event.is_action_pressed(&"interact"):
		press_interact(aim_target())
	elif event.is_action_released(&"interact"):
		release_interact()
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if _held != null:
			_held.drag(motion.relative)
		elif not _interact_down:
			_look(motion.relative)


func _physics_process(delta: float) -> void:
	if is_multiplayer_authority():
		_simulate(delta)
		sync_position = position
		sync_yaw = rotation.y
		sync_pitch = _head.rotation.x
	else:
		var w: float = 1.0 - exp(-REMOTE_SMOOTHING * delta)
		position = position.lerp(sync_position, w)
		rotation.y = lerp_angle(rotation.y, sync_yaw, w)
		_head.rotation.x = lerp_angle(_head.rotation.x, sync_pitch, w)
	_track_speed(delta)
	_landing_left = maxf(_landing_left - delta, 0.0)
	if sync_landings != _seen_landings:
		_seen_landings = sync_landings
		_landing_left = LANDING_NOISE_S
		footstep.emit(1.0)


func _simulate(delta: float) -> void:
	var gravity: Vector3 = Vector3.DOWN * SubFrame.GRAVITY
	if _sub_frame != null:
		gravity = _sub_frame.gravity_in_sub()
	var input: Vector2 = bot_move
	if input == Vector2.ZERO and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if _seat != null and not (_seat is PilotSeat):
		position = _seat.seat_transform().origin
		velocity = Vector3.ZERO
		return
	if _seat != null:
		# Seated: the helm. W/S throttle, A/D rudder, R/F planes, and in
		# single-player mode Numpad 8/2 blow and flood.
		var planes: float = 0.0
		var ballast: float = 0.0
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			planes = Input.get_axis(&"pilot_planes_rise", &"pilot_planes_dive")
			ballast = Input.get_axis(&"pilot_flood", &"pilot_blow")
		planes += bot_planes
		ballast += bot_ballast
		(_seat as PilotSeat).drive(-input.y, input.x, clampf(planes, -1.0, 1.0), clampf(ballast, -1.0, 1.0), delta)
		position = _seat.seat_transform().origin
		velocity = Vector3.ZERO
		return
	var sneaking: bool = Input.is_action_pressed(&"sneak")
	var speed: float = SNEAK_SPEED if sneaking else WALK_SPEED
	# Part of gravity along the deck. The deck is flat in the sub frame, so the
	# physics engine never sees a slope; tilt is handled here instead.
	var along_deck: Vector3 = Vector3(gravity.x, 0.0, gravity.z)
	var tilt: float = asin(clampf(along_deck.length() / gravity.length(), 0.0, 1.0))
	var wish_dir: Vector3 = transform.basis * Vector3(input.x, 0.0, input.y)
	if wish_dir.length_squared() > 0.0 and along_deck.length_squared() > 0.0:
		var downhill: float = wish_dir.normalized().dot(along_deck.normalized())
		speed *= clampf(1.0 + downhill * sin(tilt) * SLOPE_SPEED_EFFECT, 0.35, 1.4)
	var wish: Vector3 = wish_dir * speed
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.lerp(wish, 1.0 - exp(-ACCEL * delta))
	velocity = Vector3(horizontal.x, velocity.y, horizontal.z)
	var jump_pressed: bool = bot_jump or (
		Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed(&"jump")
	)
	bot_jump = false
	if is_on_floor():
		if tilt > deg_to_rad(SLIDE_ANGLE_DEG):
			velocity += along_deck * delta
		velocity.y = minf(velocity.y, 0.0) + gravity.y * delta
		if jump_pressed:
			velocity.y = sqrt(2.0 * gravity.length() * jump_height)
			_airborne = true
	else:
		velocity += gravity * delta
	var before: Vector3 = position
	move_and_slide()
	if _worn != null and position.distance_to(_worn.global_position) > _worn.cord_length:
		take_off()
	if not INTERIOR_BOUNDS.has_point(position):
		push_warning("Player %s left the interior at %s; moving back inside" % [name, position])
		position = RESCUE_POINT
		velocity = Vector3.ZERO
	if _airborne and is_on_floor() and velocity.y <= 0.0:
		_airborne = false
		sync_landings += 1
	if is_on_floor():
		_stride += (position - before).length()
		if _stride >= STRIDE_M:
			_stride = 0.0
			footstep.emit(clampf(_speed / WALK_SPEED, 0.0, 1.0))


## Moves this player (on its owner) to a sub-local point, letting go of
## everything first.
func teleport(spot: Vector3) -> void:
	_release_held()
	stand_up()
	take_off()
	position = spot
	velocity = Vector3.ZERO
	sync_position = spot
	_last_position = spot
	_speed = 0.0


@rpc("any_peer", "call_local", "reliable")
func rpc_teleport(spot: Vector3) -> void:
	if multiplayer.get_remote_sender_id() not in [0, 1]:
		return
	if is_multiplayer_authority():
		teleport(spot)


func set_shake(amount: float) -> void:
	_shake = amount


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		return
	if _seat != null and _seat.has_table_view():
		# Lean over the table: ease the camera to the table's view.
		var want: Transform3D = _seat.table_view()
		_camera.global_transform = _camera.global_transform.interpolate_with(want, 1.0 - exp(-8.0 * delta))
		return
	if _camera.position != Vector3.ZERO:
		_camera.transform = Transform3D.IDENTITY
	if _shake > 0.0001:
		_camera.rotation = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1) * 0.5) * _shake
	elif _camera.rotation != Vector3.ZERO:
		_camera.rotation = Vector3.ZERO


func _track_speed(delta: float) -> void:
	if delta <= 0.0:
		return
	var moved: Vector3 = position - _last_position
	_last_position = position
	var instant: float = Vector2(moved.x, moved.z).length() / delta
	if instant > TELEPORT_SPEED:
		# A teleport (respawn, debug placement), not a footstep.
		_speed = 0.0
		return
	_speed = lerpf(_speed, instant, 1.0 - exp(-8.0 * delta))
	# Remote players get footstep events from their replicated movement, so
	# everyone hears everyone's steps.
	if not is_multiplayer_authority():
		_stride += instant * delta
		if _stride >= STRIDE_M:
			_stride = 0.0
			footstep.emit(clampf(_speed / WALK_SPEED, 0.0, 1.0))


## Movement noise (linear intensity). The host polls this for every player,
## using replicated movement, so a client can't fake being quiet.
func noise_intensity() -> float:
	if _seat != null:
		return 0.0
	var landing: float = LANDING_INTENSITY * _landing_left / LANDING_NOISE_S
	if _speed < 0.2:
		return landing
	return FOOTSTEP_INTENSITY * pow(_speed / WALK_SPEED, 3.0) + landing


func _look(relative: Vector2) -> void:
	rotation.y -= relative.x * MOUSE_SENSITIVITY
	_head.rotation.x = clampf(
		_head.rotation.x - relative.y * MOUSE_SENSITIVITY, deg_to_rad(-85.0), deg_to_rad(85.0)
	)


## The control under the aiming point, or null.
func aim_target() -> Interactable:
	_ray.force_raycast_update()
	if not _ray.is_colliding():
		return null
	var node: Node = _ray.get_collider() as Node
	while node != null and not (node is Interactable):
		node = node.get_parent()
	return node as Interactable


## The control this player is working right now (held, worn or sat in).
func held_control() -> Interactable:
	return _held


func seat() -> StationSeat:
	return _seat


func worn() -> Wearable:
	return _worn


## E: take or leave a station (pilot seat, sonar headset).
func _activate() -> void:
	if _seat != null:
		stand_up()
		return
	var node: Interactable = aim_target()
	if node is StationSeat:
		_release_held()
		sit_in(node as StationSeat)
	elif node is Wearable:
		if _worn == node:
			take_off()
		else:
			put_on(node as Wearable)
	elif _worn != null:
		take_off()


## The interact button went down on [param node] (what the player aims at).
## Grabs it unless a seat forbids grabbing.
func press_interact(node: Interactable) -> void:
	_interact_down = true
	if _seat == null or _seat.allows_grabbing:
		_try_grab(node)


## The interact button came up: a click action on the held control (a switch
## flipping) runs while the player still holds it, then the control is let go.
func release_interact() -> void:
	_interact_down = false
	if _held != null:
		_held.click_action()
	_release_held()


func _try_grab(node: Interactable) -> void:
	if node == null or node is StationSeat or node is Wearable:
		return  # Stations are taken with E, not grabbed.
	_held = node
	_held.begin_interaction()


## Sits in the pilot's chair. Stands up again if someone else got there first.
func sit_in(seat: StationSeat) -> void:
	if _seat != null:
		return
	_seat = seat
	_seat.holder_changed.connect(_on_seat_holder_changed)
	_seat.begin_interaction()
	_head.position.y = seat.eye_height
	# Face the station.
	rotation.y = seat.seat_transform().basis.get_euler().y
	_head.rotation.x = 0.0
	if seat is SonarSeat and (seat as SonarSeat).headset != null:
		put_on((seat as SonarSeat).headset)


func stand_up() -> void:
	if _seat == null:
		return
	var seat: StationSeat = _seat
	_seat = null
	seat.holder_changed.disconnect(_on_seat_holder_changed)
	seat.end_interaction()
	_head.position.y = STANDING_EYE_HEIGHT
	if seat is SonarSeat:
		take_off()
	# Step out of the seat, backward from the way it faces, onto the deck.
	var out: Vector3 = seat.seat_transform().origin + seat.seat_transform().basis.z * 0.7
	position = Vector3(out.x, maxf(out.y, 0.0) + 0.05, out.z)


## Puts on a wearable (the sonar headset). Takes off any other first.
func put_on(item: Wearable) -> void:
	take_off()
	_worn = item
	_worn.holder_changed.connect(_on_worn_holder_changed)
	_worn.begin_interaction()


func take_off() -> void:
	if _worn == null:
		return
	var item: Wearable = _worn
	_worn = null
	item.holder_changed.disconnect(_on_worn_holder_changed)
	item.end_interaction()


func _on_worn_holder_changed(peer_id: int) -> void:
	if peer_id != Net.local_id() and peer_id != InteractableState.NO_HOLDER:
		take_off()


func is_seated() -> bool:
	return _seat != null


func _on_seat_holder_changed(peer_id: int) -> void:
	if peer_id != Net.local_id() and peer_id != InteractableState.NO_HOLDER:
		stand_up()


func _release_held() -> void:
	if _held != null:
		_held.end_interaction()
		_held = null


func _tint_from_id(peer_id: int) -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(float(peer_id % 997) * 0.618, 1.0), 0.5, 0.8)  # palette-ok: generated per-peer hue, not a design colour
	_body_mesh.material_override = mat
