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
	expect_eq(c.generate_more_args(3, "fal"), PackedStringArray(["concept", "angler", "--n", "3", "--image-provider", "fal"]))


func test_prompt_writer_is_passed_on_generate_refine_and_brief() -> void:
	var l: Dictionary = _listing()
	var c: AssetConceptModel = AssetConceptModel.new()
	c.load_asset((l["assets"] as Array)[0] as Dictionary, {"prompt_writer": ["mock", "claude-cli"]}, {"prompt_writer": "claude-cli"})
	expect_eq(c.prompt_writers.size(), 2)
	expect_eq(c.default_writer, "claude-cli")
	expect_eq(c.generate_more_args(3, "", "claude-cli"), PackedStringArray(["concept", "angler", "--n", "3", "--prompt-writer", "claude-cli"]))
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
	var frames: int = 0
	while seen.is_empty() and frames < 600:
		await runner.get_tree().process_frame
		frames += 1
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
	expect_eq(t.views.size(), 4)
	expect_eq(t.views[0]["view"], "front")
	expect_eq(t.views[3]["view"], "right")
	expect_eq(t.view("front")["id"], "t2_front", "the newest set wins")
	expect_eq(t.view("front")["provider"], "openai")
	expect(not t.view("right")["present"], "t2 has no right view")
	expect_eq(t.view("right")["caption"], "right · missing")
	expect_eq(t.present_count(), 3)


func test_turnaround_actions() -> void:
	var t: AssetTurnaroundModel = AssetTurnaroundModel.new()
	t.load_asset(_model_asset(), _fixture("brief.md"))
	expect_eq(t.generate_args("fal"), PackedStringArray(["turnaround", "angler2", "--image-provider", "fal"]))
	expect_eq(t.regenerate_args("back", "openai"), PackedStringArray(["turnaround", "angler2", "--view", "back", "--image-provider", "openai"]))
	expect_eq(t.regenerate_args("left"), PackedStringArray(["turnaround", "angler2", "--view", "left"]))
	expect(t.regenerate_args("top").is_empty(), "unknown view builds no command")
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
