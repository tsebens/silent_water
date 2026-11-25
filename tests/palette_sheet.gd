extends Node3D
## Renders the palette as swatch sheets, one PNG per light (needs a display server):
##   xvfb-run -a godot --path . --rendering-driver vulkan res://tests/palette_sheet.tscn -- <out_dir>
## Every swatch is a matte card, every light swatch a glowing card, every role a card in its own material with a
## ball on it to show its finish. The board sits on the darkest background colour, unlit, as the ocean would be.
##
## Brightness is relative to today's cabin lights (src/sub/interior.tscn: omni lights of energy about 0.6, range
## 4.5 m). "1x" lights the board as evenly as one of them lights a surface 1.5 m away. The environment (ambient,
## filmic tonemap, glow) matches src/game/game.tscn.

const CABIN_ENERGY: float = 0.6
const CABIN_DISTANCE: float = 1.5
const CABIN_RANGE: float = 4.5
const COLS: int = 12
const PITCH_X: float = 0.115
const CARD: Vector2 = Vector2(0.09, 0.055)
const LIGHTS: Array[Dictionary] = [
	{"file": "palette_white_2x", "title": "White light, 2x today's cabin light", "swatch": &"", "level": 2.0},
	{"file": "palette_white_1x", "title": "White light, 1x today's cabin light", "swatch": &"", "level": 1.0},
	{"file": "palette_white_0.4x", "title": "White light, 0.4x today's cabin light", "swatch": &"", "level": 0.4},
	{"file": "palette_white_0.15x", "title": "White light, 0.15x today's cabin light", "swatch": &"", "level": 0.15},
	{"file": "palette_stealth_red_1x", "title": "Stealth red light (light_stealth_red), 1x", "swatch": &"light_stealth_red", "level": 1.0},
]
const SECTIONS: Array[Array] = [
	["Environment and sea floor (paint)", ["env_", "floor_"]],
	["Life and flora (paint)", ["life_", "flora_"]],
	["Infrastructure (paint)", ["infra_"]],
	["Sub interior and information (paint)", ["sub_", "info_"]],
]

var _key: DirectionalLight3D
var _title: Label3D
var _y: float = 0.0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "res://build/palette_sheets"
	get_window().size = Vector2i(1800, 1700)
	DirAccess.make_dir_recursive_absolute(out)
	var pal: Palette = Palette.main()
	_environment(pal)
	_title = _label("", Vector3(0, 0.03, 0.01), 0.0009, Color(0.85, 0.9, 0.9))
	_y = -0.06
	for sec: Array in SECTIONS:
		var names: Array[StringName] = []
		for n: StringName in pal.paint:
			for prefix: String in sec[1]:
				if String(n).begins_with(prefix):
					names.append(n)
		_section(String(sec[0]), names, func(n: StringName) -> Material: return _matte(pal.paint[n]),
			func(n: StringName) -> String: return "%s\n#%s" % [n, pal.paint[n].to_html(false).to_upper()], false)
	var lights: Array[StringName] = []
	lights.assign(pal.light.keys())
	_section("Light swatches (emitted)", lights, func(n: StringName) -> Material: return _glowing(pal.light[n]),
		func(n: StringName) -> String: return "%s\n#%s" % [n, pal.light[n].to_html(false).to_upper()], false)
	var roles: Array[StringName] = []
	for f: String in DirAccess.get_files_at(RoleMaterial.ROLES_DIR):
		if f.ends_with(".tres"):
			roles.append(StringName(f.get_basename()))
	_section("Roles (shared materials, with their finish)", roles,
		func(n: StringName) -> Material: return RoleMaterial.lookup(String(n)),
		func(n: StringName) -> String: return String(n), true)
	var cam: Camera3D = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = -_y + 0.12
	cam.position = Vector3(0, (_y + 0.06) * 0.5, 3.0)
	cam.near = 0.1
	add_child(cam)
	cam.current = true
	for spec: Dictionary in LIGHTS:
		var c: Color = Color.WHITE if spec["swatch"] == &"" else pal.color(spec["swatch"])
		_key.light_color = c
		# Irradiance of one cabin omni light at CABIN_DISTANCE (inverse square, Godot's range window), times the level,
		# delivered by a directional light tilted from the board's normal.
		var window: float = pow(1.0 - pow(CABIN_DISTANCE / CABIN_RANGE, 4.0), 2.0)
		var irradiance: float = CABIN_ENERGY / (CABIN_DISTANCE * CABIN_DISTANCE) * window * float(spec["level"])
		_key.light_energy = irradiance / cos(deg_to_rad(25.0))
		_title.text = "%s. Board lit evenly; the background (env_abyss) is unlit, as open water is." % spec["title"]
		for i: int in range(6):
			await RenderingServer.frame_post_draw
		var img: Image = get_viewport().get_texture().get_image()
		img.save_png(out.path_join(String(spec["file"]) + ".png"))
		print("SHEET ", spec["file"])
	get_tree().quit(0)


func _environment(pal: Palette) -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = pal.color(&"env_abyss")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.16, 0.2)
	env.ambient_light_energy = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_strength = 1.15
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_key = DirectionalLight3D.new()
	_key.rotation_degrees = Vector3(-15, 20, 0)
	add_child(_key)


func _section(title: String, names: Array[StringName], material: Callable, caption: Callable, ball: bool) -> void:
	_label(title, Vector3(-COLS * PITCH_X * 0.5, _y, 0.01), 0.0011, Color(0.75, 0.82, 0.82), HORIZONTAL_ALIGNMENT_LEFT)
	_y -= 0.055
	for i: int in range(names.size()):
		if i > 0 and i % COLS == 0:
			_y -= 0.11
		var x: float = (float(i % COLS) - (COLS - 1) * 0.5) * PITCH_X
		var mat: Material = material.call(names[i])
		var card: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(CARD.x, CARD.y, 0.008)
		card.mesh = box
		card.material_override = mat
		card.position = Vector3(x, _y, 0.004)
		add_child(card)
		if ball:
			var b: MeshInstance3D = MeshInstance3D.new()
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = 0.016
			sphere.height = 0.032
			b.mesh = sphere
			b.material_override = mat
			b.position = Vector3(x + CARD.x * 0.28, _y, 0.024)
			add_child(b)
		_label(String(caption.call(names[i])), Vector3(x, _y - CARD.y * 0.5 - 0.016, 0.01), 0.00045, Color(0.62, 0.68, 0.68))
	_y -= 0.11


func _matte(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _glowing(c: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_color = Color.BLACK
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.6
	return m


func _label(text: String, pos: Vector3, pixel: float, color: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER) -> Label3D:
	var l: Label3D = Label3D.new()
	l.text = text
	l.pixel_size = pixel
	l.position = pos
	l.modulate = color
	l.font_size = 32
	l.outline_size = 0
	l.horizontal_alignment = align
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		l.offset = Vector2(0, 0)
	add_child(l)
	return l
