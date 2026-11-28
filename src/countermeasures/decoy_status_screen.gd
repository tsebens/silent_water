class_name DecoyStatusScreen
extends MeshInstance3D
## Status screen for the decoy launcher: lists each [DecoyBuoy] in the water as a row of
## number, bearing (degrees, 0 = dead ahead of the sub, clockwise), distance (m) and a noise bar
## of how loud that decoy is where the sub is. Bearings and distances are taken from
## [method SubFrame.render_transform]. The bar is computed from intensity (pressure squared,
## spreading loss via [NoiseLevel]); only the bar's length is scaled in dB for display.
##
## With no decoys it shows only its heading rule on a dark face. A [QuadMesh] facing local +Z
## carries the texture, so no child nodes are needed. Computed locally on every peer.
## Colours are palette swatches; the cyan band is used only for readouts.

const GLYPHS: Dictionary = {
	"0": "111101101101111", "1": "010110010010111", "2": "111001111100111", "3": "111001111001111",
	"4": "101101111001001", "5": "111100111001111", "6": "111100111101111", "7": "111001001001001",
	"8": "111101111101111", "9": "111101111001111",
}
const GLYPH_W: int = 3
const GLYPH_H: int = 5
const ROW_H: int = 12
const HEADER_H: int = 8

@export var frame_group: StringName = &"sub_frame"
@export var buoy_group: StringName = &"decoy_buoys"
@export var sound_type: SoundType = preload("res://src/noise/sound_types/decoy.tres")
## Most rows drawn.
@export var max_rows: int = 6
## Noise bar spans this many dB ending at [member bar_top_db].
@export var bar_top_db: float = 100.0
@export var bar_span_db: float = 60.0
@export var resolution: Vector2i = Vector2i(128, 80)
## Size of the screen quad (m).
@export var screen_size: Vector2 = Vector2(0.16, 0.10)
@export var ink_swatch: StringName = &"light_readout"
@export var face_swatch: StringName = &"info_black"

## Rows from the last update: `{number, bearing, distance, intensity, bar}`.
var rows: Array[Dictionary] = []
var image: Image
var texture: ImageTexture
## False while the DISPLAYS circuit is unpowered.
var powered: bool = true

var _quad: QuadMesh
var _sub_frame: SubFrame


func _ready() -> void:
	_quad = QuadMesh.new()
	_quad.size = screen_size
	image = Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(image)
	mesh = _quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = texture
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	draw()


func _process(_delta: float) -> void:
	if _sub_frame == null or not is_instance_valid(_sub_frame):
		_sub_frame = get_tree().get_first_node_in_group(frame_group) as SubFrame
	if _sub_frame == null:
		return
	var points: PackedVector3Array = PackedVector3Array()
	for n: Node in get_tree().get_nodes_in_group(buoy_group):
		var b: Node3D = n as Node3D
		if b != null:
			points.append(b.global_position)
	update_from_pose(_sub_frame.render_transform(), points)


## Rebuild [member rows] for the sub at [param pose] and decoys at [param positions] (world), and redraw.
func update_from_pose(pose: Transform3D, positions: PackedVector3Array) -> void:
	rows = rows_for(pose, positions)
	if image != null:
		draw()


func rows_for(pose: Transform3D, positions: PackedVector3Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var inv: Transform3D = pose.affine_inverse()
	for i: int in range(mini(positions.size(), max_rows)):
		var local: Vector3 = inv * positions[i]
		var dist: float = local.length()
		var inten: float = heard_intensity(dist)
		out.append({
			"number": i + 1,
			"bearing": bearing_of(local),
			"distance": dist,
			"intensity": inten,
			"bar": bar_fraction(inten),
		})
	return out


## Bearing in whole degrees 0..359 of [param local] (sub space): 0 ahead (-Z), 90 to starboard (+X).
static func bearing_of(local: Vector3) -> int:
	var deg: int = roundi(rad_to_deg(atan2(local.x, -local.z)))
	return posmod(deg, 360)


## Linear intensity of one decoy as heard [param distance] metres away.
func heard_intensity(distance: float) -> float:
	return NoiseLevel.attenuate(sound_type.intensity, distance)


## 0..1 bar length for a linear [param intensity].
func bar_fraction(intensity: float) -> float:
	var db: float = NoiseLevel.to_db(intensity)
	return clampf((db - (bar_top_db - bar_span_db)) / bar_span_db, 0.0, 1.0)


func draw() -> void:
	var pal: Palette = Palette.main()
	var face: Color = pal.color(face_swatch)
	var ink: Color = pal.color(ink_swatch)
	image.fill(face)
	if powered:
		# Heading: a title rule across the top.
		for x: int in range(2, resolution.x - 2):
			image.set_pixel(x, HEADER_H - 2, ink)
		for i: int in range(rows.size()):
			var r: Dictionary = rows[i]
			var y: int = HEADER_H + i * ROW_H + 2
			_text(str(int(r["number"])), 3, y, ink)
			_text(str(int(r["bearing"])).pad_zeros(3), 14, y, ink)
			_text(str(roundi(float(r["distance"]))), 34, y, ink)
			var x0: int = 62
			var w: int = roundi(float(r["bar"]) * float(resolution.x - 2 - x0))
			for bx: int in range(w):
				for by: int in range(GLYPH_H):
					_put(x0 + bx, y + by, ink)
	texture.update(image)


func _text(s: String, x: int, y: int, c: Color) -> void:
	var cx: int = x
	for ch: String in s:
		var g: String = GLYPHS.get(ch, "")
		for k: int in range(g.length()):
			if g[k] == "1":
				_put(cx + k % GLYPH_W, y + k / GLYPH_W, c)
		cx += GLYPH_W + 1


func _put(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < resolution.x and y < resolution.y:
		image.set_pixel(x, y, c)
