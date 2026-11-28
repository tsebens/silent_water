extends Node3D
## Renders tests/herring_swim_demo.tscn as a contact sheet: one loop in FRAMES steps, a top-down row and a side row.
##   xvfb-run -a godot --path . --rendering-driver vulkan res://tests/herring_swim_shot.tscn -- <out.png>
## (tools/herring_swim_sheet.sh wraps this.) Needs a display server.

const FRAMES: int = 8
const TILE: Vector2i = Vector2i(360, 225)
const VIEWS: Array[Dictionary] = [
	{"name": "top", "pos": Vector3(0, 0.6, 0), "up": Vector3.FORWARD, "size": 0.3},
	{"name": "side", "pos": Vector3(0.6, 0, 0), "up": Vector3.UP, "size": 0.2},
]


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <out.png>")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 800)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.62)
	env.ambient_light_energy = 0.5
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -35, 0)
	add_child(key)
	var demo: Node3D = (load("res://tests/herring_swim_demo.tscn") as PackedScene).instantiate() as Node3D
	if demo == null:
		get_tree().quit(1)
		return
	add_child(demo)
	demo.set_process(false)
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.2
	cam.near = 0.01
	var sheet: Image = Image.create(TILE.x * FRAMES, TILE.y * VIEWS.size(), false, Image.FORMAT_RGB8)
	for r: int in range(VIEWS.size()):
		var v: Dictionary = VIEWS[r]
		cam.position = v["pos"] as Vector3
		cam.look_at(Vector3.ZERO, v["up"] as Vector3)
		cam.size = float(v["size"])
		for f: int in range(FRAMES):
			demo.call("apply", float(f) / FRAMES * float(demo.get("PERIOD")))
			for i: int in range(4):
				await RenderingServer.frame_post_draw
			var img: Image = get_viewport().get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.resize(TILE.x, TILE.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(Vector2i.ZERO, TILE), Vector2i(f * TILE.x, r * TILE.y))
	DirAccess.make_dir_recursive_absolute(args[0].get_base_dir())
	sheet.save_png(args[0])
	print("SHEET ", args[0])
	get_tree().quit(0)
