class_name LinearGauge
extends Node3D
## In-world bar instrument. A bar rises from the bottom of a vertical track as a
## readout on the node in [member source_group] climbs from [member min_value]
## to [member max_value]. The bar's colour steps with the fraction: ok up to
## [member warn_at], warn up to [member alarm_at], alarm above. Like [Gauge] it
## is one node that builds itself in [method _ready]; a scene places it and sets
## the exports. Colour is not the only cue: the bar's height carries the value.
##
## Local axes: the track stands along +Y from the origin (its bottom) and faces +Z.

## Group of the node that provides `readout(name) -> float`.
@export var source_group: StringName = &"sub_readouts"
@export var readout: StringName = &"depth"
@export var min_value: float = 0.0
@export var max_value: float = 100.0
## Fractions of the range where the colour steps: ok below [member warn_at], warn
## from there to [member alarm_at], alarm above it.
@export_range(0.0, 1.0) var warn_at: float = 0.5
@export_range(0.0, 1.0) var alarm_at: float = 0.85
## Palette swatches for the three bands.
@export var ok_swatch: StringName = &"light_ok"
@export var warn_swatch: StringName = &"light_warn"
@export var alarm_swatch: StringName = &"light_alarm"
@export var track_swatch: StringName = &"info_black"
## Track size (m).
@export var track_height: float = 0.2
@export var track_width: float = 0.02
## Bar smoothing (1/s); instruments have lag.
@export var response: float = 8.0

var _bar: Node3D
var _bar_material: StandardMaterial3D
var _source: Node
var _shown: float = 0.0


func _ready() -> void:
	_build()
	_apply(0.0)
	Palette.main().changed.connect(_recolor)


func _exit_tree() -> void:
	var pal: Palette = Palette.main()
	if pal.changed.is_connected(_recolor):
		pal.changed.disconnect(_recolor)


func _process(delta: float) -> void:
	if _source == null or not is_instance_valid(_source):
		_source = get_tree().get_first_node_in_group(source_group)
		if _source == null:
			return
	var target: float = fraction_for(float(_source.call(&"readout", readout)))
	_apply(lerpf(_shown, target, 1.0 - exp(-response * delta)))


## Fill fraction (0..1) for a readout value; out-of-range values clamp.
func fraction_for(v: float) -> float:
	if is_equal_approx(max_value, min_value):
		return 0.0
	return clampf(inverse_lerp(min_value, max_value, v), 0.0, 1.0)


## Swatch name of the band that fraction [param t] falls in.
func swatch_for(t: float) -> StringName:
	if t > alarm_at:
		return alarm_swatch
	if t > warn_at:
		return warn_swatch
	return ok_swatch


## The fraction the bar currently shows.
func shown_fraction() -> float:
	return _shown


## Show [param t] at once, with no smoothing.
func show_fraction(t: float) -> void:
	_apply(clampf(t, 0.0, 1.0))


func _apply(t: float) -> void:
	_shown = t
	if _bar == null:
		return
	# The bar's mesh stands on its origin, so scaling Y grows it upward from the track bottom.
	_bar.scale.y = maxf(t, 0.0001)
	_bar.visible = t > 0.0
	_recolor()


func _recolor() -> void:
	if _bar_material != null:
		_bar_material.albedo_color = Palette.main().color(swatch_for(_shown))
		_bar_material.emission = _bar_material.albedo_color
	var track: MeshInstance3D = get_node_or_null("Track") as MeshInstance3D
	if track != null and track.material_override is StandardMaterial3D:
		(track.material_override as StandardMaterial3D).albedo_color = Palette.main().color(track_swatch)


func _build() -> void:
	var track: MeshInstance3D = MeshInstance3D.new()
	track.name = "Track"
	var track_mesh: BoxMesh = BoxMesh.new()
	track_mesh.size = Vector3(track_width, track_height, 0.002)
	track.mesh = track_mesh
	track.position = Vector3(0, track_height * 0.5, 0)
	var track_mat: StandardMaterial3D = StandardMaterial3D.new()
	track_mat.albedo_color = Palette.main().color(track_swatch)
	track.material_override = track_mat
	add_child(track)

	# The pivot sits at the track bottom, so scaling its Y grows the fill upward.
	_bar = Node3D.new()
	_bar.name = "Bar"
	_bar.position = Vector3(0, 0, 0.0012)
	add_child(_bar)
	var fill: MeshInstance3D = MeshInstance3D.new()
	fill.name = "Fill"
	var bar_mesh: BoxMesh = BoxMesh.new()
	bar_mesh.size = Vector3(track_width * 0.7, track_height, 0.002)
	fill.mesh = bar_mesh
	fill.position = Vector3(0, track_height * 0.5, 0)
	_bar_material = StandardMaterial3D.new()
	_bar_material.emission_enabled = true
	_bar_material.emission_energy_multiplier = 1.5
	fill.material_override = _bar_material
	_bar.add_child(fill)
