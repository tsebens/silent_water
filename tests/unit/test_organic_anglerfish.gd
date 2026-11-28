extends TestCase
## The generated anglerfish (organics, M20): a static faceted model about 20 cm mouth to tail, centred, mouth toward +Z.

const SCENE: String = "res://assets/models/organics/anglerfish/anglerfish.tscn"
const ROLES: Array[String] = ["interior_dark", "trim_black", "infra_metal", "concrete"]
const TRIANGLE_BUDGET: int = 8000


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	var mi: MeshInstance3D = n as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(mi)
	for c: Node in n.get_children():
		_meshes(c, out)


func test_bounds_are_centred_and_twenty_centimetres_long() -> void:
	var root: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(root)
	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	expect(not meshes.is_empty(), "the scene has a mesh")
	var box: AABB = AABB()
	var first: bool = true
	for mi: MeshInstance3D in meshes:
		var b: AABB = root.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	expect_near(box.size.z, 0.20, 0.01, "about 20 cm mouth to tail along Z")
	expect_near(box.get_center().x, 0.0, 0.002, "centred in X")
	expect_near(box.get_center().y, 0.0, 0.002, "centred in Y")
	expect_near(box.get_center().z, 0.0, 0.002, "centred in Z")
	root.queue_free()


func test_surfaces_use_only_palette_roles_and_stay_in_budget() -> void:
	var root: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(root)
	var meshes: Array[MeshInstance3D] = []
	_meshes(root, meshes)
	var tris: int = 0
	var seen: Array[String] = []
	for mi: MeshInstance3D in meshes:
		for s: int in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var idx: Variant = arr[Mesh.ARRAY_INDEX]
			tris += (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
			var m: Material = mi.mesh.surface_get_material(s)
			expect(m != null and m.resource_name in ROLES, "surface %d uses an anglerfish palette role" % s)
			if m != null:
				seen.append(m.resource_name)
	for r: String in ROLES:
		expect(seen.has(r), "the model has a %s surface" % r)
	expect(tris > 0 and tris <= TRIANGLE_BUDGET, "%d triangles, within %d" % [tris, TRIANGLE_BUDGET])
	root.queue_free()
