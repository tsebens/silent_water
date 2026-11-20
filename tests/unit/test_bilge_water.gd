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
