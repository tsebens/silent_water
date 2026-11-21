extends TestCase
## The terrain lab: loads headless, builds the same ground as the game, and its
## panel binds every exported property of the spec and the site tunables.

const SAMPLES: Array[Vector2] = [
	Vector2(0, -250), Vector2(-42, -100), Vector2(40, -280), Vector2(-100, -200),
	Vector2(36, -250), Vector2(10, 40), Vector2(55, -400), Vector2(-20, -330),
]


func test_lab_scene_loads_and_generates() -> void:
	var lab: TerrainLab = (load(TerrainLab.SCENE_PATH) as PackedScene).instantiate() as TerrainLab
	runner.add_child(lab)
	await runner.get_tree().process_frame
	expect(lab.site != null and lab.site.is_inside_tree(), "site generated")
	expect(lab.site.get_node_or_null("Terrain") != null, "terrain built")
	expect(lab.camera != null and lab.camera.current, "camera")
	expect(lab.last_build_ms > 0.0, "generation time measured")
	lab.toggle_lighting()
	lab.toggle_lighting()
	lab.regenerate()
	expect(lab.site != null, "regenerates")
	lab.free()


func test_lab_site_matches_game_site() -> void:
	var game_site: CanyonSite = CanyonSite.new()
	var lab_spec: SiteSpec = (load(CanyonSite.PRESET) as SiteSpec).duplicate_deep()
	var lab_site: CanyonSite = TerrainLab.build_site(lab_spec, CanyonSite.new())
	for s: Vector2 in SAMPLES:
		expect_eq(lab_site.height_at(s.x, s.y), game_site.height_at(s.x, s.y), "at %s" % s)
	# Same seed after an edit round trip: another seed differs, the seed back matches.
	lab_spec.seed = 1
	var other: CanyonSite = TerrainLab.build_site(lab_spec, CanyonSite.new())
	var differs: bool = false
	for s: Vector2 in SAMPLES:
		differs = differs or other.height_at(s.x, s.y) != game_site.height_at(s.x, s.y)
	expect(differs, "a new seed changes the ground")
	lab_spec.seed = (load(CanyonSite.PRESET) as SiteSpec).seed
	var again: CanyonSite = TerrainLab.build_site(lab_spec, CanyonSite.new())
	for s: Vector2 in SAMPLES:
		expect_eq(again.height_at(s.x, s.y), game_site.height_at(s.x, s.y), "restored %s" % s)
	game_site.free()
	lab_site.free()
	other.free()
	again.free()


func test_tunables_carry_to_generated_site() -> void:
	var t: CanyonSite = CanyonSite.new()
	t.detail_amp = 9.0
	t.strata_height = 3.0
	var s: CanyonSite = TerrainLab.build_site(load(CanyonSite.PRESET) as SiteSpec, t)
	expect_eq(s.detail_amp, 9.0)
	expect_eq(s.strata_height, 3.0)
	t.free()
	s.free()


func test_panel_binds_every_exported_property() -> void:
	var spec: SiteSpec = (load(CanyonSite.PRESET) as SiteSpec).duplicate_deep()
	var tunables: CanyonSite = CanyonSite.new()
	var panel: LabPanel = LabPanel.new()
	runner.add_child(panel)
	panel.setup(spec, tunables)
	var spec_props: Array[Dictionary] = LabPanel.exported_properties(spec)
	expect(spec_props.size() >= 12, "SiteSpec exports found (%d)" % spec_props.size())
	for p: Dictionary in spec_props:
		expect(panel.control_for(LabPanel.SECTION_SPEC, p["name"]) != null, "SiteSpec.%s has a control" % p["name"])
	var site_props: int = 0
	for p: Dictionary in LabPanel.exported_properties(tunables):
		if p["name"] == "spec":
			continue
		site_props += 1
		expect(panel.control_for(LabPanel.SECTION_SITE, p["name"]) != null, "CanyonSite.%s has a control" % p["name"])
	expect(site_props >= 15, "CanyonSite exports found (%d)" % site_props)
	panel.free()
	tunables.free()


func test_panel_edits_reach_the_objects() -> void:
	var spec: SiteSpec = (load(CanyonSite.PRESET) as SiteSpec).duplicate_deep()
	var tunables: CanyonSite = CanyonSite.new()
	var panel: LabPanel = LabPanel.new()
	runner.add_child(panel)
	panel.setup(spec, tunables)
	(panel.control_for(LabPanel.SECTION_SPEC, "seed") as SpinBox).value = 77
	(panel.control_for(LabPanel.SECTION_SPEC, "wall_foot") as SpinBox).value = 25.0
	(panel.control_for(LabPanel.SECTION_SITE, "detail_octaves") as SpinBox).value = 2
	expect_eq(spec.seed, 77)
	expect_near(spec.wall_foot, 25.0)
	expect_eq(tunables.detail_octaves, 2)
	(panel.control_for(LabPanel.SECTION_SPEC, "centreline") as LineEdit).text_submitted.emit("0,60; 10,-200")
	expect_eq(spec.centreline.size(), 2)
	(panel.control_for(LabPanel.SECTION_SPEC, "width_curve") as LineEdit).text_submitted.emit("0,1; 1,2")
	expect(spec.width_curve != null and absf(spec.width_curve.sample(1.0) - 2.0) < 0.01, "curve set")
	panel.free()
	tunables.free()


func test_point_text_round_trip() -> void:
	var pts: PackedVector2Array = PackedVector2Array([Vector2(1, 2), Vector2(-3.5, 4)])
	expect_eq(LabPanel.text_to_points(LabPanel.points_to_text(pts)), pts)
	expect_eq(LabPanel.text_to_points("junk; 1,x; 5,6").size(), 1)
