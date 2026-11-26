extends TestCase
## PhotoObjective and CameraModule: shot quality from range, light and stillness; the flash; logging.

var ctrl: SubController
var obj: PhotoObjective
var mod: CameraModule
var subject: Node3D
var lamp: Light3D
var log_node: Node
var logged: Array[String] = []


func before_each() -> void:
	ctrl = SubController.new()
	runner.add_child(ctrl)
	ctrl.model.position = Vector3.ZERO
	ctrl.speed = 0.0
	subject = Node3D.new()
	subject.name = "Wreck"
	runner.add_child(subject)
	subject.position = Vector3(0, 0, -10)
	lamp = SpotLight3D.new()
	lamp.visible = false
	runner.add_child(lamp)
	obj = PhotoObjective.new()
	obj.controller = ctrl
	obj.headlight = lamp
	obj.subjects = [subject]
	obj.aim = Vector3(0, 0, -1)
	runner.add_child(obj)
	mod = CameraModule.new()
	mod.objective = obj
	runner.add_child(mod)
	logged.clear()
	log_node = CameraLogStub.new()
	log_node.sink = logged
	log_node.add_to_group(&"session_log")
	runner.add_child(log_node)


func after_each() -> void:
	for n: Node in [log_node, mod, obj, lamp, subject, ctrl]:
		n.free()


func test_quality_rises_with_closeness_light_and_stillness() -> void:
	lamp.visible = true
	expect(obj.quality_at(30.0) < obj.quality_at(15.0), "closer is better")
	expect(obj.quality_at(15.0) < obj.quality_at(5.0) + 0.001, "inside close range is full")
	var lit: float = obj.quality_at(10.0)
	lamp.visible = false
	expect(obj.quality_at(10.0) < lit, "light raises quality")
	lamp.visible = true
	ctrl.speed = 1.0
	expect(obj.quality_at(10.0) < lit, "motion lowers quality")
	ctrl.speed = 0.0
	expect_eq(obj.quality_at(10.0), lit, "still again, full quality")


func test_shot_in_range_logs_reading() -> void:
	lamp.visible = true
	mod.armed = true
	var q: float = obj.take_shot()
	expect(q >= PhotoObjective.GOOD_QUALITY, "a lit, still, close shot is good")
	expect(obj.complete, "the only subject is photographed")
	expect(not mod.armed, "viewfinder closes")
	expect(logged.size() == 1 and logged[0].begins_with("PHOTO Wreck"), "reading logged")


func test_out_of_range_or_frame_logs_nothing() -> void:
	lamp.visible = true
	mod.armed = true
	subject.position = Vector3(0, 0, -100)
	expect_eq(obj.take_shot(), -1.0, "too far")
	subject.position = Vector3(10, 0, 0)
	expect_eq(obj.take_shot(), -1.0, "off frame")
	expect_eq(logged.size(), 0, "nothing logged")
	mod.armed = false
	subject.position = Vector3(0, 0, -10)
	expect_eq(obj.take_shot(), -1.0, "viewfinder closed")


func test_no_light_no_flash_is_poor() -> void:
	mod.armed = true
	var q: float = obj.take_shot()
	expect(q > 0.0 and q < PhotoObjective.GOOD_QUALITY, "dark shot is poor")
	expect(not obj.complete, "a poor shot does not count")
	expect_eq(logged.size(), 1, "but the reading is logged")
	expect_eq(mod.hint(), "LIGHT", "hint asks for light")


func test_flash_adds_light_and_noise() -> void:
	mod.armed = true
	obj.flash_enabled = true
	expect(obj.light_level(true) > PhotoObjective.EXT_LIGHT, "flash is brighter than the lights")
	expect_eq(obj.noise_intensity(), 0.0, "quiet before the shot")
	var q: float = obj.take_shot()
	expect(q >= PhotoObjective.GOOD_QUALITY, "flash rescues a dark shot")
	expect_eq(obj.noise_intensity(), PhotoObjective.FLASH_INTENSITY, "the discharge is heard")
	obj._physics_process(PhotoObjective.FLASH_NOISE_SEC + 0.1)
	expect_eq(obj.noise_intensity(), 0.0, "quiet again")


func test_module_input_aims_and_fires() -> void:
	lamp.visible = true
	mod.toggle_armed()
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.relative = Vector2(200, 0)
	expect(mod.work(move), "mouse motion is used")
	expect(not obj.in_frame(subject), "aimed away")
	expect(not mod.hint().is_empty(), "hint says to aim")
	move.relative = Vector2(-200, 0)
	mod.work(move)
	expect(obj.in_frame(subject), "aimed back")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	expect(mod.work(click), "shutter used")
	expect(obj.complete, "shot taken")


func test_unpowered_cannot_arm() -> void:
	mod.set_powered(false)
	mod.toggle_armed()
	expect(not mod.armed, "no power, no camera")


class CameraLogStub:
	extends Node
	var sink: Array[String]

	func write(msg: String) -> void:
		sink.append(msg)
