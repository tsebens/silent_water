class_name ScanScreen
extends MeshInstance3D
## The SCAN module's screen: a progress ring, the range to the array and a hint, drawn from the parent [ScanModule].
## The quad faces local +Z. Colours are palette swatches. Dark while the module is unpowered.

@export var screen_size: Vector2 = Vector2(0.16, 0.16)
@export var resolution: int = 128
@export var ring_swatch: StringName = &"light_readout"
@export var face_swatch: StringName = &"info_black"

var image: Image
var texture: ImageTexture
var range_label: Label3D
var hint_label: Label3D
## The ring fill last drawn, 0..1 (-1 before the first draw).
var drawn_fill: float = -1.0

var _module: ScanModule


func _ready() -> void:
	_module = get_parent() as ScanModule
	image = Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(image)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = screen_size
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = texture
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	range_label = _add_label(Vector3(0, 0.0, 0.0005), 0.0006)
	hint_label = _add_label(Vector3(0, -screen_size.y * 0.32, 0.0005), 0.0004)
	refresh()


func _process(_delta: float) -> void:
	refresh()


## Redraw the ring and the labels from the module.
func refresh() -> void:
	var on: bool = _module != null and _module.powered
	range_label.visible = on
	hint_label.visible = on
	var fill: float = _module.ring() if on else 0.0
	if on:
		var r: float = _module.range_m()
		range_label.text = "%d m" % roundi(r) if r >= 0.0 else "-- m"
		hint_label.text = _module.hint()
	if not is_equal_approx(fill, drawn_fill):
		draw_ring(fill)


## Draw the ring filled clockwise from the top to [param fill].
func draw_ring(fill: float) -> void:
	drawn_fill = fill
	var pal: Palette = Palette.main()
	var face: Color = pal.color(face_swatch)
	var lit: Color = pal.color(ring_swatch)
	var dim: Color = face.lerp(lit, 0.2)
	image.fill(face)
	var c: float = float(resolution - 1) * 0.5
	var r_out: float = c * 0.92
	var r_in: float = c * 0.72
	for y: int in range(resolution):
		for x: int in range(resolution):
			var d: Vector2 = Vector2(float(x) - c, float(y) - c)
			var dist: float = d.length()
			if dist < r_in or dist > r_out:
				continue
			var a: float = fposmod(atan2(d.x, -d.y), TAU) / TAU
			image.set_pixel(x, y, lit if a <= fill else dim)
	texture.update(image)


func _add_label(pos: Vector3, pixel: float) -> Label3D:
	var l: Label3D = Label3D.new()
	l.pixel_size = pixel
	l.position = pos
	l.modulate = Palette.main().color(ring_swatch)
	l.outline_size = 0
	l.font_size = 32
	add_child(l)
	return l
