extends TestCase
## The kit lit_guarded_toggle: a guarded switch whose lamp follows it with no setup.

const SCENE: String = "res://assets/models/kit/lit_guarded_toggle/lit_guarded_toggle.tscn"


func _make() -> SwitchLever:
	var sw: SwitchLever = (load(SCENE) as PackedScene).instantiate() as SwitchLever
	runner.add_child(sw)
	return sw


func _bat_tip(sw: SwitchLever) -> Vector3:
	var bat: MeshInstance3D = sw.pivot.get_child(0).get_child(0) as MeshInstance3D
	var aabb: AABB = bat.get_aabb()
	var far: Vector3 = aabb.position + aabb.size * 0.5
	far.z = aabb.end.z
	return sw.global_transform.affine_inverse() * bat.global_transform * far


func test_lamp_is_dark_off_and_lit_on() -> void:
	var sw: SwitchLever = _make()
	expect(sw.indicator != null, "indicator wired in the scene")
	expect(not sw.indicator.is_lit(), "off at start: dark")
	sw.host_set_value(sw.max_value)
	expect(sw.indicator.is_lit(), "on: lit")
	sw.host_set_value(sw.min_value)
	expect(not sw.indicator.is_lit(), "off again: dark")
	sw.queue_free()


func test_bat_works_at_both_ends() -> void:
	var sw: SwitchLever = _make()
	sw.host_set_value(sw.max_value)
	var up: Vector3 = _bat_tip(sw)
	sw.host_set_value(sw.min_value)
	var down: Vector3 = _bat_tip(sw)
	expect(up.y > 0.01, "on: tip above the hinge (%s)" % up)
	expect(down.y < -0.01, "off: tip below the hinge (%s)" % down)
	expect(absf(up.y) < 0.034 and absf(down.y) < 0.034, "tip within the guard height")
	sw.queue_free()


func test_footprint_and_stand_out_match_the_entry() -> void:
	var sw: SwitchLever = _make()
	var grab: CollisionShape3D = sw.get_node_or_null("Grab/Shape") as CollisionShape3D
	expect(grab != null, "grab box present")
	var box: BoxShape3D = grab.shape as BoxShape3D
	expect_near(box.size.x, 0.056, 0.0005, "56 mm wide")
	expect_near(box.size.y, 0.176, 0.0005, "176 mm tall")
	expect_near(box.size.z, 0.046, 0.0005, "grab box reaches the guard front")
	sw.host_set_value((sw.min_value + sw.max_value) * 0.5)
	expect_near(_bat_tip(sw).z, 0.056, 0.0005, "bat reaches the entry's 56 mm stand-out")
	var lamp: Node3D = sw.indicator
	expect(lamp.position.y > 0.032 + 0.01 and lamp.position.y + 0.01 < 0.088, "lamp above the guard, on the plate")
	sw.queue_free()
