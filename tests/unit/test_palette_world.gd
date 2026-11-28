extends TestCase
## The world, creatures and objectives take their colours from the palette (docs/palette.md, M13.6).

const FILES: PackedStringArray = [
	"res://src/world/light_preset.gd", "res://src/world/ocean_surface.gd", "res://src/site/canyon_site.gd",
	"res://src/creature/apex_monster.gd", "res://src/objective/scan_target.gd", "res://src/damage/leak.tscn",
	"res://src/game/game.tscn", "res://src/player/underwater_view.gd", "res://src/world/surface_lighting.gd",
	"res://src/world/presets/day.tres", "res://src/world/presets/night.tres",
]


func test_listed_files_have_no_colour_literals() -> void:
	for f: String in FILES:
		var text: String = FileAccess.get_file_as_string(f)
		expect(not text.contains("Color(") or _only_palette_calls(text), "%s has a Color( literal" % f)


## Allows `Color(<expression>, alpha)` built from a swatch lookup, nothing numeric.
func _only_palette_calls(text: String) -> bool:
	for line: String in text.split("\n"):
		var i: int = line.find("Color(")
		if i < 0 or line.strip_edges().begins_with("#") or line.strip_edges().begins_with("##"):
			continue
		var rest: String = line.substr(i + 6)
		if not (rest.begins_with("Palette.") or rest.begins_with("OceanSurface.")):
			return false
	return true


func test_presets_store_swatch_names_that_exist() -> void:
	var pal: Palette = Palette.main()
	for p: LightPreset in [SurfaceLighting.DAY, SurfaceLighting.NIGHT]:
		for s: StringName in [p.sky_swatch, p.light_swatch, p.surface_top_swatch, p.surface_under_swatch]:
			expect(pal.has(s), "%s names missing swatch %s" % [p.preset_name, s])
		expect(p.sky_color == pal.color(p.sky_swatch), "%s sky follows the palette" % p.preset_name)


func test_ocean_fog_follows_env_deep() -> void:
	var pal: Palette = Palette.main()
	var old: Color = pal.color(&"env_deep")
	var env: Environment = Environment.new()
	var node: SurfaceLighting = SurfaceLighting.new()
	var holder: WorldEnvironment = WorldEnvironment.new()
	holder.environment = env
	node.environment_node = holder
	runner.add_child(node)
	var deep: Color = Color(0.5, 0.25, 0.125)
	pal.set_color(&"env_deep", deep)
	node._apply(500.0)
	expect(env.fog_light_color.is_equal_approx(deep), "fog follows env_deep")
	expect(OceanSurface.fog_color().is_equal_approx(deep), "ocean fog colour follows env_deep")
	pal.set_color(&"env_deep", old)
	node._apply(500.0)
	expect(env.fog_light_color.is_equal_approx(old), "fog restored")
	node.free()
	holder.free()


func test_water_and_floor_follow_the_palette() -> void:
	var pal: Palette = Palette.main()
	var old: Color = pal.color(&"env_water")
	pal.set_color(&"env_water", Color(0.2, 0.4, 0.6))
	expect(OceanSurface.water_color().is_equal_approx(Color(0.2, 0.4, 0.6)), "water follows env_water")
	pal.set_color(&"env_water", old)
	expect(CanyonSite.sand_color() == pal.color(&"floor_sand"), "sand")
	expect(CanyonSite.rock_color() == pal.color(&"floor_rock"), "rock")


static func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


func test_ocean_swatches_are_lifted_and_still_go_dark() -> void:
	var pal: Palette = Palette.main()
	var abyss: float = _lum(pal.color(&"env_abyss"))
	var deep: float = _lum(pal.color(&"env_deep"))
	var water: float = _lum(pal.color(&"env_water"))
	var teal: float = _lum(pal.color(&"env_teal"))
	expect(abyss < deep and deep < water and water < teal, "env swatches darken in order teal, water, deep, abyss")
	var w: Color = pal.color(&"env_water")
	expect(w.g > 0.5 and w.b > 0.65 and w.r < 0.15, "env_water is a saturated turquoise")
	expect(pal.color(&"env_teal").s < w.s and pal.color(&"env_teal").v > w.v, "env_teal is the paler, lit tone")


func test_silt_stays_dark_and_apart_from_lit_water() -> void:
	var pal: Palette = Palette.main()
	expect(_lum(pal.color(&"floor_silt")) < _lum(pal.color(&"env_water")), "silt is darker than the lit water")
