extends TestCase
## The hologram's curved back panel: a plain translucent backdrop behind the
## table's relief, absent from the pilot's disc.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()


func after_each() -> void:
	game.end_session()
	game.free()


func test_panel_on_the_table_and_not_the_pilot_disc() -> void:
	var table: HoloMap = game.get_node("Interior/Stations/Maps/MapTable/TableHolo") as HoloMap
	var pilot: HoloMap = game.get_node("Interior/Stations/Maps/PilotHolo") as HoloMap
	expect(table.get_node_or_null("BackPanel") != null, "table has a back panel")
	expect(pilot.get_node_or_null("BackPanel") == null, "pilot has none")


func test_panel_fits_the_back_edge_and_within_the_hologram_height() -> void:
	var table: HoloMap = game.get_node("Interior/Stations/Maps/MapTable/TableHolo") as HoloMap
	var panel: MeshInstance3D = table.get_node("BackPanel") as MeshInstance3D
	var box: AABB = panel.get_aabb()
	var edge_half: float = sqrt(1.0 - table.d_flat_z * table.d_flat_z) * table.clip_rx
	expect(box.size.x <= edge_half * 2.0 + 0.0001, "width %s within back edge %s" % [box.size.x, edge_half * 2.0])
	var cap: float = float(SubLayout.record(&"map_table")["hologram_height_m"])
	expect(box.size.y <= cap + 0.0001, "height %s within the hologram height %s" % [box.size.y, cap])
	expect(box.size.y > 0.0 and box.size.x > 0.0, "panel has size")
	expect(box.position.z + box.size.z <= 0.0, "panel stands at the back, not over the relief centre")
	expect(panel.get_node_or_null("Surface") != null, "has a content mount point")


func test_panel_is_translucent_and_palette_coloured() -> void:
	var table: HoloMap = game.get_node("Interior/Stations/Maps/MapTable/TableHolo") as HoloMap
	var mat: StandardMaterial3D = (table.get_node("BackPanel") as MeshInstance3D).material_override as StandardMaterial3D
	expect(mat.albedo_color.a < 1.0, "alpha below 1")
	var want: Color = Palette.main().color(&"light_readout")
	expect(is_equal_approx(mat.albedo_color.r, want.r) and is_equal_approx(mat.albedo_color.b, want.b), "panel uses light_readout")
