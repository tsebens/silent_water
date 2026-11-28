extends TestCase
## Impaired walking: wander and slowdown scale with strength, vanish at zero, stay continuous.

var m: ImpairmentModel


func before_each() -> void:
	m = ImpairmentModel.new(load("res://src/life_support/impairment_params.tres") as ImpairmentParams)


func test_zero_impairment_is_unchanged() -> void:
	m.strength = 0.0
	var input: Vector2 = Vector2(0.3, -0.9)
	for t: float in [0.0, 1.3, 7.7]:
		expect(Player.impaired_input(input, m, t) == input)
	expect_near(Player.impaired_speed(2.6, m), 2.6)


func test_below_start_is_unchanged() -> void:
	m.strength = 0.15
	expect(Player.impaired_input(Vector2(0, -1), m, 2.0) == Vector2(0, -1))


func test_no_input_no_wander() -> void:
	m.strength = 1.0
	expect(Player.impaired_input(Vector2.ZERO, m, 2.0) == Vector2.ZERO)


func test_wander_and_slowdown_grow_with_strength() -> void:
	var prev_w: float = -1.0
	var prev_s: float = 99.0
	var s: float = 0.0
	while s <= 1.0001:
		m.strength = s
		var w: float = Player.impaired_wander(Vector2(0, -1), m, 0.9).length()
		var sp: float = Player.impaired_speed(2.6, m)
		expect(w >= prev_w - 0.000001, "wander monotonic at %f" % s)
		expect(sp <= prev_s + 0.000001, "speed loss monotonic at %f" % s)
		prev_w = w
		prev_s = sp
		s += 0.05
	expect(prev_w > 0.1)
	expect(prev_s < 2.6)


func test_continuous_in_time() -> void:
	m.strength = 1.0
	var prev: Vector2 = Player.impaired_input(Vector2(0, -1), m, 0.0)
	var t: float = 0.01
	while t < 10.0:
		var cur: Vector2 = Player.impaired_input(Vector2(0, -1), m, t)
		expect(cur.distance_to(prev) < 0.1, "continuous at %f" % t)
		prev = cur
		t += 0.01


func test_deterministic() -> void:
	m.strength = 0.8
	expect(Player.impaired_input(Vector2(1, 0), m, 3.3) == Player.impaired_input(Vector2(1, 0), m, 3.3))


func test_seated_player_input_unchanged() -> void:
	# The seated branches return before the impairment is applied: the helm drive
	# reads the raw input. Check the order in the source so it cannot regress.
	var src: String = FileAccess.get_file_as_string("res://src/player/player.gd")
	var seat_at: int = src.find("(_seat as PilotSeat).drive(")
	var apply_at: int = src.find("impaired_input(input,")
	expect(seat_at > 0 and apply_at > seat_at, "impairment applied only after seated branches")
