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
## The chart view (focus, scale, rotation, follow) is host-authoritative: the
## operator's inputs are requests to the host, which applies them and sends
## the view to every peer, so everyone's table hologram shows the operator's
## chart. The operator is whoever holds the table or one of its console controls.
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
## Longest gap between view updates while the operator is steering (s).
const VIEW_SEND_INTERVAL: float = 1.0 / 30.0
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
## A local operator input changed the view and it hasn't been sent yet.
var _view_dirty: bool = false
var _since_view_send: float = 0.0

## The host sent the view to [param peer] (0: everyone). Fires offline too, for tests.
signal view_sent(peer: int, view: Dictionary)


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
	Net.peer_joined.connect(_on_peer_joined)


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
	var look: Vector3 = base + holo.global_basis * Vector3(0, holo.relief_max_height() * 0.3, holo.clip_rz * 0.4)
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
		_view_dirty = true


## Pans the display by [param d_display] display metres (in the table's own directions).
## Taking the camera off the sub switches following off.
func pan_display(d_display: Vector3) -> void:
	if holo == null:
		return
	_set_follow(false)
	holo.focus += holo.display_basis().inverse() * d_display * holo.meters_per_unit
	_view_dirty = true


## Sets the chart scale (the operator's zoom).
func zoom_to(mpu: float) -> void:
	if holo != null:
		holo.set_zoom(mpu)
		_view_dirty = true


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
	_view_dirty = true
	_update_lamp()


func _on_follow_toggled(value: float) -> void:
	# The toggle's value replicates to everyone; only the peer driving it acts
	# on it, the rest get the result with the view.
	if _drives(follow_toggle):
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
	if zoom_lever != null and _drives(zoom_lever):
		var rate: float = zoom_lever.zoom_rate()
		if absf(rate) > LEVER_DEADZONE:
			zoom_to(holo.meters_per_unit * pow(2.0, -rate * delta / LEVER_ZOOM_SECONDS))
	_since_view_send += delta
	if _view_dirty and _since_view_send >= VIEW_SEND_INTERVAL:
		_publish_view()
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
				zoom_to(holo.meters_per_unit / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_to(holo.meters_per_unit * ZOOM_STEP)
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


# --- Shared chart view ---------------------------------------------------------

## Whether this peer is the one steering console control [param c]: it holds it
## here, or it is the host and no remote player does (the control is driven by
## game logic or offline).
func _drives(c: Interactable) -> bool:
	if c.is_held_locally():
		return true
	return multiplayer.is_server() and (c.state.holder == InteractableState.NO_HOLDER or c.state.holder == Net.local_id())


## Whether [param peer] is the operator: it holds the table or a console control.
func is_operator(peer: int) -> bool:
	for c: Interactable in [self, pan_ball, zoom_lever, follow_toggle]:
		if c != null and c.state.holder == peer:
			return true
	return false


## The chart view as it goes over the wire.
func view_dict() -> Dictionary:
	return {"focus": holo.focus, "mpu": holo.meters_per_unit, "rot": holo.table_rotation_deg, "follow": holo.follow_sub}


## Shows [param view] on this peer's table hologram.
func apply_view(view: Dictionary) -> void:
	if holo == null:
		return
	holo.focus = view["focus"] as Vector3
	holo.set_zoom(float(view["mpu"]))
	holo.table_rotation_deg = float(view["rot"])
	holo.follow_sub = bool(view["follow"])
	_update_lamp()


## This peer is steering: send the view to the host (or, on the host, to everyone).
func _publish_view() -> void:
	_view_dirty = false
	_since_view_send = 0.0
	var v: Dictionary = view_dict()
	if multiplayer.is_server():
		_send_view(0, v)
	elif Net.is_online():
		_rpc_request_view.rpc_id(1, v["focus"], v["mpu"], v["rot"], v["follow"])


## Host: a peer asks for this view. Only the operator is heard.
func host_request_view(sender: int, view: Dictionary) -> bool:
	if not multiplayer.is_server() or not is_operator(sender):
		return false
	apply_view(view)
	_send_view(0, view_dict())
	return true


func _send_view(peer: int, view: Dictionary) -> void:
	view_sent.emit(peer, view)
	if not Net.is_online():
		return
	if peer == 0:
		_rpc_set_view.rpc(view["focus"], view["mpu"], view["rot"], view["follow"])
	else:
		_rpc_set_view.rpc_id(peer, view["focus"], view["mpu"], view["rot"], view["follow"])


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_view(focus: Vector3, mpu: float, rot: float, follow: bool) -> void:
	host_request_view(multiplayer.get_remote_sender_id(), {"focus": focus, "mpu": mpu, "rot": rot, "follow": follow})


@rpc("authority", "call_remote", "reliable")
func _rpc_set_view(focus: Vector3, mpu: float, rot: float, follow: bool) -> void:
	# The local operator is steering and already shows its own view.
	if is_held_locally() or (pan_ball != null and pan_ball.is_held_locally()) \
			or (zoom_lever != null and zoom_lever.is_held_locally()) \
			or (follow_toggle != null and follow_toggle.is_held_locally()):
		return
	apply_view({"focus": focus, "mpu": mpu, "rot": rot, "follow": follow})


func _on_peer_joined(peer_id: int) -> void:
	if multiplayer.is_server() and holo != null:
		_send_view(peer_id, view_dict())


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
	var mid_y: float = holo.to_world(Vector3(0, holo.relief_max_height() * 0.5, 0)).y
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
