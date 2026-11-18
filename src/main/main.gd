extends Node
## Boot scene. Reads launch args, hosts or joins, and loads the game scene
## once a session is up. Without args it shows the dev connect menu.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
const DEV_MENU_SCENE: PackedScene = preload("res://src/main/dev_menu.tscn")

var _game: Node = null
var _menu: DevMenu = null


func _ready() -> void:
	Net.hosting_started.connect(_start_game)
	Net.connected_to_host.connect(_start_game)
	Net.session_ended.connect(_end_game)
	Net.connection_failed.connect(_on_connection_failed)
	Net.peer_joined.connect(func(id: int) -> void: print("[net] peer %d joined" % id))
	Net.peer_left.connect(func(id: int) -> void: print("[net] peer %d left" % id))

	var args: LaunchArgs = LaunchArgs.parse(OS.get_cmdline_user_args())
	for e: String in args.errors:
		push_error("Launch args: " + e)

	if args.host:
		_report(Net.host(args.port), "host")
	elif args.join:
		_report(Net.join(args.address, args.port), "join")
	else:
		_show_menu()


func _show_menu() -> void:
	if _menu != null:
		return
	_menu = DEV_MENU_SCENE.instantiate() as DevMenu
	_menu.host_requested.connect(func(port: int) -> void: _report(Net.host(port), "host"))
	_menu.join_requested.connect(
		func(address: String, port: int) -> void: _report(Net.join(address, port), "join")
	)
	add_child(_menu)


func _start_game() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	if _game != null:
		return
	print("[net] session up as %s (peer %d)" % ["host" if Net.is_host() else "client", Net.local_id()])
	_game = GAME_SCENE.instantiate()
	_game.name = "Game"
	add_child(_game)


func _end_game() -> void:
	if _game != null:
		_game.queue_free()
		_game = null
	_show_menu()


func _on_connection_failed() -> void:
	push_warning("Could not connect to host.")
	_show_menu()


func _report(err: Error, action: String) -> void:
	if err != OK:
		push_error("Failed to %s: %s" % [action, error_string(err)])
		_show_menu()
