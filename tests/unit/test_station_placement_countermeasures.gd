extends TestCase
## The countermeasures station sits on its starboard reservation at the bulkhead, its operator's standing space clear of the
## lock-out trunk's hatch and the aisle, and every FIRE button and lamp set names its loader's LaunchTube by node path.

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")
const LOADER_SCENE: PackedScene = preload("res://assets/models/panels/decoy_loader/decoy_loader.tscn")

var interior: Node3D


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)


func after_each() -> void:
	interior.free()


func _panel() -> Node3D:
	return interior.get_node("Stations/Countermeasures/Panel") as Node3D


## The tube path set on a FIRE or lamp node (the node itself holds null until a loader is there to resolve it).
func _tube_path(node_name: String) -> NodePath:
	var state: SceneState = INTERIOR_SCENE.get_state()
	var want: String = "./Stations/Countermeasures/Panel/%s" % node_name
	for i: int in state.get_node_count():
		var path: String = str(state.get_node_path(i))
		if path != want:
			continue
		for j: int in state.get_node_property_count(i):
			if state.get_node_property_name(i, j) == &"tube":
				return state.get_node_property_value(i, j) as NodePath
	return NodePath()


func test_station_is_in_the_interior_with_no_placeholder() -> void:
	expect(_panel() != null, "the station is at Stations/Countermeasures")
	expect_eq(interior.get_node("Stations").find_children("*Countermeasure*", "", false, false).size(), 1, "one countermeasures node, no placeholder")


func test_footprint_is_inside_the_full_reservation() -> void:
	var fp: Rect2 = SubLayout.footprint(&"countermeasures")
	expect_near(fp.size.x, 0.45, 0.001, "the reservation is 0.45 m deep")
	expect_near(fp.size.y, 1.0, 0.001, "and the full 1.0 m along the hull")
	expect_near(fp.end.y, SubLayout.compartment_span(&"midships").y, 0.001, "ending at the bulkhead")
	var p: Vector3 = _panel().global_position
	expect_near(p.y, SubLayout.main_deck_y() + 1.1 + 0.95, 0.001, "1.1 m above the floor")
	# The panel and rack are 0.99 m along the hull by 0.45 m out, centred on the origin.
	var mine: Rect2 = Rect2(p.x - 0.45, p.z - 0.495, 0.45, 0.99)
	expect(fp.grow(0.01).encloses(mine), "the station's footprint %s lies inside the reservation %s" % [mine, fp])
	expect(_panel().global_basis.z.is_equal_approx(Vector3(-1, 0, 0)), "it faces the aisle (-X)")
	for dz: float in [-0.45, 0.0, 0.45]:
		expect(SubLayout.inside_hull(p.x - 0.01, p.y + 0.4, p.z + dz), "the top of its back is inside the hull at dz %f" % dz)


func test_operator_space_is_clear_of_the_trunk_the_aisle_and_the_walk_around() -> void:
	var eye: Vector3 = (_panel().get_node("OperatorEye") as Node3D).global_position
	var trunk: Rect2 = SubLayout.footprint(&"lock_out_trunk")
	var fp: Rect2 = SubLayout.footprint(&"countermeasures")
	expect(not fp.grow(-0.001).intersects(trunk), "the reservation does not overlap the lock-out trunk")
	var half: float = 0.3  # the player capsule's standing space
	var stand: Rect2 = Rect2(eye.x - half, eye.z - half, half * 2.0, half * 2.0)
	expect(not stand.intersects(trunk), "the operator's standing space %s is clear of the trunk's hatch %s" % [stand, trunk])
	expect(not fp.has_point(Vector2(eye.x, eye.z)), "and the eye is in front of the station, not inside it")
	expect(SubLayout.inside_hull(eye.x, eye.y, eye.z), "the operator's eye is inside the hull")
	# What is left of the aisle between the station and the trunk's side, and the port side, still lets a crew member pass.
	var aisle: float = SubLayout.clearance("aisle_min_m")
	var port: float = maxf(SubLayout.footprint(&"lockers").end.x, SubLayout.footprint(&"tower_ladder").end.x)
	expect(fp.position.x - port >= aisle, "the aisle past the station is %f m (need %f)" % [fp.position.x - port, aisle])
	for id: StringName in [&"science", &"sonar", &"map_table", &"lockers", &"tower_ladder"]:
		expect(not SubLayout.footprint(id).grow(-0.001).intersects(fp), "%s does not overlap the station" % id)


func test_every_fire_and_lamp_tube_path_resolves_to_a_launch_tube() -> void:
	var stations: Node = interior.get_node("Stations")
	for t: String in ["Fore", "Aft"]:
		var loader: Node = LOADER_SCENE.instantiate()
		loader.name = "%sLoader" % t
		stations.add_child(loader)
		for kind: String in ["Fire", "Lamps"]:
			var path: NodePath = _tube_path("%s%s" % [t, kind])
			expect(not path.is_empty(), "%s%s has a tube path" % [t, kind])
			var holder: Node = _panel().get_node("%s%s" % [t, kind])
			expect(holder.get_node_or_null(path) is LaunchTube, "%s%s's tube path %s resolves to a LaunchTube" % [t, kind, path])
