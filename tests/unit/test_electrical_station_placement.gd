extends TestCase
## The electrical station is placed from the program (SubLayout) on the starboard wall of engineering, clear of its
## neighbours, bound to the interior's PowerSystem, with a junction box at each line node and the emergency lights up
## on the wall (arc #563, concept #534).

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")
const BREAKERS: Array[String] = [
	"BreakerMotor", "BreakerThrusters", "BreakerBilgePump", "BreakerCabinLts", "BreakerExtLts", "BreakerSonar",
	"BreakerFans", "BreakerHelm", "BreakerDisplays",
]

var interior: Node3D


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)


func after_each() -> void:
	interior.free()


func _panel() -> Node3D:
	return interior.get_node("Stations/Engineering/Panel") as Node3D


## The panel's body on the floor plan (x across the hull, y along it), from its meshes.
func _body_footprint() -> Rect2:
	var out: Rect2 = Rect2()
	var first: bool = true
	for n: Node in _panel().get_node("Body").find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n as MeshInstance3D
		var b: AABB = m.global_transform * m.get_aabb()
		var r: Rect2 = Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		out = r if first else out.merge(r)
		first = false
	return out


func test_panel_is_at_the_program_position_on_the_starboard_wall() -> void:
	var o: Vector3 = SubLayout.position(&"engineering")
	var p: Vector3 = _panel().global_position
	expect_near(p.z, o.z, 0.001, "along the hull at the program's z")
	expect_near(p.y, 1.1, 0.001, "board centre 1.1 m above the floor")
	expect(p.x > 0.0, "starboard")
	expect(SubLayout.footprint(&"engineering").grow(0.01).has_point(Vector2(p.x, p.z)), "the board's back is on its footprint")
	# Controls face the aisle (-X): local +Z points toward port.
	expect(_panel().global_basis.z.is_equal_approx(Vector3(-1, 0, 0)), "controls face the aisle")


func test_panel_clears_the_aisle_and_neighbours() -> void:
	var fp: Rect2 = _body_footprint()
	var allowed: Rect2 = SubLayout.footprint(&"engineering").grow(0.02)
	expect(allowed.encloses(fp), "body %s inside the program footprint %s" % [fp, allowed])
	for id: StringName in [&"drop_weights", &"scanner", &"lockers", &"countermeasures", &"life_support", &"ballast"]:
		expect(not fp.intersects(SubLayout.footprint(id).grow(-0.001)), "body clear of %s" % id)
	# Controls reach out at most 0.2 m from the wall, leaving the aisle clear.
	expect(fp.position.x > 0.6, "body does not reach toward the centre line (x %f)" % fp.position.x)


func test_panel_is_inside_the_hull() -> void:
	var p: Vector3 = _panel().global_position
	for dz: float in [-0.5, 0.0, 0.5]:
		for dy: float in [-0.65, 0.0, 0.65]:
			expect(SubLayout.inside_hull(p.x - 0.1, p.y + dy, p.z + dz), "inside the hull at dz %f dy %f" % [dz, dy])


func test_breakers_generator_and_readouts_are_bound_to_the_interior_power_system() -> void:
	var power: PowerSystem = interior.get_node("PowerSystem") as PowerSystem
	expect(power != null and power.is_in_group(PowerSystem.GROUP), "the interior has a PowerSystem in its group")
	for name: String in BREAKERS:
		var b: Node = _panel().get_node_or_null(name)
		expect(b != null, "%s present" % name)
		if b != null:
			b.call(&"refresh")
			expect(b.get("power") == power, "%s is bound to the interior's PowerSystem" % name)
	for name: String in ["HeatGauge", "LoadGauge", "BatteryBar"]:
		var g: Node = _panel().get_node(name)
		expect(g.get("source_group") == PowerSystem.GROUP, "%s reads the power system group" % name)
	var lamp: Node = _panel().get_node("RunningLampDriver")
	expect(lamp.get("source_group") == PowerSystem.GROUP, "RUNNING lamp reads the power system")
	expect(lamp.get("readout") == &"generator_running", "RUNNING lamp is on generator_running")
	expect(_panel().get_node("GeneratorLink") != null, "generator link present")


func test_a_junction_box_sits_on_each_line_node() -> void:
	var power: PowerSystem = interior.get_node("PowerSystem") as PowerSystem
	var boxes: Array[Node] = interior.get_node("JunctionBoxes").get_children()
	expect_eq(boxes.size(), PowerSystem.Circuit.size() * power.config.junction_boxes_per_line, "two boxes per circuit")
	var seen: Dictionary = {}
	for n: Node in boxes:
		var jb: JunctionBox = n as JunctionBox
		expect(jb != null, "%s is a JunctionBox" % n.name)
		seen["%d:%d" % [jb.circuit, jb.box_index]] = true
		expect(jb.power == power, "%s is bound to the interior's PowerSystem" % n.name)
	expect_eq(seen.size(), boxes.size(), "every box is a distinct line node")


func test_emergency_light_fixtures_exist_inside_the_hull() -> void:
	var root: Node3D = interior.get_node("EmergencyLights") as Node3D
	var lights: Array[Node] = root.find_children("*", "OmniLight3D", true, false)
	expect(lights.size() >= 2, "emergency lights fore and aft (%d)" % lights.size())
	for l: Node in lights:
		var p: Vector3 = (l as Node3D).position
		expect(SubLayout.inside_hull(p.x, p.y, p.z), "%s inside the hull" % l.name)
