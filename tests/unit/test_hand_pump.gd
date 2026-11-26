extends TestCase
## HandPump: stroke cycle, water removed, springing back, no noise.

const STEP: float = 1.0 / 60.0


class StubLeaks:
	extends Node
	var bailed: float = 0.0

	func manual_bail(t: float) -> void:
		bailed += t


func _make() -> Array:
	var l: StubLeaks = StubLeaks.new()
	runner.add_child(l)
	var p: HandPump = HandPump.new()
	p.leaks = l
	runner.add_child(p)
	return [p, l]


func _free(a: Array) -> void:
	for n: Node in a:
		n.queue_free()


## One steady cycle: hold the down stroke, release, spring back, refill.
func _cycle(p: HandPump) -> void:
	var t: float = 0.0
	while t < HandPump.DOWN_SEC:
		p.step(STEP, true)
		t += STEP
	t = 0.0
	while t < HandPump.SPRING_SEC + HandPump.REFILL_SEC + 0.05:
		p.step(STEP, false)
		t += STEP


func test_one_cycle_removes_expected_water() -> void:
	var a: Array = _make()
	_cycle(a[0])
	expect_near((a[1] as StubLeaks).bailed, HandPump.TONNES_PER_STROKE, 0.002)
	_free(a)


func test_idle_removes_nothing() -> void:
	var a: Array = _make()
	for i: int in range(120):
		(a[0] as HandPump).step(STEP, false)
	expect_eq((a[1] as StubLeaks).bailed, 0.0)
	_free(a)


func test_refill_beat_removes_nothing() -> void:
	var a: Array = _make()
	var p: HandPump = a[0]
	var l: StubLeaks = a[1]
	var t: float = 0.0
	while t < HandPump.DOWN_SEC + 0.1:
		p.step(STEP, true)
		t += STEP
	t = 0.0
	while p.phase != HandPump.Phase.REFILL and t < 2.0:
		p.step(STEP, false)
		t += STEP
	expect(p.phase == HandPump.Phase.REFILL, "reached refill")
	var before: float = l.bailed
	# Holding during the refill beat does nothing.
	for i: int in range(20):
		p.step(STEP, true)
	expect_eq(l.bailed, before)
	expect_eq(p.get_value(), 0.0)
	_free(a)


func test_lever_springs_back_on_release() -> void:
	var a: Array = _make()
	var p: HandPump = a[0]
	for i: int in range(20):
		p.step(STEP, true)
	expect(p.get_value() > 0.2, "pushed down")
	for i: int in range(int(HandPump.SPRING_SEC / STEP) + 3):
		p.step(STEP, false)
	expect_eq(p.get_value(), 0.0)
	_free(a)


func test_ten_seconds_steady_averages_035() -> void:
	var a: Array = _make()
	var p: HandPump = a[0]
	for i: int in range(6):
		_cycle(p)
	# Six cycles of exactly CYCLE_SEC (the 0.05 s slack per cycle is idle time).
	var rate: float = (a[1] as StubLeaks).bailed / (6.0 * (HandPump.CYCLE_SEC + 0.05))
	expect(absf(rate - 0.035) <= 0.0035, "rate %f" % rate)
	var ideal: float = HandPump.TONNES_PER_STROKE / HandPump.CYCLE_SEC
	expect_near(ideal, 0.035, 0.0035)
	_free(a)


func test_no_noise() -> void:
	var a: Array = _make()
	var p: HandPump = a[0]
	for i: int in range(30):
		p.step(STEP, true)
	expect_eq(p.noise_intensity(), 0.0)
	_free(a)


func test_leak_system_noise_unaffected_by_manual_bail() -> void:
	var game: Game = (load("res://src/game/game.tscn") as PackedScene).instantiate() as Game
	runner.add_child(game)
	game.start_session()
	var leaks: LeakSystem = game.get_node("LeakSystem") as LeakSystem
	var ctl: SubController = game.get_node("SubController") as SubController
	ctl.model.bilge_water_t = 2.0
	var before: float = leaks.noise_intensity()
	leaks.manual_bail(0.5)
	expect(ctl.model.bilge_water_t < 2.0, "bailed")
	expect_eq(leaks.noise_intensity(), before)
	game.end_session()
	game.free()
