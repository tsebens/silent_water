extends TestCase
## Map table control behaviours: PanBall, ZoomLever, IndicatorLamp.

var _rolls: Array[Vector2] = []
var _rates: Array[float] = []
var _lit: Array[bool] = []


func _on_rolled(d: Vector2) -> void:
	_rolls.append(d)


func _on_rate(r: float) -> void:
	_rates.append(r)


func _on_lit(v: bool) -> void:
	_lit.append(v)


func test_pan_ball_roll_delta_scales_the_drag() -> void:
	var p: PanBall = PanBall.new()
	p.roll_per_px = 0.5
	expect_eq(p.roll_delta(Vector2(4, -2)), Vector2(2, -1), "2D delta, both axes")
	p.free()


func test_pan_ball_emits_roll_while_held() -> void:
	var p: PanBall = PanBall.new()
	p.rolled.connect(_on_rolled)
	p.drag(Vector2(10, 10))
	expect_eq(_rolls.size(), 0, "ignored when not held")
	p._local_grabbing = true
	p.roll_per_px = 0.1
	p.drag(Vector2(10, -20))
	expect_eq(_rolls.size(), 1, "one signal per drag")
	expect_near(_rolls[0].x, 1.0, 1e-6)
	expect_near(_rolls[0].y, -2.0, 1e-6)
	p.free()


func test_pan_ball_ball_turns() -> void:
	var p: PanBall = PanBall.new()
	var ball: Node3D = Node3D.new()
	p.add_child(ball)
	p.ball = ball
	p._local_grabbing = true
	p.roll_per_px = 1.0
	p.drag(Vector2(0.5, 0))
	expect_near(ball.rotation.y, 0.5, 1e-5, "rolls about up")
	p.free()


func test_zoom_lever_range_and_spring() -> void:
	var z: ZoomLever = ZoomLever.new()
	expect_eq(z.min_value, -1.0)
	expect_eq(z.max_value, 1.0)
	expect_eq(z._release_value(0.8), 0.0, "springs to centre on release")
	expect(z._drag_to_value(0.0, Vector2(0, -50)) > 0.0, "up zooms in")
	z.free()


func test_zoom_lever_emits_rate() -> void:
	var z: ZoomLever = ZoomLever.new()
	z.zoom_rate_changed.connect(_on_rate)
	z.state = InteractableState.new(-1.0, 1.0, 0.0)
	z.state.set_value(0.6)
	z._after_change()
	expect_eq(_rates.size(), 1)
	expect_near(_rates[0], 0.6, 1e-6)
	expect_near(z.zoom_rate(), 0.6, 1e-6)
	z.free()


func test_indicator_lamp_follows_bool() -> void:
	var l: IndicatorLamp = IndicatorLamp.new()
	l.lit_changed.connect(_on_lit)
	l.set_lit(true)
	l.set_lit(true)
	l.set_lit(false)
	expect_eq(_lit, [true, false], "signals only on change")
	expect(not l.is_lit())
	l.free()


func test_indicator_lamp_switches_emission() -> void:
	var l: IndicatorLamp = IndicatorLamp.new()
	var m: MeshInstance3D = MeshInstance3D.new()
	m.mesh = BoxMesh.new()
	m.material_override = StandardMaterial3D.new()
	l.add_child(m)
	l.lamp = m
	l.lit_energy = 3.0
	l.set_lit(true)
	var mat: StandardMaterial3D = m.material_override as StandardMaterial3D
	expect(mat.emission_enabled, "lit glows")
	expect_near(mat.emission_energy_multiplier, 3.0, 1e-6)
	l.set_lit(false)
	expect(not (m.material_override as StandardMaterial3D).emission_enabled, "unlit dark")
	l.free()
