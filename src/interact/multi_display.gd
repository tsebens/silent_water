class_name MultiDisplay
extends MeshInstance3D
## A round instrument face with up to four widget slots (top, left, right,
## bottom). Each slot reads a named readout from the node in [member source_group]
## (`readout(name) -> float`) and shows it as a number, text, pie, dial, vertical
## bar, or nothing. What each slot shows is a [MultiDisplaySlot] resource.
##
## Like [Gauge] it is one node that builds itself in [method _ready]. The face is
## drawn by a SubViewport onto a quad of [member screen_diameter]. Colours are
## palette swatches: `light_readout` for information, the indicator swatches for
## warnings, and a warning also adds `!` marks so colour is never the only cue.
##
## The quad faces local +Z.

enum Slot { TOP, LEFT, RIGHT, BOTTOM }

@export var source_group: StringName = &"sub_readouts"
## Slots in the order top, left, right, bottom. Missing entries are empty.
@export var slots: Array[MultiDisplaySlot] = []
## Diameter of the round face, and so the quad (m).
@export var screen_diameter: float = 0.3:
	set(v):
		screen_diameter = v
		if _quad != null:
			_quad.size = Vector2(v, v)
@export var resolution: int = 512
@export var face_swatch: StringName = &"info_black"
@export var rim_swatch: StringName = &"light_readout"

## Latest readout of each slot (0 for an empty slot or until a source is found).
var values: Array[float] = [0.0, 0.0, 0.0, 0.0]

var viewport: SubViewport
var canvas: MultiDisplayCanvas
var _quad: QuadMesh
var _source: Node


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = Vector2i(resolution, resolution)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	canvas = MultiDisplayCanvas.new()
	canvas.name = "Canvas"
	canvas.display = self
	canvas.size = Vector2(resolution, resolution)
	viewport.add_child(canvas)
	_quad = QuadMesh.new()
	_quad.size = Vector2(screen_diameter, screen_diameter)
	mesh = _quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat


func _process(_delta: float) -> void:
	refresh()
	if canvas != null:
		canvas.queue_redraw()


## The slot at [param i], or null when there is none.
func slot_at(i: int) -> MultiDisplaySlot:
	return slots[i] if i >= 0 and i < slots.size() else null


## True when slot [param i] has something to draw.
func draws_slot(i: int) -> bool:
	var s: MultiDisplaySlot = slot_at(i)
	return s != null and s.kind != MultiDisplaySlot.Kind.EMPTY


## Read every slot's readout from the source group into [member values].
func refresh() -> void:
	if _source == null or not is_instance_valid(_source):
		_source = get_tree().get_first_node_in_group(source_group) if is_inside_tree() else null
		if _source == null:
			return
	for i: int in range(4):
		if draws_slot(i) and slot_at(i).readout != &"":
			values[i] = float(_source.call(&"readout", slot_at(i).readout))


## Palette colour for slot [param i] at its current value.
func colour_for(i: int) -> Color:
	return Palette.main().color(slot_at(i).swatch_for(values[i]))


class MultiDisplayCanvas:
	extends Control

	var display: MultiDisplay
	## Slots painted in the last draw.
	var painted: int = 0

	func _draw() -> void:
		painted = 0
		if display == null:
			return
		var pal: Palette = Palette.main()
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 * 0.97
		draw_circle(c, r, pal.color(display.face_swatch))
		draw_arc(c, r, 0.0, TAU, 64, pal.color(display.rim_swatch), 3.0, true)
		for i: int in range(4):
			if not display.draws_slot(i):
				continue
			var dir: Vector2 = [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)][i]
			_paint_slot(display.slot_at(i), display.values[i], c + dir * r * 0.5, r * 0.4, i)
			painted += 1

	func _text(pos: Vector2, s: String, px: int, col: Color) -> void:
		var f: Font = ThemeDB.fallback_font
		var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(f, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

	## Paint one slot inside the box of half-size [param h] centred at [param at].
	func _paint_slot(s: MultiDisplaySlot, v: float, at: Vector2, h: float, i: int) -> void:
		var col: Color = display.colour_for(i)
		var px: int = int(h * 0.6)
		if not s.label.is_empty():
			_text(at + Vector2(0, -h * 0.72), s.label, int(h * 0.3), Palette.main().color(s.swatch))
		var mark: String = s.marker_for(v)
		match s.kind:
			MultiDisplaySlot.Kind.NUMBER:
				_text(at + Vector2(0, px * 0.3), mark + s.number_for(v), px, col)
			MultiDisplaySlot.Kind.TEXT:
				_text(at + Vector2(0, px * 0.3), mark + s.text_for(v), px, col)
			MultiDisplaySlot.Kind.PIE:
				var pts: PackedVector2Array = [at]
				var n: int = 32
				var f: float = s.pie_for(v)
				for k: int in range(n + 1):
					var a: float = -PI * 0.5 + TAU * f * float(k) / float(n)
					pts.append(at + Vector2(cos(a), sin(a)) * h * 0.5)
				if f > 0.001:
					draw_colored_polygon(pts, col)
				draw_arc(at, h * 0.5, 0.0, TAU, 32, col, 2.0, true)
				_text(at + Vector2(0, h * 0.95), mark + s.number_for(v), int(h * 0.3), col)
			MultiDisplaySlot.Kind.DIAL:
				var start: float = deg_to_rad(135.0)
				var sweep: float = deg_to_rad(270.0)
				draw_arc(at, h * 0.55, start, start + sweep, 32, col, 2.0, true)
				var a2: float = start + sweep * s.fraction_for(v)
				draw_line(at, at + Vector2(cos(a2), sin(a2)) * h * 0.5, col, 4.0, true)
				_text(at + Vector2(0, h * 0.95), mark + s.number_for(v), int(h * 0.3), col)
			MultiDisplaySlot.Kind.BAR:
				var top: float = at.y - h * 0.6
				var len: float = h * 1.2
				var w: float = h * 0.3
				draw_rect(Rect2(at.x - w * 0.5, top, w, len), col, false, 2.0)
				var span: Vector2 = s.bar_span(v)
				var y1: float = top + len * (1.0 - span.y)
				var y0: float = top + len * (1.0 - span.x)
				draw_rect(Rect2(at.x - w * 0.5, y1, w, maxf(y0 - y1, 1.0)), col)
				_text(at + Vector2(0, h * 1.1), mark + s.number_for(v), int(h * 0.3), col)
