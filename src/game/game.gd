class_name Game
extends Node3D
## Root of a running dive. Always present in the main scene so node paths for
## spawning and replication exist on every peer before a session starts.
## The host spawns one Player per peer, named after the peer id.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")
## Spawn points along the corridor, sub-local.
const SPAWN_POINTS: Array[Vector3] = [
	Vector3(0, 0.1, -1.0), Vector3(0, 0.1, 1.0), Vector3(0.8, 0.1, 2.5), Vector3(-0.8, 0.1, -2.5),
]

@onready var sub_frame: SubFrame = $SubFrame
@onready var players: Node3D = $Players

var _active: bool = false


func _ready() -> void:
	sub_frame.add_to_group(&"sub_frame")
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)


func start_session() -> void:
	if _active:
		return
	_active = true
	if multiplayer.is_server():
		_spawn_player(Net.local_id())
		for peer_id: int in multiplayer.get_peers():
			_spawn_player(peer_id)


func end_session() -> void:
	_active = false
	for child: Node in players.get_children():
		child.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func local_player() -> Player:
	return players.get_node_or_null(str(Net.local_id())) as Player


func _on_peer_joined(peer_id: int) -> void:
	if _active and multiplayer.is_server():
		_spawn_player(peer_id)


func _on_peer_left(peer_id: int) -> void:
	if multiplayer.is_server():
		var p: Node = players.get_node_or_null(str(peer_id))
		if p != null:
			p.queue_free()


func _spawn_player(peer_id: int) -> void:
	if players.has_node(str(peer_id)):
		return
	var p: Player = PLAYER_SCENE.instantiate() as Player
	p.name = str(peer_id)
	p.position = SPAWN_POINTS[players.get_child_count() % SPAWN_POINTS.size()]
	players.add_child(p, true)
