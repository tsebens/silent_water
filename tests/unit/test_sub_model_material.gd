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
	for part_name: String in ["hull_shell", "deck_midships", "bulkhead"]:
		var mi: MeshInstance3D = m.part(part_name)
		expect(mi != null, "%s exists" % part_name)
		if mi != null:
			expect(_is_worn_metal(mi), "%s uses worn metal" % part_name)
	var trim: MeshInstance3D = m.part("hatch_frame")
	expect(trim != null and _is_worn_metal(trim), "hatch_frame uses worn metal")
	m.free()


func test_glass_keeps_its_look() -> void:
	var m: SubModel = _model()
	var dome: MeshInstance3D = m.part("dome_glass")
	expect(dome != null and not _is_worn_metal(dome), "dome is not metal")
	m.free()


func test_every_hull_part_is_indexed_and_has_collision_where_documented() -> void:
	var m: SubModel = _model()
	for part_name: String in ["hull_shell", "dome_glass", "dome_rim", "deck_cockpit", "deck_midships", "deck_bulkhead",
			"deck_engineering", "cockpit_step", "bulkhead", "hatch_frame", "tower", "tower_hatch"]:
		expect(m.part(part_name) != null, "%s exists" % part_name)
	for part_name: String in ["hull_shell", "deck_midships", "bulkhead"]:
		var mi: MeshInstance3D = m.part(part_name)
		expect(mi.get_child_count() == 1 and mi.get_child(0) is StaticBody3D, "%s has imported collision" % part_name)
	m.free()


func test_material_exposes_parameters_with_defaults() -> void:
	var m: SubModel = _model()
	var sm: ShaderMaterial = m.part("hull_shell").material_override as ShaderMaterial
	expect_near(float(sm.get_shader_parameter("wear_amount")), SubModel.METAL_WEAR_AMOUNT, 0.0001, "wear default")
	expect_near(float(sm.get_shader_parameter("scale")), SubModel.METAL_SCALE, 0.0001, "scale default")
	expect(sm.get_shader_parameter("base_tone") is Color, "base tone set")
	m.free()
