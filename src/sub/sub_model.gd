class_name SubModel
extends Node3D
## The sub's hull, generated from `assets/models/vehicles/sub_interior/program.yaml` (`assets/sub/sub_hull.glb`, made
## by tools/build_sub_hull.py). Interior frame: origin on the main deck at the centreline, bow toward -Z.
## Parts are named for what they are (`hull_shell`, `deck_midships`, `bulkhead`, ...; docs/sub_frame.md).
##
## At startup this gives every part its look: worn industrial metal on the hull, decks and bulkhead, trim for the
## rings and coamings, and a clear glass dome. Collision comes from the hull's `-col` nodes, which the glTF import
## turns into static bodies, so this adds none.

## The shared worn-metal interior shader (see docs/art_direction.md).
const WORN_METAL: Shader = preload("res://src/sub/worn_metal.gdshader")

## Default worn-metal parameters, applied to every interior part.
const METAL_WEAR_AMOUNT: float = 0.35
const METAL_SCALE: float = 1.0

## The glass part.
const GLASS_PART: String = "dome_glass"

var _parts: Dictionary = {}


func _ready() -> void:
	_index(self)
	for part_name: String in _parts:
		var mi: MeshInstance3D = _parts[part_name]
		mi.material_override = _material_for(part_name)
		if part_name == GLASS_PART:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A part's mesh node by role name (see docs/sub_frame.md), or null.
func part(part_name: String) -> MeshInstance3D:
	return _parts.get(part_name) as MeshInstance3D


func _index(node: Node) -> void:
	for child: Node in node.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi != null:
			_parts[String(mi.name)] = mi
		_index(child)


## Worn-metal parts: role (its swatch is the base tone), metallic, roughness. Parts not listed here are trim
## (rings and coamings).
const METAL_LOOKS: Dictionary = {
	"hull_shell": [&"hull_metal", 0.1, 0.85],
	"tower": [&"hull_metal", 0.1, 0.85],
	"deck_cockpit": [&"interior_dark", 0.35, 0.75],
	"deck_midships": [&"interior_dark", 0.35, 0.75],
	"deck_bulkhead": [&"interior_dark", 0.35, 0.75],
	"deck_engineering": [&"interior_dark", 0.35, 0.75],
	"cockpit_step": [&"interior_dark", 0.35, 0.75],
	"bulkhead": [&"interior_panel", 0.4, 0.85],
	"tower_hatch": [&"interior_panel", 0.4, 0.85],
}
const FITTING_LOOK: Array = [&"trim_black", 0.0, 0.85]

var _metals: Array[ShaderMaterial] = []
var _roles: Array[StringName] = []
var _glass: StandardMaterial3D


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


func _material_for(part_name: String) -> Material:
	var pal: Palette = Palette.main()
	if not pal.changed.is_connected(_refresh_colors):
		pal.changed.connect(_refresh_colors)
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.roughness = 0.85
	if part_name == GLASS_PART:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.roughness = 0.04
		m.metallic = 0.2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
		_glass = m
		_refresh_colors()
		return m
	var look: Array = FITTING_LOOK
	if METAL_LOOKS.has(part_name):
		look = METAL_LOOKS[part_name]
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
