extends TestCase
## The world-shot tool's argument parsing and named cameras (tests/world_shot.gd, tools/shot.sh).


func _args(list: Array[String]) -> Dictionary:
	return WorldShot.parse_args(PackedStringArray(list))


func test_defaults() -> void:
	var a: Dictionary = _args(["pilot_view"])
	expect_eq(a["errors"].size(), 0)
	expect_eq(a["camera"], "pilot_view")
	expect_eq(a["light"], "day")
	expect_eq(a["size"], Vector2i(1280, 720))
	expect_eq(a["depths"], [0.0])
	expect(not bool(a["sheet"]))


func test_options_in_both_forms() -> void:
	var a: Dictionary = _args(["midships_forward", "--depth", "100", "--light=night", "--size", "640x360", "--out", "x.png", "--frames=5"])
	expect_eq(a["errors"].size(), 0)
	expect_eq(a["depths"], [100.0])
	expect_eq(a["light"], "night")
	expect_eq(a["size"], Vector2i(640, 360))
	expect_eq(a["out"], "x.png")
	expect_eq(a["frames"], 5)


func test_sheet_lists_depths() -> void:
	var a: Dictionary = _args(["outside_bow", "--sheet", "0,20,100"])
	expect_eq(a["errors"].size(), 0)
	expect(bool(a["sheet"]))
	expect_eq(a["depths"], [0.0, 20.0, 100.0])


func test_bad_arguments_are_reported() -> void:
	expect(_args([])["errors"].size() > 0, "camera required")
	expect(_args(["nope"])["errors"].size() > 0, "unknown camera")
	expect(_args(["pilot_view", "--depth", "deep"])["errors"].size() > 0, "bad depth")
	expect(_args(["pilot_view", "--light", "dusk"])["errors"].size() > 0, "bad light")
	expect(_args(["pilot_view", "--size", "big"])["errors"].size() > 0, "bad size")
	expect(_args(["pilot_view", "--sheet", "0,x"])["errors"].size() > 0, "bad sheet")
	expect(_args(["pilot_view", "--wat"])["errors"].size() > 0, "unknown option")


func test_program_cameras_resolve_to_the_program_positions() -> void:
	var mf: Dictionary = WorldShot.camera_spec("midships_forward")
	expect_eq(mf["pos"], SubLayout.to_interior(Vector3(0.25, 0.70, 1.05)))
	expect_eq(mf["look"], SubLayout.to_interior(Vector3(0.0, 0.05, -4.6)))
	var pv: Dictionary = WorldShot.camera_spec("pilot_view")
	expect_eq(pv["pos"], SubLayout.to_interior(Vector3(0.0, 0.0, -3.9)))


func test_pilot_eye_sits_at_the_helm_looking_level() -> void:
	var pe: Dictionary = WorldShot.camera_spec("pilot_eye")
	var pv: Dictionary = WorldShot.camera_spec("pilot_view")
	expect_eq(pe["pos"], pv["pos"])
	expect_near(((pe["look"] as Vector3) - (pe["pos"] as Vector3)).y, 0.0)
	expect(((pe["look"] as Vector3) - (pe["pos"] as Vector3)).z < 0.0, "looks toward the bow")


func test_outside_cameras_are_outside_the_hull() -> void:
	var hull: Vector3 = SubLayout.hull_size()
	for d: String in ["bow", "stern", "port", "starboard", "top", "bottom"]:
		var s: Dictionary = WorldShot.camera_spec("outside_" + d)
		expect(not s.is_empty(), "outside_%s resolves" % d)
		var p: Vector3 = (s["pos"] as Vector3) - Vector3(0, SubLayout.hull_centre_y(), 0)
		expect(absf(p.x) > hull.x / 2.0 or absf(p.y) > hull.y / 2.0 or absf(p.z) > hull.z / 2.0, "outside_%s is clear of the hull" % d)
	expect(WorldShot.camera_spec("outside_sideways").is_empty(), "unknown direction")


func test_every_listed_camera_resolves() -> void:
	for n: String in WorldShot.camera_names():
		expect(not WorldShot.camera_spec(n).is_empty(), n)
