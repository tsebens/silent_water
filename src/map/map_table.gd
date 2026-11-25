class_name MapTable
extends StationSeat
## The map table. The operator stands at it; E steps up to it: the view leans
## over the hologram and the cursor appears. The table's console carries the
## physical controls, which work whether or not anyone is stepped up:
##   trackball   pan             lever   zoom (spring-centred rate)
##   toggle      follow the sub  lamp    lit while following
## Stepped up, the keys and mouse do the same, and pins:
##   WASD   pan            wheel   zoom          F   follow the sub
##   Q / R  rotate the chart (or hold the middle button and drag)
##   1-4    pin type       click   place a pin   right-click   remove a pin
##   E/Esc  step back
## Pins go to the shared [MapModel], so they show on the pilot's map too.
## There is no seat: [member sit_point] is where the operator stands.
## Whoever steps up leans over the table ([constant LEAN_DOWN], [constant LEAN_TOWARD]).
## Only the operator drives the camera; [MapTableObserver] points either side
## let others step up to place and remove pins.

const PAN_SPEED: float = 0.6  # display metres per second
## Display metres of pan per unit of trackball roll.
const BALL_PAN: float = 0.08
const ZOOM_STEP: float = 1.15
## The lever at full throw halves or doubles the scale in this many seconds.
const LEVER_ZOOM_SECONDS: float = 1.5
const LEVER_DEADZONE: float = 0.02
## Chart rotation speed on the keys, degrees per second, and per pixel of mouse drag.
const ROTATE_DEG_PER_S: float = 60.0
const ROTATE_DEG_PER_PX: float = 0.4
## How far a stepped-up player's eye drops below the standing eye (m).
const LEAN_DOWN: float = 0.25
## How far it moves toward the hologram (m, horizontal).
const LEAN_TOWARD: float = 0.15
const PICK_RADIUS_PX: float = 24.0
## Pin types offered on keys 1-4.
const KEY_KINDS: Array[int] = [MapModel.Kind.WAYPOINT, MapModel.Kind.DANGER, MapModel.Kind.APEX, MapModel.Kind.NOTE]

@export var holo: HoloMap
@export var pan_ball: PanBall
@export var zoom_lever: ZoomLever
@export var follow_toggle: SwitchLever
@export var follow_lamp: IndicatorLamp
## The standing operator's eye (the station's OperatorEye). Without it the view
## leans in at [member view_offset] from the hologram's base.
@export var eye_point: Node3D
## Where the leaning view sits, relative to the hologram's base.
@export var view_offset: Vector3 = Vector3(0, 0.95, 0.72)

var pin_kind: int = MapModel.Kind.WAYPOINT
## -1 turning with Q, +1 with R, 0 neither (set from key events).
var _rotate_dir: float = 0.0
var _rotate_keys: Dictionary = {}
var _dragging_rotate: bool = false


func _init() -> void:
	super._init()
	eye_height = 1.65


func _ready() -> void:
	super._ready()
	if pan_ball != null:
		pan_ball.rolled.connect(_on_ball_rolled)
	if follow_toggle != null:
		follow_toggle.value_changed.connect(_on_follow_toggled)
	if holo != null and follow_toggle != null:
		holo.follow_sub = follow_toggle.get_value() > 0.5
	_update_lamp()


func station_name() -> String:
	return "MAP TABLE"


func seated_hint() -> String:
	return "WASD pan · wheel zoom · Q/R rotate · F %s · 1-4 pin: %s · click place · right-click remove · E leave" % [
		"stop following" if holo != null and holo.follow_sub else "follow sub", MapModel.kind_name(pin_kind)]


func interaction_hint() -> String:
	return "press E to use the map table"


func has_table_view() -> bool:
	return true


func table_view() -> Transform3D:
	return view_transform()


## The standing eye of the operator (render space).
func standing_eye() -> Vector3:
	return eye_point.global_position if eye_point != null else holo.global_position + holo.global_basis * view_offset


## [param eye] leaned over the table: [constant LEAN_DOWN] lower and
## [constant LEAN_TOWARD] toward the hologram. Same for everyone.
func lean_eye(eye: Vector3) -> Vector3:
	var up: Vector3 = holo.global_basis.y
	var flat: Vector3 = holo.global_position - eye
	flat -= up * flat.dot(up)
	var toward: Vector3 = flat.normalized() if flat.length() > 1e-4 else Vector3.ZERO
	return eye - up * LEAN_DOWN + toward * LEAN_TOWARD


## Camera pose for a player whose standing eye is [param eye] (render space).
func view_transform_from(eye: Vector3) -> Transform3D:
	var leaned: Vector3 = lean_eye(eye)
	var base: Vector3 = holo.global_position
	var look: Vector3 = base + holo.global_basis * Vector3(0, holo.height * 0.3, holo.clip_rz * 0.4)
	return Transform3D.IDENTITY.looking_at(look - leaned, holo.global_basis.y).translated(leaned)


## Camera pose of the operator at the table (render space).
func view_transform() -> Transform3D:
	return view_transform_from(standing_eye())


## Places a pin of [param kind] under a screen position, if it meets the display.
func place_pin_at(screen_pos: Vector2, kind: int) -> void:
	var p: Variant = pick_world(screen_pos)
	if p != null:
		_model().add_pin(p as Vector3, kind)


## Removes the pin nearest a screen position, if one is close enough.
func remove_pin_at(screen_pos: Vector2) -> void:
	var id: int = pin_near(screen_pos)
	if id != -1:
		_model().remove_pin(id)


func _model() -> MapModel:
	return holo.get_tree().get_first_node_in_group(&"map_model") as MapModel


func begin_interaction() -> void:
	super.begin_interaction()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func end_interaction() -> void:
	super.end_interaction()
	_rotate_keys.clear()
	_rotate_dir = 0.0
	_dragging_rotate = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Turns the chart on the table by [param degrees].
func rotate_table(degrees: float) -> void:
	if holo != null:
		holo.table_rotation_deg = fposmod(holo.table_rotation_deg + degrees, 360.0)


## Pans the display by [param d_display] display metres (in the table's own directions).
## Taking the camera off the sub switches following off.
func pan_display(d_display: Vector3) -> void:
	if holo == null:
		return
	_set_follow(false)
	holo.focus += holo.display_basis().inverse() * d_display * holo.meters_per_unit


## Turns following on or off: the toggle's position is the shared state, the lamp follows it.
func _set_follow(on: bool) -> void:
	if holo == null:
		return
	_apply_follow(on)
	if follow_toggle != null and not follow_toggle.is_held_locally() and follow_toggle.is_inside_tree() \
			and (follow_toggle.get_value() > 0.5) != on:
		follow_toggle.begin_interaction()
		follow_toggle.drive_to(follow_toggle.max_value if on else follow_toggle.min_value, true)
		follow_toggle.end_interaction()


func _apply_follow(on: bool) -> void:
	if holo == null or holo.follow_sub == on:
		return
	if not on:
		holo.focus = holo.game.sub_frame.sub_transform.origin
	holo.follow_sub = on
	_update_lamp()


func _on_follow_toggled(value: float) -> void:
	_apply_follow(value > 0.5)


func _on_ball_rolled(delta: Vector2) -> void:
	pan_display(Vector3(delta.x, 0.0, delta.y) * BALL_PAN)


func _update_lamp() -> void:
	if follow_lamp != null and holo != null:
		follow_lamp.set_lit(holo.follow_sub)


func _process(delta: float) -> void:
	if holo == null:
		return
	_update_lamp()
	# The lever's position is a zoom rate, held for as long as it is held.
	if zoom_lever != null:
		var rate: float = zoom_lever.zoom_rate()
		if absf(rate) > LEVER_DEADZONE:
			holo.set_zoom(holo.meters_per_unit * pow(2.0, -rate * delta / LEVER_ZOOM_SECONDS))
	if not is_held_locally():
		return
	var move: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if move != Vector2.ZERO:
		pan_display(Vector3(move.x, 0.0, move.y) * PAN_SPEED * delta)
	if _rotate_dir != 0.0:
		rotate_table(_rotate_dir * ROTATE_DEG_PER_S * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not is_held_locally() or holo == null:
		return
	var mm: InputEventMouseMotion = event as InputEventMouseMotion
	if mm != null:
		if _dragging_rotate:
			rotate_table(mm.relative.x * ROTATE_DEG_PER_PX)
			get_viewport().set_input_as_handled()
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging_rotate = mb.pressed
		get_viewport().set_input_as_handled()
		return
	if mb != null and mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				holo.set_zoom(holo.meters_per_unit / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				holo.set_zoom(holo.meters_per_unit * ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				place_pin_at(mb.position, pin_kind)
			MOUSE_BUTTON_RIGHT:
				remove_pin_at(mb.position)
		get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if key == null or key.echo:
		return
	if key.keycode == KEY_Q or key.keycode == KEY_R:
		if key.pressed:
			_rotate_keys[key.keycode] = true
		else:
			_rotate_keys.erase(key.keycode)
		_rotate_dir = (1.0 if _rotate_keys.has(KEY_R) else 0.0) - (1.0 if _rotate_keys.has(KEY_Q) else 0.0)
		get_viewport().set_input_as_handled()
	elif key.pressed:
		if key.keycode >= KEY_1 and key.keycode <= KEY_4:
			pin_kind = KEY_KINDS[key.keycode - KEY_1]
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_F:
			_set_follow(not holo.follow_sub)
			get_viewport().set_input_as_handled()


## The world point under a screen position: the real terrain where the ray
## through the hologram meets it, else the display's middle depth.
func pick_world(screen_pos: Vector2) -> Variant:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		return null
	var from_r: Vector3 = cam.project_ray_origin(screen_pos)
	var dir_r: Vector3 = cam.project_ray_normal(screen_pos)
	return pick_world_from_ray(from_r, dir_r)


## Same as [method pick_world] for a ray in render space (testable).
func pick_world_from_ray(from_r: Vector3, dir_r: Vector3) -> Variant:
	var to_local: Transform3D = holo.global_transform.affine_inverse()
	var a_world: Vector3 = holo.to_world(to_local * from_r)
	var b_world: Vector3 = holo.to_world(to_local * (from_r + dir_r * 5.0))
	var dir_world: Vector3 = (b_world - a_world).normalized()
	var frame: SubFrame = holo.game.sub_frame
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var render_from_world: Transform3D = frame.sub_transform.affine_inverse()
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		render_from_world * a_world, render_from_world * (a_world + dir_world * 4000.0), 1 << 3)
	var hit: Dictionary = space.intersect_ray(q)
	if not hit.is_empty():
		return frame.sub_transform * (hit["position"] as Vector3)
	# No terrain under the cursor: use the depth at the middle of the display.
	var mid_y: float = holo.to_world(Vector3(0, holo.height * 0.5, 0)).y
	if absf(dir_world.y) < 1e-4:
		return null
	var t: float = (mid_y - a_world.y) / dir_world.y
	return a_world + dir_world * t if t > 0.0 else null


## Id of the pin marker nearest a screen position, or -1.
func pin_near(screen_pos: Vector2) -> int:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var best: int = -1
	var best_d: float = PICK_RADIUS_PX
	for m: Node3D in holo.pin_markers():
		var sp: Vector2 = cam.unproject_position(m.global_position)
		var d: float = sp.distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = int(m.get_meta(&"pin_id"))
	return best
