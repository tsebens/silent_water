class_name StationPlacement
extends Node3D
## Places a station's parts from the program (SubLayout), so no position in the scene is a literal in the
## hull frame. The node sits at the interior origin; each entry of [member placements] maps a node path
## (relative to this node) to an offset from the station's floor position, in the interior frame.

## Id of the station in the program (assets/models/vehicles/sub_interior/program.yaml).
@export var station_id: StringName = &"pilot"
## Node path (String) -> Vector3 offset from the station's floor position.
@export var placements: Dictionary = {}
## Node path (relative to this node) -> path of a Node3D in this tree whose position it takes, once the tree is ready
## (the pilot hologram sits at the station's HologramAnchor).
@export var follow: Dictionary = {}


func _enter_tree() -> void:
	apply()


func _ready() -> void:
	for path: Variant in follow.keys():
		var target: Node3D = get_node_or_null(NodePath(String(path))) as Node3D
		var anchor: Node3D = get_node_or_null(NodePath(String(follow[path]))) as Node3D
		assert(target != null and anchor != null, "StationPlacement: bad follow '%s' under %s" % [path, get_path()])
		if target != null and anchor != null:
			target.global_position = anchor.global_position


## Moves every listed node to the station's program position plus its offset.
func apply() -> void:
	var origin: Vector3 = SubLayout.position(station_id)
	for path: Variant in placements.keys():
		var target: Node3D = get_node_or_null(NodePath(String(path))) as Node3D
		assert(target != null, "StationPlacement: no node '%s' under %s" % [path, get_path()])
		if target != null:
			target.position = origin + (placements[path] as Vector3)
