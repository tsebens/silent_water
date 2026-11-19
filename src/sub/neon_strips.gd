class_name NeonStrips
extends Node3D
## Thin glowing light strips that trace the cabin's shape: hull ribs, the
## bulkhead door frame, the map table rim, the pilot map ring, the sonar desk
## edge and the floor edges. They give the space crisp lines in the dark
## without lighting it up (they emit, but cast no light). CabinLights dims
## them with the cabin lights.
##
## All geometry is sub-local and matches the hull from tools/convert_sub.py:
## a 2 m radius cylinder around (0, 0.98, z), cabin floor at y = 0.

const COLOR: Color = Color(0.3, 0.85, 0.95)
const ENERGY: float = 3.0
const TUBE_RADIUS: float = 0.007
const SIDES: int = 6

## Hull centreline height and the radius the ribs sit at (just inside the lining).
const HULL_AXIS_Y: float = 0.98
const RIB_RADIUS: float = 1.86
## Rib positions along the hull (z): forward cabin, then aft compartment.
const RIB_Z: PackedFloat32Array = [0.15, 0.95, 1.7, 2.45, 3.25, 4.15]

var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = COLOR
	_material.emission_enabled = true
	_material.emission = COLOR
	_material.emission_energy_multiplier = ENERGY
	for z: float in RIB_Z:
		_add("Rib", _hull_arc(z), false)
	# Bulkhead door frame (oval opening, forward face).
	_add("DoorFrame", _ellipse(Vector3(0, 1.03, 1.81), 0.5, 1.02, Vector3.RIGHT, Vector3.UP), true)
	# Map table rim and pilot map ring.
	_add("MapTableRim", _ellipse(Vector3(0, 0.775, 0.285), 0.64, 0.385, Vector3.RIGHT, Vector3.BACK), true)
	_add("PilotMapRing", _ellipse(Vector3(0, -0.39, -2.2), 0.52, 0.52, Vector3.RIGHT, Vector3.BACK), true)
	# Sonar desk: front top edge.
	_add("SonarDeskEdge", PackedVector3Array([Vector3(0.75, 1.0, 1.25), Vector3(1.65, 1.0, 1.25)]), false)
	# Floor edges, both sides, the length of the forward cabin and aft space.
	for x: float in [-1.45, 1.45]:
		_add("FloorEdge", PackedVector3Array([Vector3(x, 0.015, -0.3), Vector3(x, 0.015, 1.8)]), false)
		_add("FloorEdgeAft", PackedVector3Array([Vector3(x * 0.95, 0.015, 2.0), Vector3(x * 0.95, 0.015, 4.6)]), false)


## The arc of a hull rib above the deck, from floor to floor over the top.
func _hull_arc(z: float) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	# Angle (from straight down) where the rib meets the floor at y = 0.05.
	var floor_angle: float = acos(clampf((HULL_AXIS_Y - 0.05) / RIB_RADIUS, -1.0, 1.0))
	var steps: int = 40
	for i: int in range(steps + 1):
		var a: float = lerpf(floor_angle, TAU - floor_angle, float(i) / steps)
		pts.append(Vector3(sin(a) * RIB_RADIUS, HULL_AXIS_Y - cos(a) * RIB_RADIUS, z))
	return pts


func _ellipse(center: Vector3, ra: float, rb: float, axis_a: Vector3, axis_b: Vector3) -> PackedVector3Array:
	var pts: PackedVector3Array = PackedVector3Array()
	var steps: int = 48
	for i: int in range(steps):
		var a: float = TAU * float(i) / steps
		pts.append(center + axis_a * cos(a) * ra + axis_b * sin(a) * rb)
	return pts


func _add(strip_name: String, points: PackedVector3Array, closed: bool) -> void:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = strip_name
	mi.mesh = tube_mesh(points, closed, TUBE_RADIUS, _material)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi, true)


## A thin tube along a polyline.
static func tube_mesh(points: PackedVector3Array, closed: bool, radius: float, material: Material) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = points.size()
	var segs: int = n if closed else n - 1
	var rings: Array[PackedVector3Array] = []
	for i: int in range(n):
		var prev: Vector3 = points[(i - 1 + n) % n] if (closed or i > 0) else points[i]
		var next: Vector3 = points[(i + 1) % n] if (closed or i < n - 1) else points[i]
		var tangent: Vector3 = (next - prev).normalized()
		var side: Vector3 = tangent.cross(Vector3.UP)
		if side.length_squared() < 1e-6:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized()
		var up: Vector3 = side.cross(tangent).normalized()
		var ring: PackedVector3Array = PackedVector3Array()
		for k: int in range(SIDES):
			var a: float = TAU * float(k) / SIDES
			ring.append(points[i] + (side * cos(a) + up * sin(a)) * radius)
		rings.append(ring)
	for i: int in range(segs):
		var r0: PackedVector3Array = rings[i]
		var r1: PackedVector3Array = rings[(i + 1) % n]
		for k: int in range(SIDES):
			var k1: int = (k + 1) % SIDES
			st.add_vertex(r0[k])
			st.add_vertex(r1[k])
			st.add_vertex(r1[k1])
			st.add_vertex(r0[k])
			st.add_vertex(r1[k1])
			st.add_vertex(r0[k1])
	st.generate_normals()
	st.set_material(material)
	return st.commit()
