extends Node
## Headless test entry point:
##   godot --headless --path . res://tests/test_runner.tscn
## 1. Loads every script under res://src to catch parse errors.
## 2. Runs every `test_*.gd` under res://tests/unit.
## Exits with code 1 on any failure.

const SRC_DIR: String = "res://src"
const UNIT_DIR: String = "res://tests/unit"


func _ready() -> void:
	var failures: int = 0
	failures += _check_scripts(SRC_DIR)
	failures += await _run_unit_tests(UNIT_DIR)
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d FAILURE(S)" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check_scripts(dir: String) -> int:
	var failures: int = 0
	for path: String in _find_files(dir, ".gd"):
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			printerr("PARSE FAIL %s" % path)
			failures += 1
	return failures


func _run_unit_tests(dir: String) -> int:
	var failures: int = 0
	var passed: int = 0
	for path: String in _find_files(dir, ".gd"):
		if not path.get_file().begins_with("test_"):
			continue
		var script: GDScript = load(path) as GDScript
		if script == null or not script.can_instantiate():
			printerr("PARSE FAIL %s" % path)
			failures += 1
			continue
		var case: TestCase = script.new() as TestCase
		if case == null:
			printerr("NOT A TestCase %s" % path)
			failures += 1
			continue
		for method: Dictionary in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			case._current = "%s::%s" % [path.get_file(), name]
			var before: int = case._failures.size()
			case.before_each()
			await case.call(name)
			case.after_each()
			if case._failures.size() == before:
				passed += 1
			else:
				for i: int in range(before, case._failures.size()):
					printerr("FAIL " + case._failures[i])
				failures += 1
	print("%d test(s) passed" % passed)
	return failures


func _find_files(dir: String, ext: String) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var d: DirAccess = DirAccess.open(dir)
	if d == null:
		return out
	for sub: String in d.get_directories():
		out.append_array(_find_files(dir.path_join(sub), ext))
	for f: String in d.get_files():
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	out.sort()
	return out
