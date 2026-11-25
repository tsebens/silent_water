extends TestCase
## layout.json is generated from program.yaml by plan.py; the committed copy must be current.

const PLAN: String = "res://assets/models/vehicles/sub_interior/plan.py"


func test_committed_layout_matches_program() -> void:
	var tmp: String = OS.get_temp_dir().path_join("silent_water_layout_check_%d" % OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(tmp)
	var out_json: String = tmp.path_join("layout.json")
	var output: Array = []
	var args: PackedStringArray = [
		"run", "--project", ProjectSettings.globalize_path("res://tools/asset_pipeline"),
		"python", ProjectSettings.globalize_path(PLAN), tmp, out_json,
	]
	var rc: int = OS.execute("uv", args, output, true)
	expect_eq(rc, 0, "plan.py failed or uv is missing: %s" % str(output))
	if rc != 0:
		return
	var fresh: String = FileAccess.get_file_as_string(out_json)
	var committed: String = FileAccess.get_file_as_string("res://assets/models/vehicles/sub_interior/layout.json")
	expect(not fresh.is_empty(), "plan.py wrote no layout")
	expect(fresh == committed, "layout.json is stale: run plan.py and commit the result")
