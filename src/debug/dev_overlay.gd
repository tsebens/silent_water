class_name DevOverlay
extends CanvasLayer
## Developer overlay, toggled with F1 in development builds (or with `--dev`).
## Drawn over the normal view:
##   left       console: engine output, warnings, errors and game events
##              (host events reach clients too)
##   top right  3D minimap: water surface, canyon, sub (green), apex (red),
##              array (yellow), slowly orbiting
##   right      live stats for the sub, the noise, the apex and the dive
## A setting to lock it away comes later; for now dev builds always allow it.

const MAP_SIZE: Vector2i = Vector2i(360, 270)
const MAP_ORBIT_DEG_PER_SEC: float = 8.0
const MAP_CENTER: Vector3 = Vector3(0, -110, -200)
const MAP_DISTANCE: float = 520.0
const CONSOLE_LINES: int = 60

const KIND_COLORS: Dictionary = {
	0: "c8c8c0",  # message
	1: "f0c060",  # warning
	2: "ff6a5a",  # error
	3: "8fe0b0",  # game event
}

@export var game: Game

var _console: RichTextLabel
var _stats: Label
var _map_camera: Camera3D
var _sub_blip: MeshInstance3D
var _apex_blip: MeshInstance3D
var _array_blip: MeshInstance3D
var _map_world_root: Node3D
var _map_built: bool = false
var _seen_revision: int = -1
var _orbit: float = 30.0


static func allowed() -> bool:
	return OS.is_debug_build() or OS.get_cmdline_user_args().has("--dev")


func _ready() -> void:
	layer = 10
	visible = OS.get_cmdline_user_args().has("--dev-overlay")
	_build_console()
	_build_map()
	_build_stats()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"dev_overlay") and allowed():
		visible = not visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_update_console()
	if not _map_built:
		_populate_map()
	_update_map(delta)
	_update_stats()


# --- Console -------------------------------------------------------------------

func _build_console() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.42
	panel.anchor_bottom = 0.72
	panel.offset_left = 10
	panel.offset_top = 10
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.35)
	bg.set_content_margin_all(8)
	panel.add_theme_stylebox_override(&"panel", bg)
	add_child(panel)
	_console = RichTextLabel.new()
	_console.bbcode_enabled = true
	_console.scroll_following = true
	_console.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_console.add_theme_font_size_override(&"normal_font_size", 12)
	_console.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_console.add_theme_constant_override(&"outline_size", 3)
	panel.add_child(_console)


func _update_console() -> void:
	if DevLog.revision == _seen_revision:
		return
	_seen_revision = DevLog.revision
	var start: int = maxi(DevLog.lines.size() - CONSOLE_LINES, 0)
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(start, DevLog.lines.size()):
		var entry: Array = DevLog.lines[i]
		var color: String = KIND_COLORS.get(int(entry[0]), "ffffff")
		var text: String = String(entry[1]).replace("[", "[lb]")
		parts.append("[color=#%s]%6.1f  %s[/color]" % [color, float(entry[2]), text])
	_console.text = "\n".join(parts)


# --- Minimap -----------------------------------------------------------------

func _build_map() -> void:
	var container: SubViewportContainer = SubViewportContainer.new()
	container.anchor_left = 1.0
	container.anchor_right = 1.0
	container.offset_left = -MAP_SIZE.x - 10
	container.offset_right = -10
	container.offset_top = 10
	container.offset_bottom = 10 + MAP_SIZE.y
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	var vp: SubViewport = SubViewport.new()
	vp.size = MAP_SIZE
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(vp)
	_map_world_root = Node3D.new()
	vp.add_child(_map_world_root)
	_map_camera = Camera3D.new()
	_map_camera.fov = 50.0
	_map_camera.far = 3000.0
	_map_world_root.add_child(_map_camera)
	_sub_blip = _blip(Color(0.3, 1.0, 0.4), 6.0)
	_apex_blip = _blip(Color(1.0, 0.25, 0.2), 12.0)
	_array_blip = _blip(Color(1.0, 0.9, 0.3), 4.0)


## Copies the dive site's geometry into the minimap's own world as
## translucent, unlit boxes, plus a water surface.
func _populate_map() -> void:
	if game == null:
		return
	var site: Node3D = game.get_node_or_null("World/Site") as Node3D
	if site == null:
		return
	_map_built = true
	var rock: StandardMaterial3D = _map_material(Color(0.55, 0.6, 0.65, 0.16))
	for child: Node in site.get_children():
		var body: StaticBody3D = child as StaticBody3D
		if body == null:
			continue
		for part: Node in body.get_children():
			var mi: MeshInstance3D = part as MeshInstance3D
			if mi == null:
				continue
			var copy: MeshInstance3D = MeshInstance3D.new()
			copy.mesh = mi.mesh
			copy.material_override = rock
			copy.transform = body.transform * mi.transform
			_map_world_root.add_child(copy)
	var water: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(CanyonSite.HALF_WIDTH * 2.0 + 80.0, CanyonSite.SOUTH_Z - CanyonSite.NORTH_Z + 80.0)
	water.mesh = plane
	water.material_override = _map_material(Color(0.2, 0.5, 0.9, 0.3))
	water.position = Vector3(0, 0, (CanyonSite.SOUTH_Z + CanyonSite.NORTH_Z) * 0.5)
	_map_world_root.add_child(water)


func _update_map(delta: float) -> void:
	_orbit += MAP_ORBIT_DEG_PER_SEC * delta
	var a: float = deg_to_rad(_orbit)
	var eye: Vector3 = MAP_CENTER + Vector3(cos(a), 0.55, sin(a)).normalized() * MAP_DISTANCE
	_map_camera.look_at_from_position(eye, MAP_CENTER, Vector3.UP)
	if game == null:
		return
	_sub_blip.position = game.sub_frame.sub_transform.origin
	var apex: ApexMonster = game.get_node_or_null("World/Apex") as ApexMonster
	if apex != null:
		_apex_blip.position = apex.position
	var target: Node3D = game.get_node_or_null("World/ScanTarget") as Node3D
	if target != null:
		_array_blip.position = target.position


func _blip(color: Color, radius: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mi.mesh = sphere
	var mat: StandardMaterial3D = _map_material(color)
	mat.no_depth_test = true  # Always visible through the terrain.
	mat.render_priority = 1
	mi.material_override = mat
	_map_world_root.add_child(mi)
	return mi


static func _map_material(color: Color) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


# --- Stats -------------------------------------------------------------------

func _build_stats() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.offset_left = -MAP_SIZE.x - 10
	panel.offset_right = -10
	panel.offset_top = 20 + MAP_SIZE.y
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg: StyleBoxFlat = StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.4)
	bg.set_content_margin_all(8)
	panel.add_theme_stylebox_override(&"panel", bg)
	add_child(panel)
	_stats = Label.new()
	_stats.add_theme_font_size_override(&"font_size", 12)
	_stats.add_theme_color_override(&"font_color", Color(0.85, 0.92, 0.85))
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_stats)


func _update_stats() -> void:
	if game == null:
		return
	_stats.text = stats_text(game)


## The stats panel's text. Static so tests can check it without rendering.
static func stats_text(g: Game) -> String:
	var c: SubController = g.get_node("SubController") as SubController
	var lines: PackedStringArray = PackedStringArray()
	var b: float = c.buoyancy
	var b_word: String = "NEUTRAL" if absf(b) < 0.02 else ("POSITIVE (rising)" if b > 0.0 else "NEGATIVE (sinking)")
	lines.append("SUB")
	lines.append("  depth %.1f m   speed %+.2f m/s   heading %03.0f   pitch %+.0f°" % [c.depth, c.speed, c.heading_deg, c.pitch_deg])
	lines.append("  vertical %+.2f m/s   buoyancy %s %+.2f m/s²" % [c.vertical_speed, b_word, b])
	lines.append("  engine %+.0f%%   tank %.0f%%   air %.0f%%   bilge %.0f%%%s" % [
		c.engine_output * 100.0, c.tank_fraction * 100.0, c.air_fraction * 100.0, c.bilge_fraction * 100.0, "   SURFACED" if c.surfaced else ""])
	var margin: float = Acoustics.sub_db() - Acoustics.ambient_db()
	lines.append("NOISE")
	if Acoustics.sub_intensity <= 0.0:
		lines.append("  sub silent   ocean %.1f dB   masked" % Acoustics.ambient_db())
	else:
		lines.append("  sub %.1f dB   ocean %.1f dB   %s (%+.1f dB)" % [
			Acoustics.sub_db(), Acoustics.ambient_db(), "masked" if margin < 0.0 else "EXPOSED", margin])
	lines.append("  loudest: %s" % (Acoustics.top_text if Acoustics.top_text != "" else "nothing"))
	var apex: ApexMonster = g.get_node_or_null("World/Apex") as ApexMonster
	if apex != null:
		var dist: float = apex.position.distance_to(g.sub_frame.sub_transform.origin)
		lines.append("APEX  %s" % SuspicionModel.state_name(apex.state() as SuspicionModel.State))
		lines.append("  distance %.0f m   speed %.1f m/s   depth %.0f m" % [dist, apex.speed, -apex.position.y])
		lines.append("  suspicion %.0f   last SNR %s   alertness %.2f" % [
			apex.sync_suspicion, ("%+.1f dB" % apex.sync_snr) if apex.sync_snr > -99.0 else "none", apex.sync_alertness])
	var director: DiveDirector = g.get_node_or_null("DiveDirector") as DiveDirector
	var scan: ScanObjective = g.get_node_or_null("ScanObjective") as ScanObjective
	if director != null:
		lines.append("DIVE  %s   scan %.0f%%%s" % [
			DiveDirector.Phase.keys()[director.phase], (scan.progress * 100.0) if scan != null else 0.0,
			"  DONE" if scan != null and scan.complete else ""])
	return "\n".join(lines)
