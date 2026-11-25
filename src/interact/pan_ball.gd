class_name PanBall
extends Interactable
## A trackball that pans a view. Dragging while held rolls the ball and emits
## [signal rolled] with a 2D roll delta (screen-space: x right, y down, scaled
## by [member roll_per_px]); it is not a hydrophone bearing. The value is the
## total roll about the ball's local Y axis, kept only so the ball pose
## replicates.

## Emitted on the holder's machine for every drag step.
signal rolled(delta: Vector2)

## Roll (radians) per pixel of mouse drag.
@export var roll_per_px: float = 0.02
@export var ball: Node3D

var _ball_basis: Basis = Basis.IDENTITY
var _have_ball: bool = false


func _init() -> void:
	super._init()
	min_value = -1.0e6
	max_value = 1.0e6


func drag(relative: Vector2) -> void:
	if not is_held_locally():
		return
	var delta: Vector2 = roll_delta(relative)
	if delta == Vector2.ZERO:
		return
	_roll_ball(delta)
	rolled.emit(delta)
	if is_inside_tree():
		drive_to(get_value() + delta.x, true)


## The roll a mouse drag of [param relative] pixels produces.
func roll_delta(relative: Vector2) -> Vector2:
	return relative * roll_per_px


func _roll_ball(delta: Vector2) -> void:
	if ball == null:
		return
	if not _have_ball:
		_ball_basis = ball.transform.basis
		_have_ball = true
	# Dragging right spins the ball about up; dragging down about the X axis.
	var b: Basis = Basis(Vector3.UP, delta.x) * Basis(Vector3.RIGHT, delta.y)
	ball.transform.basis = b * ball.transform.basis


func _apply_visual(_v: float) -> void:
	pass


func interaction_hint() -> String:
	return "hold click, drag to pan"
