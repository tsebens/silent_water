extends TestCase
## The sub interior takes its colours from the palette (docs/palette.md): lights and worn-metal tones follow swatch
## changes, and stealth mode swaps cabin lights to the stealth red.

const INTERIOR: PackedScene = preload("res://src/sub/interior.tscn")


func _swatches() -> Dictionary:
	var pal: Palette = Palette.main()
	return {&"light_cabin": pal.color(&"light_cabin"), &"light_stealth_red": pal.color(&"light_stealth_red"),
		&"infra_metal": pal.color(&"infra_metal"), &"light_work_white": pal.color(&"light_work_white")}


func _restore(saved: Dictionary) -> void:
	for k: StringName in saved:
		Palette.main().set_color(k, saved[k])


func test_lights_follow_the_palette() -> void:
	var saved: Dictionary = _swatches()
	var pal: Palette = Palette.main()
	var interior: Node3D = INTERIOR.instantiate() as Node3D
	runner.add_child(interior)
	var fore: Light3D = interior.get_node("Lights/Fore") as Light3D
	var head: Light3D = interior.get_node("Lights/Headlight") as Light3D
	expect(fore.light_color.is_equal_approx(pal.color(&"light_cabin")), "cabin light starts at light_cabin")
	expect(head.light_color.is_equal_approx(pal.color(&"light_work_white")), "headlight is work white")
	var cabin: Color = Color(0.1, 0.2, 0.3)
	pal.set_color(&"light_cabin", cabin)
	expect(fore.light_color.is_equal_approx(cabin), "cabin light follows light_cabin")
	var red: Color = Color(0.7, 0.1, 0.05)
	pal.set_color(&"light_stealth_red", red)
	var cl: CabinLights = CabinLights.new()
	cl.lights_root = interior.get_node("Lights") as Node3D
	cl.excluded = [head]
	runner.add_child(cl)
	cl.stealth = true
	expect(fore.light_color.is_equal_approx(red), "stealth mode takes light_stealth_red")
	expect(head.light_color.is_equal_approx(pal.color(&"light_work_white")), "headlight ignores stealth")
	pal.set_color(&"light_stealth_red", Color(0.4, 0.05, 0.02))
	expect(fore.light_color.is_equal_approx(Color(0.4, 0.05, 0.02)), "stealth light follows its swatch")
	cl.stealth = false
	expect(fore.light_color.is_equal_approx(cabin), "leaving stealth restores the cabin light")
	cl.free()
	interior.free()
	_restore(saved)


func test_metal_follows_the_palette() -> void:
	var saved: Dictionary = _swatches()
	var m: SubModel = (preload("res://src/sub/sub_model.tscn")).instantiate() as SubModel
	runner.add_child(m)
	var sm: ShaderMaterial = m.part("Shell").material_override as ShaderMaterial
	var c: Color = Color(0.9, 0.5, 0.1)
	Palette.main().set_color(&"infra_metal", c)
	expect((sm.get_shader_parameter("base_tone") as Color).is_equal_approx(c), "hull tone follows infra_metal")
	m.free()
	_restore(saved)


func test_no_colour_literals() -> void:
	for path: String in ["res://src/sub/sub_model.gd"]:
		expect(not FileAccess.get_file_as_string(path).contains("Color("), "%s has no Color( literal" % path)
	expect(not FileAccess.get_file_as_string("res://src/sub/interior.tscn").contains("light_color"), "no literal light colours")
