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
	controller.model.position = Vector3(0, -0.2, 30)
	await _frames(int(60 * (DiveDirector.SURFACED_HOLD_SEC + 0.5)))
	expect_eq(director.phase, DiveDirector.Phase.COMPLETE)
	expect(director.status_text().contains("DIVE COMPLETE"))
	await _frames(int(60 * (DiveDirector.COMPLETE_HOLD_SEC + 0.5)))
	expect_eq(director.phase, DiveDirector.Phase.DIVING, "reset for another run")
	expect(not scan.complete, "objective reset")


func test_surfacing_without_scan_does_not_complete() -> void:
	controller.model.position = Vector3(0, -0.2, 30)
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
	expect(cabin.cabin_lights().size() == 3, "three cabin lights")


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
