extends TestCase

const MODEL: PackedScene = preload("res://src/sub/sub_model.tscn")


func _model() -> SubModel:
	var m: SubModel = MODEL.instantiate() as SubModel
	runner.add_child(m)
	return m


func _is_worn_metal(mi: MeshInstance3D) -> bool:
	var sm: ShaderMaterial = mi.material_override as ShaderMaterial
	return sm != null and sm.shader == SubModel.WORN_METAL


func test_interior_parts_use_worn_metal() -> void:
	var m: SubModel = _model()
	for part_name: String in ["Shell", "Deck"]:
		var mi: MeshInstance3D = m.part(part_name)
		expect(mi != null, "%s exists" % part_name)
		if mi != null:
			expect(_is_worn_metal(mi), "%s uses worn metal" % part_name)
	var fitting: MeshInstance3D = m.part("EngineBlock")
	if fitting != null:
		expect(_is_worn_metal(fitting), "EngineBlock uses worn metal")
	m.free()


func test_glass_and_displays_keep_their_look() -> void:
	var m: SubModel = _model()
	var dome: MeshInstance3D = m.part("FrontWindow")
	expect(dome != null and not _is_worn_metal(dome), "dome is not metal")
	for part_name: String in ["Display", "Display2", "Display3"]:
		var mi: MeshInstance3D = m.part(part_name)
		if mi != null:
			expect(not _is_worn_metal(mi), "%s is not metal" % part_name)
	m.free()


func test_material_exposes_parameters_with_defaults() -> void:
	var m: SubModel = _model()
	var sm: ShaderMaterial = m.part("Shell").material_override as ShaderMaterial
	expect_near(float(sm.get_shader_parameter("wear_amount")), SubModel.METAL_WEAR_AMOUNT, 0.0001, "wear default")
	expect_near(float(sm.get_shader_parameter("scale")), SubModel.METAL_SCALE, 0.0001, "scale default")
	expect(sm.get_shader_parameter("base_tone") is Color, "base tone set")
	m.free()
