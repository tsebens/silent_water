extends TestCase
## The generated joystick: a boot on the plate and a separate stick that JoystickIndicator can tilt.

const SCENE: String = "res://assets/models/kit/joystick/joystick.tscn"


func _make() -> Node3D:
	var j: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(j)
	return j


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c: Node in n.get_children():
		var m: MeshInstance3D = _first_mesh(c)
		if m != null:
			return m
	return null


## The stick's top, in the scene root's frame.
func _top(j: Node3D) -> Vector3:
	var mi: MeshInstance3D = _first_mesh(j.get_node("Frame/Stick"))
	var aabb: AABB = mi.get_aabb()
	var far: Vector3 = aabb.position + Vector3(aabb.size.x * 0.5, aabb.size.y, aabb.size.z * 0.5)
	return j.global_transform.affine_inverse() * mi.global_transform * far


func test_scene_has_a_separate_stick() -> void:
	var j: Node3D = _make()
	expect(j.get_node_or_null("Boot") != null, "boot")
	expect(j.get_node_or_null("Frame/Stick") != null, "stick under Frame")
	expect(not j.get_node("Boot").is_ancestor_of(j.get_node("Frame/Stick")), "stick is not part of the boot")
	j.queue_free()


func test_stick_rises_from_the_origin_along_z() -> void:
	var j: Node3D = _make()
	var top: Vector3 = _top(j)
	expect(top.z > 0.08 and absf(top.x) < 0.001 and absf(top.y) < 0.01, "stick top is straight up +Z: %s" % top)
	j.queue_free()


func test_indicator_can_tilt_it_and_it_stays_over_the_boot() -> void:
	var j: Node3D = _make()
	var ind: JoystickIndicator = JoystickIndicator.new()
	ind.stick = j.get_node("Frame/Stick") as Node3D
	j.add_child(ind)
	var axis: SpringAxis = SpringAxis.new()
	runner.add_child(axis)
	ind.fore_aft = axis
	var flat: Vector3 = _top(j)
	axis._set_local(1.0, true)
	ind.refresh()
	var tilted: Vector3 = _top(j)
	expect(tilted.distance_to(flat) > 0.01, "the stick moved: %s vs %s" % [tilted, flat])
	expect(tilted.z > 0.08, "still standing up at full tilt")
	expect(absf(tilted.x) < 0.001, "pitch leans in one plane")
	axis.queue_free()
	ind.queue_free()
	j.queue_free()
