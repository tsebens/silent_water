extends TestCase
## The generated operator seat (docs/asset_process.md): the backrest leans
## back, away from the sitter, who faces -Z.

const SCENE: String = "res://assets/models/furniture/operator_seat/operator_seat.tscn"


func _mean_z(verts: PackedVector3Array, y_lo: float, y_hi: float) -> float:
	var sum: float = 0.0
	var n: int = 0
	for v: Vector3 in verts:
		if v.y >= y_lo and v.y <= y_hi and v.z > 0.15:
			sum += v.z
			n += 1
	expect(n > 0, "backrest vertices found in %.2f..%.2f m" % [y_lo, y_hi])
	return sum / maxf(n, 1)


func test_backrest_top_is_further_back_than_its_bottom() -> void:
	var seat: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(seat)
	var verts: PackedVector3Array = PackedVector3Array()
	var stack: Array[Node] = [seat]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi: MeshInstance3D = n as MeshInstance3D
			var xf: Transform3D = seat.global_transform.affine_inverse() * mi.global_transform
			for s: int in mi.mesh.get_surface_count():
				for v: Vector3 in mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]:
					verts.append(xf * v)
		stack.append_array(n.get_children())
	var top: float = _mean_z(verts, 0.85, 0.95)
	var bottom: float = _mean_z(verts, 0.5, 0.6)
	expect(top > bottom + 0.03, "backrest top (z %.3f) is toward +Z of its bottom (z %.3f)" % [top, bottom])
	seat.queue_free()
