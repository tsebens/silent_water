extends TestCase
## Asset Studio plugin: queue and concept view models from fixture manifests, and the
## backend result parser (errors are shown verbatim).

const FIXTURES: String = "res://tests/fixtures/asset_studio/"


func _fixture(name: String) -> String:
	return FileAccess.get_file_as_string(FIXTURES + name)


func _listing() -> Dictionary:
	return JSON.parse_string(_fixture("list.json")) as Dictionary


func test_queue_rows_from_manifests() -> void:
	var q: AssetQueueModel = AssetQueueModel.new()
	q.load_assets(_listing()["assets"])
	expect_eq(q.rows.size(), 3)
	expect_eq(q.rows[0]["slug"], "angler")
	var a: Dictionary = q.find("angler")
	expect_eq(a["class"], "creature")
	expect_eq(a["stage"], "locked")
	expect_eq(a["issue_text"], "#12")
	expect_eq(a["last_result"], "locked v3")
	var b: Dictionary = q.find("bulkhead")
	expect_eq(b["issue_text"], "-")
	expect_eq(b["last_result"], "check failed: triangles, bbox")
	expect_eq(q.find("coral")["last_result"], "-")
	expect(q.find("nope").is_empty())


func test_concept_variants_and_state() -> void:
	var l: Dictionary = _listing()
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset((l["assets"] as Array)[0] as Dictionary, l["providers"] as Dictionary, l["selected"] as Dictionary)
	expect_eq(c.variants.size(), 3)
	expect_eq(c.variant("v1")["state"], "rejected")
	expect_eq(c.variant("v2")["state"], "pending")
	expect_eq(c.variant("v3")["state"], "locked")
	expect_eq(c.variant("v2")["prompt"], "angler, bigger lure")
	expect_eq(c.variant("v2")["provider"], "openai")
	expect_eq(c.image_providers.size(), 4)
	expect_eq(c.default_provider, "mock")


func _concept_asset(decisions: Array, locked: Variant) -> Dictionary:
	var lin: Array = []
	for id: String in ["v1", "v2", "v3", "v4"]:
		lin.append({"id": id, "kind": "concept", "path": "", "provider": "mock", "model": "m", "prompt": "p", "parent": null})
	return {"slug": "x", "lineage": lin, "decisions": decisions, "locked": locked}


func test_concept_groups_pending_accepted_rejected() -> void:
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset(_concept_asset([
		{"variant": "v1", "decision": "approved"},
		{"variant": "v2", "decision": "rejected"},
		{"variant": "v3", "decision": "approved"},
	], {"variant": "v3", "decision": "approved"}))
	expect_eq(c.group("accepted").size(), 2)
	expect_eq(c.group("accepted")[0]["id"], "v3")
	expect_eq(c.variant("v3")["state"], "locked")
	expect_eq(c.variant("v1")["state"], "accepted")
	expect_eq(c.locked_id(), "v3")
	expect_eq(c.group("rejected").size(), 1)
	expect_eq(c.group("pending").size(), 1)
	c.in_flight = 2
	expect_eq(c.section_title("pending"), "Pending (3)")
	expect_eq(c.section_title("accepted"), "Accepted (2)")
	expect_eq(c.section_title("rejected"), "Rejected (1)")


func test_concept_approve_reject_regroup_at_once() -> void:
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset(_concept_asset([], null))
	expect_eq(c.group("pending").size(), 4)
	c.approve("v1")
	expect_eq(c.locked_id(), "v1")
	c.approve("v2")
	expect_eq(c.locked_id(), "v2", "lock moves to the latest approval")
	expect_eq(c.variant("v1")["state"], "accepted")
	expect_eq(c.group("accepted").size(), 2)
	c.reject("v2")
	expect_eq(c.locked_id(), "v1", "rejecting the lock hands it back to the previous approval")
	expect_eq(c.group("rejected").size(), 1)
	c.reject("v1")
	expect_eq(c.locked_id(), "")
	expect_eq(c.group("pending").size(), 2)
	c.approve("v1")
	expect_eq(c.group("rejected").size(), 1, "re-approving leaves rejected")
	c.approve("nope")
	expect_eq(c.group("accepted").size(), 1)


func test_texture_cache_loads_each_file_once() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build/"))
	var good: String = ProjectSettings.globalize_path("res://build/tc_good.png")
	var bad: String = ProjectSettings.globalize_path("res://build/tc_bad.png")
	var img: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.save_png(good)
	var f: FileAccess = FileAccess.open(bad, FileAccess.WRITE)
	f.store_string("not a png")
	f.close()
	var cache: AssetTextureCache = AssetTextureCache.new()
	var t1: Texture2D = cache.get_texture(good)
	expect(t1 != null, "good file loads")
	expect(cache.get_texture(good) == t1, "same texture on redraw")
	expect_eq(cache.loads, 1)
	expect(cache.get_texture(bad) == null)
	expect(cache.get_texture(bad) == null)
	expect(cache.get_texture(bad) == null)
	expect_eq(cache.loads, 2, "bad file read once")
	expect_eq(cache.warnings, 1, "one warning for the bad file")
	expect(cache.error_for(bad) != "", "reason kept for the placeholder")
	expect_eq(cache.error_for(good), "")
	DirAccess.remove_absolute(good)
	DirAccess.remove_absolute(bad)


func test_concept_lineage_panel() -> void:
	var l: Dictionary = _listing()
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset((l["assets"] as Array)[0] as Dictionary)
	var chain: Array[Dictionary] = c.lineage_of("v3")
	expect_eq(chain.size(), 3)
	expect_eq(chain[0]["id"], "v3")
	expect_eq(chain[1]["id"], "v2")
	expect_eq(chain[2]["parent"], null)
	expect_eq(chain[0]["model"], "gpt-image-1")


func test_action_arguments() -> void:
	var l: Dictionary = _listing()
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset((l["assets"] as Array)[0] as Dictionary)
	expect_eq(c.approve_args("v2"), PackedStringArray(["lock", "angler", "v2", "--decision", "approved"]))
	expect_eq(c.reject_args("v2", "meh"), PackedStringArray(["lock", "angler", "v2", "--decision", "rejected", "--notes", "meh"]))
	expect_eq(
		c.refine_args("v2", "more teeth", "openai"),
		PackedStringArray(["concept", "angler", "--refine", "v2", "--notes", "more teeth", "--image-provider", "openai"])
	)
	expect(c.refine_args("v2", "  ").is_empty(), "refine without notes builds no command")
	expect_eq(c.generate_more_args(3, "fal"), PackedStringArray(["concept", "angler", "--n", "3", "--image-provider", "fal", "--presentation", "subject"]))


func test_prompt_writer_is_passed_on_generate_refine_and_brief() -> void:
	var l: Dictionary = _listing()
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset((l["assets"] as Array)[0] as Dictionary, {"prompt_writer": ["mock", "claude-cli"]}, {"prompt_writer": "claude-cli"})
	expect_eq(c.prompt_writers.size(), 2)
	expect_eq(c.default_writer, "claude-cli")
	expect_eq(c.generate_more_args(3, "", "claude-cli"), PackedStringArray(["concept", "angler", "--n", "3", "--prompt-writer", "claude-cli", "--presentation", "subject"]))
	expect_eq(
		c.refine_args("v2", "more teeth", "fal", "mock"),
		PackedStringArray(["concept", "angler", "--refine", "v2", "--notes", "more teeth", "--image-provider", "fal", "--prompt-writer", "mock"])
	)
	expect_eq(c.brief_args("claude-cli"), PackedStringArray(["brief", "angler", "--prompt-writer", "claude-cli"]))
	expect_eq(c.brief_args(), PackedStringArray(["brief", "angler"]))


func test_backend_success_parse() -> void:
	var r: AssetBackendResult = AssetBackendResult.parse(0, "warming up\n" + JSON.stringify({"ok": true, "assets": []}))
	expect(r.ok)
	expect(r.data.has("assets"))


func test_backend_error_is_verbatim() -> void:
	var r: AssetBackendResult = AssetBackendResult.parse(1, _fixture("error.txt"))
	expect(not r.ok)
	expect_eq(r.error, "OPENAI_API_KEY is not set (put it in tools/asset_pipeline/.env)")


func test_backend_non_json_output_is_verbatim() -> void:
	var text: String = "Traceback (most recent call last):\n  File \"x.py\", line 1\nBoom"
	var r: AssetBackendResult = AssetBackendResult.parse(2, text)
	expect(not r.ok)
	expect_eq(r.error, text)
	expect(not AssetBackendResult.parse(0, "").ok, "empty output is never a success")


func test_backend_failed_gate_without_error_text() -> void:
	var r: AssetBackendResult = AssetBackendResult.parse(1, '{"ok": false, "failed": ["triangles"]}')
	expect(not r.ok)
	expect(r.error.contains("triangles"))


func test_runner_reports_missing_executable_without_blocking() -> void:
	var r: AssetBackendRunner = AssetBackendRunner.new()
	r.executable = "/nonexistent/asset-backend"
	runner.add_child(r)
	var seen: Array[AssetBackendResult] = []
	r.finished.connect(func(_a: PackedStringArray, res: AssetBackendResult) -> void: seen.append(res))
	expect(r.run(PackedStringArray(["list"])))
	expect(r.busy)
	expect(not r.run(PackedStringArray(["list"])), "a second command is refused while one runs")
	var t0: int = Time.get_ticks_msec()
	while seen.is_empty() and Time.get_ticks_msec() - t0 < 10000:
		await runner.get_tree().process_frame
	expect_eq(seen.size(), 1)
	if not seen.is_empty():
		expect(not seen[0].ok)
		expect(seen[0].error.contains("/nonexistent/asset-backend"), seen[0].error)
	expect(not r.busy)
	r.queue_free()


func test_panel_loads_fixture_and_shows_backend_error() -> void:
	var panel: AssetStudioPanel = AssetStudioPanel.new()
	panel.set_meta("fixture", true)
	runner.add_child(panel)
	panel.show_listing(_listing())
	expect_eq(panel.queue.rows.size(), 3)
	expect_eq(panel.concept.slug, "angler")
	panel.show_error("boom [x]")
	expect(panel._error.visible)
	expect(panel._error.get_parsed_text().contains("boom [x]"), "error text shown verbatim")
	panel.queue_free()


# --- turnaround, brief and model views (M10.10) ---------------------------------------------

func _model_listing() -> Dictionary:
	return JSON.parse_string(_fixture("list_model.json")) as Dictionary


func _model_asset() -> Dictionary:
	return (_model_listing()["assets"] as Array)[0] as Dictionary


func _reports() -> Dictionary:
	return {"tests/fixtures/asset_studio/check_report.json": JSON.parse_string(_fixture("check_report.json"))}


func _load_model() -> AssetModelModel:
	var l: Dictionary = _model_listing()
	var m: AssetModelModel = AssetModelModel.new()
	m.load_asset(_model_asset(), l["providers"] as Dictionary, l["selected"] as Dictionary, _reports())
	return m


func test_turnaround_uses_latest_set_in_view_order() -> void:
	var t: AssetTurnaroundModel = AssetTurnaroundModel.new()
	t.load_asset(_model_asset(), _fixture("brief.md"))
	expect_eq(t.views.size(), 6)
	expect_eq(t.views[0]["view"], "front")
	expect_eq(t.views[3]["view"], "right")
	expect_eq(t.view("front")["id"], "t2_front", "the newest set wins")
	expect_eq(t.view("front")["provider"], "openai")
	expect(not t.view("right")["present"], "t2 has no right view")
	expect_eq(t.view("right")["caption"], "right · missing")
	expect_eq(t.present_count(), 3)


func test_cross_layout_maps_views_to_cells() -> void:
	var t: AssetTurnaroundModel = AssetTurnaroundModel.new()
	t.load_asset(_model_asset(), "")
	expect_eq(t.view("front")["cell"], Vector2i(1, 1), "front centre")
	expect_eq(t.view("top")["cell"], Vector2i(1, 0), "top above")
	expect_eq(t.view("left")["cell"], Vector2i(0, 1))
	expect_eq(t.view("right")["cell"], Vector2i(2, 1))
	expect_eq(t.view("back")["cell"], Vector2i(0, 2), "back bottom-left")
	expect_eq(t.view("bottom")["cell"], Vector2i(1, 2), "bottom below front")
	expect_eq(t.view_at(Vector2i(1, 1)), "front")
	expect_eq(t.view_at(Vector2i(0, 0)), "", "corner has no view")
	expect_eq(t.view_at(Vector2i(2, 2)), "")


func test_missing_views_are_empty_slots() -> void:
	var t: AssetTurnaroundModel = AssetTurnaroundModel.new()
	t.load_asset(_model_asset(), "")
	expect_eq(t.empty_views(), PackedStringArray(["right", "top", "bottom"]))
	var asset: Dictionary = _model_asset().duplicate(true)
	(asset["lineage"] as Array).append({"id": "t2_right", "kind": "turnaround", "path": "", "provider": "openai", "model": "gpt-image-1", "parent": "v1"})
	t.load_asset(asset, "")
	expect_eq(t.empty_views(), PackedStringArray(["top", "bottom"]), "a four-view asset has empty top and bottom")
	expect(not t.view("top")["present"])
	expect_eq(t.view("top")["caption"], "top · missing")
	expect_eq(t.regenerate_args("top"), PackedStringArray(["turnaround", "angler2", "--view", "top"]), "the empty slot's Generate calls --view")


func test_fit_cell_size_keeps_aspect_and_shrinks() -> void:
	var big: float = AssetTurnaroundModel.fit_cell_size(Vector2(1200, 900))
	var small: float = AssetTurnaroundModel.fit_cell_size(Vector2(600, 450))
	expect(big > small and small > 0.0, "shrinks with the panel")
	var wide: float = AssetTurnaroundModel.fit_cell_size(Vector2(3000, 600))
	var narrow: float = AssetTurnaroundModel.fit_cell_size(Vector2(600, 600))
	expect(wide > 0.0 and wide < 600.0, "height limits a wide panel")
	expect_near(AssetTurnaroundModel.fit_cell_size(Vector2(3 * 200 + 8, 3 * (200 + AssetTurnaroundModel.CELL_CHROME) + 8)), 200.0, 0.001)
	expect(narrow <= 600.0 / 3.0, "width limits a narrow panel")
	expect_eq(AssetTurnaroundModel.fit_cell_size(Vector2(10, 10)), 0.0, "never negative")


func test_turnaround_actions() -> void:
	var t: AssetTurnaroundModel = AssetTurnaroundModel.new()
	t.load_asset(_model_asset(), _fixture("brief.md"))
	expect_eq(t.generate_args("fal"), PackedStringArray(["turnaround", "angler2", "--image-provider", "fal"]))
	expect_eq(t.regenerate_args("back", "openai"), PackedStringArray(["turnaround", "angler2", "--view", "back", "--image-provider", "openai"]))
	expect_eq(t.regenerate_args("left"), PackedStringArray(["turnaround", "angler2", "--view", "left"]))
	expect_eq(t.regenerate_args("top"), PackedStringArray(["turnaround", "angler2", "--view", "top"]))
	expect(t.regenerate_args("up").is_empty(), "unknown view builds no command")
	expect(t.draft_brief_args().is_empty(), "drafting needs all four views")
	var bare: AssetTurnaroundModel = AssetTurnaroundModel.new()
	bare.load_asset({"slug": "coral", "locked": null, "lineage": []})
	expect(bare.generate_args().is_empty(), "nothing to turn around without a locked concept")
	expect(bare.regenerate_args("front").is_empty())
	expect_eq(bare.present_count(), 0)


func test_brief_edit_state() -> void:
	var t: AssetTurnaroundModel = AssetTurnaroundModel.new()
	t.load_asset(_model_asset(), _fixture("brief.md"))
	expect_eq(t.brief_path, "tests/fixtures/asset_studio/brief.md")
	expect(t.brief_text.contains("size_m: 2.5"))
	expect(not t.dirty)
	expect(not t.can_save_brief())
	t.set_brief_text(t.brief_text + "- extra\n")
	expect(t.dirty and t.can_save_brief())
	t.set_brief_text(_fixture("brief.md"))
	expect(not t.dirty, "editing back to the saved text is clean again")
	t.set_brief_text("changed")
	t.mark_saved()
	expect(not t.dirty)
	var none: AssetTurnaroundModel = AssetTurnaroundModel.new()
	none.load_asset({"slug": "coral", "lineage": []})
	expect_eq(none.target_brief_path(), "assets/models/coral/concept/brief.md")


func test_draft_brief_needs_four_views_and_clean_text() -> void:
	var asset: Dictionary = _model_asset().duplicate(true)
	(asset["lineage"] as Array).append({"id": "t2_right", "kind": "turnaround", "path": "", "provider": "openai", "model": "gpt-image-1", "parent": "v1"})
	var t: AssetTurnaroundModel = AssetTurnaroundModel.new()
	t.load_asset(asset, "text")
	expect_eq(t.draft_brief_args(), PackedStringArray(["brief", "angler2"]))
	t.set_brief_text("edited")
	expect(t.draft_brief_args().is_empty(), "unsaved edits block a redraft that would overwrite them")


func test_model_runs_from_manifest_and_gate_report() -> void:
	var m: AssetModelModel = _load_model()
	expect_eq(m.runs.size(), 3)
	expect_eq(m.run("r1_tripo")["stage"], "raw")
	expect_eq(m.run("c1")["stage"], "cleaned")
	expect_eq(m.run("c1")["triangles"], 6120)
	expect_eq(m.triangle_text("c1"), "6120 triangles")
	expect_eq(m.triangle_text("r1_meshy"), "triangles: unknown")
	expect_eq(m.gate_summary("c1"), "failed: triangles, silhouette_back")
	expect_eq(m.gate_summary("r1_meshy"), "not checked")
	var rows: Array[Dictionary] = m.gate_rows("c1")
	expect_eq(rows.size(), 8)
	expect_eq(rows[0]["name"], "triangles")
	expect(not rows[0]["ok"])
	expect(rows[1]["ok"])
	expect_eq(rows[6]["name"], "silhouette_back")
	expect(m.gate_rows("r1_meshy").is_empty())
	expect_eq(m.three_d_providers.size(), 3)
	expect_eq(m.default_provider, "mock")


func test_model_bake_off_compare_set() -> void:
	var m: AssetModelModel = _load_model()
	expect_eq(m.compare_ids, PackedStringArray(["c1"]), "starts on the newest run")
	expect(m.toggle_compare("r1_tripo"))
	expect(m.toggle_compare("r1_meshy"))
	expect_eq(m.compare_ids.size(), 3)
	expect(not m.toggle_compare("nope"))
	expect(m.toggle_compare("c1"), "a run can be dropped")
	expect_eq(m.compare_ids, PackedStringArray(["r1_tripo", "r1_meshy"]))
	m.toggle_compare("r1_tripo")
	expect(not m.toggle_compare("r1_meshy"), "the last run stays")
	expect_eq(m.compare_ids.size(), 1)


func test_model_light_toggle() -> void:
	var m: AssetModelModel = AssetModelModel.new()
	expect_eq(m.light, AssetModelModel.LIGHT_WHITE)
	expect_eq(m.light_color(), Color(1, 1, 1))
	m.toggle_light()
	expect_eq(m.light, AssetModelModel.LIGHT_RED)
	expect(m.light_color().r > 0.9 and m.light_color().g < 0.1, "red light is red")
	m.toggle_light()
	expect_eq(m.light, AssetModelModel.LIGHT_WHITE)
	m.set_light(&"red")
	expect_eq(m.light, AssetModelModel.LIGHT_RED)
	m.set_light(&"green")
	expect_eq(m.light, AssetModelModel.LIGHT_RED, "unknown light is ignored")


func test_model_wireframe_and_turntable_state() -> void:
	var m: AssetModelModel = AssetModelModel.new()
	expect(not m.wireframe)
	m.toggle_wireframe()
	expect(m.wireframe)
	m.toggle_wireframe()
	expect(not m.wireframe)
	expect(m.turntable, "turntable starts on")
	expect_near(m.advance(1.0), AssetModelModel.TURNTABLE_DEG_PER_SEC, 0.001)
	m.toggle_turntable()
	var held: float = m.angle_deg
	expect_near(m.advance(5.0), held, 0.001)
	m.toggle_turntable()
	m.angle_deg = 350.0
	expect_near(m.advance(1.0), fmod(350.0 + AssetModelModel.TURNTABLE_DEG_PER_SEC, 360.0), 0.001)


func test_model_triangle_count_from_mesh() -> void:
	expect_eq(AssetModelModel.count_triangles(null), 0)
	expect_eq(AssetModelModel.count_triangles(BoxMesh.new()), 12)


func test_model_backend_arguments() -> void:
	var m: AssetModelModel = _load_model()
	expect_eq(m.to3d_args(PackedStringArray(["tripo", "meshy"])), PackedStringArray(["to3d", "angler2", "--3d-provider", "tripo", "meshy"]))
	expect(m.to3d_args(PackedStringArray()).is_empty())
	expect_eq(m.cleanup_args("r1_tripo"), PackedStringArray(["cleanup", "angler2", "--source", "r1_tripo"]))
	expect(m.cleanup_args("c1").is_empty(), "cleanup starts from a raw mesh")
	expect_eq(m.check_args("c1"), PackedStringArray(["check", "angler2", "--source", "c1"]))
	expect(m.check_args("r1_tripo").is_empty())
	expect(not m.can_export("c1"), "a mesh that failed its gates cannot be exported")
	expect(m.export_args("r1_tripo").is_empty())


func _picker_model() -> AssetModelModel:
	var l: Dictionary = _model_listing()
	var m: AssetModelModel = AssetModelModel.new()
	m.load_asset(_model_asset(), l["providers"] as Dictionary, l["selected"] as Dictionary, _reports(), {"tripo": 4, "meshy": 4, "mock": 8, "single": 1})
	return m


func test_view_picker_lists_latest_turnaround_views() -> void:
	var m: AssetModelModel = _picker_model()
	expect(m.turnaround_views.size() >= 1)
	expect_eq(m.turnaround_views[0]["view"], "front")
	expect(m.is_single("single"))
	expect(not m.is_single("tripo"))
	expect(not m.is_single("unknown-provider"), "an unknown limit counts as multi-image")


func test_view_picker_single_is_a_radio_choice() -> void:
	var m: AssetModelModel = _picker_model()
	expect(m.toggle_view("left", "single"))
	expect(m.toggle_view("back", "single"))
	expect_eq(m.picked_views, PackedStringArray(["back"]), "picking another view replaces the choice")
	expect(m.toggle_view("back", "single"), "picking it again clears it")
	expect(m.picked_views.is_empty())
	expect(not m.toggle_view("nonexistent", "single"))


func test_view_picker_multi_keeps_pick_order_and_limit() -> void:
	var m: AssetModelModel = _picker_model()
	m.toggle_view("back", "tripo")
	m.toggle_view("front", "tripo")
	m.toggle_view("left", "tripo")
	expect_eq(m.picked_views, PackedStringArray(["back", "front", "left"]))
	m.toggle_view("front", "tripo")
	expect_eq(m.picked_views, PackedStringArray(["back", "left"]))
	m.max_views = {"tripo": 2}
	expect(not m.toggle_view("front", "tripo"), "a full multi-select refuses another view")
	expect_eq(m.picked_views, PackedStringArray(["back", "left"]))


func test_view_picker_remembered_per_asset() -> void:
	var m: AssetModelModel = _picker_model()
	m.toggle_view("left", "tripo")
	m.toggle_view("back", "tripo")
	expect_eq(m.picked_text(), "left,back")
	var l: Dictionary = _model_listing()
	m.load_asset({"slug": "other"}, l["providers"] as Dictionary)
	expect(m.picked_views.is_empty(), "another asset has its own choice")
	m.load_asset(_model_asset(), l["providers"] as Dictionary, l["selected"] as Dictionary, _reports(), {"tripo": 4})
	expect_eq(m.picked_views, PackedStringArray(["left", "back"]), "back on the asset, its choice returns")
	var fresh: AssetModelModel = AssetModelModel.new()
	fresh.load_asset(_model_asset(), l["providers"] as Dictionary, l["selected"] as Dictionary, _reports(), {"tripo": 4})
	fresh.restore_picks("back,bogus,back,front")
	expect_eq(fresh.picked_views, PackedStringArray(["back", "front"]), "restore drops unknown and repeated views")


func test_view_picker_backend_arguments() -> void:
	var m: AssetModelModel = _picker_model()
	expect_eq(m.to3d_args(PackedStringArray(["tripo"])), PackedStringArray(["to3d", "angler2", "--3d-provider", "tripo"]))
	m.toggle_view("left", "tripo")
	m.toggle_view("front", "tripo")
	expect_eq(m.to3d_args(PackedStringArray(["tripo"])), PackedStringArray(["to3d", "angler2", "--3d-provider", "tripo", "--views", "left,front"]))
	expect_eq(m.to3d_args(PackedStringArray(["tripo", "meshy"])), PackedStringArray(["to3d", "angler2", "--3d-provider", "tripo", "meshy", "--views", "left,front"]), "the bake-off uses the picked views")
	expect_eq(m.to3d_args(PackedStringArray(["tripo", "single"])), PackedStringArray(["to3d", "angler2", "--3d-provider", "tripo", "single", "--views", "left"]), "cut to the smallest limit so the call is not refused")


func test_bake_off_without_picks_uses_provider_defaults() -> void:
	var m: AssetModelModel = _picker_model()
	expect_eq(m.to3d_args(PackedStringArray(["tripo", "single"])), PackedStringArray(["to3d", "angler2", "--3d-provider", "tripo", "single"]))
	m.toggle_view("left", "tripo")
	m.toggle_view("left", "tripo")
	expect_eq(m.to3d_args(PackedStringArray(["tripo", "meshy"])), PackedStringArray(["to3d", "angler2", "--3d-provider", "tripo", "meshy"]), "unpicking everything returns to defaults")


func test_model_export_after_passing_gates() -> void:
	var asset: Dictionary = _model_asset().duplicate(true)
	var chk: Dictionary = (asset["checks"] as Array)[0]
	chk["ok"] = true
	chk["failed"] = []
	var m: AssetModelModel = AssetModelModel.new()
	m.load_asset(asset, {}, {}, _reports())
	expect_eq(m.gate_summary("c1"), "all gates pass")
	expect_eq(m.export_args("c1"), PackedStringArray(["export", "angler2", "--source", "c1"]))


func test_preview_follows_model_state() -> void:
	var m: AssetModelModel = AssetModelModel.new()
	var pv: AssetModelPreview = AssetModelPreview.new()
	pv.state = m
	runner.add_child(pv)
	var box: MeshInstance3D = MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	var root: Node3D = Node3D.new()
	root.add_child(box)
	pv.show_node(root, "box")
	expect(pv.has_model())
	m.toggle_light()
	m.toggle_wireframe()
	m.angle_deg = 40.0
	pv.apply_state()
	expect_eq(pv._light.light_color, m.light_color())
	expect_eq(pv._viewport.debug_draw, Viewport.DEBUG_DRAW_WIREFRAME)
	expect_near(pv._pivot.rotation_degrees.y, 40.0, 0.001)
	expect(pv._viewport.own_world_3d, "the preview has its own world, so game lighting cannot leak in")
	pv.queue_free()


func test_panel_shows_turnaround_and_model_tabs() -> void:
	var panel: AssetStudioPanel = AssetStudioPanel.new()
	panel.set_meta("fixture", true)
	runner.add_child(panel)
	panel.show_listing(_model_listing())
	expect_eq(panel.turnaround.present_count(), 3)
	expect_eq(panel._turn_views.get_child_count(), 9, "3x3 cross grid")
	expect(panel._turn_views.find_child("View_top", true, false) != null)
	expect_eq(panel.model.runs.size(), 3)
	expect(panel._brief_edit.text.contains("size_m: 2.5"))
	expect(panel._brief_save_btn.disabled)
	panel._brief_edit.text = "new brief"
	panel._on_brief_changed()
	expect(not panel._brief_save_btn.disabled)
	expect(panel._gate_text.get_parsed_text().contains("FAIL"))
	expect_eq(panel._tabs.get_tab_count(), 3)
	panel.queue_free()


func test_project_path_joins_posix_manifest_path() -> void:
	expect(AssetBackendResult.project_path("C:/games/silent_water", "assets/models/a/concept/v1.png") == "C:/games/silent_water/assets/models/a/concept/v1.png")
	expect(AssetBackendResult.project_path("/home/u/sw/", "assets/models/a/brief.md") == "/home/u/sw/assets/models/a/brief.md")
	expect(AssetBackendResult.project_path("C:/sw", "assets\\models\\a.glb") == "C:/sw/assets/models/a.glb")


func test_new_asset_slug_validation() -> void:
	var m: AssetNewAssetModel = AssetNewAssetModel.new()
	m.load_existing(PackedStringArray(["angler"]))
	expect(m.slug_error() != "", "empty slug rejected")
	for bad: String in ["Angler", "my-asset", "a b", "é"]:
		m.slug = bad
		expect(m.slug_error() != "", "format rejects '%s'" % bad)
	m.slug = "angler"
	expect(m.slug_error().contains("already exists"), "duplicate rejected")
	m.slug = "reef_fish2"
	expect_eq(m.slug_error(), "")


func test_new_asset_builds_backend_call() -> void:
	var m: AssetNewAssetModel = AssetNewAssetModel.new()
	m.slug = "reef_fish"
	m.asset_class = "creature"
	expect(m.new_args().is_empty(), "no description, no call")
	m.description = "  A small reef fish.\nStriped.  "
	expect_eq(m.new_args(), PackedStringArray(["new", "reef_fish", "--class", "creature", "--description", "A small reef fish.\nStriped."]))
	m.issue_text = "#42"
	expect_eq(m.new_args(), PackedStringArray(["new", "reef_fish", "--class", "creature", "--issue", "42", "--description", "A small reef fish.\nStriped."]))
	m.issue_text = "abc"
	expect(m.new_args().is_empty(), "bad issue rejected")


func test_generate_more_needs_description() -> void:
	var l: Dictionary = _listing()
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset((l["assets"] as Array)[1] as Dictionary)
	expect(not c.can_generate_more(), "bulkhead has no description")
	expect(c.generate_hint() != "", "hint shown")
	expect(not c.can_generate_more("   "), "blank edit still disabled")
	expect(c.can_generate_more("A hatch."), "enabled with a description")
	expect_eq(c.generate_hint("A hatch."), "")
	c.load_asset((l["assets"] as Array)[0] as Dictionary)
	expect(c.can_generate_more(), "angler has a description")


func test_describe_args() -> void:
	var l: Dictionary = _listing()
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset((l["assets"] as Array)[0] as Dictionary)
	expect_eq(c.describe_args(" Bigger lure. "), PackedStringArray(["describe", "angler", "Bigger lure."]))
	expect(c.describe_args("  ").is_empty(), "blank description builds no command")


# --- cost UI (M10.20) ------------------------------------------------------------------------

func test_queue_exposes_per_asset_cost_totals() -> void:
	var q: AssetQueueModel = AssetQueueModel.new()
	q.load_assets(_listing()["assets"])
	var a: Dictionary = q.find("angler")
	# 0.12 reported + 0.08 and 0.40 estimated; the subscription entry and the unknown one add nothing.
	expect_eq(snappedf(float(a["cost_usd"]), 0.001), 0.6)
	expect_eq(a["cost_text"], "~$0.60")
	expect(bool(a["over_budget"]), "0.60 is over the 0.50 budget")
	var b: Dictionary = q.find("bulkhead")
	expect_eq(b["cost_text"], "$0.35")
	expect(not bool(b["over_budget"]))
	expect_eq(q.find("coral")["cost_text"], "$0.00")


func test_cost_panel_groups_by_stage_and_provider_and_marks_estimates() -> void:
	var m: AssetCostModel = AssetCostModel.new()
	m.load_asset(_listing()["assets"][0])
	expect_eq(m.total_text(), "~$0.60")
	expect_eq(m.unknown_count, 1)
	var stages: Dictionary = {}
	for r: Dictionary in m.by_stage:
		stages[r["name"]] = r
	expect_eq((stages["concept"] as Dictionary)["usd"], 0.12)
	expect(not bool((stages["concept"] as Dictionary)["estimated"]), "a reported figure is not marked")
	expect(bool((stages["refine"] as Dictionary)["estimated"]))
	expect_eq((stages["to3d"] as Dictionary)["unknown"], 1)
	var providers: Dictionary = {}
	for r: Dictionary in m.by_provider:
		providers[r["name"]] = r
	expect(not providers.has("claude-cli"), "subscription calls are not spend")
	expect_eq((providers["tripo"] as Dictionary)["count"], 1)
	var text: String = "\n".join(m.panel_lines())
	expect(text.contains("refine  ~$0.08"), "estimated figures carry a ~")
	expect(text.contains("concept  $0.12"))
	expect(text.contains("could not be priced"))
	expect(m.warning().contains("over its $0.50 budget"))


func test_cost_panel_with_no_calls() -> void:
	var m: AssetCostModel = AssetCostModel.new()
	m.load_asset(_listing()["assets"][2])
	expect(not m.over_budget())
	expect_eq(m.warning(), "")
	expect_eq(m.panel_lines()[0], "No paid calls recorded yet.")


func test_estimate_args_and_text_from_stubbed_backend_result() -> void:
	var a: PackedStringArray = AssetCostModel.estimate_args(PackedStringArray(["concept", "angler", "--n", "3"]))
	expect_eq(a[a.size() - 1], "--estimate")
	expect(AssetCostModel.estimate_args(PackedStringArray()).is_empty(), "no action, no estimate")
	var paid: Dictionary = {"estimate": {"usd": 0.36, "calls": [{"basis": "estimated", "usd": 0.36}], "unknown": []}}
	expect_eq(AssetCostModel.estimate_text(paid), "~$0.36")
	var mock: Dictionary = {"estimate": {"usd": 0.0, "calls": [{"basis": "mock"}], "unknown": []}}
	expect_eq(AssetCostModel.estimate_text(mock), "free")
	var mixed: Dictionary = {"estimate": {"usd": 0.4, "calls": [{"basis": "estimated"}, {"basis": "unknown"}], "unknown": [{"basis": "unknown"}]}}
	expect_eq(AssetCostModel.estimate_text(mixed), "~$0.40 + unknown")
	var none: Dictionary = {"estimate": {"usd": 0.0, "calls": [{"basis": "unknown"}], "unknown": [{"basis": "unknown"}]}}
	expect_eq(AssetCostModel.estimate_text(none), "cost unknown")
	var m: AssetCostModel = AssetCostModel.new()
	m.set_estimate("more", paid)
	expect_eq(m.label("more", "Generate more"), "Generate more (~$0.36)")
	expect_eq(m.label("send", "Send to provider"), "Send to provider")


func test_panel_buttons_show_stubbed_estimates() -> void:
	var panel: AssetStudioPanel = AssetStudioPanel.new()
	panel.set_meta("fixture", true)
	runner.add_child(panel)
	panel.show_listing(_listing())
	var cmds: Dictionary = panel.estimate_commands()
	expect(not (cmds["more"] as PackedStringArray).is_empty())
	expect_eq((cmds["more"] as PackedStringArray)[0], "concept")
	panel.cost.set_estimate("more", {"estimate": {"usd": 0.36, "calls": [{"basis": "estimated"}], "unknown": []}})
	panel.cost.set_estimate("bakeoff", {"estimate": {"usd": 0.75, "calls": [{"basis": "estimated"}], "unknown": []}})
	panel._refresh_est_labels()
	expect_eq(panel._more_btn.text, "Generate more (~$0.36)")
	var found: bool = false
	for e: Variant in panel._est_buttons["bakeoff"]:
		found = found or (e["button"] as Button).text == "Bake-off (all) (~$0.75)"
	expect(found, "the bake-off button shows its estimate")
	expect(panel._cost_text.text.contains("refine"), "cost panel is filled for the selected asset")
	panel.queue_free()


# --- queue tree and folders (M10.22) ---------------------------------------------------------

func _tree_queue() -> AssetQueueModel:
	var l: Dictionary = JSON.parse_string(_fixture("list_tree.json")) as Dictionary
	var q: AssetQueueModel = AssetQueueModel.new()
	q.load_assets(l["assets"], l["folders"])
	return q


func test_queue_tree_from_nested_folders_keeps_empty_ones() -> void:
	var q: AssetQueueModel = _tree_queue()
	expect_eq(q.folder_paths(), PackedStringArray(["organic", "organic/fauna", "organic/fauna/apex", "organic/flora", "props", "props/empty_shelf"]))
	expect_eq((q.find_folder("organic/fauna/apex")["assets"] as Array).size(), 1)
	expect_eq((q.find_folder("organic/flora")["assets"] as Array).size(), 0, "an empty folder is kept")
	expect_eq((q.find_folder("organic")["folders"] as Array).size(), 2)
	expect_eq((q.root["assets"] as Array).size(), 1, "coral sits at the root")
	expect_eq(q.find("eel")["folder"], "organic/fauna")
	expect(q.find_folder("nope").is_empty())


func test_queue_rows_without_folders_stay_flat() -> void:
	var q: AssetQueueModel = AssetQueueModel.new()
	q.load_assets(_listing()["assets"])
	expect_eq(q.folder_paths().size(), 0)
	expect_eq((q.root["assets"] as Array).size(), 3)
	expect(AssetQueueModel.tooltip(q.find("angler")).contains("#12"), "details live in the tooltip")


func test_drop_validation() -> void:
	var q: AssetQueueModel = _tree_queue()
	var apex: Dictionary = {"kind": "folder", "path": "organic/fauna/apex"}
	var fauna: Dictionary = {"kind": "folder", "path": "organic/fauna"}
	var props: Dictionary = {"kind": "folder", "path": "props"}
	expect(not q.can_drop(fauna, fauna), "a folder into itself")
	expect(not q.can_drop(fauna, apex), "a folder into its descendant")
	expect(q.can_drop(apex, props), "a folder into an unrelated folder")
	expect(q.can_drop(apex, {"kind": "folder", "path": ""}), "a folder to the root")
	expect(not q.can_drop(apex, fauna), "already there")
	expect(not q.can_drop({"kind": "asset", "slug": "eel"}, {"kind": "asset", "slug": "angler"}), "an asset onto an asset")
	expect(q.can_drop({"kind": "asset", "slug": "eel"}, props))
	expect(not q.can_drop({"kind": "asset", "slug": "eel"}, fauna), "an asset onto its own folder")
	expect(not q.can_drop({"kind": "asset", "slug": "ghost"}, props))
	expect_eq(q.drop_args({"kind": "asset", "slug": "eel"}, props), PackedStringArray(["move", "eel", "--to", "props"]))
	expect_eq(q.drop_args(apex, props), PackedStringArray(["folder", "move", "organic/fauna/apex", "--to", "props"]))
	expect(q.drop_args(fauna, apex).is_empty())


func test_new_asset_folder_resolution() -> void:
	var q: AssetQueueModel = _tree_queue()
	expect_eq(q.new_asset_folder({"kind": "folder", "path": "props"}), "props")
	expect_eq(q.new_asset_folder({"kind": "asset", "slug": "eel"}), "organic/fauna")
	expect_eq(q.new_asset_folder({}), "")
	expect_eq(q.new_asset_folder({"kind": "asset", "slug": "coral"}), "")
	var m: AssetNewAssetModel = AssetNewAssetModel.new()
	m.slug = "kelp"
	m.description = "Tall kelp."
	m.folder = "organic/flora"
	expect_eq(m.new_args(), PackedStringArray(["new", "kelp", "--class", "creature", "--folder", "organic/flora", "--description", "Tall kelp."]))


func test_folder_command_args() -> void:
	expect_eq(AssetQueueModel.create_folder_args("props", "shelf"), PackedStringArray(["folder", "create", "props/shelf"]))
	expect_eq(AssetQueueModel.create_folder_args("", "props"), PackedStringArray(["folder", "create", "props"]))
	expect(AssetQueueModel.create_folder_args("", "a/b").is_empty())
	expect_eq(AssetQueueModel.rename_args("props/shelf", "rack"), PackedStringArray(["folder", "rename", "props/shelf", "rack"]))
	expect(AssetQueueModel.rename_args("", "x").is_empty(), "the root cannot be renamed")


func test_latest_stderr_line_reaches_the_status_bar() -> void:
	if OS.get_name() == "Windows":
		return
	var panel: AssetStudioPanel = AssetStudioPanel.new()
	panel.set_meta("fixture", true)
	runner.add_child(panel)
	# A stub backend: two progress lines on stderr, one JSON object on stdout.
	panel.runner.executable = "sh"
	panel.runner.base_args = PackedStringArray(["-c", "echo 'writing prompts (claude-cli)...' >&2; echo 'image 2/3 (google)...' >&2; sleep 0.2; echo '{\"ok\": true}'", "stub"])
	var lines: Array[String] = []
	panel.runner.progress.connect(func(l: String) -> void: lines.append(l))
	var done: Array[bool] = []
	panel.runner.finished.connect(func(_a: PackedStringArray, _r: AssetBackendResult) -> void: done.append(true))
	expect(panel.runner.run(PackedStringArray(["concept"])))
	var t0: int = Time.get_ticks_msec()
	while done.is_empty() and Time.get_ticks_msec() - t0 < 10000:
		await runner.get_tree().process_frame
	expect_eq(lines, ["writing prompts (claude-cli)...", "image 2/3 (google)..."] as Array[String])
	panel._on_progress(lines[0])
	expect_eq(panel._status.text, "writing prompts (claude-cli)...")
	panel.queue_free()


func test_panel_shows_folder_tree() -> void:
	var panel: AssetStudioPanel = AssetStudioPanel.new()
	panel.set_meta("fixture", true)
	runner.add_child(panel)
	panel.show_listing(JSON.parse_string(_fixture("list_tree.json")) as Dictionary)
	var top: TreeItem = panel._tree.get_root().get_first_child()
	expect_eq(top.get_text(0), "assets/models")
	expect_eq(top.get_child_count(), 3, "organic, props and coral")
	expect_eq(panel._tree.columns, 2, "name and stage only")
	panel.queue_free()


# --- remembered provider and writer choices (M10.24) -----------------------------------------

func _choice_panel() -> AssetStudioPanel:
	var panel: AssetStudioPanel = AssetStudioPanel.new()
	panel.set_meta("fixture", true)
	runner.add_child(panel)
	panel.choice.keys_set = PackedStringArray(["OPENAI_API_KEY"])
	panel.show_listing(_listing())
	return panel


func test_choice_remembered_value_survives_refresh_and_asset_switch() -> void:
	var panel: AssetStudioPanel = _choice_panel()
	expect_eq(panel._picked(panel._provider_pick), "mock")
	for i: int in panel._provider_pick.item_count:
		if str(panel._provider_pick.get_item_metadata(i)) == "openai":
			panel._provider_pick.select(i)
	panel._remember("concept_image", panel._provider_pick)
	panel.show_listing(_listing())
	expect_eq(panel._picked(panel._provider_pick), "openai", "survives a refresh")
	panel._selected_slug = panel.queue.rows[1]["slug"]
	panel.show_listing(_listing())
	expect_eq(panel._picked(panel._provider_pick), "openai", "survives an asset switch")
	expect_eq(panel._picked(panel._turn_provider), "mock", "dropdowns are remembered separately")
	panel.queue_free()


func test_choice_stale_remembered_value_falls_back() -> void:
	var c: AssetProviderChoice = AssetProviderChoice.new()
	c.remembered["concept_image"] = "gone"
	expect_eq(c.resolve("concept_image", PackedStringArray(["mock", "fal"]), "fal"), "fal")
	expect_eq(c.resolve("other", PackedStringArray(["mock", "fal"]), "mock"), "mock")
	c.remembered["concept_image"] = "mock"
	expect_eq(c.resolve("concept_image", PackedStringArray(["mock", "fal"]), "fal"), "mock")


func test_choice_fallback_order_follows_effective_selection() -> void:
	# `asset list` already folds providers.local.yaml over providers.yaml into `selected`.
	var c: AssetProviderChoice = AssetProviderChoice.new()
	var opts: PackedStringArray = PackedStringArray(["fal", "mock"])
	expect_eq(c.resolve("d", opts, "fal"), "fal", "local selection is the effective one")
	expect_eq(c.resolve("d", opts, "mock"), "mock", "else the committed default")
	c.remembered["d"] = "fal"
	expect_eq(c.resolve("d", opts, "mock"), "fal", "remembered wins over both")
	expect_eq(c.resolve("d", opts, "absent"), "fal")
	c.remembered.clear()
	expect_eq(c.resolve("d", opts, "absent"), "", "nothing configured selects nothing")


func test_choice_mock_label_needs_a_keyed_real_provider() -> void:
	var c: AssetProviderChoice = AssetProviderChoice.new()
	var opts: PackedStringArray = PackedStringArray(["fal", "mock", "openai"])
	expect_eq(c.label("mock", opts, "mock"), "mock", "no key set: plain mock")
	c.keys_set = PackedStringArray(["OPENAI_API_KEY"])
	expect_eq(c.label("mock", opts, "mock"), AssetProviderChoice.MOCK_LABEL)
	expect_eq(c.label("mock", PackedStringArray(["mock", "fal"]), "mock"), "mock", "keyed provider not of this kind")
	expect_eq(c.label("mock", opts, "openai"), "mock", "only when mock is the effective choice")
	expect_eq(c.label("openai", opts, "mock"), "openai")


func test_choice_keys_from_env_text() -> void:
	var k: PackedStringArray = AssetProviderChoice.keys_from("# c\nFAL_KEY=abc\nexport TRIPO_API_KEY=\"x\"\nMESHY_API_KEY=\n")
	expect(k.has("FAL_KEY") and k.has("TRIPO_API_KEY"), "set keys found")
	expect(not k.has("MESHY_API_KEY"), "empty value is not set")


func test_choice_panel_labels_mock_and_sends_real_name() -> void:
	var panel: AssetStudioPanel = _choice_panel()
	expect_eq(panel._provider_pick.get_item_text(panel._provider_pick.selected), AssetProviderChoice.MOCK_LABEL)
	expect_eq(panel._picked_provider(), "mock", "commands get the provider name, not the label")
	panel.queue_free()


func test_queue_menu_items() -> void:
	var asset: Array[Dictionary] = AssetQueueModel.menu_items("asset", false, false)
	expect_eq(asset.map(func(e: Dictionary) -> String: return e["id"]), ["rename", "delete"])
	expect(not asset[0]["disabled"] and not asset[1]["disabled"])
	var folder: Array[Dictionary] = AssetQueueModel.menu_items("folder", false, false)
	expect_eq(folder.map(func(e: Dictionary) -> String: return e["id"]), ["new_here", "new_folder", "rename_folder", "delete"])
	for e: Dictionary in AssetQueueModel.menu_items("asset", false, true) + AssetQueueModel.menu_items("folder", false, true):
		expect(e["disabled"], "%s disabled while busy" % e["id"])
	for e: Dictionary in AssetQueueModel.menu_items("folder", true, false):
		expect_eq(e["disabled"], e["id"] in ["rename_folder", "delete"], "root: %s" % e["id"])


func test_rename_dialog_model() -> void:
	var m: AssetRenameModel = AssetRenameModel.new()
	m.open("eel", PackedStringArray(["eel", "angler"]))
	expect(not m.is_valid(), "unchanged slug")
	m.new_slug = "Bad Name"
	expect(m.error() != "")
	m.new_slug = "angler"
	expect(m.error().contains("already exists"))
	expect(m.rename_args().is_empty())
	m.new_slug = "moray"
	expect_eq(m.error(), "")
	expect_eq(m.rename_args(), PackedStringArray(["rename", "eel", "moray"]))


func test_delete_dialog_summary() -> void:
	var asset: Dictionary = {"slug": "eel", "class": "creature", "stage": "locked",
		"lineage": [{"kind": "concept"}, {"kind": "concept"}, {"kind": "turnaround"}, {"kind": "mesh"}],
		"exports": [{"files": ["a/eel.glb", "a/eel.tscn"]}]}
	var text: String = AssetQueueModel.delete_summary(asset, PackedStringArray(["a/eel.glb"]))
	expect(text.contains("'eel'"))
	expect(text.contains("Class: creature, stage: locked"))
	expect(text.contains("Variants: 2, turnaround views: 1, meshes: 1"))
	expect(text.contains("Exported files: a/eel.glb"))
	expect(AssetQueueModel.delete_summary(asset, PackedStringArray()).contains("No exported files"))
	expect_eq(AssetQueueModel.exported_files(asset), PackedStringArray(["a/eel.glb", "a/eel.tscn"]))
	expect_eq(AssetQueueModel.delete_args("eel"), PackedStringArray(["delete", "eel"]))
	expect_eq(AssetQueueModel.folder_delete_args("props"), PackedStringArray(["folder", "delete", "props"]))
	expect(AssetQueueModel.folder_delete_args("").is_empty())
	var q: AssetQueueModel = _tree_queue()
	expect(q.delete_folder_summary("props/empty_shelf").begins_with("Delete empty folder"))
	expect(q.delete_folder_summary("organic").contains("eel"))


func test_reference_list_builds_backend_args() -> void:
	var c: AssetConceptModel = AssetConceptModel.new()
	c.slug = "angler"
	expect_eq(c.reference_args(), PackedStringArray())
	expect(c.add_reference("/home/me/sketch.PNG"))
	expect(c.add_reference("/home/me/photo.webp"))
	expect(not c.add_reference("/home/me/sketch.PNG"), "a duplicate is ignored")
	expect(not c.add_reference("/home/me/notes.txt"), "only PNG, JPEG and WebP")
	expect_eq(c.references.size(), 2)
	expect_eq(c.generate_more_args(3, "fal"), PackedStringArray([
		"concept", "angler", "--n", "3", "--image-provider", "fal", "--presentation", "subject",
		"--reference", "/home/me/sketch.PNG", "--reference", "/home/me/photo.webp", "--mode", "paint-over"]))
	c.set_reference_mode("inspire")
	c.set_reference_mode("bogus")
	expect_eq(c.reference_mode, "inspire")
	c.remove_reference(0)
	expect_eq(c.generate_more_args(2), PackedStringArray([
		"concept", "angler", "--n", "2", "--presentation", "subject", "--reference", "/home/me/photo.webp", "--mode", "inspire"]))
	expect_eq(c.generate_more_args(2, "", "", false), PackedStringArray(["concept", "angler", "--n", "2", "--presentation", "subject"]))
	expect_eq(c.generate_more_args(2, "", "", false, false), PackedStringArray(["concept", "angler", "--n", "2"]))
	c.remove_reference(5)
	c.remove_reference(0)
	expect_eq(c.generate_more_args(1), PackedStringArray(["concept", "angler", "--n", "1", "--presentation", "subject"]))
	c.references = PackedStringArray(["/a.png"])
	expect(c.refine_args("v1", "more teeth").has("--reference") == false, "a refine keeps its own reference")


func test_variant_cards_expose_their_reference() -> void:
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset({"slug": "angler", "lineage": [
		{"id": "v1", "kind": "concept", "path": "a/v1.png", "provider": "mock", "model": "m", "prompt": "p", "parent": null,
			"reference": {"name": "sketch.png", "sha256": "0123456789abcdef0123"}, "mode": "paint-over"},
		{"id": "v2", "kind": "concept", "path": "a/v2.png", "provider": "mock", "model": "m", "prompt": "p", "parent": null},
	]})
	var r: Dictionary = c.variant("v1")["reference"]
	expect_eq(r["name"], "sketch.png")
	expect_eq(r["path"], ".asset_work/angler/references/0123456789ab.png")
	expect_eq(c.variant("v1")["mode"], "paint-over")
	expect(c.variant("v2")["reference"].is_empty(), "no reference when the manifest has none")
	expect_eq(c.lineage_of("v1")[0]["reference"]["name"], "sketch.png")


func test_presentation_toggle_builds_backend_args_and_presets_from_class() -> void:
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset({"slug": "cab", "class": "interior", "concept_presentation": "scene"})
	expect_eq(c.presentation, "scene")
	expect_eq(c.generate_more_args(2), PackedStringArray(["concept", "cab", "--n", "2", "--presentation", "scene"]))
	c.set_presentation("subject")
	c.set_presentation("bogus")
	expect_eq(c.presentation, "subject")
	expect_eq(c.generate_more_args(1), PackedStringArray(["concept", "cab", "--n", "1", "--presentation", "subject"]))
	expect(not c.refine_args("v1", "more light").has("--presentation"), "a refine keeps its variant's presentation")
	c.load_asset({"slug": "cab", "class": "interior", "concept_presentation": "scene"})
	expect_eq(c.presentation, "scene", "loading re-presets from the class default")
	c.load_asset({"slug": "eel", "class": "creature"})
	expect_eq(c.presentation, "subject", "no class default means subject")


func test_interior_hides_build_tabs_and_architecture_does_not() -> void:
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset({"slug": "cab", "class": "interior"})
	expect(c.hides_build_tabs())
	c.load_asset({"slug": "wall", "class": "architecture"})
	expect(not c.hides_build_tabs(), "architecture is unchanged")
	c.load_asset({"slug": "eel", "class": "creature"})
	expect(not c.hides_build_tabs())
