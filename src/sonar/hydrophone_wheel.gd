class_name HydrophoneWheel
extends Valve
## Handwheel that trains the hydrophone. Turns freely; one full turn of the
## wheel swings the listening bearing [member degrees_per_turn] degrees.
## Bearings are relative to the bow, clockwise (90 = starboard beam).

@export var degrees_per_turn: float = 120.0

var _base_basis: Basis = Basis.IDENTITY
var _axle: Vector3 = Vector3.BACK
var _have_axle: bool = false


func _init() -> void:
	super._init()
	min_value = -1.0e6
	max_value = 1.0e6
	initial_value = 0.0


func _ready() -> void:
	super._ready()
	# When driving a mesh from the sub model, hide this scene's own wheel.
	for n: String in ["Wheel", "Stem"]:
		var own: Node3D = get_node_or_null(n) as Node3D
		if own != null and own != wheel:
			own.visible = false


func bearing_deg() -> float:
	return fposmod(get_value(), 360.0)


func _drag_to_value(current: float, relative: Vector2) -> float:
	return current + _swept_turns(relative) * degrees_per_turn


func _apply_visual(v: float) -> void:
	if wheel == null:
		return
	if not _have_axle:
		_base_basis = wheel.transform.basis
		_axle = axle_of(wheel)
		_have_axle = true
	# Spin about the wheel's own axle, keeping its mounting orientation.
	# The axle points toward the operator, so a negative angle is clockwise.
	var angle: float = -deg_to_rad(v / degrees_per_turn * 360.0)
	wheel.transform.basis = _base_basis * Basis(_axle, angle)


## The wheel's axle in its node's local space: the thin axis of a disc mesh
## (smallest principal axis of its vertices), signed to point toward +Z.
## Falls back to +Z for nodes without a mesh.
static func axle_of(node: Node3D) -> Vector3:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi == null or mi.mesh == null or mi.mesh.get_surface_count() == 0:
		return Vector3.BACK
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return Vector3.BACK
	var mean: Vector3 = Vector3.ZERO
	for p: Vector3 in verts:
		mean += p
	mean /= float(verts.size())
	var c: Basis = Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
	for p: Vector3 in verts:
		var d: Vector3 = p - mean
		c.x += d * d.x
		c.y += d * d.y
		c.z += d * d.z
	# Dominant axis of (trace*I - C) is the smallest axis of C.
	var tr: float = c.x.x + c.y.y + c.z.z
	var a: Vector3 = Vector3(0.577, 0.577, 0.577)
	for i: int in range(60):
		var n: Vector3 = a * tr - c * a
		if n.length() < 1.0e-12:
			return Vector3.BACK
		a = n.normalized()
	return a if a.z >= 0.0 else -a


func interaction_hint() -> String:
	return "hold click, circle the mouse to train the hydrophone"
