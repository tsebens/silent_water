class_name CanisterRing
extends Node3D
## The ring of indicator lights round a canister's top. Lights a run of its
## segments, from the first, in proportion to the canister's remaining capacity,
## in a colour that steps with it: green fresh, yellow from half, red when nearly
## spent. Bind it to a canister with [member canister]; it follows
## [signal ScrubberCanister.capacity_changed]. Build in [method _ready]; the
## segments lie on a circle in the local XZ plane.
##
## Network sync is not required: display only.

## Fraction of the circle the ring covers (about 300 degrees).
const ARC_FRACTION: float = 300.0 / 360.0

@export var canister: ScrubberCanister
@export var segment_count: int = 12
@export var radius: float = 0.065
@export var segment_size: float = 0.012
## Capacity at or below which the ring turns yellow, and then red.
@export_range(0.0, 1.0) var warn_below: float = 0.5
@export_range(0.0, 1.0) var alarm_below: float = 0.15
@export var ok_swatch: StringName = &"light_ok"
@export var warn_swatch: StringName = &"light_warn"
@export var alarm_swatch: StringName = &"light_alarm"
@export var unlit_swatch: StringName = &"info_black"

var _segments: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _capacity: float = 1.0


func _ready() -> void:
	_build()
	if canister != null:
		bind(canister)
	else:
		set_capacity(_capacity)
	Palette.main().changed.connect(_refresh)


func _exit_tree() -> void:
	var pal: Palette = Palette.main()
	if pal.changed.is_connected(_refresh):
		pal.changed.disconnect(_refresh)


func bind(c: ScrubberCanister) -> void:
	if canister != null and canister.capacity_changed.is_connected(set_capacity):
		canister.capacity_changed.disconnect(set_capacity)
	canister = c
	c.capacity_changed.connect(set_capacity)
	set_capacity(c.capacity)


func set_capacity(v: float) -> void:
	_capacity = clampf(v, 0.0, 1.0)
	_refresh()


## Number of segments lit for [param capacity]: proportional, rounded up, so any
## capacity left shows at least one segment and only a spent canister shows none.
func lit_count_for(capacity: float) -> int:
	return clampi(ceili(clampf(capacity, 0.0, 1.0) * segment_count - 0.0001), 0, segment_count)


func lit_count() -> int:
	return lit_count_for(_capacity)


## Swatch name for [param capacity].
func swatch_for(capacity: float) -> StringName:
	if capacity <= alarm_below:
		return alarm_swatch
	if capacity <= warn_below:
		return warn_swatch
	return ok_swatch


func segment_count_built() -> int:
	return _segments.size()


func segment_lit(i: int) -> bool:
	return i >= 0 and i < _materials.size() and _materials[i].emission_enabled


func segment_color(i: int) -> Color:
	return _materials[i].albedo_color


func _refresh() -> void:
	var lit: int = lit_count_for(_capacity)
	var pal: Palette = Palette.main()
	var on: Color = pal.color(swatch_for(_capacity))
	for i: int in _materials.size():
		var m: StandardMaterial3D = _materials[i]
		if i < lit:
			m.albedo_color = on
			m.emission_enabled = true
			m.emission = on
			m.emission_energy_multiplier = 1.5
		else:
			m.albedo_color = pal.color(unlit_swatch)
			m.emission_enabled = false


func _build() -> void:
	for i: int in segment_count:
		var seg: MeshInstance3D = MeshInstance3D.new()
		seg.name = "Segment%d" % i
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(segment_size, segment_size * 0.4, segment_size)
		seg.mesh = mesh
		var a: float = ARC_FRACTION * TAU * (float(i) / float(maxi(segment_count - 1, 1)))
		seg.position = Vector3(sin(a) * radius, 0.0, cos(a) * radius)
		seg.rotation.y = a
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		seg.material_override = mat
		add_child(seg)
		_segments.append(seg)
		_materials.append(mat)
