extends TestCase
## The kit multidisplay scene: housing meshes fit the stated footprint and stand-out, and the screen is a
## MultiDisplay with the pilot preset, facing +Z.

const SCENE: String = "res://assets/models/kit/multidisplay/multidisplay.tscn"
const PILOT: String = "res://assets/models/cockpit/pilot_multidisplay.tres"


func _make() -> Node3D:
	var n: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(n)
	return n


func _housing_box(n: Node3D) -> AABB:
	var box: AABB
	var first: bool = true
	for m: Node in n.get_node("Housing").find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m as MeshInstance3D
		var b: AABB = n.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_screen_is_a_multidisplay_with_the_pilot_preset() -> void:
	var n: Node3D = _make()
	var d: MultiDisplay = n.get_node("Screen") as MultiDisplay
	expect(d != null, "Screen is a MultiDisplay")
	expect(d.preset != null and d.preset.resource_path == PILOT, "the pilot preset is set")
	expect(d.slots.size() == 4 and d.chevrons_enabled and d.ring_enabled, "the preset was applied")
	expect_near(d.screen_diameter, 0.2, 1e-6)
	n.queue_free()


func test_screen_faces_plus_z_and_sits_inside_the_housing() -> void:
	var n: Node3D = _make()
	var d: MultiDisplay = n.get_node("Screen") as MultiDisplay
	var facing: Vector3 = d.global_transform.basis.z.normalized()
	expect(facing.dot(Vector3.BACK) > 0.999, "the quad's front faces +Z")
	var box: AABB = _housing_box(n)
	expect(d.position.z > 0.0 and d.position.z < box.end.z, "the screen is behind the bezel's front")
	expect(d.screen_diameter * 0.5 <= box.size.x * 0.5, "the screen is no wider than the housing")
	n.queue_free()


func test_meshes_fit_footprint_and_stand_out() -> void:
	var n: Node3D = _make()
	var box: AABB = _housing_box(n)
	expect(absf(box.position.z) < 0.0005, "back on Z=0")
	expect(box.size.x <= 0.2801 and box.size.y <= 0.2801, "within the 280 mm plate limit")
	expect(box.size.x >= 0.26, "the plate fills the footprint")
	expect(box.end.z <= 0.0372 and box.end.z >= 0.03, "stand-out within the scaled 37 mm")
	expect(absf(box.get_center().x) < 0.001 and absf(box.get_center().y) < 0.001, "centred on the origin")
	n.queue_free()
