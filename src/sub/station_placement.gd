class_name StationPlacement
extends Node3D
## Places a station's parts from the program (SubLayout), so no position in the scene is a literal in the
## hull frame. The node sits at the interior origin; each entry of [member placements] maps a node path
## (relative to this node) to an offset from the station's floor position, in the interior frame.

## Id of the station in the program (assets/models/vehicles/sub_interior/program.yaml).
@export var station_id: StringName = &"pilot"
## Node path (String) -> Vector3 offset from the station's floor position.
@export var placements: Dictionary = {}


func _enter_tree() -> void:
	apply()


## Moves every listed node to the station's program position plus its offset.
func apply() -> void:
	var origin: Vector3 = SubLayout.position(station_id)
	for path: Variant in placements.keys():
		var target: Node3D = get_node_or_null(NodePath(String(path))) as Node3D
		assert(target != null, "StationPlacement: no node '%s' under %s" % [path, get_path()])
		if target != null:
			target.position = origin + (placements[path] as Vector3)
