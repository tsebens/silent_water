class_name VertexColorFix
extends RefCounted
## Gives every surface under a node its proper material, on import. Used by the shared post-import script; kept
## separate so unit tests can call it.
##
## - A surface whose material is named after a palette role (docs/palette.md) gets that role's shared material, so
##   a palette change reaches it with no re-import. Generated assets (cadkit) name roles.
## - Any other surface shows its vertex colours: Godot imports glTF vertex colours but does not apply them to the
##   albedo by default (assets from the image-to-3D route and the Onshape import).


static func apply(node: Node) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		var mesh: Mesh = mi.mesh
		for s: int in mesh.get_surface_count():
			var current: Material = mesh.surface_get_material(s)
			var role: RoleMaterial = RoleMaterial.lookup(current.resource_name if current != null else "")
			if role != null:
				mesh.surface_set_material(s, role)
				continue
			var mat: BaseMaterial3D = current as BaseMaterial3D
			if mat == null:
				mat = StandardMaterial3D.new()
				mesh.surface_set_material(s, mat)
			mat.vertex_color_use_as_albedo = true
	for child: Node in node.get_children():
		apply(child)
