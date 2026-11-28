extends TestCase
## The review-shot tool's sea light preset and large-scene framing (tests/scene_shot.gd).

var _shot: Node3D


func before_each() -> void:
	_shot = (load("res://tests/scene_shot.gd") as GDScript).new() as Node3D
	_shot.call("_lights")


func after_each() -> void:
	_shot.free()


func _env() -> Environment:
	return (_shot.get("_env") as WorldEnvironment).environment


func _snapshot() -> Dictionary:
	var e: Environment = _env()
	return {
		"fog": e.fog_enabled, "ambient": e.ambient_light_color, "ambient_e": e.ambient_light_energy, "bg": e.background_color,
		"key": (_shot.get("_key") as DirectionalLight3D).light_energy, "keyc": (_shot.get("_key") as DirectionalLight3D).light_color,
		"fill": (_shot.get("_fill") as OmniLight3D).light_energy, "work": (_shot.get("_work") as OmniLight3D).visible,
	}


func test_white_and_red_keep_their_values() -> void:
	_shot.call("_set_light", "white")
	var w: Dictionary = _snapshot()
	expect(not bool(w["fog"]) and not bool(w["work"]))
	expect_eq(w["ambient"], Color(0.55, 0.6, 0.62))
	expect_near(float(w["key"]), 1.1)
	expect_near(float(w["fill"]), 0.6)
	expect_eq(w["keyc"], Color(1.0, 0.97, 0.92))
	_shot.call("_set_light", "red")
	var r: Dictionary = _snapshot()
	expect(not bool(r["fog"]))
	expect_eq(r["ambient"], Color(0.35, 0.05, 0.04))
	expect_near(float(r["key"]), 0.9)
	expect_near(float(r["fill"]), 0.8)


func test_sea_differs_from_white() -> void:
	_shot.call("_set_light", "white")
	var w: Dictionary = _snapshot()
	_shot.call("_set_light", "sea")
	var s: Dictionary = _snapshot()
	expect(bool(s["fog"]) and bool(s["work"]))
	expect(s["ambient"] != w["ambient"])
	expect(s["bg"] != w["bg"])
	expect(float(s["key"]) < float(w["key"]))
	expect(_env().glow_enabled, "neon glows")
	expect_eq(_env().fog_light_color, OceanSurface.fog_color())
	expect_eq(s["ambient"], Palette.main().color(&"env_teal"))
	# About 100 m reach: mostly fogged by then, little fogged at 10 m.
	var d: float = _env().fog_density
	expect(1.0 - exp(-d * 100.0) > 0.75)
	expect(1.0 - exp(-d * 10.0) < 0.25)
	_shot.call("_set_light", "white")
	expect_eq(_snapshot()["ambient"], w["ambient"], "white restored after sea")


func test_sea_reach_scales_fog() -> void:
	_shot.call("_set_light", "sea", 200.0)
	var far: float = _env().fog_density
	_shot.call("_set_light", "sea", 50.0)
	expect(_env().fog_density > far)


func test_large_scene_cameras_contain_it() -> void:
	var scene: Node3D = Node3D.new()
	var mi: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(60, 20, 30)
	mi.mesh = box
	scene.add_child(mi)
	var cams: Array = _shot.call("_auto_cameras", scene)
	var sea: int = 0
	var centre: Vector3 = Vector3.ZERO
	var radius: float = Vector3(60, 20, 30).length() * 0.5
	for c: Dictionary in cams:
		var p: Array = c["pos"]
		var pos: Vector3 = Vector3(p[0], p[1], p[2])
		var dist: float = pos.distance_to(centre)
		if c.has("ortho"):
			expect(float(c["ortho"]) >= radius * 2.0, "ortho covers the scene")
		else:
			expect(dist * sin(deg_to_rad(float(c["fov"]) * 0.5)) >= radius, "%s contains the scene" % c["name"])
		if c.get("light", "") == "sea":
			sea += 1
			expect(1.0 - exp(-1.8 / float(c["reach"]) * dist) < 0.5, "scene is not fogged out")
	expect_eq(sea, 1)
	scene.free()
