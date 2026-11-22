extends TestCase
## The shared post-import logic (assets/import/vertex_color_fix.gd, called by vertex_color_import.gd) turns on
## vertex_color_use_as_albedo for every surface of an imported asset.



func _mesh_instance(material: Material) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func test_sets_vertex_colour_flag_on_existing_material() -> void:
	var root: Node3D = Node3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	expect(not mat.vertex_color_use_as_albedo, "flag starts off")
	var mi: MeshInstance3D = _mesh_instance(mat)
	var holder: Node3D = Node3D.new()
	root.add_child(holder)
	holder.add_child(mi)  # nested, to check the walk recurses
	VertexColorFix.apply(root)
	var out: BaseMaterial3D = mi.mesh.surface_get_material(0) as BaseMaterial3D
	expect(out != null and out.vertex_color_use_as_albedo, "flag set on the material")
	root.free()


func test_gives_untextured_surface_a_material_that_shows_colours() -> void:
	var root: Node3D = Node3D.new()
	var mi: MeshInstance3D = _mesh_instance(null)
	root.add_child(mi)
	VertexColorFix.apply(root)
	var out: BaseMaterial3D = mi.mesh.surface_get_material(0) as BaseMaterial3D
	expect(out != null and out.vertex_color_use_as_albedo, "default material created with the flag")
	root.free()
