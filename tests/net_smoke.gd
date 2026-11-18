extends Node
## Two-process network smoke test. Run one host and one client:
##   godot --headless --path . res://tests/net_smoke.tscn -- --host --port 24600
##   godot --headless --path . res://tests/net_smoke.tscn -- --join --port 24600
## The client pings the host over RPC, the host answers, and both exit 0.
## Either side exits 1 if the exchange doesn't finish within the time limit.

const TIME_LIMIT_SEC: float = 15.0

var _is_host: bool = false


func _ready() -> void:
	var args: LaunchArgs = LaunchArgs.parse(OS.get_cmdline_user_args())
	get_tree().create_timer(TIME_LIMIT_SEC).timeout.connect(_fail.bind("timed out"))
	_is_host = args.host
	if args.host:
		Net.peer_left.connect(func(_id: int) -> void: _pass("client left after exchange"))
		if Net.host(args.port) != OK:
			_fail("could not host")
	elif args.join:
		Net.connected_to_host.connect(func() -> void: ping.rpc_id(1, Net.local_id()))
		Net.connection_failed.connect(_fail.bind("connection failed"))
		if Net.join(args.address, args.port) != OK:
			_fail("could not join")
	else:
		_fail("pass --host or --join")


@rpc("any_peer", "reliable")
func ping(sender_id: int) -> void:
	if multiplayer.get_remote_sender_id() != sender_id:
		_fail("sender id mismatch")
		return
	print("host: ping from %d" % sender_id)
	pong.rpc_id(sender_id)


@rpc("authority", "reliable")
func pong() -> void:
	print("client: pong from host")
	# Give ENet a moment to flush before leaving.
	await get_tree().create_timer(0.2).timeout
	Net.leave()
	_pass("exchange complete")


func _pass(reason: String) -> void:
	print("NET SMOKE PASS (%s): %s" % ["host" if _is_host else "client", reason])
	get_tree().quit(0)


func _fail(reason: String) -> void:
	printerr("NET SMOKE FAIL (%s): %s" % ["host" if _is_host else "client", reason])
	get_tree().quit(1)
