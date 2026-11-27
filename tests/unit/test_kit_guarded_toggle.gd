extends TestCase
## The kit guarded_toggle: a switch under a hinged cap, driven by GuardedSwitch.

const SCENE: String = "res://assets/models/kit/guarded_toggle/guarded_toggle.tscn"


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


func test_script_and_cap_wired() -> void:
	var sw: GuardedSwitch = _make()
	expect(sw != null, "root is a GuardedSwitch")
	expect(sw.cap != null and sw.cap.name == &"Cap", "Cap node wired")
	expect(not sw.cap_open, "closed by default")
	expect_near(sw.cap.rotation.x, 0.0, 0.0001, "closed pose")
	expect(sw.cap_open_deg < -90.0, "opens up and forward")
	sw.queue_free()


func test_cap_is_pivoted_at_the_top_edge() -> void:
	var sw: GuardedSwitch = _make()
	expect_near(sw.cap.position.y, 0.033, 0.0005, "hinge 33 mm above the plate centre")
	var mesh: MeshInstance3D = sw.cap.get_child(0) as MeshInstance3D
	expect(mesh != null, "cap mesh")
	var aabb: AABB = mesh.get_aabb()
	expect(aabb.end.y < 0.004, "cap hangs below its hinge")
	expect(aabb.position.y < -0.06, "cap covers the bat")
	sw.queue_free()


func test_cap_lifts_with_the_first_click() -> void:
	var sw: GuardedSwitch = _make()
	sw.begin_interaction()
	sw.click_action()
	sw.end_interaction()
	expect(sw.cap_open, "lifted")
	expect_eq(sw.get_value(), sw.min_value, "still off")
	expect_near(sw.cap.rotation.x, deg_to_rad(sw.cap_open_deg), 0.0001, "cap posed open")
	sw.queue_free()


func test_bat_works_at_both_ends() -> void:
	var sw: GuardedSwitch = _make()
	sw.host_set_value(sw.max_value)
	var up: Vector3 = _bat_tip(sw)
	sw.host_set_value(sw.min_value)
	var down: Vector3 = _bat_tip(sw)
	expect(up.y > 0.01, "on: tip above the hinge (%s)" % up)
	expect(down.y < -0.01, "off: tip below the hinge (%s)" % down)
	expect(absf(up.y) < 0.033 and absf(down.y) < 0.033, "tip within the cap")
	sw.queue_free()


func test_footprint_and_stand_out_match_the_entry() -> void:
	var sw: GuardedSwitch = _make()
	var grab: CollisionShape3D = sw.get_node_or_null("Grab/Shape") as CollisionShape3D
	expect(grab != null, "grab box present")
	var box: BoxShape3D = grab.shape as BoxShape3D
	expect_near(box.size.x, 0.056, 0.0005, "56 mm wide")
	expect_near(box.size.y, 0.116, 0.0005, "116 mm tall")
	expect_near(box.size.z, 0.0715, 0.0005, "grab box reaches the closed cap's tab")
	var cap_box: AABB = (sw.cap.get_child(0) as MeshInstance3D).get_aabb()
	expect_near(sw.cap.position.z + cap_box.end.z, 0.0715, 0.0005, "closed cap reaches the entry's stand-out")
	sw.queue_free()
