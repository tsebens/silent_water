extends TestCase
## The cockpit dome (#594): a true sphere from layout.json's `dome` block, smooth and dense, bulging forward of a
## ring; and the hull aft of the ring is the loft it always was.

const HULL: PackedScene = preload("res://assets/sub/sub_hull.glb")
## Tolerances from the arc's acceptance: every vertex within 5 mm of the sphere, every normal within 2 degrees of radial.
const MAX_VERTEX_ERROR_M: float = 0.005
const MAX_NORMAL_ERROR_DEG: float = 2.0

var hull: Node3D


func before_each() -> void:
	hull = HULL.instantiate() as Node3D
	runner.add_child(hull)


func after_each() -> void:
	hull.free()


func _arrays(part_name: String) -> Array:
	var mi: MeshInstance3D = hull.get_node(part_name) as MeshInstance3D
	return mi.mesh.surface_get_arrays(0)


func test_every_vertex_is_on_the_sphere() -> void:
	var d: Dictionary = SubLayout.dome()
	var centre: Vector3 = d["centre"]
	var verts: PackedVector3Array = _arrays("dome_glass")[Mesh.ARRAY_VERTEX]
	expect(verts.size() > 1000, "the dome has vertices (%d)" % verts.size())
	var worst: float = 0.0
	for v: Vector3 in verts:
		worst = maxf(worst, absf(v.distance_to(centre) - float(d["radius"])))
	expect(worst <= MAX_VERTEX_ERROR_M, "worst vertex %.4f m off the sphere" % worst)


func test_every_normal_is_radial() -> void:
	var d: Dictionary = SubLayout.dome()
	var centre: Vector3 = d["centre"]
	var arrays: Array = _arrays("dome_glass")
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	expect_eq(normals.size(), verts.size(), "a normal per vertex")
	var worst: float = 0.0
	for i: int in range(verts.size()):
		var radial: Vector3 = (verts[i] - centre).normalized()
		# the glass is seen from inside, so the normals face the centre; the angle is measured to that direction
		worst = maxf(worst, rad_to_deg(normals[i].angle_to(-radial)))
	expect(worst <= MAX_NORMAL_ERROR_DEG, "worst normal %.3f degrees off radial" % worst)


func test_dome_is_a_forward_hemisphere_under_its_ceiling() -> void:
	var d: Dictionary = SubLayout.dome()
	var verts: PackedVector3Array = _arrays("dome_glass")[Mesh.ARRAY_VERTEX]
	var centre: Vector3 = d["centre"]
	var tris: int = (_arrays("dome_glass")[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	expect(tris <= int(d["max_triangles"]), "dome is over its triangle ceiling (%d)" % tris)
	expect(tris >= 3000, "dome is dense enough to read as smooth (%d)" % tris)
	for v: Vector3 in verts:
		if v.z > float(d["ring_z"]) + 0.001:
			expect(false, "dome vertex aft of the ring plane at %s" % v)
			return
	var aabb: AABB = (hull.get_node("dome_glass") as MeshInstance3D).get_aabb()
	expect_near(aabb.size.x, 2.0 * float(d["radius"]), 0.01, "2.2 m across")
	expect_near(aabb.position.z, centre.z - float(d["radius"]), 0.01, "apex one radius forward of the ring")


func test_collision_is_a_trimesh_of_the_same_surface() -> void:
	var mi: MeshInstance3D = hull.get_node("dome_glass") as MeshInstance3D
	var shapes: Array[Node] = mi.find_children("*", "CollisionShape3D", true, false)
	expect(shapes.size() == 1, "the dome has one collision shape (-col import)")
	if shapes.is_empty():
		return
	var shape: ConcavePolygonShape3D = (shapes[0] as CollisionShape3D).shape as ConcavePolygonShape3D
	expect(shape != null, "a trimesh")
	if shape != null:
		var tris: int = (_arrays("dome_glass")[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		expect_eq(shape.get_faces().size() / 3, tris, "same triangles")


## Fingerprints taken from the hull before the dome was made spherical (the tower and shell ones retaken when the tower shaft was cut, #920): the non-dome parts must be what they were
## (triangle count and the sum of all vertex coordinates), and the loft aft of the ring the same.
const UNCHANGED: Dictionary = {
	"deck_midships": [196, -560.547],
	"deck_bulkhead": [196, 923.139],
	"deck_engineering": [196, 1861.946],
	"cockpit_step": [12, -132.378],
	"bulkhead": [232, 2005.411],
	"hatch_frame": [72, 618.48],
	"tower": [96, 1285.375],
	"tower_hatch": [96, 1483.137],
}


func _fingerprint(part_name: String, z_min: float) -> Array:
	var arrays: Array = _arrays(part_name)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]      # the importer welds vertices: walk the triangles by index
	var count: int = 0
	var total: float = 0.0
	for t: int in range(index.size() / 3):
		var tri: Array[Vector3] = [verts[index[3 * t]], verts[index[3 * t + 1]], verts[index[3 * t + 2]]]
		if tri[0].z < z_min or tri[1].z < z_min or tri[2].z < z_min:
			continue
		count += 1
		for v: Vector3 in tri:
			total += v.x + v.y + v.z
	return [count, total]


func test_non_dome_parts_are_unchanged() -> void:
	for part: String in UNCHANGED:
		var want: Array = UNCHANGED[part]
		var got: Array = _fingerprint(part, -INF)
		expect_eq(got[0], want[0], "%s triangle count" % part)
		expect_near(float(got[1]), float(want[1]), 0.05 + absf(float(want[1])) * 1e-5, "%s geometry" % part)


func test_hull_shell_aft_of_the_old_cockpit_is_unchanged() -> void:
	var got: Array = _fingerprint("hull_shell", -3.2)
	expect_eq(got[0], 7010, "shell triangles aft of z -3.2")
	expect_near(float(got[1]), 39471.918, 0.5, "shell geometry aft of z -3.2")


func test_hull_ring_data_aft_of_the_ring_is_unchanged() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SubLayout.LAYOUT_PATH))
	var count: int = 0
	var total: float = 0.0
	for r: Dictionary in layout["hull"]["rings"]:
		if float(r["z"]) <= -3.9:
			continue
		count += 1
		total += float(r["z"])
		for p: Array in r["points"]:
			total += float(p[0]) + float(p[1])
	expect_eq(count, 107, "rings aft of the pilot's z")
	expect_near(total, 62.167, 0.01, "ring points aft of the pilot's z")
