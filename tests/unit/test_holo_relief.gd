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


func test_relief_heights() -> void:
	await _frames(3)
	expect(table_holo.relief and pilot_holo.relief, "both use the relief")
	expect(table_holo.relief_max_height() >= 0.6 and table_holo.relief_max_height() <= 0.7, "table relief about 0.7 m (%s)" % table_holo.relief_max_height())
	expect(pilot_holo.relief_max_height() >= 0.05 and pilot_holo.relief_max_height() <= 0.07, "pilot relief about 6 cm (%s)" % pilot_holo.relief_max_height())
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


func test_dot_over_high_terrain_sits_above_dot_over_low() -> void:
	chart.add_pin(Vector3(0, -40, -100), MapModel.Kind.WAYPOINT)
	chart.add_pin(Vector3(0, -200, -100), MapModel.Kind.NOTE)
	await _frames(3)
	for h: HoloMap in [table_holo, pilot_holo]:
		var ys: Array[float] = []
		for n: Node3D in h.pin_markers():
			ys.append(n.position.y)
		expect_eq(ys.size(), 2, "two markers")
		expect(absf(ys[0] - ys[1]) > h.relief_max_height() * 0.5, "high terrain dot is clearly above low one (%s)" % [ys])
		expect(ys[0] > ys[1], "the shallower pin sits higher")


func test_table_hologram_fits_program_height_and_overhead() -> void:
	await _frames(3)
	var top: float = table_holo.relief_max_height() + HoloMap.RELIEF_MARGIN
	var cap: float = float(SubLayout.record(&"map_table")["hologram_height_m"])
	expect(top <= cap + 0.0001, "hologram top %s within hologram_height_m %s" % [top, cap])
	var interior: Node3D = game.get_node("Interior") as Node3D
	var base: Vector3 = interior.to_local(table_holo.global_position)
	var margin: float = SubLayout.clearance("overhead_margin_m")
	# Every corner of the hologram's footprint, at its top plus the margin, is inside the hull.
	for sx: float in [-1.0, 0.0, 1.0]:
		for sz: float in [table_holo.d_flat_z, 1.0]:
			var p: Vector3 = base + table_holo.global_basis * Vector3(sx * table_holo.clip_rx, 0, sz * table_holo.clip_rz)
			var r: Vector3 = SubLayout.to_program(Vector3(p.x, p.y + top + margin, p.z))
			expect(SubLayout.inside_hull(r.x, r.y, r.z), "clear of the overhead at %s" % p)


func test_back_panel_is_at_least_as_tall_as_the_relief() -> void:
	expect(table_holo.back_panel, "table has the panel")
	expect(table_holo.panel_height >= table_holo.relief_max_height(), "panel %s covers relief %s" % [table_holo.panel_height, table_holo.relief_max_height()])


func test_pilot_relief_inside_station_hologram_envelope() -> void:
	const HOLO_H_M: float = 0.2  # tools/cadkit/scenes/pilot_station.py HOLO_H (200 mm)
	expect(pilot_holo.relief_max_height() + HoloMap.RELIEF_MARGIN <= HOLO_H_M, "disc relief plus margin inside the 200 mm envelope")
