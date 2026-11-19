extends TestCase


func test_lever_drag_up_increases() -> void:
	var lever: Lever = Lever.new()
	lever.sensitivity = 0.01
	expect_near(lever._drag_to_value(0.5, Vector2(0, -10)), 0.6)
	lever.free()


func test_valve_clockwise_circle_opens_by_one_turn() -> void:
	var valve: Valve = Valve.new()
	valve.turns_full_range = 4.0
	var v: float = 0.0
	# Trace a clockwise circle on screen (y down) in 64 steps.
	var steps: int = 64
	var r: float = 120.0
	for i: int in range(steps):
		var a0: float = TAU * float(i) / steps
		var a1: float = TAU * float(i + 1) / steps
		var rel: Vector2 = Vector2(cos(a1), sin(a1)) * r - Vector2(cos(a0), sin(a0)) * r
		v = valve._drag_to_value(v, rel)
	expect_near(v, 0.25, 0.012, "one turn of four (first step only sets direction)")
	valve.free()


func test_valve_counter_clockwise_closes() -> void:
	var valve: Valve = Valve.new()
	var v: float = 0.5
	# A counter-clockwise quarter circle on screen.
	for i: int in range(16):
		var a0: float = -TAU * float(i) / 64.0
		var a1: float = -TAU * float(i + 1) / 64.0
		v = valve._drag_to_value(v, Vector2(cos(a1), sin(a1)) * 150.0 - Vector2(cos(a0), sin(a0)) * 150.0)
	expect(v < 0.5)
	valve.free()
