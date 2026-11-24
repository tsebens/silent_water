extends TestCase
## The kit toggle switch (Onshape import): the bat pivots on its hinge and stays inside the guard.

const SCENE: String = "res://assets/models/kit/toggle_switch/toggle_switch.tscn"


func _make() -> SwitchLever:
	var sw: SwitchLever = (load(SCENE) as PackedScene).instantiate() as SwitchLever
	runner.add_child(sw)
	return sw


func _bat_tip(sw: SwitchLever) -> Vector3:
	# The far end of the bat from the hinge, in the switch's frame.
	var bat: MeshInstance3D = sw.get_node("Model/Pivot/Switch") as MeshInstance3D
	var aabb: AABB = bat.get_aabb()
	var far: Vector3 = aabb.position + Vector3(aabb.size.x * 0.5, aabb.size.y * 0.5, aabb.size.z)
	return sw.global_transform.affine_inverse() * bat.global_transform * far


func test_scene_wires_the_pivot() -> void:
	var sw: SwitchLever = _make()
	expect(sw.pivot != null, "pivot is set")
	expect_eq(sw.pivot.name, &"Pivot")
	expect(sw.get_node_or_null("Model/Pivot/Switch") != null, "bat mesh under the pivot")
	sw.queue_free()


func test_on_is_bat_up_and_off_is_bat_down() -> void:
	var sw: SwitchLever = _make()
	sw.host_set_value(sw.max_value)
	var up: Vector3 = _bat_tip(sw)
	sw.host_set_value(sw.min_value)
	var down: Vector3 = _bat_tip(sw)
	expect(up.y > 0.02, "on: tip above the hinge (%s)" % up)
	expect(down.y < -0.02, "off: tip below the hinge (%s)" % down)
	expect_near(rad_to_deg(sw.pivot.rotation.x), 40.0, 0.01, "off is the 40 degree limit")
	sw.queue_free()


func test_bat_stays_inside_the_guard() -> void:
	var sw: SwitchLever = _make()
	for v: float in [sw.min_value, (sw.min_value + sw.max_value) * 0.5, sw.max_value]:
		sw.host_set_value(v)
		var tip: Vector3 = _bat_tip(sw)
		expect(absf(tip.y) < 0.05 and tip.z > 0.0 and tip.z < 0.085, "tip %s within the guard at %f" % [tip, v])
	sw.queue_free()
