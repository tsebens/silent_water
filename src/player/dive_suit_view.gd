class_name DiveSuitView
extends Node3D
## Helmet frame for the local camera while a [DiveSuit] is worn: the screen
## narrows from the edges by the model's view narrowing, and the frame takes the
## low-air warning colour as the air runs down (the air cue, no HUD). Drawn only
## while the tracked camera is the one rendering, like [ImpairmentView].

@export var camera_path: NodePath = ^".."
@export var player_path: NodePath = ^"../../.."
## Frame tint at each warning level: palette swatches.
@export var frame_swatch: StringName = &"sub_black"
@export var low_swatch: StringName = &"light_warn"
@export var critical_swatch: StringName = &"light_alarm"
## How far the warning swatch tints the frame (0 to 1).
@export_range(0.0, 1.0) var warning_tint: float = 0.6

## Last applied narrowing (0 to 1) and warning level, for tests and tuning.
var narrowing: float = 0.0
var warning: int = DiveSuitModel.WARN_NONE

var _camera: Node3D
var _player: Player
var _quad: MeshInstance3D


## Swatch for the frame at a warning [param level].
func swatch_for(level: int) -> StringName:
	match level:
		DiveSuitModel.WARN_LOW:
			return low_swatch
		DiveSuitModel.WARN_CRITICAL:
			return critical_swatch
	return frame_swatch


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Node3D
	_player = get_node_or_null(player_path) as Player
	_quad = get_node_or_null("Quad") as MeshInstance3D
	_apply(null)


func _process(_delta: float) -> void:
	var suit: DiveSuit = _player.worn_suit() if _player != null else null
	if suit == null or not _camera_is_active():
		_apply(null)
		return
	_apply(suit.model)


func _camera_is_active() -> bool:
	var cam: Camera3D = _camera as Camera3D
	return cam == null or cam.current


## Shows the frame for [param model], or hides it when null.
func _apply(model: DiveSuitModel) -> void:
	narrowing = model.view_narrowing() if model != null else 0.0
	warning = model.warning_level() if model != null else DiveSuitModel.WARN_NONE
	if _quad == null:
		return
	_quad.visible = narrowing > 0.0005
	var mat: ShaderMaterial = _quad.material_override as ShaderMaterial
	if mat == null:
		return
	var base: Color = Palette.main().color(frame_swatch)
	var tint: float = 0.0 if warning == DiveSuitModel.WARN_NONE else warning_tint
	mat.set_shader_parameter(&"narrowing", narrowing)
	mat.set_shader_parameter(&"frame_color", base.lerp(Palette.main().color(swatch_for(warning)), tint))
