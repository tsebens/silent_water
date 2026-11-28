extends TestCase
## DorsalHatch: opens at the surface or when mated, refuses underwater, closes itself (with the chime) when the
## sub dives, gates the tower's climb, takes the wheel, and replicates to a client.

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")

var interior: Node3D
var hatch: DorsalHatch
var opened: int = 0
var closed: int = 0


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)
	hatch = interior.get_node("DorsalHatchStation/DorsalHatch") as DorsalHatch
	hatch.depth_override = 0.0
	opened = 0
	closed = 0
	hatch.hatch_opened.connect(func() -> void: opened += 1)
	hatch.hatch_closed.connect(func() -> void: closed += 1)
	Acoustics.recent_events.clear()


func after_each() -> void:
	interior.free()


func _events(kind: StringName) -> int:
	var n: int = 0
	for e: Dictionary in Acoustics.recent_events:
		if e["kind"] == kind:
			n += 1
	return n


func test_opens_at_the_surface() -> void:
	expect(hatch.request_open(), "opens with the sub at the surface")
	expect(hatch.is_open)
	expect_eq(opened, 1, "hatch_opened fires")
	expect_eq(_events(&"clank"), 1, "one clank")
	expect(hatch.request_close(), "closes by hand")
	expect_eq(closed, 1, "hatch_closed fires")
	expect_eq(_events(&"clank"), 2, "and another clank")


func test_refuses_at_depth() -> void:
	hatch.depth_override = 30.0
	expect(not hatch.request_open(), "refuses underwater")
	expect(not hatch.is_open)
	expect_eq(opened, 0)


func test_unknown_depth_counts_as_deep() -> void:
	hatch.depth_override = -1.0
	expect(not hatch.request_open(), "no sub controller in this scene: shut")


func test_opens_at_depth_when_mated() -> void:
	hatch.depth_override = 30.0
	hatch.set_mated(true)
	expect(hatch.request_open(), "opens at depth while mated")
	expect(hatch.is_open)


func test_a_dive_closes_it_with_the_chime() -> void:
	hatch.request_open()
	hatch.depth_override = 12.0
	Acoustics.recent_events.clear()
	expect(hatch.check_dive(), "the dive closes it")
	expect(not hatch.is_open)
	expect_eq(closed, 1, "hatch_closed fires")
	expect(Acoustics.recent_events.size() >= 2, "a clank and the chime, got %d events" % Acoustics.recent_events.size())


func test_a_dive_while_mated_leaves_it_open() -> void:
	hatch.set_mated(true)
	hatch.depth_override = 30.0
	hatch.request_open()
	expect(not hatch.check_dive(), "mated: stays open")
	hatch.set_mated(false)
	expect(hatch.check_dive(), "unmated at depth: closes")


func test_the_climb_is_gated_on_the_hatch() -> void:
	var climb: ClimbTransit = interior.get_node("DorsalHatchStation/Climb") as ClimbTransit
	expect(not climb.is_open(), "shut hatch, blocked ladder")
	hatch.request_open()
	expect(climb.is_open(), "open hatch, open ladder")
	expect(climb.extra_bounds.size != Vector3.ZERO, "the tower transit declares its extra bounds")


func test_the_wheel_works_the_hatch() -> void:
	var wheel: Valve = hatch.wheel
	wheel.state.set_value_silent(1.0)
	wheel.value_changed.emit(1.0)
	expect(hatch.is_open, "wheel to the end opens")
	wheel.state.set_value_silent(0.0)
	wheel.value_changed.emit(0.0)
	expect(not hatch.is_open, "wheel back closes")
	hatch.depth_override = 20.0
	wheel.state.set_value_silent(1.0)
	wheel.value_changed.emit(1.0)
	expect(not hatch.is_open, "wheel does nothing underwater")


func test_state_replicates_to_a_client() -> void:
	var client: DorsalHatch = DorsalHatch.new()
	client.simulate_client = true
	runner.add_child(client)
	var got: Array[int] = [0, 0]
	client.hatch_opened.connect(func() -> void: got[0] += 1)
	client.hatch_closed.connect(func() -> void: got[1] += 1)
	hatch.set_mated(true)
	hatch.request_open()
	client.apply_snapshot(hatch.snapshot())
	expect(client.is_open, "client sees it open")
	expect(client.mated, "client sees mated")
	expect_eq(got[0], 1, "client hears hatch_opened")
	expect(not client.request_open(), "a client does not act on its own")
	hatch.request_close()
	client.apply_snapshot(hatch.snapshot())
	expect(not client.is_open, "client sees it closed")
	expect_eq(got[1], 1, "client hears hatch_closed")
	client.free()
