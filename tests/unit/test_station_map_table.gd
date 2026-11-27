extends TestCase
## The generated map table station (docs/asset_process.md): its controls and mount nodes by name, no seat, reach from
## the standing eye, grab boxes apart. The brief's constraints are the thresholds.

const SCENE: String = "res://assets/models/stations/map_table/map_table.tscn"
const REACH_M: float = 0.75


func _make() -> Node3D:
	var st: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(st)
	return st


func _grab_aabb(c: Interactable) -> AABB:
	var shape_node: CollisionShape3D = c.get_node("Grab/Shape") as CollisionShape3D
	var box: BoxShape3D = shape_node.shape as BoxShape3D
	return shape_node.global_transform * AABB(-box.size * 0.5, box.size)


func _interactables(st: Node3D) -> Array[Interactable]:
	var out: Array[Interactable] = []
	for n: Node in st.get_node("Controls").get_children():
		if n is Interactable:
			out.append(n as Interactable)
	return out


func test_every_function_has_its_control() -> void:
	var st: Node3D = _make()
	expect(st.get_node_or_null("Controls/PanTrackball") is PanBall, "pan trackball")
	expect(st.get_node_or_null("Controls/ZoomLever") is ZoomLever, "zoom lever")
	expect(st.get_node_or_null("Controls/FollowToggle") is SwitchLever, "follow toggle")
	expect(st.get_node_or_null("Controls/FollowLamp") is IndicatorLamp, "follow lamp")
	expect(st.get_node_or_null("Controls/RotaryKnob") != null, "decorative rotary knob")
	expect(st.get_node_or_null("Controls/RotaryKnob/Grab") == null, "the knob has no grab box")
	expect(st.get_node_or_null("Shelf/NoiseRepeater") is Gauge, "noise repeater on the shelf")
	st.queue_free()


func test_shelf_gauges_stand_off_their_module() -> void:
	# #596: the dial face is drawn on the anchor's Z=0, so each gauge sits 2 mm off the module's front plate.
	var st: Node3D = _make()
	var shelf: Node3D = st.get_node("Shelf") as Node3D
	var n: int = 0
	for child: Node in shelf.get_children():
		if child is Gauge:
			n += 1
			expect((child as Node3D).position.z >= 0.0019, "%s stands off the module's front plate" % child.name)
	expect(n == 5, "five gauges on the shelf (%d)" % n)
	st.queue_free()


func test_mount_nodes_exist() -> void:
	var st: Node3D = _make()
	var holo: Node3D = st.get_node_or_null("HoloMount") as Node3D
	expect(holo != null, "HoloMount")
	expect(st.get_node_or_null("BackPanelAnchor") != null, "BackPanelAnchor")
	if holo != null:
		expect_near(holo.position.y, 0.75, 0.01, "the hologram mounts on the 0.75 m table top")
	st.queue_free()


func test_no_seat_and_no_scripts_of_its_own() -> void:
	var st: Node3D = _make()
	expect(st.get_script() == null, "the station adds no script")
	for n: Node in st.find_children("*", "", true, false):
		expect(not n.scene_file_path.contains("operator_seat"), "no operator_seat instance (%s)" % n.name)
		expect(not (n is StationSeat), "no seat node (%s)" % n.name)
	expect(st.get_node_or_null("Seat") == null, "no Seat node")
	st.queue_free()


func test_lean_eye_is_the_standing_eye_leaned() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).global_position
	expect_near(eye.y, 1.65, 0.001, "standing eye height (the game leans this one)")
	var lean: Vector3 = (st.get_node("LeanEye") as Node3D).global_position
	var toward: Vector3 = (st.get_node("HoloMount") as Node3D).global_position - eye
	toward.y = 0.0
	toward = toward.normalized()
	expect_near(eye.y - lean.y, MapTable.LEAN_DOWN, 0.001, "LeanEye is LEAN_DOWN below OperatorEye")
	expect_near((lean - eye).dot(toward), MapTable.LEAN_TOWARD, 0.001, "LeanEye is LEAN_TOWARD toward the table")
	expect_near(lean.y, 1.40, 0.001, "leaning eye height matches the brief")
	st.queue_free()


func test_controls_within_reach_of_the_leaning_eye() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("LeanEye") as Node3D).global_position
	var controls: Array[Interactable] = _interactables(st)
	expect_eq(controls.size(), 3, "trackball, lever and toggle are touched")
	for c: Interactable in controls:
		var d: float = eye.distance_to(_grab_aabb(c).get_center())
		expect(d <= REACH_M, "%s is %.2f m from the leaning eye" % [c.name, d])
	for n: String in ["RotaryKnob", "FollowLamp"]:
		var d2: float = eye.distance_to((st.get_node("Controls/" + n) as Node3D).global_position)
		expect(d2 <= REACH_M, "%s is %.2f m from the leaning eye" % [n, d2])
	st.queue_free()


func test_console_is_level_with_the_table_top() -> void:
	var st: Node3D = _make()
	var holo_y: float = (st.get_node("HoloMount") as Node3D).global_position.y
	var strip: Node3D = st.get_node("Controls") as Node3D
	expect_near(strip.global_position.y, holo_y, 0.012, "the control strip's middle is level with the 0.75 m table top")
	var rake: float = rad_to_deg(acos(clampf(strip.global_basis.z.dot(Vector3.UP), -1.0, 1.0)))
	expect(rake <= 5.0, "strip rake %.1f degrees" % rake)
	for c: Interactable in _interactables(st):
		expect(c.global_position.y < holo_y + 0.12, "%s does not stand proud of the table" % c.name)
	st.queue_free()


func test_grab_boxes_do_not_overlap() -> void:
	var st: Node3D = _make()
	var controls: Array[Interactable] = _interactables(st)
	for i: int in range(controls.size()):
		for j: int in range(i + 1, controls.size()):
			expect(not _grab_aabb(controls[i]).grow(-0.0005).intersects(_grab_aabb(controls[j]).grow(-0.0005)),
				"%s and %s grab boxes overlap" % [controls[i].name, controls[j].name])
	st.queue_free()


func test_floor_back_and_top() -> void:
	var st: Node3D = _make()
	var body: MeshInstance3D = st.get_node("Body").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var aabb: AABB = body.global_transform * body.get_aabb()
	expect_near(aabb.position.y, 0.0, 0.001, "floor at Y=0")
	expect(aabb.position.z >= -0.001, "nothing behind Z=0")
	st.queue_free()
