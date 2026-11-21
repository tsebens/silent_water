extends TestCase
## Underwater treatment when the camera dips below the bilge water.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")


func test_state_follows_camera_height() -> void:
	expect(UnderwaterView.next_state(false, 0.2, 0.5, 0.04), "below surface -> underwater")
	expect(not UnderwaterView.next_state(true, 0.8, 0.5, 0.04), "above surface -> not underwater")
	expect(not UnderwaterView.next_state(false, 0.8, 0.5, 0.04), "above stays out")
	expect(UnderwaterView.next_state(true, 0.2, 0.5, 0.04), "below stays in")


func test_hysteresis_stops_flicker() -> void:
	var state: bool = false
	var toggles: int = 0
	for i: int in 200:
		# Wobble +-1 cm around a 0.5 m surface; the band is 4 cm wide.
		var y: float = 0.5 + 0.01 * sin(float(i))
		var next: bool = UnderwaterView.next_state(state, y, 0.5, 0.04)
		if next != state:
			toggles += 1
		state = next
	expect_eq(toggles, 0, "small oscillation toggles nothing")
	# A real dunk and rise toggles exactly twice.
	state = UnderwaterView.next_state(state, 0.45, 0.5, 0.04)
	expect(state, "dunked")
	state = UnderwaterView.next_state(state, 0.49, 0.5, 0.04)
	expect(state, "still under inside the band")
	state = UnderwaterView.next_state(state, 0.53, 0.5, 0.04)
	expect(not state, "surfaced")


func test_view_tracks_bilge_in_scene() -> void:
	var holder: Node3D = Node3D.new()
	runner.add_child(holder)
	var w: BilgeWater = (load("res://src/sub/bilge_water.tscn") as PackedScene).instantiate() as BilgeWater
	holder.add_child(w)
	w.set_tonnage(4.0)
	var cam: Node3D = Node3D.new()
	holder.add_child(cam)
	var v: UnderwaterView = UnderwaterView.new()
	v.camera_path = ^".."
	cam.add_child(v)
	cam.global_position = Vector3(0, w.global_position.y - 0.3, 0)
	v._process(0.0)
	expect(v.underwater, "head below the surface")
	cam.global_position = Vector3(0, w.global_position.y + 0.5, 0)
	v._process(0.0)
	expect(not v.underwater, "head above the surface")
	w.set_tonnage(0.0)
	cam.global_position = Vector3(0, -1.0, 0)
	v._process(0.0)
	expect(not v.underwater, "dry bilge is never underwater")
	holder.free()


func test_tunables_exported_on_player_scene() -> void:
	var p: Node = PLAYER_SCENE.instantiate()
	var v: UnderwaterView = p.get_node("Head/Camera3D/UnderwaterView") as UnderwaterView
	expect(v != null, "player has an UnderwaterView")
	var names: PackedStringArray = PackedStringArray()
	for prop: Dictionary in v.get_property_list():
		if (int(prop["usage"]) & PROPERTY_USAGE_EDITOR) != 0:
			names.append(str(prop["name"]))
	for n: String in ["tint", "fog_density", "hysteresis_m"]:
		expect(names.has(n), "%s exported" % n)
	p.free()


func test_bilge_surface_is_two_sided_and_shades_underside() -> void:
	var w: BilgeWater = (load("res://src/sub/bilge_water.tscn") as PackedScene).instantiate() as BilgeWater
	var mat: ShaderMaterial = w.material_override as ShaderMaterial
	expect(mat != null, "shader material")
	var code: String = mat.shader.code
	expect(code.contains("cull_disabled"), "cull disabled")
	expect(code.contains("FRONT_FACING"), "back faces are shaded separately")
	expect(mat.shader.get_shader_uniform_list().any(func(u: Dictionary) -> bool: return u["name"] == "underside_color"), "underside colour uniform")
	w.free()
