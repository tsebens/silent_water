extends TestCase
## The generated decoy loader panel (docs/asset_process.md, brief #746): drawer, lever and lamps wired into a LaunchTube;
## a decoy can be loaded, primed and fired, leaving the tube empty; the lever is within reach of the operator.

const SCENE: String = "res://assets/models/panels/decoy_loader/decoy_loader.tscn"
const REACH_M: float = 1.1
const SHOULDER_DROP_M: float = 0.25


func _make() -> Node3D:
	var st: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	var ctrl: SubController = SubController.new()
	st.add_child(ctrl)    # freed with the panel, so no stray sub_controller outlives the test
	runner.add_child(st)
	var tube: LaunchTube = st.get_node("Tube") as LaunchTube
	tube.simulate_host = true
	tube.controller = ctrl
	return st


func _bounds(st: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [st]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi: MeshInstance3D = c as MeshInstance3D
		# The lever's arm swings through its throw (it may top the box by a few mm when up); the unit is what is static.
		if mi != null and not st.get_node("PrimeLever").is_ancestor_of(mi):
			var b: AABB = st.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(c.get_children())
	return out


func test_scene_wiring() -> void:
	var st: Node3D = _make()
	expect(st.get_script() == null, "the panel adds no script of its own")
	var tube: LaunchTube = st.get_node_or_null("Tube") as LaunchTube
	expect(tube != null, "Tube is a LaunchTube")
	expect_eq(tube.tube_name, "FORE TUBE", "default tube name")
	expect(tube.drawer == st.get_node("Drawer"), "tube drawer is the Drawer")
	expect(tube.cradle == st.get_node("Drawer/Slide/Cradle"), "tube cradle is the drawer's cradle")
	expect(tube.prime_lever == st.get_node("PrimeLever") and tube.prime_lever is SwitchLever, "tube lever is the PrimeLever")
	var lamps: TubeLamps = st.get_node_or_null("Lamps") as TubeLamps
	expect(lamps != null and lamps.tube == tube, "TubeLamps follows the tube")
	expect(lamps.empty_lamp == st.get_node("EmptyLamp") and lamps.loaded_lamp == st.get_node("LoadedLamp")
			and lamps.primed_lamp == st.get_node("PrimedLamp"), "three lamps wired")
	st.queue_free()


func test_size_and_depth() -> void:
	var st: Node3D = _make()
	var b: AABB = _bounds(st)
	expect(b.position.z > -0.001, "nothing behind the wall")
	var drawer: LoaderDrawer = st.get_node("Drawer") as LoaderDrawer
	expect_near(drawer.travel_m, 0.65, 0.001, "open reach 0.65 m")
	var deepest: float = b.end.z
	expect(deepest <= 0.4501, "closed, at most 0.45 m deep (%.3f)" % deepest)
	expect(b.size.y <= 0.6001, "0.6 m tall (%.3f)" % b.size.y)
	st.queue_free()


func test_lever_in_reach() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).position
	var shoulder: Vector3 = eye - Vector3(0.0, SHOULDER_DROP_M, 0.0)
	var lever: Node3D = st.get_node("PrimeLever") as Node3D
	var grip: Node3D = lever.get_node("Pivot/Arm") as Node3D
	expect(lever.position.distance_to(shoulder) < REACH_M, "lever within reach")
	for m: MeshInstance3D in _arm_meshes(grip):
		var p: Vector3 = st.global_transform.affine_inverse() * (m.global_transform * m.get_aabb().get_center())
		expect(p.distance_to(shoulder) <= REACH_M, "grip %s within 1.1 m of the shoulder" % p)
	st.queue_free()


func _arm_meshes(n: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is MeshInstance3D:
			out.append(c as MeshInstance3D)
		stack.append_array(c.get_children())
	return out


func test_load_prime_fire_empties_the_tube() -> void:
	var st: Node3D = _make()
	var tube: LaunchTube = st.get_node("Tube") as LaunchTube
	var drawer: LoaderDrawer = st.get_node("Drawer") as LoaderDrawer
	var cradle: DecoyCradle = st.get_node("Drawer/Slide/Cradle") as DecoyCradle
	var lamps: Array[IndicatorLamp] = [st.get_node("EmptyLamp") as IndicatorLamp,
			st.get_node("LoadedLamp") as IndicatorLamp, st.get_node("PrimedLamp") as IndicatorLamp]
	expect_eq(tube.state(), LaunchTube.State.EMPTY, "starts empty")
	expect(lamps[0].is_lit() and not lamps[1].is_lit() and not lamps[2].is_lit(), "EMPTY lamp lit")
	drawer.begin_interaction()
	drawer.drive_to(1.0)
	drawer.end_interaction()
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	var item: DecoyItem = DecoyItem.new()
	runner.add_child(item)
	item.pick_up(carrier)
	item.drop_into(cradle)
	expect(cradle.is_occupied(), "decoy seated")
	drawer.begin_interaction()
	drawer.drive_to(0.0)
	drawer.end_interaction()
	expect_eq(tube.state(), LaunchTube.State.LOADED, "loaded with the drawer closed")
	expect(lamps[1].is_lit() and not lamps[0].is_lit() and not lamps[2].is_lit(), "LOADED lamp lit")
	expect(tube.request_prime(), "prime accepted")
	expect_eq(tube.state(), LaunchTube.State.PRIMED, "primed")
	expect(drawer.locked, "drawer locked while primed")
	expect(lamps[2].is_lit() and not lamps[0].is_lit() and not lamps[1].is_lit(), "PRIMED lamp lit")
	expect(tube.fire(), "fired")
	expect_eq(tube.state(), LaunchTube.State.EMPTY, "tube back to empty")
	expect(not cradle.is_occupied(), "cradle empty")
	expect(lamps[0].is_lit() and not lamps[2].is_lit(), "EMPTY lamp lit again")
	carrier.queue_free()
	st.queue_free()
