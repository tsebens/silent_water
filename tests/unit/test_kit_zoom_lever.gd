extends TestCase
## The generated zoom lever: wired to its pivot, spring-centred, and inside the plate at both ends of the throw.

const SCENE: String = "res://assets/models/kit/zoom_lever/zoom_lever.tscn"


func _make() -> ZoomLever:
	var z: ZoomLever = (load(SCENE) as PackedScene).instantiate() as ZoomLever
	runner.add_child(z)
	return z


func _tip(z: ZoomLever) -> Vector3:
	var handle: Node3D = z.pivot.get_node("Handle") as Node3D
	var mi: MeshInstance3D = _first_mesh(handle)
	var aabb: AABB = mi.get_aabb()
	var far: Vector3 = aabb.position + Vector3(aabb.size.x * 0.5, aabb.size.y * 0.5, aabb.size.z)
	return z.global_transform.affine_inverse() * mi.global_transform * far


func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c: Node in n.get_children():
		var m: MeshInstance3D = _first_mesh(c)
		if m != null:
			return m
	return null


func test_scene_wires_the_pivot() -> void:
	var z: ZoomLever = _make()
	expect(z.pivot != null, "pivot is set")
	expect_eq(z.pivot.name, &"Pivot")
	expect(z.pivot.get_node_or_null("Handle") != null, "handle under the pivot")
	z.queue_free()


func test_rests_upright_at_centre() -> void:
	var z: ZoomLever = _make()
	expect_near(rad_to_deg(z.pivot.rotation.x), 0.0, 0.01, "rate 0 is upright")
	expect_eq(z._release_value(0.7), 0.0, "springs to centre")
	z.queue_free()


func test_up_is_zoom_in_and_throw_is_symmetric() -> void:
	var z: ZoomLever = _make()
	z.host_set_value(1.0)
	var up: Vector3 = _tip(z)
	expect_near(rad_to_deg(z.pivot.rotation.x), -30.0, 0.01)
	z.host_set_value(-1.0)
	var down: Vector3 = _tip(z)
	expect_near(rad_to_deg(z.pivot.rotation.x), 30.0, 0.01)
	expect(up.y > 0.01 and down.y < -0.01, "tip up at +1, down at -1 (%s, %s)" % [up, down])
	z.queue_free()


func test_handle_stays_inside_the_plate() -> void:
	var z: ZoomLever = _make()
	for v: float in [-1.0, 0.0, 1.0]:
		z.host_set_value(v)
		var tip: Vector3 = _tip(z)
		expect(absf(tip.y) < 0.05 and tip.z > 0.0, "tip %s inside the plate at %f" % [tip, v])
	z.queue_free()
