class_name MapTable
extends StationSeat
## The map table. E steps up to it: the view leans over the hologram and the
## cursor appears.
##   WASD   pan            wheel   zoom          F   follow the sub
##   1-4    pin type       click   place a pin   right-click   remove a pin
##   E/Esc  step back
## Pins go to the shared [MapModel], so they show on the pilot's map too.

const PAN_SPEED: float = 0.6  # display metres per second
const ZOOM_STEP: float = 1.15
const PICK_RADIUS_PX: float = 24.0
## Pin types offered on keys 1-4.
const KEY_KINDS: Array[int] = [MapModel.Kind.WAYPOINT, MapModel.Kind.DANGER, MapModel.Kind.APEX, MapModel.Kind.NOTE]

@export var holo: HoloMap
## Where the leaning view sits, relative to the hologram's base.
@export var view_offset: Vector3 = Vector3(0, 0.95, 0.72)

var pin_kind: int = MapModel.Kind.WAYPOINT


func _init() -> void:
	super._init()
	eye_height = 1.6


func station_name() -> String:
	return "MAP TABLE"


func seated_hint() -> String:
	return "WASD pan · wheel zoom · F %s · 1-4 pin: %s · click place · right-click remove · E leave" % [
		"stop following" if holo != null and holo.follow_sub else "follow sub", MapModel.kind_name(pin_kind)]


func interaction_hint() -> String:
	return "press E to use the map table"


## Camera pose while leaning over the table (render space).
func view_transform() -> Transform3D:
	var base: Vector3 = holo.global_position
	var eye: Vector3 = base + holo.global_basis * view_offset
	var look: Vector3 = base + holo.global_basis.y * holo.height * 0.3
	return Transform3D.IDENTITY.looking_at(look - eye, holo.global_basis.y).translated(eye)


func begin_interaction() -> void:
	super.begin_interaction()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func end_interaction() -> void:
	super.end_interaction()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not is_held_locally() or holo == null:
		return
	var move: Vector2 = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
	if move != Vector2.ZERO:
		if holo.follow_sub:
			holo.focus = holo.game.sub_frame.sub_transform.origin
			holo.follow_sub = false
		# Pan in the table's own directions, converted to world metres.
		var d_display: Vector3 = Vector3(move.x, 0.0, move.y) * PAN_SPEED * delta
		holo.focus += holo.display_basis().inverse() * d_display * holo.meters_per_unit


func _unhandled_input(event: InputEvent) -> void:
	if not is_held_locally() or holo == null:
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb != null and mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				holo.set_zoom(holo.meters_per_unit / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				holo.set_zoom(holo.meters_per_unit * ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				var p: Variant = pick_world(mb.position)
				if p != null:
					(holo.get_tree().get_first_node_in_group(&"map_model") as MapModel).add_pin(p as Vector3, pin_kind)
			MOUSE_BUTTON_RIGHT:
				var id: int = pin_near(mb.position)
				if id != -1:
					(holo.get_tree().get_first_node_in_group(&"map_model") as MapModel).remove_pin(id)
		get_viewport().set_input_as_handled()
		return
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode >= KEY_1 and key.keycode <= KEY_4:
			pin_kind = KEY_KINDS[key.keycode - KEY_1]
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_F:
			holo.follow_sub = not holo.follow_sub
			if not holo.follow_sub:
				holo.focus = holo.game.sub_frame.sub_transform.origin
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
