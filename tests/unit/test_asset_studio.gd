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
