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

## Centre chevron column: up when the readout is positive, down when negative.
@export var chevrons_enabled: bool = false
@export var chevron_readout: StringName = &""
## Chevrons in each direction.
@export var chevron_count: int = 3
## Readout units per lit chevron.
@export var chevron_step: float = 1.0
## Edge ring of segments, lit in proportion to a 0..1 readout.
@export var ring_enabled: bool = false
@export var ring_readout: StringName = &""
@export var ring_segments: int = 24
## The ring steps to the warning swatch at or below this fraction, then the alarm swatch.
@export_range(0.0, 1.0) var ring_warn_below: float = 0.5
@export_range(0.0, 1.0) var ring_alarm_below: float = 0.2
@export var ring_ok_swatch: StringName = &"light_ok"
@export var ring_warn_swatch: StringName = &"light_warn"
@export var ring_alarm_swatch: StringName = &"light_alarm"
@export var ring_unlit_swatch: StringName = &"interior_dark"
## Optional configuration copied onto this display in [method _ready].
@export var preset: MultiDisplayPreset

## Latest chevron and ring readouts.
var chevron_value: float = 0.0
var ring_value: float = 0.0

## Latest readout of each slot (0 for an empty slot or until a source is found).
var values: Array[float] = [0.0, 0.0, 0.0, 0.0]

var viewport: SubViewport
var canvas: MultiDisplayCanvas
var _quad: QuadMesh
var _source: Node


func _ready() -> void:
	if preset != null:
		apply_preset(preset)
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


## Copy [param p] onto this display.
func apply_preset(p: MultiDisplayPreset) -> void:
	slots = p.slots
	chevrons_enabled = p.chevrons_enabled
	chevron_readout = p.chevron_readout
	chevron_count = p.chevron_count
	chevron_step = p.chevron_step
	ring_enabled = p.ring_enabled
	ring_readout = p.ring_readout
	ring_segments = p.ring_segments
	ring_warn_below = p.ring_warn_below
	ring_alarm_below = p.ring_alarm_below


## Chevrons lit for [param v]: 0 when off or zero, otherwise 1..[member chevron_count].
func chevrons_lit(v: float) -> int:
	if not chevrons_enabled or chevron_step <= 0.0 or is_zero_approx(v):
		return 0
	return clampi(ceili(absf(v) / chevron_step), 1, maxi(chevron_count, 0))


## Segments lit for the 0..1 readout [param v]: 0 when the ring is off.
func ring_lit(v: float) -> int:
	if not ring_enabled:
		return 0
	return clampi(roundi(clampf(v, 0.0, 1.0) * ring_segments), 0, ring_segments)


## Fraction of the ring lit for [param v].
func ring_lit_fraction(v: float) -> float:
	return float(ring_lit(v)) / float(ring_segments) if ring_segments > 0 else 0.0


## Swatch of the lit ring segments at [param v].
func ring_swatch_for(v: float) -> StringName:
	if v <= ring_alarm_below:
		return ring_alarm_swatch
	return ring_warn_swatch if v <= ring_warn_below else ring_ok_swatch


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
	if chevrons_enabled and chevron_readout != &"":
		chevron_value = float(_source.call(&"readout", chevron_readout))
	if ring_enabled and ring_readout != &"":
		ring_value = float(_source.call(&"readout", ring_readout))
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
		_paint_ring(c, r, pal)
		_paint_chevrons(c, r, pal)
		for i: int in range(4):
			if not display.draws_slot(i):
				continue
			var dir: Vector2 = [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)][i]
			_paint_slot(display.slot_at(i), display.values[i], c + dir * r * 0.5, r * 0.4, i)
			painted += 1

	func _paint_ring(c: Vector2, r: float, pal: Palette) -> void:
		var n: int = display.ring_segments
		if not display.ring_enabled or n <= 0:
			return
		var lit: int = display.ring_lit(display.ring_value)
		var on: Color = pal.color(display.ring_swatch_for(display.ring_value))
		var off: Color = pal.color(display.ring_unlit_swatch)
		var step: float = TAU / float(n)
		for k: int in range(n):
			var a0: float = -PI * 0.5 + step * float(k) + step * 0.12
			draw_arc(c, r * 0.93, a0, a0 + step * 0.76, 6, on if k < lit else off, r * 0.05, true)

	func _paint_chevrons(c: Vector2, r: float, pal: Palette) -> void:
		if not display.chevrons_enabled:
			return
		var v: float = display.chevron_value
		var lit: int = display.chevrons_lit(v)
		var up: float = -1.0 if v >= 0.0 else 1.0
		var on: Color = pal.color(&"light_readout")
		var off: Color = pal.color(display.ring_unlit_swatch)
		var w: float = r * 0.12
		for k: int in range(display.chevron_count):
			var y: float = c.y + up * (k + 0.5) * r * 0.1 - up * r * 0.02
			var tip: Vector2 = Vector2(c.x, y + up * w * 0.5)
			var col: Color = on if k < lit else off
			draw_polyline(PackedVector2Array([tip + Vector2(-w, -up * w), tip, tip + Vector2(w, -up * w)]), col, 3.0, true)

	func _text(pos: Vector2, s: String, px: int, col: Color) -> void:
		var f: Font = ThemeDB.fallback_font
		var w: float = f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(f, pos - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)

	## Paint one slot inside the box of half-size [param h] centred at [param at].
	func _paint_slot(s: MultiDisplaySlot, v: float, at: Vector2, h: float, i: int) -> void:
		var col: Color = display.colour_for(i)
		var px: int = int(h * 0.6)
		if not s.label.is_empty():
			# The bottom slot sits under the rate chevrons, so its label goes
			# below the value instead of above it.
			var label_y: float = -h * 0.72
			if i == MultiDisplay.Slot.BOTTOM:
				label_y = px * 0.3 + h * 0.4
			_text(at + Vector2(0, label_y), s.label, int(h * 0.3), Palette.main().color(s.swatch))
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
