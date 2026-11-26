extends TestCase
## GeneratorLink: the switch sends start/stop; the generator's state moves the switch.


class StubPower:
	extends Node
	var running: bool = false
	var log: Array = []

	func readout(n: StringName) -> float:
		return 1.0 if n == &"generator_running" and running else 0.0

	func request_generator(run: bool) -> void:
		log.append(run)


func _make(running: bool = false) -> Array:
	var p: StubPower = StubPower.new()
	p.running = running
	runner.add_child(p)
	var sw: SwitchLever = SwitchLever.new()
	runner.add_child(sw)
	var link: GeneratorLink = GeneratorLink.new()
	link.power = p
	link.switch_lever = sw
	runner.add_child(link)
	return [link, sw, p]


func _free(a: Array) -> void:
	for n: Node in a:
		n.queue_free()


func test_switch_sends_start_and_stop() -> void:
	var a: Array = _make()
	var sw: SwitchLever = a[1]
	sw.begin_interaction()
	sw.drive_to(sw.max_value)
	sw.drive_to(sw.min_value)
	sw.end_interaction()
	expect_eq((a[2] as StubPower).log, [true, false])
	_free(a)


func test_running_change_moves_switch_without_request() -> void:
	var a: Array = _make()
	var link: GeneratorLink = a[0]
	var sw: SwitchLever = a[1]
	var p: StubPower = a[2]
	expect_eq(sw.get_value(), sw.min_value)
	p.running = true
	link._process(0.0)
	expect_eq(sw.get_value(), sw.max_value)
	p.running = false
	link._process(0.0)
	expect_eq(sw.get_value(), sw.min_value)
	expect_eq(p.log.size(), 0)
	_free(a)


func test_starts_in_step_with_running_generator() -> void:
	var a: Array = _make(true)
	expect_eq((a[1] as SwitchLever).get_value(), (a[1] as SwitchLever).max_value)
	expect_eq((a[2] as StubPower).log.size(), 0)
	_free(a)
