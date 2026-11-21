class_name SonarPanel
extends Node3D
## Fits out the sonar panel on the sub model's bezels: the bearing chart
## ([FlatChart]) becomes the screen on the large bezel, and the SIGNAL and
## BRG RATE dials sit in the two small ones. Which mesh part is which is a
## property of the model (see [SubModel.part]); everything is mounted facing
## the seat (-Z in the sub frame).

@export var screen_part: StringName = &"Bezel"
@export var signal_part: StringName = &"Bezel2"
@export var rate_part: StringName = &"Bezel3"
@export var model: SubModel
@export var screen: FlatChart
@export var signal_gauge: Gauge
@export var rate_gauge: Gauge
## How far in front of the bezel's face centre-plane the dials and screen sit
## (m, local -Z is the front).
@export var screen_z: float = -0.063
@export var gauge_z: float = -0.026


func _ready() -> void:
	# The parent is still adding its children; mount once that is done.
	_mount_all.call_deferred()


func _mount_all() -> void:
	_mount(screen, screen_part, Vector3(0, 0, screen_z), 0.0)
	_mount(signal_gauge, signal_part, Vector3(0, 0, gauge_z), PI)
	_mount(rate_gauge, rate_part, Vector3(0, 0, gauge_z), PI)


func _mount(node: Node3D, part_name: StringName, local_pos: Vector3, yaw: float) -> void:
	var part: MeshInstance3D = model.part(String(part_name)) if model != null else null
	if node == null or part == null:
		push_warning("SonarPanel: cannot mount onto '%s'" % part_name)
		return
	node.get_parent().remove_child(node)
	part.add_child(node)
	node.position = local_pos
	if node is Gauge:
		node.rotation = Vector3(0, yaw, 0)
