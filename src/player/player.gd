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
const LAYER_INTERACTABLE: int = 1 << 1
## Deck tilt past which boots lose grip and the crew slides.
const SLIDE_ANGLE_DEG: float = 30.0
## How strongly tilt slows walking uphill and speeds walking downhill.
const SLOPE_SPEED_EFFECT: float = 1.5
## Interior bounds (sub-local). A player outside them is put back inside;
## this guards against physics glitches pushing someone through the hull.
const INTERIOR_BOUNDS: AABB = AABB(Vector3(-1.5, -0.5, -6.0), Vector3(3.0, 3.0, 12.0))
const RESCUE_POINT: Vector3 = Vector3(0, 0.1, 0)

## Replicated pose (sub-local). Written by the owning peer.
@export var sync_position: Vector3 = Vector3.ZERO
@export var sync_yaw: float = 0.0
@export var sync_pitch: float = 0.0

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var _body_mesh: MeshInstance3D = $Body

## Scripted movement input for automated tests; overrides the keyboard when set.
var bot_move: Vector2 = Vector2.ZERO

var _sub_frame: SubFrame
var _held: Interactable = null
var _seat: PilotSeat = null
var _stride: float = 0.0


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


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return
	if event.is_action_pressed(&"release_mouse"):
		_release_held()
		stand_up()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if event.is_action_pressed(&"interact"):
		if _seat != null:
			stand_up()
		else:
			_try_grab()
	elif event.is_action_released(&"interact"):
		_release_held()
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null:
		if _held != null:
			_held.drag(motion.relative)
		else:
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


func _simulate(delta: float) -> void:
	var gravity: Vector3 = Vector3.DOWN * SubFrame.GRAVITY
	if _sub_frame != null:
		gravity = _sub_frame.gravity_in_sub()
	var input: Vector2 = bot_move
	if input == Vector2.ZERO and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		input = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if _seat != null:
		# Seated: WASD flies the sub; the body stays in the chair.
		_seat.drive(input, delta)
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
	if is_on_floor():
		if tilt > deg_to_rad(SLIDE_ANGLE_DEG):
			velocity += along_deck * delta
		velocity.y = minf(velocity.y, 0.0) + gravity.y * delta
	else:
		velocity += gravity * delta
	var before: Vector3 = position
	move_and_slide()
	if not INTERIOR_BOUNDS.has_point(position):
		push_warning("Player %s left the interior at %s; moving back inside" % [name, position])
		position = RESCUE_POINT
		velocity = Vector3.ZERO
	if is_on_floor():
		_stride += (position - before).length()
		if _stride >= STRIDE_M:
			_stride = 0.0
			footstep.emit(0.3 if sneaking else 1.0)


func _look(relative: Vector2) -> void:
	rotation.y -= relative.x * MOUSE_SENSITIVITY
	_head.rotation.x = clampf(
		_head.rotation.x - relative.y * MOUSE_SENSITIVITY, deg_to_rad(-85.0), deg_to_rad(85.0)
	)


func _try_grab() -> void:
	_ray.force_raycast_update()
	if not _ray.is_colliding():
		return
	var node: Node = _ray.get_collider() as Node
	while node != null and not (node is Interactable):
		node = node.get_parent()
	if node == null:
		return
	if node is PilotSeat:
		sit_in(node as PilotSeat)
		return
	_held = node as Interactable
	_held.begin_interaction()


## Sits in the pilot's chair. Stands up again if someone else got there first.
func sit_in(seat: PilotSeat) -> void:
	if _seat != null:
		return
	_seat = seat
	_seat.holder_changed.connect(_on_seat_holder_changed)
	_seat.begin_interaction()


func stand_up() -> void:
	if _seat == null:
		return
	var seat: PilotSeat = _seat
	_seat = null
	seat.holder_changed.disconnect(_on_seat_holder_changed)
	seat.end_interaction()
	# Step out of the chair, back toward the corridor.
	position = seat.seat_transform().origin + seat.seat_transform().basis.z * 0.6


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
	mat.albedo_color = Color.from_hsv(fmod(float(peer_id % 997) * 0.618, 1.0), 0.5, 0.8)
	_body_mesh.material_override = mat
