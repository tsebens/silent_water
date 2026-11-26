extends TestCase
## SwitchLever's optional indicator lamp.


func _lamp() -> IndicatorLamp:
	var l: IndicatorLamp = IndicatorLamp.new()
	runner.add_child(l)
	return l


func _lever(lamp: IndicatorLamp, start: float) -> SwitchLever:
	var s: SwitchLever = SwitchLever.new()
	s.indicator = lamp
	s.initial_value = start
	runner.add_child(s)
	return s


func test_lamp_follows_lever() -> void:
	var lamp: IndicatorLamp = _lamp()
	var s: SwitchLever = _lever(lamp, 0.0)
	expect(not lamp.is_lit(), "off at start: dark")
	s.host_set_value(1.0)
	expect(lamp.is_lit(), "moved on: lit")
	s.host_set_value(0.0)
	expect(not lamp.is_lit(), "moved off: dark")
	s.queue_free()
	lamp.queue_free()


func test_starting_value_is_honoured() -> void:
	var lamp: IndicatorLamp = _lamp()
	var s: SwitchLever = _lever(lamp, 1.0)
	expect(lamp.is_lit(), "starts on: lit at _ready")
	s.queue_free()
	lamp.queue_free()


func test_unset_indicator_changes_nothing() -> void:
	var s: SwitchLever = _lever(null, 0.0)
	s.host_set_value(1.0)
	expect(is_equal_approx(s.get_value(), 1.0), "moves normally with no lamp")
	s.queue_free()
