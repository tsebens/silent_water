class_name SubModel
extends Node3D
## The sub's geometry from the Onshape concept (`assets/sub/sub_model.glb`,
## made by tools/convert_sub.py). Sub-local frame: origin on the main cabin
## floor at the centreline, bow toward -Z.
##
## At startup this:
## - gives every part its look: worn industrial metal; a clear glass dome;
##   softly glowing displays
## - builds collision: exact (trimesh) for the hull, deck, dome and frames,
##   convex for furniture
## - swings the bulkhead door open

const LAYER_INTERIOR: int = 1

## The shared worn-metal interior shader (see docs/art_direction.md).
const WORN_METAL: Shader = preload("res://src/sub/worn_metal.gdshader")

## Default worn-metal parameters, applied to every interior part.
const METAL_WEAR_AMOUNT: float = 0.35
const METAL_SCALE: float = 1.0

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


## Worn-metal parts: role (its swatch is the base tone), metallic, roughness. Parts not listed here are furniture
## and fittings.
const METAL_LOOKS: Dictionary = {
	"Shell": [&"hull_metal", 0.1, 0.85],
	"Deck": [&"interior_dark", 0.35, 0.75],
	"BulkheadHatch": [&"interior_panel", 0.4, 0.85],
}
const MACHINERY_LOOK: Array = [&"hull_metal", 0.6, 0.5]
const PRESSURE_LOOK: Array = [&"hull_metal", 0.55, 0.55]
const FITTING_LOOK: Array = [&"interior_panel", 0.0, 0.85]

var _metals: Array[ShaderMaterial] = []
var _roles: Array[StringName] = []
var _glass: StandardMaterial3D
var _displays: Array[StandardMaterial3D] = []


## The colour a role gets from the palette.
func _role_color(role: StringName) -> Color:
	var rm: RoleMaterial = RoleMaterial.lookup(String(role))
	return Palette.main().color(rm.swatch)


func _refresh_colors() -> void:
	for i: int in range(_metals.size()):
		_metals[i].set_shader_parameter("base_tone", _role_color(_roles[i]))
	if _glass != null:
		_glass.albedo_color = _role_color(&"glass")
		_glass.albedo_color.a = 0.07
	for d: StandardMaterial3D in _displays:
		d.albedo_color = _role_color(&"screen_off")
		d.emission = Palette.main().color(&"light_readout")


func _material_for(part_name: String) -> Material:
	var pal: Palette = Palette.main()
	if not pal.changed.is_connected(_refresh_colors):
		pal.changed.connect(_refresh_colors)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.roughness = 0.85
	if part_name == "FrontWindow":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_glass = m
		_refresh_colors()
		return m
	if part_name.begins_with("Display"):
		m.emission_enabled = true
		m.emission_energy_multiplier = 0.55
		_displays.append(m)
		_refresh_colors()
		return m
	var look: Array = FITTING_LOOK
	if METAL_LOOKS.has(part_name):
		look = METAL_LOOKS[part_name]
	elif part_name.begins_with("PressurizedCylinder"):
		look = PRESSURE_LOOK
	elif part_name in ["EngineBlock", "Flywheel", "EngineMount", "HydrophoneWheel"] or part_name.begins_with("Slider"):
		look = MACHINERY_LOOK
	var sm: ShaderMaterial = ShaderMaterial.new()
	sm.shader = WORN_METAL
	sm.set_shader_parameter("wear_amount", METAL_WEAR_AMOUNT)
	sm.set_shader_parameter("scale", METAL_SCALE)
	sm.set_shader_parameter("metallic_amount", float(look[1]))
	sm.set_shader_parameter("roughness_amount", float(look[2]))
	_metals.append(sm)
	_roles.append(look[0] as StringName)
	_refresh_colors()
	return sm
