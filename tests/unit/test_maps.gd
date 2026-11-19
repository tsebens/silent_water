extends TestCase
## Shared chart, holograms, map table picking and sonar contact marks,
## in a real Game scene, offline.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var chart: MapModel
var table: MapTable
var pilot_holo: HoloMap
var controller: SubController


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	chart = game.get_node("MapModel") as MapModel
	table = game.get_node("Interior/Stations/Maps/MapTable") as MapTable
	pilot_holo = game.get_node("Interior/Stations/Maps/PilotHolo") as HoloMap
	controller = game.get_node("SubController") as SubController
	var apex: ApexMonster = game.get_node("World/Apex") as ApexMonster
	apex.set_active(false)


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func test_pins_add_and_remove() -> void:
	chart.add_pin(Vector3(10, -50, -100), MapModel.Kind.DANGER)
	chart.add_pin(Vector3(20, -60, -120), MapModel.Kind.WAYPOINT)
	expect_eq(chart.pins.size(), 2)
	var id: int = int(chart.pins[0]["id"])
	chart.remove_pin(id)
	expect_eq(chart.pins.size(), 1)
	expect(chart.pin_by_id(id).is_empty())


func test_pins_show_on_both_holograms() -> void:
	chart.add_pin(Vector3(0, -40, -60), MapModel.Kind.APEX)
	await runner.get_tree().process_frame
	await runner.get_tree().process_frame
	expect_eq(pilot_holo.pin_markers().size(), 1, "pilot map shows the pin")
	expect_eq(table.holo.pin_markers().size(), 1, "map table shows the pin")


func test_display_mapping_round_trips() -> void:
	await runner.get_tree().process_frame
	var p: Vector3 = Vector3(12, -80, -150)
	expect(table.holo.to_world(table.holo.to_display(p)).distance_to(p) < 0.01)


func test_heading_up_puts_the_bow_away_from_the_pilot() -> void:
	controller.enabled = false
	controller.model.position = Vector3(0, -40, -100)
	# Turn the sub to face east (+X); the pilot map should still show what's
	# ahead of the bow at -Z on the display.
	game.sub_frame.set_pose(Transform3D(Basis(Vector3.UP, -PI / 2.0), Vector3(0, -40, -100)))
	await runner.get_tree().process_frame
	var ahead: Vector3 = pilot_holo.to_display(Vector3(50, -40, -100)) - pilot_holo.to_display(Vector3(0, -40, -100))
	expect(ahead.z < -0.1 and absf(ahead.x) < 0.01, "ahead of the bow is up the display (%s)" % ahead)


func test_table_click_picks_the_real_terrain() -> void:
	controller.enabled = false
	game.sub_frame.set_pose(Transform3D(Basis(), Vector3(0, -40, -100)))
	table.holo.follow_sub = false
	table.holo.focus = Vector3(0, -100, -200)
	await _frames(3)
	# A ray straight down through the display over the middle of the canyon.
	var over: Vector3 = table.holo.to_display(Vector3(0, 0, -200))
	var from_r: Vector3 = table.holo.global_transform * Vector3(over.x, table.holo.height + 0.2, over.z)
	var hit: Variant = table.pick_world_from_ray(from_r, -table.holo.global_basis.y)
	expect(hit != null, "the ray should find terrain")
	if hit != null:
		var p: Vector3 = hit as Vector3
		expect(absf(p.y - (CanyonSite.FLOOR_Y)) < 15.0, "landed near the canyon floor (%s)" % p)


func test_sonar_contact_mark_at_bearing_and_range() -> void:
	controller.enabled = false
	game.sub_frame.set_pose(Transform3D(Basis(), Vector3(0, -40, -100)))
	var seat: SonarSeat = game.get_node("Interior/Stations/Sonar/Seat") as SonarSeat
	var wheel: HydrophoneWheel = game.get_node("Interior/Stations/Sonar/Wheel") as HydrophoneWheel
	wheel.host_set_value(90.0)  # Starboard beam.
	seat.contact_range_m = 200.0
	seat.mark_contact()
	expect_eq(chart.pins.size(), 1)
	var p: Vector3 = chart.pins[0]["pos"] as Vector3
	expect(p.distance_to(Vector3(200, -40, -100)) < 1.0, "contact 200 m to starboard (%s)" % p)
	expect_eq(int(chart.pins[0]["kind"]), MapModel.Kind.CONTACT as int)


func test_dive_reset_clears_the_chart() -> void:
	chart.add_pin(Vector3.ZERO, MapModel.Kind.NOTE)
	(game.get_node("DiveDirector") as DiveDirector).reset_dive()
	expect_eq(chart.pins.size(), 0)
