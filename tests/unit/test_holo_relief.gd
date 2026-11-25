extends TestCase
## The hologram display model: a thin terrain relief of contours with dots for
## pins, in the table (D-shaped, full tabletop) and pilot (small disc) setups.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var chart: MapModel
var table_holo: HoloMap
var pilot_holo: HoloMap


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	chart = game.get_node("MapModel") as MapModel
	table_holo = game.get_node("Interior/Stations/Maps/MapTable/TableHolo") as HoloMap
	pilot_holo = game.get_node("Interior/Stations/Maps/PilotHolo") as HoloMap
	(game.get_node("World/Apex") as ApexMonster).set_active(false)


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().process_frame


func test_relief_heights_are_low() -> void:
	await _frames(3)
	expect(table_holo.relief and pilot_holo.relief, "both use the relief")
	expect(table_holo.relief_max_height() <= 0.03, "table relief at most 3 cm (%s)" % table_holo.relief_max_height())
	expect(pilot_holo.relief_max_height() <= 0.01, "pilot relief at most 1 cm (%s)" % pilot_holo.relief_max_height())
	# The deepest and shallowest world points land inside that height.
	for h: HoloMap in [table_holo, pilot_holo]:
		var top: float = h.to_display(Vector3(0, h.relief_floor_y + h.relief_depth_m, 0)).y
		expect(top <= h.relief_max_height() + 0.0001, "world top maps inside the relief")
		expect(absf(h.to_display(Vector3(0, h.relief_floor_y, 0)).y) < 0.0001, "floor sits on the base")


func test_each_pin_is_a_marker_dot_in_light_marker() -> void:
	chart.add_pin(Vector3(10, -50, -100), MapModel.Kind.WAYPOINT)
	chart.add_pin(Vector3(30, -60, -120), MapModel.Kind.NOTE)
	await _frames(3)
	var marker: Color = Palette.main().color(&"light_marker")
	for h: HoloMap in [table_holo, pilot_holo]:
		var nodes: Array[Node3D] = h.pin_markers()
		expect_eq(nodes.size(), chart.pins.size(), "one marker per pin")
		for pin: Dictionary in chart.pins:
			var found: bool = false
			for n: Node3D in nodes:
				if int(n.get_meta(&"pin_id")) == int(pin["id"]):
					found = true
					var mat: ShaderMaterial = (n as MeshInstance3D).material_override as ShaderMaterial
					expect((mat.get_shader_parameter(&"holo_color") as Color).is_equal_approx(marker), "pin is light_marker")
			expect(found, "pin %d has a marker" % int(pin["id"]))


func test_outlines() -> void:
	var disc: PackedVector2Array = HoloMap.outline(0.1, 0.1, false, -0.55)
	var d: PackedVector2Array = HoloMap.outline(0.6, 0.36, true, -0.55)
	var min_z: float = 0.0
	for p: Vector2 in disc:
		expect(p.length() <= 0.1001, "disc stays round")
	for p: Vector2 in d:
		min_z = minf(min_z, p.y)
	expect(absf(min_z - (-0.55 * 0.36)) < 0.0001, "D is flat at the back")
	expect(table_holo.d_shaped and not pilot_holo.d_shaped, "table is D, pilot is a disc")
