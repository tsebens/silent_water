extends TestCase
## The kit lit_guarded_toggle: a guarded switch whose lamp follows it with no setup.

const SCENE: String = "res://assets/models/kit/lit_guarded_toggle/lit_guarded_toggle.tscn"


func _make() -> GuardedSwitch:
	var sw: GuardedSwitch = (load(SCENE) as PackedScene).instantiate() as GuardedSwitch
	runner.add_child(sw)
	return sw


func _bat_tip(sw: GuardedSwitch) -> Vector3:
	var bat: MeshInstance3D = sw.pivot.get_child(0).get_child(0) as MeshInstance3D
	var aabb: AABB = bat.get_aabb()
	var far: Vector3 = aabb.position + aabb.size * 0.5
	far.z = aabb.end.z
	return sw.global_transform.affine_inverse() * bat.global_transform * far


func test_lamp_is_dark_off_and_lit_on() -> void:
	var sw: GuardedSwitch = _make()
	expect(sw.indicator != null, "indicator wired in the scene")
	expect(not sw.indicator.is_lit(), "off at start: dark")
	sw.host_set_value(sw.max_value)
	expect(sw.indicator.is_lit(), "on: lit")
	sw.host_set_value(sw.min_value)
	expect(not sw.indicator.is_lit(), "off again: dark")
	sw.queue_free()


func test_bat_works_at_both_ends() -> void:
	var sw: GuardedSwitch = _make()
	sw.host_set_value(sw.max_value)
	var up: Vector3 = _bat_tip(sw)
	sw.host_set_value(sw.min_value)
	var down: Vector3 = _bat_tip(sw)
	expect(up.y > 0.01, "on: tip above the hinge (%s)" % up)
	expect(down.y < -0.01, "off: tip below the hinge (%s)" % down)
	expect(absf(up.y) < 0.033 and absf(down.y) < 0.034, "tip within the cap")
	sw.queue_free()


func test_cap_closed_leaves_the_lamp_visible() -> void:
	var sw: GuardedSwitch = _make()
	expect(sw.cap != null and not sw.cap_open, "cap closed by default")
	var cap_top: float = sw.cap.position.y + 0.0025
	var lamp_bottom: float = sw.indicator.position.y - 0.01
	expect(cap_top < lamp_bottom, "closed cap top (%s) below the lamp (%s)" % [cap_top, lamp_bottom])
	expect(not sw.indicator.is_lit(), "dark with the cap closed")
	sw.begin_interaction()
	sw.click_action()
	sw.click_action()
	sw.end_interaction()
	expect(sw.cap_open and sw.indicator.is_lit(), "second click: cap open, lamp lit")
	sw.queue_free()


func test_footprint_and_stand_out_match_the_entry() -> void:
	var sw: GuardedSwitch = _make()
	var grab: CollisionShape3D = sw.get_node_or_null("Grab/Shape") as CollisionShape3D
	expect(grab != null, "grab box present")
	var box: BoxShape3D = grab.shape as BoxShape3D
	expect_near(box.size.x, 0.056, 0.0005, "56 mm wide")
	expect_near(box.size.y, 0.176, 0.0005, "176 mm tall")
	expect_near(box.size.z, 0.0715, 0.0005, "grab box reaches the closed cap's tab")
	var lamp: Node3D = sw.indicator
	expect(lamp.position.y > 0.032 + 0.01 and lamp.position.y + 0.01 < 0.088, "lamp above the cap, on the plate")
	sw.queue_free()
