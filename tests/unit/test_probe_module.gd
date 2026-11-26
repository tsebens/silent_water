extends TestCase
## ProbeObjective and ProbeModule: lowering into a point's band while still logs a reading after the hold.

var ctrl: SubController
var obj: ProbeObjective
var mod: ProbeModule
var point: Node3D
var log_node: Node
var logged: Array[String] = []


func before_each() -> void:
	ctrl = SubController.new()
	runner.add_child(ctrl)
	ctrl.model.position = Vector3(0, -20, 0)
	ctrl.speed = 0.0
	point = Node3D.new()
	point.name = "Vent"
	runner.add_child(point)
	point.position = Vector3(3, -50, 0)
	obj = ProbeObjective.new()
	obj.controller = ctrl
	obj.points = [point]
	runner.add_child(obj)
	mod = ProbeModule.new()
	mod.objective = obj
	runner.add_child(mod)
	logged.clear()
	log_node = ProbeLogStub.new()
	log_node.sink = logged
	log_node.add_to_group(&"session_log")
	runner.add_child(log_node)


func after_each() -> void:
	for n: Node in [log_node, mod, obj, point, ctrl]:
		n.free()


func test_hold_in_band_logs_reading() -> void:
	mod.armed = true
	obj.lowered = 30.0
	obj.step_hold(ProbeObjective.HOLD_SEC - 1.0)
	expect(logged.is_empty(), "not yet held long enough")
	obj.step_hold(1.1)
	expect(obj.complete, "the only point is read")
	expect(not mod.armed, "winch stands down")
	expect(logged.size() == 1 and logged[0].begins_with("PROBE Vent"), "reading logged")


func test_moving_resets_hold() -> void:
	mod.armed = true
	obj.lowered = 30.0
	obj.step_hold(ProbeObjective.HOLD_SEC - 1.0)
	ctrl.speed = 1.0
	obj.step_hold(0.5)
	expect_eq(obj.hold, 0.0, "movement resets the hold")
	ctrl.speed = 0.0
	obj.step_hold(ProbeObjective.HOLD_SEC - 1.0)
	expect(not obj.complete, "must hold again from the start")


func test_out_of_band_does_not_build() -> void:
	mod.armed = true
	obj.lowered = 5.0
	obj.step_hold(1.0)
	expect_eq(obj.hold, 0.0, "tip too shallow")
	expect_eq(mod.hint(), "LOWER", "hint says lower")
	obj.lowered = 30.0
	ctrl.model.position = Vector3(50, -20, 0)
	obj.step_hold(1.0)
	expect_eq(obj.hold, 0.0, "outside the radius")
	expect_eq(mod.hint(), "TO POINT", "hint says go to the point")
	ctrl.model.position = Vector3(0, -20, 0)
	mod.armed = false
	obj.step_hold(1.0)
	expect_eq(obj.hold, 0.0, "winch not armed")


func test_reel_and_counter_follow_depth() -> void:
	mod.toggle_armed()
	obj.winch_dir = 1
	obj.step_winch(2.0)
	expect_eq(obj.lowered, ProbeObjective.LOWER_SPEED * 2.0, "line pays out")
	expect_eq(mod.counter_m(), obj.lowered, "counter shows depth lowered")
	expect_eq(mod.reel_angle(), obj.lowered * ProbeObjective.REEL_RAD_PER_M, "reel turns with the line")
	expect(obj.noise_intensity() > 0.0, "winch whirs")
	obj.winch_dir = -1
	obj.step_winch(100.0)
	expect_eq(mod.counter_m(), 0.0, "raised to the top")
	obj.winch_dir = 1
	obj.step_winch(100.0)
	expect_eq(obj.lowered, ProbeObjective.MAX_LOWER_M, "line is limited")
	obj.winch_dir = 0
	obj.step_winch(1.0)
	expect_eq(obj.noise_intensity(), 0.0, "quiet when the reel stops")


func test_module_input_winches() -> void:
	mod.toggle_armed()
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	down.pressed = true
	expect(mod.work(down), "wheel used")
	expect_eq(obj.winch_dir, 0, "a wheel notch leaves no winch running")
	expect_eq(obj.lowered, ProbeObjective.WHEEL_STEP_M, "one notch lowers one step")
	obj.step_winch(5.0)
	expect_eq(obj.lowered, ProbeObjective.WHEEL_STEP_M, "line holds after the notch")
	var wheel_up: InputEventMouseButton = InputEventMouseButton.new()
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel_up.pressed = true
	mod.work(wheel_up)
	expect_eq(obj.lowered, 0.0, "one notch raises one step")
	var up: InputEventKey = InputEventKey.new()
	up.keycode = KEY_UP
	up.pressed = true
	mod.work(up)
	expect_eq(obj.winch_dir, -1, "raising")
	up.pressed = false
	mod.work(up)
	expect_eq(obj.winch_dir, 0, "released stops")


func test_unpowered_cannot_arm() -> void:
	mod.set_powered(false)
	mod.toggle_armed()
	expect(not mod.armed, "no power, no winch")


class ProbeLogStub:
	extends Node
	var sink: Array[String]

	func write(msg: String) -> void:
		sink.append(msg)
