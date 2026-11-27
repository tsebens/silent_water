extends TestCase
## CameraModule.readout feeds kit gauges with the light and stillness meters.

var ctrl: SubController
var obj: PhotoObjective
var mod: CameraModule


func before_each() -> void:
	ctrl = SubController.new()
	runner.add_child(ctrl)
	obj = PhotoObjective.new()
	obj.controller = ctrl
	obj.aim = Vector3(0, 0, -1)
	runner.add_child(obj)
	mod = CameraModule.new()
	mod.objective = obj
	runner.add_child(mod)


func after_each() -> void:
	for n: Node in [mod, obj, ctrl]:
		n.free()


func test_readouts_match_meters() -> void:
	expect_eq(mod.readout(&"light"), mod.light_meter())
	expect_eq(mod.readout(&"stillness"), mod.stillness_meter())


func test_unknown_readout_is_zero() -> void:
	expect_eq(mod.readout(&"bogus"), 0.0)


func test_in_camera_modules_group() -> void:
	expect(mod.is_in_group(&"camera_modules"))
