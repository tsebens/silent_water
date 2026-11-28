extends Node3D
## Renders a scene from several cameras to PNGs, for asset review (needs a display server):
##   xvfb-run -a godot --path . --rendering-driver vulkan res://tests/scene_shot.tscn -- <scene.tscn> <out_dir> [cameras.json | --top]
## (--top, instead of cameras.json, adds a top-down orthographic view to the automatic ones.)
## Without cameras.json the scene is framed automatically: a three-quarter view, front, right side and top.
## cameras.json is a list of {name, pos: [x,y,z], look_at: [x,y,z], fov (deg) or ortho (m), light: "white"|"red"|"sea", reach (m, sea only)},
## in the scene's own frame (metres), plus optional "on": true, which drives a switch scene to its on end before the shot (put these last), and "cap_open": true, which lifts a guarded switch's cap first (after "on", so "on" with the cap open is a switch thrown). Lighting is neutral and dim, close to the sub's interior; red is the sub's red light. "sea" is the game outside: dark teal ambient and fog with about 100 m reach (`reach` overrides it), a white work light from the sub's side, and glow so infrastructure neon shows.

var _env: WorldEnvironment
var _key: DirectionalLight3D
var _fill: OmniLight3D
var _work: OmniLight3D

## The sea preset's fog reach in metres (the game's fog_density 0.018 gives 83% fog at about 100 m).
## A scene whose bounding box diagonal is longer than this (m) also gets a sea-lit camera.
const LARGE_SCENE: float = 20.0
const SEA_REACH: float = 100.0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- <scene.tscn> <out_dir> [cameras.json]")
		get_tree().quit(2)
		return
	get_window().size = Vector2i(1280, 800)
	var scene: Node3D = (load(args[0]) as PackedScene).instantiate() as Node3D
	add_child(scene)
	_sample_source(args[0])
	_lights()
	var cams: Array = _auto_cameras(scene) if args.size() < 3 or args[2] == "--top" else JSON.parse_string(FileAccess.get_file_as_string(args[2])) as Array
	if args.has("--top") and args.size() < 4:      # a posed render: add a top-down view, where a bend in the body reads
		var box: AABB = _aabb(scene)
		cams.append({"name": "top", "pos": _arr(box.get_center() + Vector3(0, box.size.length() * 1.2, 0)), "look_at": _arr(box.get_center()), "ortho": box.size.length() * 1.1})
	DirAccess.make_dir_recursive_absolute(args[1])
	var cam: Camera3D = Camera3D.new()
	add_child(cam)
	cam.current = true
	for spec: Dictionary in cams:
		_set_light(String(spec.get("light", "white")), float(spec.get("reach", SEA_REACH)))
		if bool(spec.get("on", false)) and scene.has_method("host_set_value"):
			scene.call("host_set_value", scene.get("max_value"))
		if bool(spec.get("cap_open", false)) and scene.has_method("_set_cap_local"):
			scene.call("_set_cap_local", true)
		var p: Array = spec["pos"]
		var t: Array = spec["look_at"]
		cam.position = Vector3(p[0], p[1], p[2])
		var target: Vector3 = Vector3(t[0], t[1], t[2])
		var up: Vector3 = Vector3.FORWARD if absf((target - cam.position).normalized().y) > 0.99 else Vector3.UP
		cam.look_at(target, up)
		if spec.has("ortho"):
			cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			cam.size = float(spec["ortho"])
		else:
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = float(spec.get("fov", 50.0))
		cam.near = 0.01
		for i: int in range(4):
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(args[1].path_join(String(spec["name"]) + ".png"))
		print("SHOT ", spec["name"])
	get_tree().quit(0)


func _lights() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.05, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.62)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env = WorldEnvironment.new()
	_env.environment = env
	add_child(_env)
	_key = DirectionalLight3D.new()
	_key.rotation_degrees = Vector3(-50, -35, 0)
	_key.shadow_enabled = true
	add_child(_key)
	_fill = OmniLight3D.new()
	_fill.position = Vector3(1.5, 2.2, 2.5)
	_fill.omni_range = 8.0
	add_child(_fill)
	_work = OmniLight3D.new()
	_work.visible = false
	add_child(_work)


func _set_light(kind: String, reach: float = SEA_REACH) -> void:
	var env: Environment = _env.environment
	var sea: bool = kind == "sea"
	_work.visible = sea
	env.fog_enabled = sea
	env.glow_enabled = sea
	if sea:
		_sea_light(env, reach)
		return
	var red: bool = kind == "red"
	var c: Color = Color(1.0, 0.12, 0.08) if red else Color(1.0, 0.97, 0.92)
	env.background_color = Color(0.02, 0.05, 0.06)
	_key.light_color = c
	_key.light_energy = 0.9 if red else 1.1
	_fill.light_color = c
	_fill.light_energy = 0.8 if red else 0.6
	env.ambient_light_energy = 0.45
	env.ambient_light_color = Color(0.35, 0.05, 0.04) if red else Color(0.55, 0.6, 0.62)


## The game outside at depth. Colours are palette swatches, as SurfaceLighting uses them below its ramp:
## background env_abyss, ambient env_teal, fog env_deep (OceanSurface.fog_color), the work light light_work_white
## (the day LightPreset's light swatch). Fog density follows game.tscn (0.018 per 100 m), scaled by `reach`.
func _sea_light(env: Environment, reach: float) -> void:
	var pal: Palette = Palette.main()
	env.background_color = pal.color(&"env_abyss")
	env.ambient_light_color = pal.color(&"env_teal")
	env.ambient_light_energy = 0.3
	env.fog_light_color = OceanSurface.fog_color()
	env.fog_density = 1.8 / maxf(reach, 1.0)
	env.fog_sky_affect = 0.0
	env.glow_intensity = 0.8
	var white: Color = pal.color(&"light_work_white")
	_key.light_color = pal.color(&"env_teal")
	_key.light_energy = 0.15
	_fill.light_energy = 0.0
	_work.light_color = white
	_work.light_energy = 6.0
	_work.omni_range = 40.0
	_work.position = Vector3(8.0, 1.0, 4.0)


func _auto_cameras(scene: Node3D) -> Array:
	var box: AABB = _aabb(scene)
	var c: Vector3 = box.get_center()
	var r: float = maxf(box.size.length() * 0.5, 0.02)
	var d: float = r / sin(deg_to_rad(25.0)) * 1.05
	var cams: Array = [
		{"name": "three_quarter", "pos": _arr(c + Vector3(0.6, 0.45, 1.0).normalized() * d), "look_at": _arr(c), "fov": 50.0},
		{"name": "front", "pos": _arr(c + Vector3(0, 0, d)), "look_at": _arr(c), "ortho": r * 2.2},
		{"name": "right", "pos": _arr(c + Vector3(d, 0, 0)), "look_at": _arr(c), "ortho": r * 2.2},
		{"name": "three_quarter_red", "pos": _arr(c + Vector3(0.6, 0.45, 1.0).normalized() * d), "look_at": _arr(c), "fov": 50.0, "light": "red"},
	]
	if box.size.length() > LARGE_SCENE:
		# A scene tens of metres across: the sea light, with fog far enough out to leave the whole scene clear.
		cams.append({"name": "three_quarter_sea", "pos": _arr(c + Vector3(0.6, 0.45, 1.0).normalized() * d), "look_at": _arr(c), "fov": 50.0, "light": "sea", "reach": d * 3.0})
	return cams


func _aabb(node: Node) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var vi: VisualInstance3D = n as VisualInstance3D
		if vi != null and not (n is Label3D):
			var b: AABB = vi.global_transform * vi.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(n.get_children())
	return out


static func _arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


class SampleSource:
	extends Node
	var vals: Dictionary = {}

	func readout(n: StringName) -> float:
		return float(vals.get(String(n), 0.0))


## `<scene folder>/review/samples.json` ({"group": ..., "values": {readout: value}}) adds a source of sample readouts,
## so a display's review render shows its face with values rather than blank.
func _sample_source(scene_path: String) -> void:
	var f: String = scene_path.get_base_dir().path_join("review/samples.json")
	if not FileAccess.file_exists(f):
		return
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(f)) as Dictionary
	var src: SampleSource = SampleSource.new()
	src.vals = d.get("values", {})
	src.add_to_group(StringName(d.get("group", "")))
	add_child(src)
