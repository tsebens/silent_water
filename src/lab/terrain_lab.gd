class_name TerrainLab
extends Node3D
## Developer scene for shaping dive sites without a game session: a
## [CanyonSite] generated from an editable [SiteSpec], a free-flying camera, the
## ocean surface and the day/night light presets for context, and a [LabPanel]
## for every parameter. It uses the same generator and [method
## CanyonSite.height_at] as the game; the lab adds no terrain code of its own.
## Reached from `--terrain-lab` or the dev menu, never from a session.

const SCENE_PATH: String = "res://src/lab/terrain_lab.tscn"
const MAIN_SCENE: String = "res://src/main/main.tscn"
const DAY: LightPreset = preload("res://src/world/presets/day.tres")
const NIGHT: LightPreset = preload("res://src/world/presets/night.tres")
## Auto-regeneration waits for the button once a build takes longer than this.
const AUTO_MAX_MS: float = 1500.0
const AUTO_DELAY: float = 0.4

var spec: SiteSpec
var tunables: CanyonSite = CanyonSite.new()
var site: CanyonSite
var camera: LabCamera
var panel: LabPanel
var last_build_ms: float = 0.0
var preset: LightPreset = DAY

var _site_holder: Node3D
var _ocean: OceanSurface
var _sun: DirectionalLight3D
var _env: Environment
var _debounce: Timer
var _stale: bool = false


## A site built the way the game builds one, from [param site_spec] with the
## tunables of [param from] (the lab's own, or the defaults) copied over. The
## caller adds it to the tree, which generates the terrain.
static func build_site(site_spec: SiteSpec, from: CanyonSite = null) -> CanyonSite:
	var s: CanyonSite = CanyonSite.new()
	if from != null:
		for p: Dictionary in LabPanel.exported_properties(from):
			if p["name"] != "spec":
				s.set(p["name"], from.get(p["name"]))
	s.spec = site_spec
	return s


func _ready() -> void:
	AudioBuses.ensure()
	spec = (load(CanyonSite.PRESET) as SiteSpec).duplicate_deep()
	_build_world()
	_build_ui()
	regenerate()
	camera.set_view(Vector3(0.0, 45.0, 150.0), 0.0, -0.45)


func _build_world() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	add_child(_sun)
	_site_holder = Node3D.new()
	_site_holder.name = "SiteHolder"
	add_child(_site_holder)
	_ocean = OceanSurface.new()
	_ocean.name = "OceanSurface"
	add_child(_ocean)
	camera = LabCamera.new()
	camera.name = "Camera"
	add_child(camera)
	_apply_preset()


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	panel = LabPanel.new()
	panel.name = "Panel"
	panel.setup(spec, tunables)
	panel.anchor_bottom = 1.0
	panel.offset_right = 400.0
	panel.changed.connect(_on_changed)
	panel.regenerate_requested.connect(regenerate)
	panel.lighting_toggled.connect(toggle_lighting)
	panel.back_requested.connect(back)
	layer.add_child(panel)
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = AUTO_DELAY
	_debounce.timeout.connect(_on_debounce)
	add_child(_debounce)


## Rebuilds the site from the current spec and tunables, and times it.
func regenerate() -> void:
	var t0: int = Time.get_ticks_usec()
	if site != null:
		_site_holder.remove_child(site)
		site.free()
	site = build_site(spec, tunables)
	site.name = "Site"
	_site_holder.add_child(site)
	last_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_stale = false
	_update_readout()


func toggle_lighting() -> void:
	preset = NIGHT if preset == DAY else DAY
	_apply_preset()


func back() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)


func _apply_preset() -> void:
	_env.background_color = preset.sky_color
	_env.ambient_light_color = preset.light_color
	_env.ambient_light_energy = preset.ambient_energy
	_sun.light_color = preset.light_color
	_sun.light_energy = preset.sun_energy
	var dir: Vector3 = preset.sun_direction.normalized()
	if not dir.is_zero_approx():
		var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
		_sun.basis = Basis.looking_at(-dir, up)
	_ocean.set_colors(preset.surface_top_color, preset.surface_under_color, preset.sky_color)
	_ocean.set_sun(preset.sun_direction, preset.light_color, preset.sun_energy)


func _on_changed() -> void:
	_stale = true
	_update_readout()
	if panel.auto_regenerate() and last_build_ms <= AUTO_MAX_MS:
		_debounce.start()


func _on_debounce() -> void:
	if _stale:
		regenerate()


func _update_readout() -> void:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("generated in %.0f ms%s" % [last_build_ms, "   (edited: press Regenerate)" if _stale else ""])
	for problem: String in spec.validate():
		lines.append("! " + problem)
	panel.set_readout("\n".join(lines))


func _process(_delta: float) -> void:
	# The sea follows the camera, snapped to its grid so it does not swim.
	var cell: float = _ocean.size / float(maxi(_ocean.subdivisions + 1, 1))
	_ocean.position = Vector3(snappedf(camera.position.x, cell), OceanSurface.SURFACE_Y, snappedf(camera.position.z, cell))
