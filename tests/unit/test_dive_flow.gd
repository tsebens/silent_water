extends TestCase
## Integration tests for the scan objective and the dive flow, offline.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var controller: SubController
var scan: ScanObjective
var director: DiveDirector
var switch: Lever


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	Acoustics.reset()
	controller = game.get_node("SubController") as SubController
	scan = game.get_node("ScanObjective") as ScanObjective
	director = game.get_node("DiveDirector") as DiveDirector
	switch = game.get_node("Interior/Stations/Scanner/Switch") as Lever
	# Keep the apex out of these tests.
	var apex: ApexMonster = game.get_node("World/Apex") as ApexMonster
	apex.brain_enabled = false
	apex.speed_unaware = 0.0


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


## Height at which the hull floats at rest with its current load: the hull's top just breaks the surface.
func _floating_y() -> float:
	var m: SubPhysicsModel = controller.model
	var height: float = SubPhysicsModel.hull_top() - SubPhysicsModel.hull_bottom()
	return -SubPhysicsModel.hull_bottom() - m.total_mass_t() / m.displacement_t * height


func _hover_over_array() -> void:
	controller.model.position = CanyonSite.OBJECTIVE_POSITION + Vector3(0, 15, 0)
	controller.model.velocity = Vector3.ZERO
	controller.model.tank_water_t = controller.model.tank_capacity_t * 0.5


func test_dive_starts_floating_at_the_surface() -> void:
	await _frames(120)
	expect(controller.surfaced, "starts at the surface (depth %f)" % controller.depth)
	expect_eq(controller.model.tank_water_t, 0.0, "tanks empty")
	expect_eq(director.phase, DiveDirector.Phase.DIVING)
	expect(game.get_node("Interior/Stations/StatusBoard").get("text").contains("SCAN SENSOR ARRAY"), "orders on the board")


func test_scan_completes_in_position_and_is_loud() -> void:
	_hover_over_array()
	switch.host_set_value(1.0)
	await _frames(30)
	expect(Acoustics.sub_db() > 82.0, "the scanner is loud (%f dB)" % Acoustics.sub_db())
	await _frames(int(60 * (ScanObjective.SCAN_TIME_SEC + 1.0)))
	expect(scan.complete, "scan done (progress %f)" % scan.progress)
	expect(switch.get_value() < 0.5, "scanner switches itself off")
	expect(Acoustics.sub_db() < 70.0, "and goes quiet")


func test_no_progress_when_far_from_the_array() -> void:
	controller.model.position = Vector3(0, -80, -100)
	controller.model.tank_water_t = controller.model.tank_capacity_t * 0.5
	switch.host_set_value(1.0)
	await _frames(60 * 3)
	expect_eq(scan.progress, 0.0)


func test_progress_drains_when_position_is_lost() -> void:
	_hover_over_array()
	switch.host_set_value(1.0)
	await _frames(60 * 6)
	var p: float = scan.progress
	expect(p > 0.15, "some progress (%f)" % p)
	switch.host_set_value(0.0)
	await _frames(60 * 3)
	expect(scan.progress < p, "drains while off")
	expect(scan.progress > 0.0, "but slowly")


func test_surfacing_after_scan_completes_the_dive_then_resets() -> void:
	scan.complete = true
	controller.model.position = Vector3(0, _floating_y(), 30)
	await _frames(int(60 * (DiveDirector.SURFACED_HOLD_SEC + 0.5)))
	expect_eq(director.phase, DiveDirector.Phase.COMPLETE)
	expect(director.status_text().contains("DIVE COMPLETE"))
	await _frames(int(60 * (DiveDirector.COMPLETE_HOLD_SEC + 0.5)))
	expect_eq(director.phase, DiveDirector.Phase.DIVING, "reset for another run")
	expect(not scan.complete, "objective reset")


func test_surfacing_without_scan_does_not_complete() -> void:
	controller.model.position = Vector3(0, _floating_y(), 30)
	await _frames(60 * 5)
	expect_eq(director.phase, DiveDirector.Phase.DIVING)


func test_cabin_dimmer_dims_cabin_but_not_headlight() -> void:
	var cabin: CabinLights = game.get_node("CabinLights") as CabinLights
	var dimmer: Lever = game.get_node("Interior/Stations/Pilot/Dimmer") as Lever
	var fore: OmniLight3D = game.get_node("Interior/Lights/Fore") as OmniLight3D
	var head: SpotLight3D = game.get_node("Interior/Lights/Headlight") as SpotLight3D
	await _frames(2)
	var bright: float = fore.light_energy
	var head_before: float = head.light_energy
	dimmer.host_set_value(0.0)
	await _frames(2)
	expect_near(fore.light_energy, bright * CabinLights.MIN_LEVEL, 0.001, "dimmed to near dark")
	expect_eq(head.light_energy, head_before, "headlight untouched")
	expect(cabin.cabin_lights().size() == 6, "six cabin lights (four room lights, two coves)")


func test_dev_overlay_stats_cover_sub_noise_and_apex() -> void:
	controller.model.position = Vector3(0, -50, -100)
	controller.model.tank_water_t = controller.model.tank_capacity_t
	await _frames(30)
	var text: String = DevOverlay.stats_text(game)
	for needle: String in ["depth", "speed", "buoyancy NEGATIVE", "sub ", "ocean", "APEX", "distance", "suspicion", "DIVE"]:
		expect(text.contains(needle), "stats should mention '%s':\n%s" % [needle, text])


func test_dev_log_captures_engine_output() -> void:
	var before: int = DevLog.revision
	print("dev log probe 7731")
	await runner.get_tree().process_frame
	expect(DevLog.revision > before, "a print should reach the developer log")
	var found: bool = false
	for entry: Array in DevLog.lines:
		if String(entry[1]).contains("dev log probe 7731"):
			found = true
	expect(found)


func test_dimmer_scales_every_cabin_light_including_the_coves() -> void:
	var lights: CabinLights = game.get_node("CabinLights") as CabinLights
	var dimmer: Lever = game.get_node("Interior/Stations/Pilot/Dimmer") as Lever
	var cabin: Array[Light3D] = lights.cabin_lights()
	var names: Array[String] = []
	for l: Light3D in cabin:
		names.append(String(l.name))
	expect(names.has("CoveLeft") and names.has("CoveRight"), "cove lights are cabin lights (%s)" % str(names))
	expect(cabin.size() <= 8, "a handful of lights (%d)" % cabin.size())
	var base: Dictionary = {}
	dimmer.host_set_value(1.0)
	await _frames(3)
	for l: Light3D in cabin:
		base[l.name] = l.light_energy
	dimmer.host_set_value(0.0)
	await _frames(3)
	for l: Light3D in cabin:
		expect_near(l.light_energy, float(base[l.name]) * CabinLights.MIN_LEVEL, 0.001, "%s dims to MIN_LEVEL" % l.name)
	dimmer.host_set_value(1.0)
	await _frames(3)
	for l: Light3D in cabin:
		expect_near(l.light_energy, float(base[l.name]), 0.001, "%s back to full" % l.name)


func test_no_visible_strip_meshes_under_the_lights() -> void:
	var lights_root: Node = game.get_node("Interior/Lights")
	var allowed: Array[String] = []
	var stray: Array[String] = []
	for n: Node in lights_root.find_children("*", "MeshInstance3D", true, false):
		if not allowed.has(String(n.name)):
			stray.append(String(n.name))
	expect(stray.is_empty(), "no strip meshes under Lights (%s)" % str(stray))


func test_single_player_helm_runs_the_ballast() -> void:
	DevSettings.single_player = true
	var me: Player = game.local_player()
	var helm: PilotSeat = game.get_node("Interior/Stations/Pilot/Seat") as PilotSeat
	var blow: Interactable = game.get_node("Interior/Stations/Ballast/BlowValve") as Interactable
	var flood: Interactable = game.get_node("Interior/Stations/Ballast/FloodValve") as Interactable
	me.sit_in(helm)
	me.bot_ballast = 1.0
	await _frames(40)
	expect(blow.get_normalized() > 0.9, "blow key opens the blow valve (%f)" % blow.get_normalized())
	expect(blow.get_noise_intensity() < 0.001, "and turns it silently")
	me.bot_ballast = -1.0
	await _frames(40)
	expect(flood.get_normalized() > 0.9 and blow.get_normalized() < 0.1, "flood key floods, blow closes")
	me.bot_ballast = 0.0
	await _frames(40)
	expect(flood.get_normalized() < 0.1, "releasing closes it")
	me.stand_up()
	DevSettings.single_player = false


func test_crew_mode_helm_leaves_the_ballast_alone() -> void:
	DevSettings.single_player = false
	var me: Player = game.local_player()
	me.sit_in(game.get_node("Interior/Stations/Pilot/Seat") as PilotSeat)
	me.bot_ballast = 1.0
	await _frames(30)
	expect_near((game.get_node("Interior/Stations/Ballast/BlowValve") as Interactable).get_normalized(), 0.0, 0.001)
	me.bot_ballast = 0.0
	me.stand_up()
