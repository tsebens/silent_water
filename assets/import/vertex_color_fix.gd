class_name VertexColorFix
extends RefCounted
## Turns on vertex_color_use_as_albedo for every surface under a node. Used by
## the shared post-import script; kept separate so unit tests can call it.


static func apply(node: Node) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var mesh: Mesh = mi.mesh
		for s: int in mesh.get_surface_count():
			var mat: BaseMaterial3D = mesh.surface_get_material(s) as BaseMaterial3D
			if mat == null:
				mat = StandardMaterial3D.new()
				mesh.surface_set_material(s, mat)
			mat.vertex_color_use_as_albedo = true
	for child: Node in node.get_children():
		apply(child)
