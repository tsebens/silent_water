@tool
class_name RoleMaterial
extends StandardMaterial3D
## A shared material for one colour role: hull metal, control interface, readout ink, alarm lamp
## (docs/palette.md). Its colours come from the palette by swatch name, so a change to a swatch reaches every
## surface with this role, in the editor and in the game. Finish (roughness, metal, transparency, emission energy)
## is this material's own, set like any StandardMaterial3D. Roles live in `res://assets/palette/roles/<role>.tres`;
## assets name roles, never colours.

const ROLES_DIR: String = "res://assets/palette/roles/"

## Paint swatch for the surface colour.
@export var swatch: StringName = &"":
	set(v):
		swatch = v
		apply()
## Light swatch the surface emits; empty for a surface that does not glow. Brightness is
## [member emission_energy_multiplier].
@export var glow: StringName = &"":
	set(v):
		glow = v
		apply()
## A second paint swatch drawn as diagonal stripes with [member swatch] (hazard stripes). Uses triplanar mapping,
## so it needs no UVs.
@export var stripe: StringName = &"":
	set(v):
		stripe = v
		apply()
## Width of one stripe (m) when [member stripe] is set.
@export var stripe_width: float = 0.05:
	set(v):
		stripe_width = v
		apply()
## Opacity of the surface colour (glass). Below 1 turns on alpha transparency.
@export_range(0.0, 1.0) var opacity: float = 1.0:
	set(v):
		opacity = v
		apply()


func _init() -> void:
	var pal: Palette = Palette.main()
	if pal != null and not pal.changed.is_connected(apply):
		pal.changed.connect(apply)


## Colours this material takes from the palette are computed, never stored: the file keeps swatch names only, so
## it can't hold a stale copy of a colour.
func _validate_property(property: Dictionary) -> void:
	var driven: Array[String] = ["albedo_color", "albedo_texture", "emission", "emission_enabled", "transparency",
		"uv1_triplanar", "uv1_world_triplanar", "uv1_scale"]
	if driven.has(String(property["name"])):
		property["usage"] = int(property["usage"]) & ~PROPERTY_USAGE_STORAGE


## The shared material for a role, or null if there is no such role.
static func lookup(role: String) -> RoleMaterial:
	if role.is_empty() or not role.is_valid_filename():
		return null
	var path: String = ROLES_DIR + role + ".tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as RoleMaterial


## The role this material is (its file name), or "" for one not saved as a role.
func role_name() -> String:
	return resource_path.get_file().get_basename() if resource_path.begins_with(ROLES_DIR) else ""


## Re-reads the palette. Called when a swatch name changes and whenever the palette changes.
func apply() -> void:
	var pal: Palette = Palette.main()
	if pal == null:
		return
	var base: Color = pal.color(swatch) if swatch != &"" else Color.BLACK
	if stripe != &"":
		albedo_texture = _stripes(base, pal.color(stripe))
		albedo_color = Color(1, 1, 1, opacity)
		uv1_triplanar = true
		uv1_world_triplanar = true
		uv1_scale = Vector3.ONE / maxf(stripe_width * 2.0, 0.001)
	else:
		albedo_texture = null
		albedo_color = Color(base, opacity)
	transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if opacity < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	emission_enabled = glow != &""
	if emission_enabled:
		emission = pal.color(glow)


## A small tileable texture of 45-degree stripes, half `a` and half `b`.
static func _stripes(a: Color, b: Color) -> ImageTexture:
	var n: int = 32
	var img: Image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y: int in range(n):
		for x: int in range(n):
			img.set_pixel(x, y, a if (x + y) % n < n / 2 else b)
	return ImageTexture.create_from_image(img)
