extends TestCase
## ScanModule arms ScanObjective like the wall switch does.

var ctrl: SubController
var target: Node3D
var obj: ScanObjective
var mod: ScanModule


func before_each() -> void:
	ctrl = SubController.new()
	runner.add_child(ctrl)
	target = Node3D.new()
	runner.add_child(target)
	obj = ScanObjective.new()
	obj.controller = ctrl
	obj.target = target
	runner.add_child(obj)
	mod = ScanModule.new()
	mod.objective = obj
	runner.add_child(mod)


func after_each() -> void:
	for n: Node in [mod, obj, target, ctrl]:
		n.free()


func _place(dist: float, speed: float) -> void:
	ctrl.model.position = target.position + Vector3(dist, 0, 0)
	ctrl.speed = speed


func test_arming_builds_progress_in_range_and_still() -> void:
	_place(10.0, 0.0)
	mod.armed = true
	expect(obj.scanner_on(), "module arms the scan")
	obj._physics_process(1.0)
	expect_near(obj.progress, 1.0 / ScanObjective.SCAN_TIME_SEC, 0.001, "builds")
	expect(obj.noise_intensity() == ScanObjective.SCAN_INTENSITY, "loud as ever")


func test_drains_when_out_of_range_or_moving() -> void:
	obj.progress = 0.5
	_place(100.0, 0.0)
	mod.armed = true
	obj._physics_process(1.0)
	expect(obj.progress < 0.5, "drains out of range")
	obj.progress = 0.5
	_place(10.0, 3.0)
	obj._physics_process(1.0)
	expect(obj.progress < 0.5, "drains when moving")


func test_not_armed_does_not_scan() -> void:
	_place(10.0, 0.0)
	expect(not obj.scanner_on(), "off")
	expect_eq(obj.noise_intensity(), 0.0, "quiet")


func test_hint_closer_out_of_range_and_ring_tracks_progress() -> void:
	_place(100.0, 0.0)
	expect_eq(mod.hint(), "CLOSER", "closer")
	expect_near(mod.range_m(), 100.0, 0.01, "range")
	_place(10.0, 0.0)
	expect_eq(mod.hint(), "", "no hint in position")
	obj.progress = 0.4
	expect_near(mod.ring(), 0.4, 0.0001, "ring")
	expect_near(mod.health(), 0.4, 0.0001, "health")


func test_completion_disarms_module() -> void:
	_place(10.0, 0.0)
	obj.progress = 0.999
	mod.armed = true
	obj._physics_process(1.0)
	expect(obj.complete, "complete")
	expect(not mod.armed, "module disarmed")


func test_unpowered_module_cannot_arm() -> void:
	mod.set_powered(false)
	mod.toggle_armed()
	expect(not mod.armed, "no power, no scan")
