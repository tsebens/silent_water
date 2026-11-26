class_name Navball
extends Node3D
## An attitude ball. Heading, pitch and roll all come out of one rotation: each frame the ball node is held
## at the inverse of the sub's orientation (from [method SubFrame.render_transform], the smoothed pose that is
## drawn, not the raw replicated one), so the apex points at world up and the N mark at world north.
## Two [Label3D] children show the heading and pitch numbers from [member source_group].
##
## The ball mesh has no UVs: [code]navball.gdshader[/code] samples the marking mask by object-space direction
## (+Y apex, -Z north). The script gives the ball node that material in [method _ready].

const SHADER: Shader = preload("res://src/interact/navball.gdshader")
const MASK: Texture2D = preload("res://assets/textures/navball_mask.png")

@export var source_group: StringName = &"sub_readouts"
@export var frame_group: StringName = &"sub_frame"
@export var ball_path: NodePath = ^"Ball"
@export var heading_label_path: NodePath = ^"HDG"
@export var pitch_label_path: NodePath = ^"PITCH"
## Mounting offset: the ball's marking frame relative to its node, as Euler angles in degrees.
@export var mount_rotation_deg: Vector3 = Vector3.ZERO
@export var heading_readout: StringName = &"heading_deg"
@export var pitch_readout: StringName = &"pitch_deg"
@export var upper_swatch: StringName = &"env_teal"
@export var lower_swatch: StringName = &"floor_rock_black"
@export var mark_swatch: StringName = &"light_readout"

var material: ShaderMaterial
var _ball: Node3D
var _heading_label: Label3D
var _pitch_label: Label3D
var _sub_frame: SubFrame
var _source: Node


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter(&"mask", MASK)
	var pal: Palette = Palette.main()
	material.set_shader_parameter(&"upper_color", pal.color(upper_swatch))
	material.set_shader_parameter(&"lower_color", pal.color(lower_swatch))
	material.set_shader_parameter(&"mark_color", pal.color(mark_swatch))
	_ball = get_node_or_null(ball_path) as Node3D
	if _ball is GeometryInstance3D:
		(_ball as GeometryInstance3D).material_override = material
	_heading_label = get_node_or_null(heading_label_path) as Label3D
	_pitch_label = get_node_or_null(pitch_label_path) as Label3D


func _process(_delta: float) -> void:
	if _sub_frame == null or not is_instance_valid(_sub_frame):
		_sub_frame = get_tree().get_first_node_in_group(frame_group) as SubFrame
	if _sub_frame != null:
		apply_pose(_sub_frame.render_transform())
	if _source == null or not is_instance_valid(_source):
		_source = get_tree().get_first_node_in_group(source_group)
	if _source != null:
		if _heading_label != null:
			_heading_label.text = heading_text(float(_source.call(&"readout", heading_readout)))
		if _pitch_label != null:
			_pitch_label.text = pitch_text(float(_source.call(&"readout", pitch_readout)))


## Orient the ball for the sub pose [param pose]: the inverse of its orientation, then the mounting offset.
func apply_pose(pose: Transform3D) -> void:
	if _ball == null:
		return
	_ball.basis = ball_basis(pose.basis)


func ball_basis(sub_basis: Basis) -> Basis:
	var mount: Basis = Basis.from_euler(mount_rotation_deg * (PI / 180.0))
	return sub_basis.orthonormalized().inverse() * mount


## Heading digits `000`-`359`.
static func heading_text(deg: float) -> String:
	return "%03d" % posmod(roundi(deg), 360)


## Pitch in signed whole degrees: `+12`, `-8`, `0`.
static func pitch_text(deg: float) -> String:
	var n: int = roundi(deg)
	if n == 0:
		return "0"
	return "%+d" % n
