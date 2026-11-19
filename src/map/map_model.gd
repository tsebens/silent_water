class_name MapModel
extends Node
## The crew's shared chart: pins on the map table and sonar contact marks.
## Every hologram (pilot map, map table) draws from this one model. The host
## owns the list; any peer can ask to add or remove a pin, and the host
## sends the whole list back to everyone (it's small).

signal changed

enum Kind { WAYPOINT, DANGER, APEX, NOTE, CONTACT }

const KIND_NAMES: PackedStringArray = ["WAYPOINT", "DANGER", "LAST SEEN: APEX", "NOTE", "SONAR CONTACT"]
const KIND_COLORS: Array[Color] = [
	Color(0.35, 0.9, 1.0), Color(1.0, 0.3, 0.25), Color(1.0, 0.55, 0.15), Color(0.9, 0.9, 0.85), Color(1.0, 0.8, 0.2),
]
const MAX_PINS: int = 64

## [{id, pos (world), kind, author}], oldest first.
var pins: Array[Dictionary] = []

var _next_id: int = 1


func _ready() -> void:
	add_to_group(&"map_model")
	Net.peer_joined.connect(_on_peer_joined)


static func kind_name(kind: int) -> String:
	return KIND_NAMES[clampi(kind, 0, KIND_NAMES.size() - 1)]


static func kind_color(kind: int) -> Color:
	return KIND_COLORS[clampi(kind, 0, KIND_COLORS.size() - 1)]


## Any peer: place a pin at a world position.
func add_pin(world_pos: Vector3, kind: int) -> void:
	if multiplayer.is_server():
		_host_add(world_pos, kind, multiplayer.get_unique_id())
	else:
		_rpc_add.rpc_id(1, world_pos, kind)


## Any peer: remove a pin by id.
func remove_pin(id: int) -> void:
	if multiplayer.is_server():
		_host_remove(id)
	else:
		_rpc_remove.rpc_id(1, id)


## Host: clears everything (new dive).
func clear() -> void:
	if multiplayer.is_server():
		pins.clear()
		_broadcast()


func pin_by_id(id: int) -> Dictionary:
	for p: Dictionary in pins:
		if int(p["id"]) == id:
			return p
	return {}


@rpc("any_peer", "reliable")
func _rpc_add(world_pos: Vector3, kind: int) -> void:
	if multiplayer.is_server():
		_host_add(world_pos, kind, multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func _rpc_remove(id: int) -> void:
	if multiplayer.is_server():
		_host_remove(id)


func _host_add(world_pos: Vector3, kind: int, author: int) -> void:
	pins.append({"id": _next_id, "pos": world_pos, "kind": clampi(kind, 0, Kind.CONTACT), "author": author})
	_next_id += 1
	while pins.size() > MAX_PINS:
		pins.remove_at(0)
	_broadcast()


func _host_remove(id: int) -> void:
	for i: int in range(pins.size()):
		if int(pins[i]["id"]) == id:
			pins.remove_at(i)
			_broadcast()
			return


func _broadcast() -> void:
	changed.emit()
	if Net.is_online():
		_rpc_set.rpc(pins)


@rpc("authority", "call_remote", "reliable")
func _rpc_set(new_pins: Array) -> void:
	pins.clear()
	for p: Variant in new_pins:
		pins.append(p as Dictionary)
	changed.emit()


func _on_peer_joined(peer_id: int) -> void:
	if multiplayer.is_server():
		_rpc_set.rpc_id(peer_id, pins)
