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
## Noise while climbing a ladder or shaft: a quiet scuffing, under a footstep.
const CLIMB_INTENSITY: float = 8e-4
const RESCUE_POINT: Vector3 = Vector3(0.0, 0.1, -0.8)
## Wander oscillator rates (rad/s). Two incommensurate sines read as drifting.
const WANDER_RATE_A: float = 1.7
const WANDER_RATE_B: float = 2.9
## Collapse: seconds to fall, and to stand up again after recovery.
const FALL_S: float = 0.8
const STAND_UP_S: float = 2.0
## Eye height (m) on the floor, and how far the view may turn while down.
const DOWN_EYE_HEIGHT: float = 0.3
const DOWN_LOOK_YAW: float = deg_to_rad(50.0)
const DOWN_LOOK_PITCH: float = deg_to_rad(25.0)

## Replicated pose (sub-local). Written by the owning peer.
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_pitch: float = 0.0
## Counts landings after a jump; every peer turns a change into landing noise.
@export var sync_landings: int = 0
## True while the owner climbs a [ClimbTransit]; others hear it as climbing.
@export var sync_climbing: bool = false
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
var _climb: ClimbTransit = null
var _climb_t: float = 0.0
var _climb_up: bool = true
## Where the player stood relative to the path's start; eased out as the climb begins.
var _climb_offset: Vector3 = Vector3.ZERO
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
## 0 standing, 1 flat on the floor. Every peer drives it from the replicated
## incapacitated flag; the camera and the remote avatar's tilt follow it.
var down_blend: float = 0.0
var _was_down: bool = false
var _down_yaw: float = 0.0


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


## Wander added to walk [param input] at time [param t] seconds: sideways and
## along the input, swinging further as strength rises. Zero when the model
## has no movement effect or there is no input. Deterministic and continuous in [param t].
static func impaired_wander(input: Vector2, model: ImpairmentModel, t: float) -> Vector2:
	var swing: float = model.wander_swing()
	if swing <= 0.0 or input == Vector2.ZERO:
		return Vector2.ZERO
	var side: Vector2 = Vector2(-input.y, input.x)
	var osc_side: float = sin(t * WANDER_RATE_A) * 0.6 + sin(t * WANDER_RATE_B + 1.3) * 0.4
	var osc_along: float = sin(t * WANDER_RATE_B + 0.4) * 0.5
	return (side * osc_side + input * osc_along) * swing


## Walk input with the impairment wander added.
static func impaired_input(input: Vector2, model: ImpairmentModel, t: float) -> Vector2:
	return input + impaired_wander(input, model, t)


## Walking [param speed] after the impairment slowdown.
static func impaired_speed(speed: float, model: ImpairmentModel) -> float:
	return speed * (1.0 - model.movement_slowdown())


## Walking [param speed] after the impairment slowdown and the worn suit's
## multiplier. Either model may be null.
static func walk_speed(speed: float, impairment_model: ImpairmentModel, suit_model: DiveSuitModel) -> float:
	var out: float = speed
	if impairment_model != null:
		out = impaired_speed(out, impairment_model)
	if suit_model != null:
		out *= suit_model.speed_multiplier()
	return out


## The dive suit this player wears, or null.
func worn_suit() -> DiveSuit:
	return _worn as DiveSuit


## True while this player is incapacitated (the host-decided, replicated flag).
func is_down() -> bool:
	var impairment: PlayerImpairment = get_node_or_null(^"Impairment") as PlayerImpairment
	return impairment != null and impairment.incapacitated


## Advances the collapse on every peer: lets go of everything on the owner at
## the moment of the drop, and eases [member down_blend] toward the pose.
func _update_collapse(delta: float) -> void:
	var down: bool = is_down()
	if down and not _was_down:
		_down_yaw = rotation.y
		if is_multiplayer_authority():
			collapse()
	_was_down = down
	var rate: float = 1.0 / (FALL_S if down else STAND_UP_S)
	down_blend = move_toward(down_blend, 1.0 if down else 0.0, rate * delta)
	# Tilt the avatar onto its back: only others see it.
	_body_mesh.rotation.x = -down_blend * PI * 0.5
	_body_mesh.position = Vector3(0.0, lerpf(0.875, 0.3, down_blend), lerpf(0.0, 0.5, down_blend))


## Drops whatever the player holds, sits in or wears.
func collapse() -> void:
	_interact_down = false
	_release_held()
	stand_up()
	take_off()
	end_climb()
	bot_move = Vector2.ZERO
	bot_planes = 0.0
	bot_ballast = 0.0
	bot_jump = false


func _ready() -> void:
	InputSetup.ensure_actions()
	_sub_frame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
	_ray.target_position = Vector3(0, 0, -INTERACT_RANGE_M)
	_ray.collision_mask = LAYER_INTERACTABLE
	var local: bool = is_multiplayer_authority()
	_camera.current = local
	if local:
		_bind_fov()
	_body_mesh.visible = not local
	_tint_from_id(name.to_int())
	if local:
		sync_position = position
	else:
		position = sync_position
	_last_position = position
	add_to_group(&"noise_sources")


func _bind_fov() -> void:
	var settings: GameSettings = get_tree().get_first_node_in_group(GameSettings.GROUP) as GameSettings
	if settings != null and not settings.changed.is_connected(_on_setting_changed):
		settings.changed.connect(_on_setting_changed)
	if not get_viewport().size_changed.is_connected(_apply_fov):
		get_viewport().size_changed.connect(_apply_fov)
	_apply_fov()


func _on_setting_changed(key: StringName, _value: Variant) -> void:
	if key == &"fov_horizontal":
		_apply_fov()


## Sets the camera's vertical FOV from the horizontal setting and the viewport's aspect.
func _apply_fov() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return
	var settings: GameSettings = get_tree().get_first_node_in_group(GameSettings.GROUP) as GameSettings
	if settings == null:
		_camera.fov = GameSettings.FALLBACK_VERTICAL_FOV_DEG
		return
	var h: float = float(settings.get_value(&"fov_horizontal"))
	_camera.fov = GameSettings.horizontal_to_vertical(h, size.x / size.y)


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	var menu: PauseMenu = get_tree().get_first_node_in_group(PauseMenu.GROUP) as PauseMenu
	if menu != null and menu.is_open():
		# The menu owns input: Escape steps back, everything else is ignored.
		if event.is_action_pressed(&"release_mouse"):
			menu.back()
		return
	if event.is_action_pressed(&"release_mouse"):
		var busy: bool = _seat != null or _held != null
		_interact_down = false
		_release_held()
		stand_up()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if not busy and menu != null:
			menu.open()
		return
	if is_down():
		# Down: only looking about, within a narrow cone. No interacting.
		var look: InputEventMouseMotion = event as InputEventMouseMotion
		if look != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_look(look.relative)
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
	_update_collapse(delta)
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
	if is_down():
		_simulate_down(delta, gravity)
		return
	if _climb != null:
		_simulate_climb(delta)
		return
	var input: Vector2 = bot_move
	var menu: PauseMenu = get_tree().get_first_node_in_group(PauseMenu.GROUP) as PauseMenu
	var menu_open: bool = menu != null and menu.is_open()
	if input == Vector2.ZERO and not menu_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
		if not menu_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
	var impairment: PlayerImpairment = get_node_or_null(^"Impairment") as PlayerImpairment
	if impairment != null and impairment.model != null:
		impairment.model.strength = impairment.impairment
		input = impaired_input(input, impairment.model, Time.get_ticks_msec() / 1000.0)
	var suit: DiveSuit = worn_suit()
	speed = walk_speed(speed, impairment.model if impairment != null else null, suit.model if suit != null else null)
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
		not menu_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_just_pressed(&"jump")
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


## Climbing: the pose follows the transit's path; the view stays free.
func _simulate_climb(delta: float) -> void:
	_climb_t = minf(_climb_t + delta / _climb.duration, 1.0)
	var pos: Vector3 = _climb.point_at(_climb_t, _climb_up) + _climb_offset * (1.0 - smoothstep(0.0, 0.25, _climb_t))
	if not _climb.bounds_allow(pos):
		push_warning("Player %s left the interior climbing; moving back inside" % name)
		end_climb()
		position = RESCUE_POINT
		velocity = Vector3.ZERO
		return
	position = pos
	velocity = Vector3.ZERO
	if _climb_t >= 1.0:
		end_climb()


## E on a transit: starts climbing if the way is open and nobody else is on it.
## Returns whether the climb began.
func start_climb(transit: ClimbTransit) -> bool:
	if _climb != null or _seat != null or is_down():
		return false
	var up: bool = transit.going_up_from(position)
	if not transit.try_enter(name.to_int(), position):
		return false
	_release_held()
	take_off()
	_climb = transit
	_climb_t = 0.0
	_climb_up = up
	_climb_offset = position - transit.point_at(0.0, up)
	sync_climbing = true
	velocity = Vector3.ZERO
	_climb.begin_interaction()
	_climb.holder_changed.connect(_on_climb_holder_changed)
	return true


## Leaves the transit (arrived or broken off).
func end_climb() -> void:
	if _climb == null:
		return
	var transit: ClimbTransit = _climb
	_climb = null
	sync_climbing = false
	transit.holder_changed.disconnect(_on_climb_holder_changed)
	transit.end_interaction()
	transit.leave(name.to_int())


func is_climbing() -> bool:
	return _climb != null


func _on_climb_holder_changed(peer_id: int) -> void:
	if peer_id != Net.local_id() and peer_id != InteractableState.NO_HOLDER:
		end_climb()


## Incapacitated: input is ignored; the body just settles under gravity.
func _simulate_down(delta: float, gravity: Vector3) -> void:
	velocity.x = move_toward(velocity.x, 0.0, ACCEL * delta)
	velocity.z = move_toward(velocity.z, 0.0, ACCEL * delta)
	if is_on_floor():
		velocity.y = minf(velocity.y, 0.0) + gravity.y * delta
	else:
		velocity += gravity * delta
	move_and_slide()
	if not INTERIOR_BOUNDS.has_point(position):
		position = RESCUE_POINT
		velocity = Vector3.ZERO


## Moves this player (on its owner) to a sub-local point, letting go of
## everything first.
func teleport(spot: Vector3) -> void:
	_release_held()
	stand_up()
	take_off()
	end_climb()
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
	if _seat == null and (down_blend > 0.0 or _head.position.y != STANDING_EYE_HEIGHT):
		_head.position.y = lerpf(STANDING_EYE_HEIGHT, DOWN_EYE_HEIGHT, smoothstep(0.0, 1.0, down_blend))
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
	if not is_multiplayer_authority() and not sync_climbing:
		_stride += instant * delta
		if _stride >= STRIDE_M:
			_stride = 0.0
			footstep.emit(clampf(_speed / WALK_SPEED, 0.0, 1.0))


## Movement noise (linear intensity). The host polls this for every player,
## using replicated movement, so a client can't fake being quiet.
func noise_intensity() -> float:
	if _seat != null:
		return 0.0
	if sync_climbing:
		return CLIMB_INTENSITY
	var landing: float = LANDING_INTENSITY * _landing_left / LANDING_NOISE_S
	if _speed < 0.2:
		return landing
	return FOOTSTEP_INTENSITY * pow(_speed / WALK_SPEED, 3.0) + landing


func _look(relative: Vector2) -> void:
	var yaw: float = rotation.y - relative.x * MOUSE_SENSITIVITY
	var pitch: float = _head.rotation.x - relative.y * MOUSE_SENSITIVITY
	if is_down():
		yaw = _down_yaw + clampf(angle_difference(_down_yaw, yaw), -DOWN_LOOK_YAW, DOWN_LOOK_YAW)
		pitch = clampf(pitch, -DOWN_LOOK_PITCH, DOWN_LOOK_PITCH)
	rotation.y = yaw
	_head.rotation.x = clampf(pitch, deg_to_rad(-85.0), deg_to_rad(85.0))


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
	if _climb != null:
		return  # Movement is locked until the climb ends.
	if _seat != null:
		stand_up()
		return
	var node: Interactable = aim_target()
	if node is ClimbTransit:
		start_climb(node as ClimbTransit)
	elif node is StationSeat:
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
	if _climb != null:
		return
	_interact_down = true
	if _seat == null or _seat.allow_grab(node):
		_try_grab(node)


## The interact button came up: a click action on the held control (a switch
## flipping) runs while the player still holds it, then the control is let go.
func release_interact() -> void:
	_interact_down = false
	if _held != null:
		_held.click_action()
	_release_held()


func _try_grab(node: Interactable) -> void:
	if node == null or node is StationSeat or node is Wearable or node is ClimbTransit:
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
