extends TestCase
## The authored example targets: each objective type can be completed headless by its module, and logs.

const TARGETS: String = "res://src/dive/science_targets.tres"

var ctrl: SubController
var targets: ScienceTargets
var holder: Node
var log_node: Node
var logged: Array[String] = []


func before_each() -> void:
	targets = load(TARGETS) as ScienceTargets
	ctrl = SubController.new()
	runner.add_child(ctrl)
	ctrl.speed = 0.0
	holder = Node.new()
	runner.add_child(holder)
	logged.clear()
	log_node = LogStub.new()
	log_node.sink = logged
	log_node.add_to_group(&"session_log")
	runner.add_child(log_node)


func after_each() -> void:
	for n: Node in [log_node, holder, ctrl]:
		n.free()


func test_resource_is_sound() -> void:
	expect(targets != null, "resource loads")
	expect_eq(targets.problems(), PackedStringArray(), "no authoring problems")


func test_sweep_completes_and_logs() -> void:
	var obj: SweepObjective = SweepObjective.new()
	obj.controller = ctrl
	targets.apply_to(obj, null, null, holder)
	runner.add_child(obj)
	var mod: SweepModule = SweepModule.new()
	mod.objective = obj
	runner.add_child(mod)
	mod.armed = true
	var half: Vector2 = targets.sweep_size * 0.5
	var x: float = -half.x
	while x <= half.x and not obj.complete:
		var z: float = -half.y
		while z <= half.y and not obj.complete:
			ctrl.model.position = Vector3(targets.sweep_center.x + x, 0, targets.sweep_center.z + z)
			obj._physics_process(0.1)
			z += SweepObjective.SWATH_M
		x += SweepObjective.SWATH_M
	expect(obj.complete, "sweep completes")
	expect(logged.any(func(s: String) -> bool: return s.begins_with("SEABED SWEPT")), "sweep logged")
	mod.free()
	obj.free()


func test_every_probe_point_can_be_read() -> void:
	var obj: ProbeObjective = ProbeObjective.new()
	obj.controller = ctrl
	targets.apply_to(null, obj, null, holder)
	runner.add_child(obj)
	var mod: ProbeModule = ProbeModule.new()
	mod.objective = obj
	runner.add_child(mod)
	for p: Node3D in obj.points.duplicate():
		mod.armed = true
		ctrl.model.position = Vector3(p.position.x, -20.0, p.position.z)
		obj.lowered = obj.point_depth(p) - 20.0
		obj.step_hold(ProbeObjective.HOLD_SEC + 0.1)
	expect(obj.complete, "probe completes")
	expect_eq(logged.size(), targets.probe_positions.size(), "one reading per point")
	expect(logged[0].begins_with("PROBE Vent A"), "reading named")
	mod.free()
	obj.free()


func test_every_photo_subject_can_be_shot() -> void:
	var obj: PhotoObjective = PhotoObjective.new()
	obj.controller = ctrl
	var lamp: Light3D = SpotLight3D.new()
	runner.add_child(lamp)
	obj.headlight = lamp
	targets.apply_to(null, null, obj, holder)
	runner.add_child(obj)
	var mod: CameraModule = CameraModule.new()
	mod.objective = obj
	runner.add_child(mod)
	for s: Node3D in obj.subjects.duplicate():
		mod.armed = true
		ctrl.model.position = s.position + Vector3(0, 0, 6)
		obj.aim = Vector3(0, 0, -1)
		expect(obj.take_shot() >= PhotoObjective.GOOD_QUALITY, "good shot of %s" % s.name)
	expect(obj.complete, "photos complete")
	expect_eq(logged.size(), targets.photo_positions.size(), "one log per subject")
	mod.free()
	obj.free()
	lamp.free()


class LogStub:
	extends Node
	var sink: Array[String]

	func write(msg: String) -> void:
		sink.append(msg)
