extends TestCase
## SweepObjective and SweepModule: coverage, completion, logging and the loud pings.

var ctrl: SubController
var obj: SweepObjective
var mod: SweepModule
var log_node: Node
var logged: Array[String] = []


func before_each() -> void:
	ctrl = SubController.new()
	runner.add_child(ctrl)
	obj = SweepObjective.new()
	obj.controller = ctrl
	obj.area_center = Vector3(0, 0, 0)
	obj.area_size = Vector2(80, 80)
	obj.target_fraction = 0.5
	runner.add_child(obj)
	mod = SweepModule.new()
	mod.objective = obj
	runner.add_child(mod)
	logged.clear()
	log_node = SweepLogStub.new()
	log_node.sink = logged
	log_node.add_to_group(&"session_log")
	runner.add_child(log_node)


func after_each() -> void:
	for n: Node in [log_node, mod, obj, ctrl]:
		n.free()


func _at(x: float, z: float) -> void:
	ctrl.model.position = Vector3(x, 0, z)


func test_unarmed_covers_nothing() -> void:
	_at(0, 0)
	obj._physics_process(0.1)
	expect_eq(obj.coverage(), 0.0, "nothing while disarmed")


func test_armed_covers_only_inside_area() -> void:
	mod.armed = true
	_at(500, 500)
	obj._physics_process(0.1)
	expect_eq(obj.coverage(), 0.0, "outside the area adds nothing")
	_at(-35, -35)
	obj._physics_process(0.1)
	expect(obj.coverage() > 0.0, "inside adds coverage")
	expect(obj.is_covered(0, 0), "the corner cell is covered")
	expect(not obj.is_covered(SweepObjective.GRID - 1, SweepObjective.GRID - 1), "the far corner is not")


func test_completes_at_target_and_is_logged() -> void:
	mod.armed = true
	for x: float in [-30.0, 0.0, 30.0]:
		for z: float in [-30.0, 0.0, 30.0]:
			_at(x, z)
			obj._physics_process(0.1)
	expect(obj.complete, "complete at the target")
	expect(not mod.armed, "module disarmed")
	expect(logged.size() == 1 and logged[0].begins_with("SEABED SWEPT"), "logged")
	var c: float = obj.coverage()
	_at(0, 0)
	obj._physics_process(0.1)
	expect_eq(obj.coverage(), c, "no change once complete")


func test_pings_are_loud_and_reveal() -> void:
	expect_eq(obj.noise_intensity(), 0.0, "quiet when off")
	_at(0, 0)
	var heard: Array[Vector3] = []
	obj.ping.connect(func(p: Vector3) -> void: heard.append(p))
	mod.armed = true
	obj._physics_process(0.1)
	expect(obj.revealing(), "pinging reveals the sub")
	expect(obj.noise_intensity() == SweepObjective.PING_INTENSITY, "adds noise intensity")
	expect_eq(heard.size(), 1, "one ping")
	expect_eq(heard[0], ctrl.model.position, "ping gives the sub's position")
	obj._physics_process(SweepObjective.PING_LENGTH_SEC + 0.1)
	expect_eq(obj.noise_intensity(), 0.0, "quiet between pings")


func test_unpowered_cannot_arm_and_hint() -> void:
	mod.set_powered(false)
	mod.toggle_armed()
	expect(not mod.armed, "no power, no sweep")
	_at(500, 0)
	expect_eq(mod.hint(), "TO AREA", "steer to the area")
	expect_eq(mod.cell_swatch(0, 0), &"sub_screen_off", "unsounded cell")


class SweepLogStub:
	extends Node
	var sink: Array[String]

	func write(msg: String) -> void:
		sink.append(msg)
