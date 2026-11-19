class_name Reticle
extends CanvasLayer
## The aiming point: a small dot at screen centre that brightens over a
## usable control and names it, with a one-line hint. A deliberate, minimal
## exception to "no HUD" (M6.1), to revisit after playtests.

const DOT_IDLE: Color = Color(1, 1, 1, 0.35)
const DOT_ACTIVE: Color = Color(1.0, 0.92, 0.6, 0.95)

@export var game: Game

var _dot: Control
var _name: Label
var _hint: Label
var _status: Label
var _active: bool = false


func _ready() -> void:
	layer = 5
	_dot = Control.new()
	_dot.set_anchors_preset(Control.PRESET_CENTER)
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dot.draw.connect(_draw_dot)
	add_child(_dot)
	_name = _label(18, Color(1.0, 0.92, 0.6), 22.0)
	_hint = _label(13, Color(0.85, 0.85, 0.8, 0.85), 46.0)
	_status = _label(13, Color(0.6, 0.85, 0.75, 0.85), -60.0)


func _process(_delta: float) -> void:
	var me: Player = game.local_player() if game != null else null
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	visible = me != null and captured
	if not visible:
		return
	var target: Interactable = me.held_control()
	var holding: bool = target != null
	if target == null and me.seat() == null:
		target = me.aim_target()
	_active = target != null
	if me.seat() != null:
		_name.text = "PILOT SEAT"
		_hint.text = "WASD flies · click to stand"
	elif target != null:
		_name.text = target.display_name() + ("  (holding)" if holding else "")
		_hint.text = target.interaction_hint()
	else:
		_name.text = ""
		_hint.text = ""
	_status.text = "SONAR HEADSET ON" if me.worn() != null else ""
	_dot.queue_redraw()


func _draw_dot() -> void:
	var r: float = 4.0 if _active else 2.5
	_dot.draw_circle(Vector2.ZERO, r, DOT_ACTIVE if _active else DOT_IDLE)
	if _active:
		_dot.draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 24, Color(DOT_ACTIVE, 0.5), 1.5)


func _label(size: int, color: Color, offset_y: float) -> Label:
	var l: Label = Label.new()
	# Full width, centred text, a fixed distance above or below screen centre.
	l.anchor_left = 0.0
	l.anchor_right = 1.0
	l.anchor_top = 0.5
	l.anchor_bottom = 0.5
	l.offset_top = offset_y
	l.offset_bottom = offset_y + size * 1.6
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override(&"outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l
