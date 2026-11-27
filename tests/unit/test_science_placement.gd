extends TestCase
## The science station sits on its starboard reservation, facing the aisle, with its SCAN module the one the dive uses.

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")

var interior: Node3D


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)


func after_each() -> void:
	interior.free()


func _station() -> ScienceStation:
	return interior.get_node("Stations/Science/Station") as ScienceStation


func _panel() -> Node3D:
	return _station().get_node("Panel") as Node3D


func test_station_is_on_the_starboard_wall_inside_the_hull_facing_the_aisle() -> void:
	var p: Vector3 = _panel().global_position
	var fp: Rect2 = SubLayout.footprint(&"science")
	expect_near(p.y, SubLayout.main_deck_y() + 1.1 + 0.95, 0.001, "centred 1.1 m above the floor")
	expect(p.x > 0.0, "starboard")
	expect(p.z > fp.position.y and p.z < fp.end.y, "centred along the reservation (z %f)" % p.z)
	expect(_panel().global_basis.z.is_equal_approx(Vector3(-1, 0, 0)), "the bays face the aisle (-X)")
	for dz: float in [-0.55, 0.0, 0.55]:
		expect(SubLayout.inside_hull(p.x - 0.01, p.y + 0.4, p.z + dz), "the top of the back is inside the hull at dz %f" % dz)
		expect(not SubLayout.inside_hull(p.x + 0.2, p.y, p.z + dz), "and against it at dz %f" % dz)


func test_operator_stands_in_the_aisle_inside_the_hull() -> void:
	var s: Vector3 = _station().sit_point.global_position
	expect(s.x < SubLayout.footprint(&"science").position.x, "the operator stands in front of the reservation (x %f)" % s.x)
	expect(SubLayout.inside_hull(s.x, s.y + 1.65, s.z), "head inside the hull")
	expect(_station().get_node("Grab") is StaticBody3D, "there is a grab to press E on")


func test_the_bays_hold_the_default_modules_and_the_scan_module_is_the_objectives() -> void:
	var bay0: Node = _panel().get_node("Bay0/Module")
	expect(bay0 is ScanModule, "bay 0 holds SCAN")
	expect(_panel().get_node("Bay1/Module") is SweepModule, "bay 1 holds SWEEP")
	expect(_panel().get_node("Bay2/Module") is CameraModule, "bay 2 holds CAMERA")
	var objective: ScanObjective = ScanObjective.new()
	runner.add_child(objective)
	(bay0 as ScanModule)._link()
	expect(objective.module == bay0, "the SCAN module drives the scan objective")
	objective.free()


func test_the_station_adds_no_second_set_of_modules() -> void:
	var st: ScienceStation = _station()
	expect_eq(st.fitted().size(), 3, "the three bays of the scene are adopted")
	expect(st.active_module() is ScanModule, "SCAN is the active module")
	for i: int in 3:
		expect_eq(st.get_node("Panel/Bay%d" % i).get_child_count() > 0, true, "bay %d is the scene's own" % i)
		expect_eq(st.bays[i].get_children().filter(func(c: Node) -> bool: return c is ScienceModule).size() <= 1, true, "bay %d holds no second module" % i)


func test_the_operator_can_select_and_arm_the_scan_module() -> void:
	var st: ScienceStation = _station()
	var scan: ScienceModule = st.active_module()
	expect(scan is ScanModule, "starts on SCAN")
	var f: InputEventKey = InputEventKey.new()
	f.keycode = ScienceStation.ARM_KEY
	f.pressed = true
	expect(st.handle_event(f), "F is used")
	expect(scan.armed, "SCAN armed")
	var d: InputEventAction = InputEventAction.new()
	d.action = &"move_right"
	d.pressed = true
	st.handle_event(d)
	expect(st.active_module() is SweepModule, "D selects SWEEP")
	st.select_step(-1)
	expect(st.active_module() == scan, "A returns to SCAN")


func test_the_station_spans_the_reservations_length() -> void:
	var fp: Rect2 = SubLayout.footprint(&"science")
	var z: float = _panel().global_position.z
	expect(z - 0.6 >= fp.position.y - 0.01 and z + 0.6 <= fp.end.y + 0.01, "the 1.2 m panel at z %f is inside the reservation %s" % [z, fp])
