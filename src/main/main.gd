extends Node
## Boot scene. Reads launch args, hosts or joins, and starts the game
## session once connected. Without args it shows the dev connect menu.

const DEV_MENU_SCENE: PackedScene = preload("res://src/main/dev_menu.tscn")

@onready var _game: Game = $Game
var _menu: DevMenu = null
var _mic: MicMeter = null


func _ready() -> void:
	AudioBuses.ensure()
	Net.hosting_started.connect(_start_game)
	Net.connected_to_host.connect(_start_game)
	Net.session_ended.connect(_end_game)
	Net.connection_failed.connect(_on_connection_failed)
	Net.peer_joined.connect(func(id: int) -> void: print("[net] peer %d joined" % id))
	Net.peer_left.connect(func(id: int) -> void: print("[net] peer %d left" % id))

	var args: LaunchArgs = LaunchArgs.parse(OS.get_cmdline_user_args())
	for e: String in args.errors:
		push_error("Launch args: " + e)

	if args.terrain_lab:
		_open_terrain_lab.call_deferred()
		return

	if OS.get_cmdline_user_args().has("--autotest"):
		var autotest: Autotest = Autotest.new()
		autotest.name = "Autotest"
		add_child(autotest)
		autotest.setup(_game, args.player_name)

	if OS.get_cmdline_user_args().has("--screenshot"):
		var shot: DebugScreenshot = DebugScreenshot.new()
		shot.name = "DebugScreenshot"
		add_child(shot)
		shot.setup(_game, OS.get_cmdline_user_args())

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
	_menu.terrain_lab_requested.connect(_open_terrain_lab)
	add_child(_menu)


## The terrain lab replaces this scene; it has no game session.
func _open_terrain_lab() -> void:
	get_tree().change_scene_to_file(TerrainLab.SCENE_PATH)


func _start_game() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
	print("[net] session up as %s (peer %d)" % ["host" if Net.is_host() else "client", Net.local_id()])
	Acoustics.reset()
	_game.start_session()
	if _mic == null:
		_mic = MicMeter.new()
		_mic.name = "MicMeter"
		add_child(_mic)


func _end_game() -> void:
	_game.end_session()
	if _mic != null:
		_mic.queue_free()
		_mic = null
	_show_menu()


func _on_connection_failed() -> void:
	push_warning("Could not connect to host.")
	_show_menu()


func _report(err: Error, action: String) -> void:
	if err != OK:
		push_error("Failed to %s: %s" % [action, error_string(err)])
		_show_menu()
