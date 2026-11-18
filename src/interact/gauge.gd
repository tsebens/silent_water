class_name Gauge
extends Node3D
## In-world dial instrument. The needle sweeps [member sweep_deg] across
## [member min_value]..[member max_value] of a readout on the node in the
## `sub_readouts` group. Builds its own simple meshes so a gauge is one node.

@export var readout: StringName = &"depth"
@export var title: String = "DEPTH"
@export var min_value: float = 0.0
@export var max_value: float = 100.0
@export var sweep_deg: float = 270.0
## Labels drawn at the ends and middle of the scale.
@export var show_scale: bool = true
@export var radius: float = 0.12
## Wraps the value around the dial (compass).
@export var wraps: bool = false
## Needle smoothing (1/s); gauges have mechanical lag.
@export var needle_response: float = 6.0

var _needle: Node3D
var _source: Node
var _shown: float = 0.0


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	if _source == null or not is_instance_valid(_source):
		_source = get_tree().get_first_node_in_group(&"sub_readouts")
		if _source == null:
			return
	var v: float = float(_source.call(&"readout", readout))
	var t: float
	if wraps:
		t = fposmod(v - min_value, max_value - min_value) / (max_value - min_value)
		var target_angle: float = t * TAU
		_shown = lerp_angle(_shown, target_angle, 1.0 - exp(-needle_response * delta))
		_needle.rotation.z = -_shown
		return
	t = clampf(inverse_lerp(min_value, max_value, v), 0.0, 1.0)
	_shown = lerpf(_shown, t, 1.0 - exp(-needle_response * delta))
	_needle.rotation.z = deg_to_rad(sweep_deg * 0.5) - deg_to_rad(sweep_deg) * _shown


func _build() -> void:
	var face_mat: StandardMaterial3D = StandardMaterial3D.new()
	face_mat.albedo_color = Color(0.85, 0.82, 0.7)
	face_mat.roughness = 0.6
	var rim_mat: StandardMaterial3D = StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.35, 0.3, 0.22)
	rim_mat.metallic = 0.8
	rim_mat.roughness = 0.35
	var needle_mat: StandardMaterial3D = StandardMaterial3D.new()
	needle_mat.albedo_color = Color(0.6, 0.08, 0.05)

	var face: MeshInstance3D = MeshInstance3D.new()
	var face_mesh: CylinderMesh = CylinderMesh.new()
	face_mesh.top_radius = radius
	face_mesh.bottom_radius = radius
	face_mesh.height = 0.02
	face_mesh.material = face_mat
	face.mesh = face_mesh
	face.rotation.x = PI / 2.0
	add_child(face)

	var rim: MeshInstance3D = MeshInstance3D.new()
	var rim_mesh: TorusMesh = TorusMesh.new()
	rim_mesh.inner_radius = radius * 0.97
	rim_mesh.outer_radius = radius * 1.12
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.rotation.x = PI / 2.0
	add_child(rim)

	_needle = Node3D.new()
	_needle.position = Vector3(0, 0, 0.015)
	add_child(_needle)
	var needle: MeshInstance3D = MeshInstance3D.new()
	var needle_mesh: BoxMesh = BoxMesh.new()
	needle_mesh.size = Vector3(0.008, radius * 0.85, 0.004)
	needle_mesh.material = needle_mat
	needle.mesh = needle_mesh
	needle.position = Vector3(0, radius * 0.4, 0)
	_needle.add_child(needle)

	# Title sits on a plate below the dial so it never collides with the scale.
	var title_label: Label3D = _add_label(title, Vector3(0, -radius * 1.35, 0.005), 0.0011)
	title_label.modulate = Color(0.9, 0.85, 0.6)
	if show_scale and not wraps:
		var a0: float = deg_to_rad(90.0 + sweep_deg * 0.5)
		var a1: float = deg_to_rad(90.0 - sweep_deg * 0.5)
		_add_label(_fmt(min_value), Vector3(cos(a0), sin(a0), 0) * radius * 0.72 + Vector3(0, 0, 0.012), 0.0009)
		_add_label(_fmt(max_value), Vector3(cos(a1), sin(a1), 0) * radius * 0.72 + Vector3(0, 0, 0.012), 0.0009)
		_add_label(_fmt((min_value + max_value) * 0.5), Vector3(0, radius * 0.72, 0.012), 0.0009)
	elif wraps:
		_add_label("N", Vector3(0, radius * 0.75, 0.012), 0.0009)
		_add_label("S", Vector3(0, -radius * 0.75, 0.012), 0.0009)
		_add_label("E", Vector3(radius * 0.75, 0, 0.012), 0.0009)
		_add_label("W", Vector3(-radius * 0.75, 0, 0.012), 0.0009)


func _add_label(text: String, pos: Vector3, pixel: float) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.pixel_size = pixel
	l.position = pos
	l.modulate = Color(0.1, 0.08, 0.06)
	l.outline_size = 0
	l.font_size = 32
	add_child(l)
	return l


static func _fmt(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v
