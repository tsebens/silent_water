class_name ImpairmentView
extends Node3D
## Bad-air view for the local camera: a soft blur that fades in and out in
## periods (longer and more frequent as strength rises) and a vignette that
## narrows from the edges, from a full-screen quad. No FOV change or lens
## distortion. Reads the owning player's [PlayerImpairment]; drawn only while
## the tracked camera is the one rendering (as [UnderwaterView] does).

const DEFAULT_PARAMS: String = "res://src/life_support/impairment_params.tres"
## Seconds between blur periods at strength 0 and 1 (start to start).
const PERIOD_AT_0: float = 40.0
const PERIOD_AT_1: float = 9.0
## Seconds each blur period lasts at strength 0 and 1.
const ON_AT_0: float = 2.0
const ON_AT_1: float = 7.0
## Longest fade in or out (s); shorter periods fade over half their length.
const FADE_MAX: float = 1.5

@export var params: ImpairmentParams
@export var camera_path: NodePath = ^".."
@export var impairment_path: NodePath = ^"../../../Impairment"
## Vignette tint: a palette swatch.
@export var vignette_swatch: StringName = &"sub_black"

## Last applied blur and vignette (0 to 1), for tests and tuning.
var blur: float = 0.0
var vignette: float = 0.0

var _camera: Node3D
var _impairment: PlayerImpairment
var _quad: MeshInstance3D
var _clock: float = 0.0


## Peak blur at [param strength]: it follows the strength.
static func blur_amount(strength: float, p: ImpairmentParams) -> float:
	return clampf(strength, 0.0, 1.0) * p.blur_at_full


## Vignette narrowing at [param strength]: none below the start, then linear.
static func vignette_amount(strength: float, p: ImpairmentParams) -> float:
	var s: float = clampf(strength, 0.0, 1.0)
	if s <= p.vignette_start_strength:
		return 0.0
	var t: float = (s - p.vignette_start_strength) / maxf(1.0 - p.vignette_start_strength, 0.0001)
	return t * p.vignette_at_full


## Seconds from the start of one blur period to the next.
static func period_for(strength: float) -> float:
	return lerpf(PERIOD_AT_0, PERIOD_AT_1, clampf(strength, 0.0, 1.0))


## Seconds each blur period lasts.
static func on_time_for(strength: float) -> float:
	return lerpf(ON_AT_0, ON_AT_1, clampf(strength, 0.0, 1.0))


## Periodic blur envelope (0 to 1) at time [param t]: 0 at or below no
## strength, otherwise a smooth pulse per period.
static func blur_envelope(strength: float, t: float) -> float:
	if strength <= 0.0:
		return 0.0
	var period: float = period_for(strength)
	var on: float = on_time_for(strength)
	var phase: float = fposmod(t, period)
	if phase >= on:
		return 0.0
	var fade: float = minf(FADE_MAX, on * 0.5)
	return smoothstep(0.0, fade, phase) * (1.0 - smoothstep(on - fade, on, phase))


func _ready() -> void:
	if params == null:
		params = load(DEFAULT_PARAMS) as ImpairmentParams
	_camera = get_node_or_null(camera_path) as Node3D
	_impairment = get_node_or_null(impairment_path) as PlayerImpairment
	_quad = get_node_or_null("Quad") as MeshInstance3D
	_apply(0.0, 0.0)


func _process(delta: float) -> void:
	if not _camera_is_active():
		_apply(0.0, 0.0)
		return
	_clock += delta
	var s: float = DevSettings.forced_impairment()
	if s < 0.0:
		s = _impairment.impairment if _impairment != null else 0.0
	var linger: float = _impairment.linger_blur if _impairment != null else 0.0
	_apply(maxf(blur_amount(s, params) * blur_envelope(s, _clock), linger), vignette_amount(s, params))


## True when the tracked camera is the one rendering. Non-camera nodes count as
## active (tests).
func _camera_is_active() -> bool:
	var cam: Camera3D = _camera as Camera3D
	return cam == null or cam.current


func _apply(blur_value: float, vignette_value: float) -> void:
	blur = blur_value
	vignette = vignette_value
	if _quad == null:
		return
	_quad.visible = blur > 0.0005 or vignette > 0.0005
	var mat: ShaderMaterial = _quad.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter(&"blur", blur)
		mat.set_shader_parameter(&"vignette", vignette)
		mat.set_shader_parameter(&"vignette_color", Palette.main().color(vignette_swatch))
