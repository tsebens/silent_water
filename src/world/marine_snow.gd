class_name MarineSnow
extends MeshInstance3D
## Drifting particulate around the sub, fixed in world space (see the shader).
## Must be a child of the world root. Follows the sub so the cube of flakes is
## always centred on it; the shader wraps flakes so they don't move with it.

@export var flake_count: int = 6000
@export var box_size: float = 24.0

var _sub_frame: SubFrame
var _material: ShaderMaterial


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://src/world/marine_snow.gdshader")
	_material.set_shader_parameter(&"box_size", box_size)
	mesh = _build_mesh()
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3.ONE * -box_size, Vector3.ONE * box_size * 2.0)


func _process(_delta: float) -> void:
	if _sub_frame == null:
		_sub_frame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
		if _sub_frame == null:
			return
	var pose: Transform3D = _sub_frame.render_transform()
	position = pose.origin
	_material.set_shader_parameter(&"sub_pos", pose.origin)
	_material.set_shader_parameter(&"sub_basis_inv", pose.basis.inverse())


func _build_mesh() -> ArrayMesh:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i: int in range(flake_count):
		var p: Vector3 = Vector3(rng.randf(), rng.randf(), rng.randf()) * box_size
		var start: int = verts.size()
		for c: Vector2 in corners:
			verts.append(p)
			uvs.append(c)
		indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var m: ArrayMesh = ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
