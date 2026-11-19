extends TestCase


func _circle(t: CrankTracker, radius: float, steps: int, clockwise: bool = true, turns: float = 1.0) -> float:
	var total: float = 0.0
	var dirn: float = 1.0 if clockwise else -1.0
	var n: int = int(steps * turns)
	for i: int in range(n):
		var a0: float = dirn * TAU * float(i) / steps
		var a1: float = dirn * TAU * float(i + 1) / steps
		total += t.feed(Vector2(cos(a1), sin(a1)) * radius - Vector2(cos(a0), sin(a0)) * radius)
	return total


func test_small_circle_is_one_turn() -> void:
	expect_near(_circle(CrankTracker.new(), 60.0, 48), 1.0, 0.05)


func test_wide_fast_circle_is_one_turn_not_doubling_back() -> void:
	# A 700 px circle in 16 big steps (~275 px each): the old orbit doubled back.
	expect_near(_circle(CrankTracker.new(), 700.0, 16), 1.0, 0.08)


func test_counter_clockwise_is_negative() -> void:
	expect_near(_circle(CrankTracker.new(), 200.0, 40, false), -1.0, 0.05)


func test_several_turns_accumulate() -> void:
	expect_near(_circle(CrankTracker.new(), 300.0, 30, true, 3.0), 3.0, 0.15)


func test_straight_drag_is_no_turn() -> void:
	var t: CrankTracker = CrankTracker.new()
	var total: float = 0.0
	for i: int in range(50):
		total += t.feed(Vector2(12, 3))
	expect_near(total, 0.0, 0.001)


func test_jitter_does_nothing() -> void:
	var t: CrankTracker = CrankTracker.new()
	var total: float = 0.0
	for i: int in range(200):
		total += t.feed(Vector2(1, -1) if i % 2 == 0 else Vector2(-1, 1))
	expect_near(total, 0.0, 0.001)
