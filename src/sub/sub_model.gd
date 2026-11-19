class_name SubModel
extends Node3D
## The sub's geometry from the Onshape concept (`assets/sub/sub_model.glb`,
## made by tools/convert_sub.py). Sub-local frame: origin on the main cabin
## floor at the centreline, bow toward -Z.
##
## At startup this:
## - gives every part its look: matte, muted surfaces; a clear glass dome;
##   softly glowing displays
## - builds collision: exact (trimesh) for the hull, deck, dome and frames,
##   convex for furniture
## - swings the bulkhead door open

const LAYER_INTERIOR: int = 1

## Parts that need exact collision (concave): you walk inside or around them.
const TRIMESH_PARTS: PackedStringArray = ["Shell", "Deck", "FrontWindow", "LifeSupportStationFrame"]
## Parts that need no collision at all.
const NO_COLLISION: PackedStringArray = [
	"Display", "Display2", "Display3", "Bezel", "Bezel2", "Bezel3", "SliderHandle", "SliderHandle2",
	"SliderHandle3", "SonarSliderTrack", "HydrophoneWheel", "Flywheel", "BulkheadHatch",
]

## Open angle of the bulkhead door (degrees about its hinge).
@export var door_open_deg: float = 100.0

var _parts: Dictionary = {}


func _ready() -> void:
	_index(self)
	for part_name: String in _parts:
		var mi: MeshInstance3D = _parts[part_name]
		mi.material_override = _material_for(part_name)
		if part_name == "FrontWindow":
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if not NO_COLLISION.has(part_name):
			_add_collision(mi, TRIMESH_PARTS.has(part_name))
	_open_door()


## A part's mesh node by role name (see tools/convert_sub.py), or null.
func part(part_name: String) -> MeshInstance3D:
	return _parts.get(part_name) as MeshInstance3D


func _index(node: Node) -> void:
	for child: Node in node.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi != null:
			_parts[String(mi.name)] = mi
		_index(child)


func _add_collision(mi: MeshInstance3D, exact: bool) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = LAYER_INTERIOR
	body.collision_mask = 0
	var shape: CollisionShape3D = CollisionShape3D.new()
	if exact:
		var tri: ConcavePolygonShape3D = mi.mesh.create_trimesh_shape()
		tri.backface_collision = true
		shape.shape = tri
	else:
		shape.shape = mi.mesh.create_convex_shape(true, true)
	body.add_child(shape)
	mi.add_child(body)


## Hinged on the door's port edge, opening aft into the machinery space.
func _open_door() -> void:
	var door: MeshInstance3D = part("BulkheadHatch")
	if door == null:
		return
	var aabb: AABB = door.mesh.get_aabb()
	var hinge_local: Vector3 = Vector3(aabb.position.x, 0.0, aabb.end.z)
	var hinge: Transform3D = Transform3D(Basis(), door.position + hinge_local)
	var swing: Transform3D = Transform3D(Basis(Vector3.UP, deg_to_rad(-door_open_deg)), Vector3.ZERO)
	door.transform = hinge * swing * hinge.affine_inverse() * door.transform


func _material_for(part_name: String) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.roughness = 0.85
	if part_name == "FrontWindow":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.55, 0.75, 0.8, 0.07)
		m.roughness = 0.04
		m.metallic = 0.2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		return m
	if part_name.begins_with("Display"):
		m.albedo_color = Color(0.03, 0.08, 0.09)
		m.emission_enabled = true
		m.emission = Color(0.2, 0.62, 0.7)
		m.emission_energy_multiplier = 0.55
		return m
	if part_name == "Shell":
		m.albedo_color = Color(0.15, 0.17, 0.18)
	elif part_name == "Deck":
		m.albedo_color = Color(0.1, 0.11, 0.115)
		m.metallic = 0.35
		m.roughness = 0.75
	elif part_name.begins_with("PressurizedCylinder"):
		m.albedo_color = Color(0.38, 0.4, 0.39)
		m.metallic = 0.55
		m.roughness = 0.55
	elif part_name == "BulkheadHatch":
		m.albedo_color = Color(0.2, 0.22, 0.23)
		m.metallic = 0.4
	elif part_name in ["EngineBlock", "Flywheel", "EngineMount", "HydrophoneWheel"] or part_name.begins_with("Slider"):
		m.albedo_color = Color(0.3, 0.31, 0.3)
		m.metallic = 0.6
		m.roughness = 0.5
	else:
		# Furniture and fittings: muted grey-blue.
		m.albedo_color = Color(0.24, 0.27, 0.29)
	return m
