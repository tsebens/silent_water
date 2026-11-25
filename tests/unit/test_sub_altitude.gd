extends TestCase
## Height above the sea floor: a ray straight down to the exterior collision,
## computed locally (nothing replicated).

var frame: SubFrame
var ctl: SubController
var world: Node3D


func before_each() -> void:
	world = Node3D.new()
	runner.add_child(world)
	frame = SubFrame.new()
	frame.world_root = world
	runner.add_child(frame)
	ctl = SubController.new()
	ctl.sub_frame = frame
	ctl.enabled = false
	runner.add_child(ctl)


func after_each() -> void:
	ctl.free()
	frame.free()
	world.free()


func _add_floor(top_y: float) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = SubController.LAYER_EXTERIOR
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2000, 2, 2000)
	shape.shape = box
	body.add_child(shape)
	body.position = Vector3(0, top_y - 1.0, 0)
	world.add_child(body)


func _physics_frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func test_altitude_at_two_heights() -> void:
	_add_floor(-100.0)
	frame.set_pose(Transform3D(Basis(), Vector3(0, -50, 0)))
	await _physics_frames(2)
	expect_near(ctl.readout(&"altitude"), 50.0, 0.01, "50 m up")
	frame.set_pose(Transform3D(Basis(), Vector3(0, -70, 0)))
	await _physics_frames(2)
	expect_near(ctl.readout(&"altitude"), 30.0, 0.01, "30 m up")


func test_altitude_clamps_when_nothing_below() -> void:
	frame.set_pose(Transform3D(Basis(), Vector3(0, -50, 0)))
	await _physics_frames(2)
	expect_eq(ctl.readout(&"altitude"), SubController.ALTITUDE_MAX, "clamped")


func test_altitude_is_not_replicated_state() -> void:
	var names: Array[String] = []
	for prop: Dictionary in ctl.get_property_list():
		names.append(prop["name"] as String)
	expect(not names.has("altitude"), "no altitude property to sync")
