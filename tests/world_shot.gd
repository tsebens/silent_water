class_name WorldShot
extends Node
## Renders a review shot of the game scene from a named viewpoint at a chosen depth (needs a display server; see
## tools/shot.sh, which wraps this). Single player, no networking, no input; it quits on its own.
##   godot --path . res://tests/world_shot.tscn -- <camera> [--depth <m>] [--light day|night] [--out <png>]
##       [--size WxH] [--frames <n>] [--sheet <d1,d2,...>]
## Cameras: the program's cameras by id (assets/models/vehicles/sub_interior/program.yaml, via layout.json),
## `pilot_eye` (seated at the helm, level) and `outside_<dir>` (dir: bow, stern, port, starboard, top, bottom).
## Depth is metres below the physical surface (0). `--sheet` tiles one shot per depth, with captions, into --out.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
const LAYOUT_PATH: String = "res://assets/models/vehicles/sub_interior/layout.json"
const DEFAULT_FRAMES: int = 20
const OUTSIDE_DISTANCE_M: float = 9.0
const CAPTION_HEIGHT: int = 56

var _game: Game
var _cam: Camera3D
var _depth: float = 0.0


## Parsed command line. `errors` is empty when the arguments are usable.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var out: Dictionary = {
		"camera": "", "depth": 0.0, "depths": [] as Array[float], "light": "day", "out": "",
		"size": Vector2i(1280, 720), "frames": DEFAULT_FRAMES, "sheet": false, "errors": [] as Array[String],
	}
	var errors: Array[String] = out["errors"]
	var i: int = 0
	while i < args.size():
		var a: String = args[i]
		var val: String = ""
		if a.begins_with("--") and a.contains("="):
			val = a.get_slice("=", 1)
			a = a.get_slice("=", 0)
		elif a.begins_with("--") and i + 1 < args.size():
			val = args[i + 1]
			i += 1
		match a:
			"--depth":
				if not val.is_valid_float():
					errors.append("--depth needs a number of metres, got '%s'" % val)
				else:
					out["depth"] = float(val)
			"--light":
				if val != "day" and val != "night":
					errors.append("--light must be day or night, got '%s'" % val)
				else:
					out["light"] = val
			"--out":
				out["out"] = val
			"--size":
				var p: PackedStringArray = val.to_lower().split("x")
				if p.size() != 2 or not p[0].is_valid_int() or not p[1].is_valid_int() or int(p[0]) < 16 or int(p[1]) < 16:
					errors.append("--size must be WxH, got '%s'" % val)
				else:
					out["size"] = Vector2i(int(p[0]), int(p[1]))
			"--frames":
				if not val.is_valid_int() or int(val) < 1:
					errors.append("--frames needs a positive integer, got '%s'" % val)
				else:
					out["frames"] = int(val)
			"--sheet":
				var depths: Array[float] = []
				for d: String in val.split(",", false):
					if d.is_valid_float():
						depths.append(float(d))
					else:
						errors.append("--sheet needs depths like 0,20,100, got '%s'" % val)
						depths = []
						break
				if depths.is_empty() and errors.is_empty():
					errors.append("--sheet needs at least one depth")
				out["sheet"] = true
				out["depths"] = depths
			_:
				if a.begins_with("--"):
					errors.append("unknown option %s" % a)
				elif String(out["camera"]) == "":
					out["camera"] = a
				else:
					errors.append("unexpected argument '%s'" % a)
		i += 1
	if String(out["camera"]) == "":
		errors.append("a camera name is required")
	elif camera_spec(String(out["camera"])).is_empty():
		errors.append("unknown camera '%s'" % out["camera"])
	if bool(out["sheet"]):
		pass
	else:
		out["depths"] = [float(out["depth"])] as Array[float]
	return out


## Viewpoint for a camera name, in the interior frame: {pos: Vector3, look: Vector3, fov: float (vertical, degrees)}.
## Empty when the name is not known.
static func camera_spec(id: String) -> Dictionary:
	if id.begins_with("outside_"):
		return _outside_spec(id.trim_prefix("outside_"))
	var cams: Array = _layout_cameras()
	if id == "pilot_eye":
		var seat: Dictionary = _find_camera(cams, "pilot_view")
		if seat.is_empty():
			return {}
		var p: Vector3 = _to_interior(seat["pos"] as Array)
		return {"pos": p, "look": p + Vector3(0, 0, -1), "fov": 75.0}
	var c: Dictionary = _find_camera(cams, id)
	if c.is_empty() or not c.has("pos") or not c.has("look"):
		return {}
	var pos: Vector3 = _to_interior(c["pos"] as Array)
	var spec: Dictionary = {"pos": pos, "look": _to_interior(c["look"] as Array), "fov": 60.0}
	if c.has("lens_mm"):
		spec["fov"] = rad_to_deg(2.0 * atan(12.0 / float(c["lens_mm"])))
	return spec


## The program's camera ids, then `pilot_eye` and the exterior names.
static func camera_names() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for c: Dictionary in _layout_cameras():
		out.append(String(c["id"]))
	out.append("pilot_eye")
	for d: String in ["bow", "stern", "port", "starboard", "top", "bottom"]:
		out.append("outside_" + d)
	return out


static func _outside_spec(dir: String) -> Dictionary:
	var dirs: Dictionary = {
		"bow": Vector3(0, 0.15, -1), "forward": Vector3(0, 0.15, -1), "stern": Vector3(0, 0.15, 1), "aft": Vector3(0, 0.15, 1),
		"port": Vector3(-1, 0.15, 0), "starboard": Vector3(1, 0.15, 0), "top": Vector3(0, 1, 0.01), "bottom": Vector3(0, -1, 0.01),
	}
	if not dirs.has(dir):
		return {}
	var centre: Vector3 = Vector3(0, SubLayout.hull_centre_y(), 0)
	var pos: Vector3 = centre + (dirs[dir] as Vector3).normalized() * OUTSIDE_DISTANCE_M
	return {"pos": pos, "look": centre, "fov": 60.0}


static func _layout_cameras() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
	if parsed is Dictionary:
		return (parsed as Dictionary).get("cameras", []) as Array
	return []


static func _find_camera(cams: Array, id: String) -> Dictionary:
	for c: Variant in cams:
		if (c as Dictionary).get("id", "") == id:
			return c as Dictionary
	return {}


static func _to_interior(a: Array) -> Vector3:
	return SubLayout.to_interior(Vector3(float(a[0]), float(a[1]), float(a[2])))


## "Forward+ (Mesa llvmpipe ...)" for captions and logs.
static func renderer_label() -> String:
	var method: String = String(RenderingServer.get_current_rendering_method())
	return "%s on %s" % [method, RenderingServer.get_video_adapter_name()]


func _ready() -> void:
	var cfg: Dictionary = parse_args(OS.get_cmdline_user_args())
	var errors: Array[String] = cfg["errors"]
	if not errors.is_empty():
		for e: String in errors:
			printerr("[shot] " + e)
		printerr("[shot] cameras: " + ", ".join(camera_names()))
		get_tree().quit(2)
		return
	print("[shot] renderer: ", renderer_label())
	var size: Vector2i = cfg["size"]
	get_window().size = size
	DevSettings.night = String(cfg["light"]) == "night"
	_game = GAME_SCENE.instantiate() as Game
	add_child(_game)
	_game.start_session()
	(_game.get_node("World/Apex") as ApexMonster).set_active(false)
	_cam = Camera3D.new()
	_game.add_child(_cam)
	_run(cfg)


func _run(cfg: Dictionary) -> void:
	var spec: Dictionary = camera_spec(String(cfg["camera"]))
	var pos: Vector3 = spec["pos"]
	_cam.fov = float(spec["fov"])
	_cam.near = 0.02
	_cam.position = pos
	var look: Vector3 = spec["look"]
	var up: Vector3 = Vector3.FORWARD if absf((look - pos).normalized().y) > 0.99 else Vector3.UP
	_cam.look_at_from_position(pos, look, up)
	var shots: Array[Image] = []
	var depths: Array = cfg["depths"]
	var t0: int = Time.get_ticks_msec()
	for d: Variant in depths:
		_depth = float(d)
		for i: int in range(int(cfg["frames"])):
			_pin()
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		shots.append(img)
		print("[shot] depth %.0f m: %d ms total" % [_depth, Time.get_ticks_msec() - t0])
	var out_path: String = String(cfg["out"])
	if out_path == "":
		out_path = "res://shot.png"
	var final: Image = shots[0]
	if bool(cfg["sheet"]):
		final = await _sheet(shots, depths, String(cfg["camera"]), String(cfg["light"]))
	var err: Error = final.save_png(out_path)
	print("[shot] wrote %s (%s)" % [out_path, error_string(err)])
	get_tree().quit(0 if err == OK else 1)


## Hold the sub at the depth with neutral ballast: the physics model would otherwise drift between frames.
func _pin() -> void:
	var c: SubController = _game.get_node("SubController") as SubController
	c.model.position = Vector3(0.0, -_depth, 0.0)
	c.model.velocity = Vector3.ZERO
	c.model.tank_water_t = c.model.tank_capacity_t * 0.5
	_cam.current = true


## Tile the shots left to right, each under a caption saying camera, depth, light and the renderer.
func _sheet(shots: Array[Image], depths: Array, camera: String, light: String) -> Image:
	var w: int = shots[0].get_width()
	var h: int = shots[0].get_height()
	var vp: SubViewport = SubViewport.new()
	vp.size = Vector2i(w * shots.size(), h + CAPTION_HEIGHT)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.08, 0.08, 0.08)
	bg.size = Vector2(vp.size)
	vp.add_child(bg)
	for i: int in range(shots.size()):
		var tr: TextureRect = TextureRect.new()
		tr.texture = ImageTexture.create_from_image(shots[i])
		tr.position = Vector2(i * w, CAPTION_HEIGHT)
		vp.add_child(tr)
		var label: Label = Label.new()
		label.text = "%s, %.0f m, %s\n%s" % [camera, float(depths[i]), light, renderer_label()]
		label.position = Vector2(i * w + 8, 4)
		label.add_theme_font_size_override(&"font_size", 16)
		vp.add_child(label)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	vp.queue_free()
	return img
