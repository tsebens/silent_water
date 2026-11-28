extends TestCase
## The lock-out trunk in the built interior: the controls drive the state machine through the
## outbound and return sequence, and the noise follows it (idle zero, pumps at least the bilge
## pump's intensity, one clank per hatch move).

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")

var interior: Node3D
var trunk: LockoutTrunk
var wiring: LockoutTrunkWiring


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)
	trunk = interior.get_node("LockoutTrunkStation/LockoutTrunk") as LockoutTrunk
	wiring = interior.get_node("LockoutTrunkStation/Wiring") as LockoutTrunkWiring
	Acoustics.recent_events.clear()


func after_each() -> void:
	interior.free()


func _clanks() -> int:
	var n: int = 0
	for e: Dictionary in Acoustics.recent_events:
		if e["kind"] == &"clank":
			n += 1
	return n


## Moves a control to a value the way its drag does: the value changes and the signal fires.
func _move(c: Interactable, v: float) -> void:
	c.state.set_value_silent(v)
	c.value_changed.emit(v)


func test_controls_drive_the_full_sequence() -> void:
	var top: Interactable = wiring.top_wheel
	var flood: Interactable = wiring.flood_valve
	var lever: Interactable = wiring.bottom_lever
	expect_eq(trunk.state, LockoutTrunk.State.DRY_OPEN, "starts dry and open")
	_move(top, 1.0)
	expect_eq(trunk.state, LockoutTrunk.State.DRY_SEALED, "wheel seals the top hatch")
	_move(flood, 1.0)
	expect_eq(trunk.state, LockoutTrunk.State.FLOODING, "valve floods")
	trunk.step(trunk.flood_time + 0.1)
	expect_eq(trunk.state, LockoutTrunk.State.FLOODED, "flooded after the pump run")
	_move(lever, 1.0)
	expect_eq(trunk.state, LockoutTrunk.State.BOTTOM_OPEN, "lever opens the bottom hatch")
	_move(lever, 0.0)
	expect_eq(trunk.state, LockoutTrunk.State.FLOODED, "lever closes the bottom hatch")
	_move(flood, 0.0)
	expect_eq(trunk.state, LockoutTrunk.State.DRAINING, "valve drains")
	trunk.step(trunk.drain_time + 0.1)
	expect_eq(trunk.state, LockoutTrunk.State.DRY_SEALED, "dry after draining")
	_move(top, 0.0)
	expect_eq(trunk.state, LockoutTrunk.State.DRY_OPEN, "wheel opens the top hatch")


func test_out_of_order_controls_do_nothing() -> void:
	_move(wiring.bottom_lever, 1.0)
	expect_eq(trunk.state, LockoutTrunk.State.DRY_OPEN, "bottom hatch cannot open on a dry trunk")
	_move(wiring.flood_valve, 1.0)
	expect_eq(trunk.state, LockoutTrunk.State.DRY_OPEN, "cannot flood with the top open")


func test_climb_is_open_only_with_the_top_hatch_open() -> void:
	var climb: ClimbTransit = wiring.transit
	expect(climb.is_open(), "open when the top hatch is open")
	_move(wiring.top_wheel, 1.0)
	expect(not climb.is_open(), "shut once the top hatch is sealed")


func test_noise_idle_pumping_and_clanks() -> void:
	expect_eq(wiring.noise_intensity(), 0.0, "idle is silent")
	_move(wiring.top_wheel, 1.0)
	expect_eq(_clanks(), 1, "sealing the top clanks once")
	expect_eq(wiring.noise_intensity(), 0.0, "sealed and idle is silent")
	_move(wiring.flood_valve, 1.0)
	expect(wiring.noise_intensity() >= LeakSystem.PUMP_INTENSITY, "pumps at least the bilge pump (%s)" % wiring.noise_intensity())
	expect_eq(_clanks(), 1, "pumping is not a clank")
	trunk.step(trunk.flood_time + 0.1)
	expect_eq(wiring.noise_intensity(), 0.0, "silent when the pumps stop")
	_move(wiring.bottom_lever, 1.0)
	expect_eq(_clanks(), 2, "opening the bottom clanks once")
	_move(wiring.bottom_lever, 0.0)
	expect_eq(_clanks(), 3, "closing the bottom clanks once")
	var pump: SoundEmitter = wiring.pump_emitter
	expect(not pump.active, "pump emitter idle")
	_move(wiring.flood_valve, 0.0)
	wiring._physics_process(0.0)
	expect(pump.active, "pump emitter runs while draining")


func test_trunk_clears_the_program_footprint() -> void:
	var fp: Rect2 = SubLayout.footprint(&"lock_out_trunk")
	for n: Node in [wiring.top_wheel, wiring.flood_valve, wiring.bottom_lever]:
		var p: Vector3 = (n as Node3D).global_position
		expect(not fp.has_point(Vector2(p.x, p.z)), "%s stands outside the hatch footprint" % n.name)
