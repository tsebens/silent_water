extends TestCase
## ScienceStation adopts the module scene instances under the science_bay scene instead of building a second set.

const SCENE: String = "res://assets/models/stations/science_bay/science_bay.tscn"


func _station() -> ScienceStation:
	var st: ScienceStation = ScienceStation.new()
	var bay: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	st.add_child(bay)
	st.anchor_root = st.get_path_to(bay)
	runner.add_child(st)
	return st


func _count_modules(n: Node) -> int:
	var c: int = 1 if n is ScienceModule else 0
	for ch: Node in n.get_children():
		c += _count_modules(ch)
	return c


func test_adopts_scene_modules() -> void:
	var st: ScienceStation = _station()
	var scene_mod: Node = st.get_node(st.anchor_root).get_node("Bay1/Module")
	expect_eq(st.bays.size(), 3, "three bays")
	expect(st.bays[1].module == scene_mod, "bay 1 holds the scene's module")
	expect_eq(_count_modules(st), 3, "no second set of modules")
	st.queue_free()


func test_loadout_swaps_scene_module() -> void:
	var st: ScienceStation = _station()
	st.loadout.fit(1, ModuleLoadout.Type.PROBE)
	await runner.get_tree().process_frame
	expect_eq(st.bays[1].module.module_type, ModuleLoadout.Type.PROBE, "probe fitted")
	expect(st.bays[1].module.get_parent() == st.get_node(st.anchor_root).get_node("Bay1"), "under the scene anchor")
	expect_eq(_count_modules(st), 3, "still three live modules")
	st.queue_free()
