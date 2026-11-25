extends TestCase
## The palette and its roles (docs/palette.md): roles name real swatches, a palette change reaches every role and
## every generated asset with no rebuild, and the information band stays reserved.

const ROLES_DIR: String = "res://assets/palette/roles/"
const GENERATED: PackedStringArray = ["res://assets/models/kit", "res://assets/models/furniture", "res://assets/models/stations"]
## Swatches allowed in the band reserved for information (bright, saturated cyan).
const INFORMATION: PackedStringArray = ["light_readout"]


func _roles() -> Array[RoleMaterial]:
	var out: Array[RoleMaterial] = []
	for f: String in DirAccess.get_files_at(ROLES_DIR):
		if f.ends_with(".tres"):
			out.append(load(ROLES_DIR + f) as RoleMaterial)
	return out


## Every GLB a cadkit build script made (a folder with a component.yaml).
func _generated_glbs() -> PackedStringArray:
	var out: PackedStringArray = []
	var stack: PackedStringArray = GENERATED.duplicate()
	while not stack.is_empty():
		var dir: String = stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		for d: String in DirAccess.get_directories_at(dir):
			stack.append(dir + "/" + d)
		if not FileAccess.file_exists(dir + "/component.yaml"):
			continue
		for f: String in DirAccess.get_files_at(dir):
			if f.ends_with(".glb"):
				out.append(dir + "/" + f)
	return out


func _surface_materials(node: Node) -> Array[Material]:
	var out: Array[Material] = []
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var mi: MeshInstance3D = n as MeshInstance3D
		if mi != null and mi.mesh != null:
			for s: int in mi.mesh.get_surface_count():
				out.append(mi.mesh.surface_get_material(s))
		stack.append_array(n.get_children())
	return out


func test_palette_loads_with_paint_and_light() -> void:
	var pal: Palette = Palette.main()
	expect(pal != null, "palette at %s" % Palette.PATH)
	expect(pal.paint.size() > 20 and pal.light.size() > 5, "swatches present")
	for name: StringName in pal.paint:
		expect(not pal.light.has(name), "%s is paint and light at once" % name)


func test_every_role_names_swatches_that_exist() -> void:
	var pal: Palette = Palette.main()
	var roles: Array[RoleMaterial] = _roles()
	expect(roles.size() >= 20, "roles present (%d)" % roles.size())
	for r: RoleMaterial in roles:
		expect(r.swatch != &"" and pal.paint.has(r.swatch), "%s: paint swatch '%s'" % [r.role_name(), r.swatch])
		expect(r.glow == &"" or pal.light.has(r.glow), "%s: light swatch '%s'" % [r.role_name(), r.glow])
		expect(r.stripe == &"" or pal.paint.has(r.stripe), "%s: stripe swatch '%s'" % [r.role_name(), r.stripe])


func test_a_palette_change_reaches_every_role_that_uses_the_swatch() -> void:
	var pal: Palette = Palette.main()
	var button: RoleMaterial = RoleMaterial.lookup("button")
	var original: Color = pal.color(button.swatch)
	pal.set_color(button.swatch, Color(0.1, 0.9, 0.2))
	expect(button.albedo_color.is_equal_approx(Color(0.1, 0.9, 0.2)), "button follows its swatch (%s)" % button.albedo_color)
	pal.set_color(button.swatch, original)
	expect(button.albedo_color.is_equal_approx(original), "and back")


func test_a_glowing_role_emits_its_light_swatch() -> void:
	var ink: RoleMaterial = RoleMaterial.lookup("readout_ink")
	expect(ink.emission_enabled, "readout ink glows")
	expect(ink.emission.is_equal_approx(Palette.main().color(&"light_readout")), "in the readout cyan")
	expect(not RoleMaterial.lookup("trim_black").emission_enabled, "paint does not glow")


func test_the_information_band_is_reserved() -> void:
	var pal: Palette = Palette.main()
	for group: Dictionary in [pal.paint, pal.light]:
		for name: StringName in group:
			if INFORMATION.has(String(name)):
				expect(Palette.in_information_band(group[name]), "%s is in the band" % name)
			else:
				expect(not Palette.in_information_band(group[name]), "%s sits in the information band" % name)


func test_lookup_refuses_names_that_are_not_roles() -> void:
	expect(RoleMaterial.lookup("brass") == null, "no such role")
	expect(RoleMaterial.lookup("") == null, "empty")
	expect(RoleMaterial.lookup("../palette") == null, "not a path")


func test_every_generated_surface_holds_a_shared_role_material() -> void:
	var glbs: PackedStringArray = _generated_glbs()
	expect(glbs.size() >= 10, "generated GLBs found (%d)" % glbs.size())
	for path: String in glbs:
		var scene: Node = (load(path) as PackedScene).instantiate()
		var mats: Array[Material] = _surface_materials(scene)
		expect(not mats.is_empty(), "%s has surfaces" % path)
		for m: Material in mats:
			var r: RoleMaterial = m as RoleMaterial
			expect(r != null and r.resource_path.begins_with(ROLES_DIR), "%s: a surface without a shared role material (%s)" % [path, m])
		scene.free()


func test_one_material_instance_per_role_across_assets() -> void:
	var a: Node = (load("res://assets/models/kit/control_base/control_base_2x2.glb") as PackedScene).instantiate()
	var b: Node = (load("res://assets/models/stations/sonar_console/sonar_console_body.glb") as PackedScene).instantiate()
	var dark: RoleMaterial = RoleMaterial.lookup("interior_dark")
	expect(_surface_materials(a).has(dark) and _surface_materials(b).has(dark), "the base plate and the console inset share one material")
	a.free()
	b.free()
