class_name DebugScreenshot
extends Node
## Debug capture, enabled with `--screenshot <path>`. Waits `--screenshot-delay`
## seconds (default 3) after the session starts, optionally points the local
## player's view with `--look <yaw_deg>,<pitch_deg>` and moves them with
## `--at <x>,<z>`, saves the frame as PNG, then quits.

var _path: String = ""
var _delay: float = 3.0
var _look: Vector2 = Vector2.ZERO
var _has_look: bool = false
var _at: Vector2 = Vector2.ZERO
var _has_at: bool = false
var _game: Game


func setup(game: Game, args: PackedStringArray) -> void:
	_game = game
	for i: int in range(args.size() - 1):
		match args[i]:
			"--screenshot":
				_path = args[i + 1]
			"--screenshot-delay":
				_delay = float(args[i + 1])
			"--look":
				var p: PackedStringArray = args[i + 1].split(",")
				_look = Vector2(float(p[0]), float(p[1]))
				_has_look = true
			"--at":
				var q: PackedStringArray = args[i + 1].split(",")
				_at = Vector2(float(q[0]), float(q[1]))
				_has_at = true
	if _path != "":
		Net.hosting_started.connect(_run)
		Net.connected_to_host.connect(_run)


func _run() -> void:
	await get_tree().create_timer(0.3).timeout
	var me: Player = _game.local_player()
	if me != null and _has_at:
		me.position = Vector3(_at.x, 0.1, _at.y)
	if me != null and _has_look:
		me.rotation.y = deg_to_rad(_look.x)
		(me.get_node("Head") as Node3D).rotation.x = deg_to_rad(_look.y)
	await get_tree().create_timer(_delay).timeout
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(_path)
	print("[debug] screenshot %s (%s)" % [_path, error_string(err)])
	get_tree().quit(0)
