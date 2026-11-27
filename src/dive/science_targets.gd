class_name ScienceTargets
extends Resource
## Authored targets for the three science objective types (sweep, probe, photo) in a dive: a sweep area, a list of
## probe points and a list of photo subjects. Content lives in a .tres of this class, not in code. [method apply_to]
## hands them to the host-side objectives; probe points and photo subjects are made as Node3Ds under [param parent].

## Centre of the area to sweep (x and z are used).
@export var sweep_center: Vector3 = Vector3.ZERO
## Size of the sweep area on x and z, metres.
@export var sweep_size: Vector2 = Vector2(120.0, 120.0)
## Fraction of the sweep area to cover.
@export_range(0.05, 1.0) var sweep_fraction: float = 0.8
## Names of the probe points, parallel to [member probe_positions].
@export var probe_names: PackedStringArray = PackedStringArray()
## World positions of the probe points (y is minus the depth).
@export var probe_positions: PackedVector3Array = PackedVector3Array()
## Names of the photo subjects, parallel to [member photo_positions].
@export var photo_names: PackedStringArray = PackedStringArray()
@export var photo_positions: PackedVector3Array = PackedVector3Array()


## Problems with the authoring, as human-readable lines; empty when sound.
func problems() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if sweep_size.x <= 0.0 or sweep_size.y <= 0.0:
		out.append("sweep area has no size")
	if probe_positions.is_empty() or probe_names.size() != probe_positions.size():
		out.append("probe names and positions must match and not be empty")
	if photo_positions.is_empty() or photo_names.size() != photo_positions.size():
		out.append("photo names and positions must match and not be empty")
	return out


func make_probe_points(parent: Node) -> Array[Node3D]:
	return _make(parent, probe_names, probe_positions)


func make_photo_subjects(parent: Node) -> Array[Node3D]:
	return _make(parent, photo_names, photo_positions)


func _make(parent: Node, names: PackedStringArray, positions: PackedVector3Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for i: int in positions.size():
		var n: Node3D = Node3D.new()
		n.name = names[i] if i < names.size() else "Target%d" % i
		parent.add_child(n)
		n.position = positions[i]
		out.append(n)
	return out


## Points the three objectives at these targets. Any of them may be null.
func apply_to(sweep: SweepObjective, probe: ProbeObjective, photo: PhotoObjective, parent: Node) -> void:
	if sweep != null:
		sweep.area_center = sweep_center
		sweep.area_size = sweep_size
		sweep.target_fraction = sweep_fraction
	if probe != null:
		probe.points = make_probe_points(parent)
	if photo != null:
		photo.subjects = make_photo_subjects(parent)
