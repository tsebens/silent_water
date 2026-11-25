class_name SonarPanel
extends Node3D
## Fits out the sonar panel: the bearing chart ([FlatChart]) becomes the screen, and the SIGNAL and BRG RATE dials
## sit either side of the hydrophone wheel. The hull no longer carries panel furniture, so each piece is placed at a
## fixed spot in the sub model's frame and faces the seat (-Z in the sub frame).

## Sub-model-frame positions of the screen and the two dials.
@export var screen_pos: Vector3 = Vector3(1.38, 0.925, 1.502)
@export var signal_pos: Vector3 = Vector3(1.075, 1.096, 1.585)
@export var rate_pos: Vector3 = Vector3(0.897, 1.096, 1.585)
@export var model: SubModel
@export var screen: FlatChart
@export var signal_gauge: Gauge
@export var rate_gauge: Gauge


func _ready() -> void:
	# The parent is still adding its children; place them once that is done.
	_mount_all.call_deferred()


func _mount_all() -> void:
	_mount(screen, screen_pos, PI)
	_mount(signal_gauge, signal_pos, PI)
	_mount(rate_gauge, rate_pos, PI)


## Place `node` at `pos` in the model's frame, turned `yaw` about up. The node stays where it is in the tree.
func _mount(node: Node3D, pos: Vector3, yaw: float) -> void:
	if node == null or model == null:
		push_warning("SonarPanel: cannot mount '%s'" % [node.name if node != null else "null"])
		return
	node.global_transform = model.global_transform * Transform3D(Basis(Vector3.UP, yaw), pos)
