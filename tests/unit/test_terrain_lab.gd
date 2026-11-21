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


func _lab() -> TerrainLab:
	var lab: TerrainLab = (load(TerrainLab.SCENE_PATH) as PackedScene).instantiate() as TerrainLab
	runner.add_child(lab)
	return lab


func test_panel_adds_moves_removes_each_constraint_type() -> void:
	var lab: TerrainLab = _lab()
	await runner.get_tree().process_frame
	lab.panel.auto_regenerate()
	var base_count: int = lab.spec.constraints.size()
	var probe: Vector2 = Vector2(-20, -100)
	var before: float = lab.site.height_at(probe.x, probe.y)
	# FlatPad
	var pad: FlatPad = lab.panel.add_constraint(FlatPad) as FlatPad
	expect_eq(lab.spec.constraints.size(), base_count + 1, "pad added")
	pad.centre = probe
	pad.height = -77.0
	pad.radius = 6.0
	lab.regenerate()
	expect(absf(lab.site.height_at(probe.x, probe.y) - (-77.0)) < 0.5, "terrain follows the pad")
	var idx: int = lab.spec.constraints.size() - 1
	expect(lab.panel.move_constraint(idx, Vector2(30, 0)), "pad moved")
	expect_eq(pad.centre, probe + Vector2(30, 0))
	lab.regenerate()
	expect(absf(lab.site.height_at(probe.x, probe.y) - (-77.0)) > 1.0, "terrain left the old spot")
	expect(lab.panel.remove_constraint(idx), "pad removed")
	lab.regenerate()
	expect_eq(lab.site.height_at(probe.x, probe.y), before, "terrain restored")
	# Corridor
	var cor: Corridor = lab.panel.add_constraint(Corridor) as Corridor
	idx = lab.spec.constraints.size() - 1
	expect(lab.panel.move_constraint(idx, Vector2(5, 7)), "corridor moved")
	expect_eq(cor.a, Vector3(5, 0, 7))
	expect_eq(cor.b, Vector3(5, 0, -43))
	lab.regenerate()
	expect(lab.overlay.line_count > 0, "overlay draws the corridor")
	expect(lab.panel.remove_constraint(idx), "corridor removed")
	# ClearColumn
	var col: ClearColumn = lab.panel.add_constraint(ClearColumn) as ClearColumn
	idx = lab.spec.constraints.size() - 1
	lab.panel.move_constraint(idx, Vector2(-9, 4))
	expect_eq(col.centre, Vector2(-9, 4))
	lab.regenerate()
	var with_col: int = lab.overlay.line_count
	expect(with_col > 0, "overlay draws the column")
	expect(lab.panel.remove_constraint(idx), "column removed")
	expect_eq(lab.spec.constraints.size(), base_count, "back to the original constraints")
	expect(not lab.panel.remove_constraint(99), "bad index rejected")
	lab.regenerate()
	expect(lab.overlay.line_count < with_col, "overlay follows the spec")
	lab.free()


func test_spec_save_load_round_trips() -> void:
	var spec: SiteSpec = (load(CanyonSite.PRESET) as SiteSpec).duplicate_deep()
	spec.seed = 31337
	spec.rim_y = -20.0
	spec.centreline = PackedVector2Array([Vector2(1, 50), Vector2(8, -200)])
	var pad: FlatPad = FlatPad.new()
	pad.label = "p"
	pad.centre = Vector2(3, -4)
	pad.radius = 7.0
	pad.height = -88.0
	pad.falloff = 5.0
	var cor: Corridor = Corridor.new()
	cor.a = Vector3(1, -50, 2)
	cor.b = Vector3(3, -60, -90)
	cor.width = 9.0
	cor.max_slope = 0.3
	var col: ClearColumn = ClearColumn.new()
	col.centre = Vector2(-5, -6)
	col.radius = 11.0
	spec.constraints = [pad, cor, col] as Array[SiteConstraint]
	var path: String = "user://test_spec_roundtrip.tres"
	expect_eq(SiteIO.save_spec(spec, path), OK)
	var back: SiteSpec = SiteIO.load_spec(path)
	expect(back != null, "loads")
	expect_eq(back.seed, 31337)
	expect_eq(back.rim_y, -20.0)
	expect_eq(back.centreline, spec.centreline)
	expect_eq(back.shelves.size(), spec.shelves.size())
	expect_eq(back.constraints.size(), 3)
	for p: Dictionary in LabPanel.exported_properties(spec):
		if p["name"] in ["constraints", "shelves", "width_curve", "depth_curve"]:
			continue
		expect_eq(back.get(p["name"]), spec.get(p["name"]), str(p["name"]))
	for k: int in range(3):
		for p: Dictionary in LabPanel.exported_properties(spec.constraints[k]):
			expect_eq(back.constraints[k].get(p["name"]), spec.constraints[k].get(p["name"]), "%d %s" % [k, p["name"]])
		expect_eq(back.constraints[k].get_script(), spec.constraints[k].get_script(), "type %d" % k)
	expect(SiteIO.load_spec("user://does_not_exist.tres") == null, "missing file gives null")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_heightmap_export_import_round_trips() -> void:
	var spec: SiteSpec = (load(CanyonSite.PRESET) as SiteSpec).duplicate_deep()
	var site: CanyonSite = TerrainLab.build_site(spec)
	var extent: Rect2 = Rect2(-80.0, -300.0, 120.0, 100.0)
	var cell: float = 4.0
	var path: String = "user://test_heightmap.png"
	expect_eq(SiteIO.export_heightmap(site, extent, cell, path), OK)
	var data: Dictionary = SiteIO.import_heightmap(path)
	expect(not data.is_empty(), "imports")
	expect(data.has("x_min") and data.has("z_min") and data.has("x_max") and data.has("z_max"), "sidecar has the extent")
	expect(data.has("min_y") and data.has("max_y") and data.has("vertical_scale"), "sidecar has the vertical scale")
	expect_eq(float(data["x_min"]), extent.position.x)
	var step: float = (float(data["max_y"]) - float(data["min_y"])) / 65535.0
	expect(absf(float(data["vertical_scale"]) - step) < 0.00001, "vertical scale is range / 65535")
	var heights: PackedFloat32Array = data["heights"]
	var w: int = data["width"]
	var h: int = data["height"]
	expect_eq(heights.size(), w * h)
	var worst: float = 0.0
	for j: int in range(h):
		for i: int in range(w):
			var y: float = site.height_at(extent.position.x + i * cell, extent.position.y + j * cell)
			worst = maxf(worst, absf(heights[j * w + i] - y))
	expect(worst <= step * 1.01 + 0.0001, "within one quantisation step (worst %f, step %f)" % [worst, step])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SiteIO.sidecar_path(path)))
	site.free()
