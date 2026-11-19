extends Node
## Network session manager (autoload `Net`).
##
## Listen-server model: one player hosts and is authoritative. Peer creation
## lives in exactly one function, [method _create_peer], so ENet can later be
## swapped for GodotSteam's peer without touching callers.

signal hosting_started
signal connected_to_host
signal connection_failed
signal session_ended
signal peer_joined(peer_id: int)
signal peer_left(peer_id: int)

const DEFAULT_PORT: int = 24550
const DEFAULT_ADDRESS: String = "127.0.0.1"
## Crew of four: the host plus three clients.
const MAX_CLIENTS: int = 3

enum Mode { OFFLINE, HOST, CLIENT }

var mode: Mode = Mode.OFFLINE


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func host(port: int = DEFAULT_PORT) -> Error:
	var peer: MultiplayerPeer = _create_peer(Mode.HOST, "", port)
	if peer == null:
		return ERR_CANT_CREATE
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	hosting_started.emit()
	return OK


func join(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> Error:
	var peer: MultiplayerPeer = _create_peer(Mode.CLIENT, address, port)
	if peer == null:
		return ERR_CANT_CONNECT
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	return OK


func leave() -> void:
	if mode == Mode.OFFLINE:
		return
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	session_ended.emit()


func is_host() -> bool:
	return mode == Mode.HOST


func is_online() -> bool:
	return mode != Mode.OFFLINE


func local_id() -> int:
	return multiplayer.get_unique_id()


## The only place a transport peer is created. Returns null on failure.
func _create_peer(new_mode: Mode, address: String, port: int) -> MultiplayerPeer:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error
	match new_mode:
		Mode.HOST:
			err = peer.create_server(port, MAX_CLIENTS)
		Mode.CLIENT:
			err = peer.create_client(address, port)
		_:
			return null
	if err != OK:
		push_error("Net: failed to create peer (%s)" % error_string(err))
		return null
	return peer


func _on_peer_connected(peer_id: int) -> void:
	peer_joined.emit(peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	peer_left.emit(peer_id)


func _on_connected_to_server() -> void:
	connected_to_host.emit()


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.OFFLINE
	session_ended.emit()
