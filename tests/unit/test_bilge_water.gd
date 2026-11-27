extends TestCase

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")


func test_height_matches_bilge_height() -> void:
	var w: BilgeWater = (load("res://src/sub/bilge_water.tscn") as PackedScene).instantiate() as BilgeWater
	runner.add_child(w)
	for t: float in [0.5, 3.0, 4.0, 12.0]:
		w.set_tonnage(t)
		expect_near(w.height_m(), SubPhysicsModel.bilge_height_m(t), 0.0001, "height at %f t" % t)
	w.free()


func test_hidden_at_zero_tonnage() -> void:
	var w: BilgeWater = (load("res://src/sub/bilge_water.tscn") as PackedScene).instantiate() as BilgeWater
	runner.add_child(w)
	w.set_tonnage(3.0)
	expect(w.visible, "visible when wet")
	w.set_tonnage(0.0)
	expect(not w.visible, "hidden when dry")
	w.free()


func test_water_lives_in_still_interior_frame() -> void:
	var game: Game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	var w: BilgeWater = game.get_node("Interior/BilgeWater") as BilgeWater
	expect(w != null, "BilgeWater is a child of Interior")
	var interior: Node = game.get_node("Interior")
	expect(w.get_parent() == interior, "direct child of the interior")
	var world: Node = (game.get_node("SubFrame") as SubFrame).world_root
	expect(not world.is_ancestor_of(w), "not under the moving world root")
	w.set_tonnage(4.0)
	expect_near(w.height_m(), SubPhysicsModel.bilge_height_m(4.0), 0.0001)
	game.free()


func test_water_stays_inside_hull_at_bilge() -> void:
	var w: BilgeWater = (load("res://src/sub/bilge_water.tscn") as PackedScene).instantiate() as BilgeWater
	runner.add_child(w)
	var half: Vector3 = SubLayout.hull_size() / 2.0
	for t: float in [0.5, 3.0, 8.0]:
		w.set_tonnage(t)
		# The plane is the hull's footprint; the shader clips what pokes out. Check the clip's reference
		# (SubLayout.inside_hull) accepts the middle of the water and rejects the hull-corner of the plane.
		expect(SubLayout.inside_hull(0.0, w.position.y, 0.0), "water middle is inside the hull at %f t" % t)
		expect(not SubLayout.inside_hull(half.x, w.position.y, half.z), "plane corner is clipped at %f t" % t)
		expect(w.position.y > SubLayout.hull_bottom_y(), "surface above the hull bottom")
	var mat: ShaderMaterial = w.material_override as ShaderMaterial
	expect_near(float(mat.get_shader_parameter(&"clip_axis_y")), SubLayout.hull_centre_y() - w.position.y, 0.0001, "clip axis follows hull centre")
	expect_near((w.mesh as PlaneMesh).size.y, SubLayout.hull_size().z, 0.0001, "plane spans the hull length")
	w.free()


func test_floor_follows_the_program_bilge_well() -> void:
	var w: BilgeWater = (load("res://src/sub/bilge_water.tscn") as PackedScene).instantiate() as BilgeWater
	runner.add_child(w)
	expect_near(w.floor_y, SubLayout.position(&"bilge").y, 0.0001, "floor from the program")
	w.set_tonnage(0.0)
	expect_near(w.position.y, SubLayout.position(&"bilge").y, 0.0001, "dry surface at the well floor")
	w.free()


func test_pump_emitter_active_only_when_pump_on() -> void:
	var game: Game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	var leaks: LeakSystem = game.get_node("LeakSystem") as LeakSystem
	expect(not leaks.pump_emitter().field_events, "pump emitter emits no field events")
	expect_eq(leaks.pump_emitter().sound_type.procedural, &"gurgle")
	leaks._process(0.0)
	expect_eq(leaks.pump_emitter().active, leaks.pump_on())
	(game.get_node("Interior/PowerSystem") as PowerSystem).set_breaker(PowerSystem.Circuit.BILGE_PUMP, true)
	leaks.pump.host_set_value(1.0)
	leaks._process(0.0)
	expect(leaks.pump_on(), "pump on")
	expect(leaks.pump_emitter().active, "emitter active with pump")
	leaks.pump.host_set_value(0.0)
	leaks._process(0.0)
	expect(not leaks.pump_emitter().active, "emitter idle with pump off")
	game.free()
