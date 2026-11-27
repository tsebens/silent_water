extends TestCase
## BreakerSwitch: state display and the requests a click sends.

const B := PowerSystem.BreakerState
const C := PowerSystem.Circuit


class StubPower:
	extends Node
	var state: int = PowerSystem.BreakerState.ON
	var spares: int = 4
	var log: Array = []

	func readout(n: StringName) -> float:
		if n == &"spares_remaining":
			return float(spares)
		return float(state)

	func request_breaker(c: int, on: bool) -> void:
		log.append(["breaker", c, on])

	func request_replace(c: int) -> void:
		log.append(["replace", c])


func _make(state: int, spares: int = 4) -> Array:
	var p: StubPower = StubPower.new()
	p.state = state
	p.spares = spares
	runner.add_child(p)
	var s: BreakerSwitch = BreakerSwitch.new()
	s.circuit = C.SONAR
	s.power = p
	s.handle = Node3D.new()
	s.add_child(s.handle)
	s.lamp = MeshInstance3D.new()
	s.add_child(s.lamp)
	runner.add_child(s)
	return [s, p]


func _free(a: Array) -> void:
	(a[0] as Node).queue_free()
	(a[1] as Node).queue_free()


func test_states_give_handle_and_lamp() -> void:
	var swatches: Array = [&"", &"light_ok", &"light_warn", &"light_alarm"]
	for st: int in [B.OFF, B.ON, B.TRIPPED, B.BLOWN]:
		var a: Array = _make(st)
		var s: BreakerSwitch = a[0]
		expect_eq(s.current_state(), st)
		expect(is_equal_approx(rad_to_deg(s.handle.rotation.x), s.handle_angles_deg[st]), "handle angle for %d" % st)
		expect_eq(BreakerSwitch.lamp_swatch(st), swatches[st])
		var mat: StandardMaterial3D = s.lamp.material_override as StandardMaterial3D
		expect(mat != null and mat.emission_enabled == (st != B.OFF), "lamp emission for %d" % st)
		_free(a)
	var up: float = BreakerSwitch.new().handle_angle_deg(B.ON)
	expect(up > BreakerSwitch.new().handle_angle_deg(B.TRIPPED), "on above tripped")
	expect(BreakerSwitch.new().handle_angle_deg(B.TRIPPED) > BreakerSwitch.new().handle_angle_deg(B.OFF), "tripped above off")


func test_click_on_switches_off() -> void:
	var a: Array = _make(B.ON)
	(a[0] as BreakerSwitch).begin_interaction()
	expect_eq((a[1] as StubPower).log, [["breaker", C.SONAR, false]])
	_free(a)


func test_click_off_and_tripped_switch_on() -> void:
	for st: int in [B.OFF, B.TRIPPED]:
		var a: Array = _make(st)
		(a[0] as BreakerSwitch).begin_interaction()
		expect_eq((a[1] as StubPower).log, [["breaker", C.SONAR, true]])
		_free(a)


func test_click_blown_replaces_with_spares() -> void:
	var a: Array = _make(B.BLOWN, 2)
	(a[0] as BreakerSwitch).begin_interaction()
	expect_eq((a[1] as StubPower).log, [["replace", C.SONAR]])
	_free(a)


func test_click_blown_without_spares_sends_nothing() -> void:
	var a: Array = _make(B.BLOWN, 0)
	(a[0] as BreakerSwitch).begin_interaction()
	expect_eq((a[1] as StubPower).log.size(), 0)
	_free(a)
