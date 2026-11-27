extends TestCase
## Science core: bays built from a loadout, module selection, one operator.


func _station(slots: Array[int]) -> ScienceStation:
	var st: ScienceStation = ScienceStation.new()
	var lo: ModuleLoadout = ModuleLoadout.new()
	lo.slots = slots
	st.loadout = lo
	runner.add_child(st)
	return st


func _types(st: ScienceStation) -> Array[int]:
	var out: Array[int] = []
	for b: ScienceBay in st.bays:
		out.append(b.module.module_type if b.module != null else ModuleLoadout.Type.NONE)
	return out


func test_default_loadout() -> void:
	var lo: ModuleLoadout = ModuleLoadout.new()
	expect_eq(lo.slots, [ModuleLoadout.Type.SCAN, ModuleLoadout.Type.SWEEP, ModuleLoadout.Type.CAMERA], "default fit")


func test_loadout_of_three_types_builds_three_bays() -> void:
	var st: ScienceStation = _station([ModuleLoadout.Type.PROBE, ModuleLoadout.Type.CAMERA, ModuleLoadout.Type.SCAN])
	expect_eq(st.bays.size(), 3, "three bays")
	expect_eq(_types(st), [ModuleLoadout.Type.PROBE, ModuleLoadout.Type.CAMERA, ModuleLoadout.Type.SCAN], "fitted")
	st.queue_free()


func test_changing_loadout_changes_modules() -> void:
	var st: ScienceStation = _station([ModuleLoadout.Type.SCAN, ModuleLoadout.Type.SWEEP, ModuleLoadout.Type.CAMERA])
	st.loadout.fit(1, ModuleLoadout.Type.PROBE)
	expect_eq(_types(st), [ModuleLoadout.Type.SCAN, ModuleLoadout.Type.PROBE, ModuleLoadout.Type.CAMERA], "bay 1 swapped")
	var other: ModuleLoadout = ModuleLoadout.new()
	other.slots = [ModuleLoadout.Type.CAMERA, ModuleLoadout.Type.CAMERA, ModuleLoadout.Type.CAMERA]
	st.loadout = other
	expect_eq(_types(st), [ModuleLoadout.Type.CAMERA, ModuleLoadout.Type.CAMERA, ModuleLoadout.Type.CAMERA], "new loadout")
	st.queue_free()


func test_empty_bay_is_valid() -> void:
	var st: ScienceStation = _station([ModuleLoadout.Type.SCAN, ModuleLoadout.Type.NONE])
	expect_eq(st.bays.size(), 3, "three bays even when slots are short")
	expect(st.bays[1].is_empty() and st.bays[2].is_empty(), "empty bays")
	expect_eq(st.fitted(), [0], "only bay 0 fitted")
	st.loadout.fit(0, ModuleLoadout.Type.NONE)
	expect_eq(st.active, -1, "nothing active")
	st.select_step(1)
	expect_eq(st.active, -1, "selecting with nothing fitted is harmless")
	st.queue_free()


func test_select_wraps_within_fitted() -> void:
	var st: ScienceStation = _station([ModuleLoadout.Type.SCAN, ModuleLoadout.Type.NONE, ModuleLoadout.Type.CAMERA])
	expect_eq(st.active, 0, "starts on first fitted")
	st.select_step(1)
	expect_eq(st.active, 2, "skips the empty bay")
	st.select_step(1)
	expect_eq(st.active, 0, "wraps right")
	st.select_step(-1)
	expect_eq(st.active, 2, "wraps left")
	st.queue_free()


func test_keys_select_and_arm() -> void:
	var st: ScienceStation = _station([ModuleLoadout.Type.SCAN, ModuleLoadout.Type.SWEEP, ModuleLoadout.Type.CAMERA])
	var right: InputEventAction = InputEventAction.new()
	right.action = &"move_right"
	right.pressed = true
	expect(st.handle_event(right), "right used")
	expect_eq(st.active, 1, "moved right")
	var f: InputEventKey = InputEventKey.new()
	f.keycode = ScienceStation.ARM_KEY
	f.pressed = true
	expect(st.handle_event(f), "arm key used")
	expect(st.active_module().armed, "armed")
	st.handle_event(f)
	expect(not st.active_module().armed, "stopped")
	st.queue_free()


func test_step_back_and_second_operator_refused() -> void:
	var st: ScienceStation = _station([ModuleLoadout.Type.SCAN])
	expect(st.request_operator(2), "first operator")
	expect(st.is_operator(2), "is operator")
	expect(not st.request_operator(3), "second refused")
	expect(not st.release_operator(3), "non-operator cannot release")
	expect(st.release_operator(2), "E/Esc steps back")
	expect(st.request_operator(3), "free again")
	st.queue_free()
