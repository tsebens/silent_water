extends TestCase
## Speed gauge scale from the physics model: top forward speed, and the Gauge
## export that takes a symmetric scale from a readout.


class FakeSource:
	extends Node
	var top: float = 3.0

	func readout(_name: StringName) -> float:
		return top


func _source(top: float) -> FakeSource:
	var s: FakeSource = FakeSource.new()
	s.top = top
	s.add_to_group(&"sub_readouts")
	runner.add_child(s)
	return s


func test_top_speed_is_terminal_speed() -> void:
	var m: SubPhysicsModel = SubPhysicsModel.new()
	m.position = Vector3(0, -50, 0)
	m.tank_water_t = (m.displacement_t - m.dry_mass_t - m.payload_t)
	expect_near(m.top_forward_speed(), 3.0, 0.05)
	var before: float = m.top_forward_speed()
	for i: int in range(60 * 600):
		m.velocity.y = 0.0
		m.step(1.0 / 60.0, 1.0, 0.0, 0.0, 0.0, 0.0)
		m.position.y = -50.0
	expect_near(m.forward_speed(), before, 0.02, "terminal speed at full ahead")
	m.thrust_accel *= 4.0
	expect_near(m.top_forward_speed(), before * 2.0, 0.001, "changes with thrust_accel")


func test_controller_exposes_top_speed() -> void:
	var c: SubController = SubController.new()
	c.enabled = false
	runner.add_child(c)
	expect_near(c.readout(&"top_speed"), c.model.top_forward_speed())
	c.free()


func test_gauge_takes_symmetric_scale() -> void:
	var src: FakeSource = _source(2.5)
	var g: Gauge = Gauge.new()
	g.scale_readout = &"top_speed"
	runner.add_child(g)
	expect_near(g.min_value, -2.5)
	expect_near(g.max_value, 2.5)
	src.free()


func test_gauge_without_export_unchanged() -> void:
	var src: FakeSource = _source(2.5)
	var g: Gauge = Gauge.new()
	runner.add_child(g)
	expect_near(g.min_value, 0.0)
	expect_near(g.max_value, 100.0)
	src.free()
