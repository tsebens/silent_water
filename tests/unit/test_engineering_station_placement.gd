extends TestCase
## The engineering station is placed from the program (SubLayout) on the port wall, replaces the ballast panel, the
## starboard drop-weights placeholder and the bilge stub, and is bound to the sub's systems (arc #572, concept #530).

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
const PANEL: String = "Interior/Stations/Ballast/Panel"

var game: Game
var controller: SubController


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	controller = game.get_node("SubController") as SubController
	var apex: ApexMonster = game.get_node("World/Apex") as ApexMonster
	apex.brain_enabled = false
	apex.speed_unaware = 0.0


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func _panel() -> Node3D:
	return game.get_node(PANEL) as Node3D


## Floor-plan rectangle (x across, y along the hull) of every mesh under `n`.
func _plan(n: Node) -> Rect2:
	var out: Rect2 = Rect2()
	var first: bool = true
	for c: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = c as MeshInstance3D
		var b: AABB = m.global_transform * m.get_aabb()
		var r: Rect2 = Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		out = r if first else out.merge(r)
		first = false
	return out


func test_old_nodes_are_gone() -> void:
	expect(game.get_node_or_null("Interior/Stations/Bilge") == null, "the bilge stub is retired")
	expect(game.get_node_or_null("Interior/Stations/Ballast/FloodValve") == null, "the old flood valve is retired")
	expect(game.get_node_or_null("Interior/Stations/Ballast/TankGauge") == null, "the old gauges are retired")
	expect(not SubLayout.has(&"drop_weights"), "the drop weights are part of this station, not a feature of their own")


func test_panel_is_at_the_program_position_on_the_port_wall() -> void:
	var o: Vector3 = SubLayout.position(&"ballast")
	var p: Vector3 = _panel().global_position
	expect_near(p.z, o.z, 0.001, "along the hull at the program's z")
	expect_near(p.y, 1.1, 0.001, "centred 1.1 m above the floor")
	expect(p.x < 0.0, "port")
	expect(SubLayout.footprint(&"ballast").grow(0.01).has_point(Vector2(p.x, p.z)), "the back is on the footprint")
	expect(_panel().global_basis.z.is_equal_approx(Vector3(1, 0, 0)), "controls face the aisle (+X)")


func test_body_stays_inside_its_footprint_and_the_hull_and_clear_of_neighbours() -> void:
	var fp: Rect2 = _plan(_panel().get_node("Body"))
	expect(SubLayout.footprint(&"ballast").grow(0.02).encloses(fp), "body %s inside the footprint" % fp)
	for id: StringName in [&"life_support", &"bilge", &"engineering"]:
		expect(not fp.intersects(SubLayout.footprint(id).grow(-0.001)), "body clear of %s" % id)
	var p: Vector3 = _panel().global_position
	for dz: float in [-0.55, 0.0, 0.55]:
		for dy: float in [-0.65, 0.0, 0.65]:
			expect(SubLayout.inside_hull(p.x - 0.1, p.y + dy, p.z + dz), "inside the hull at dz %f dy %f" % [dz, dy])


func test_the_pump_lever_sweep_leaves_the_aisle_clear() -> void:
	var pump: HandPump = _panel().get_node("HandPump") as HandPump
	var most: float = -INF
	for v: float in [0.0, 1.0]:
		pump._apply_visual(v)
		var r: Rect2 = _plan(pump.pivot)
		most = maxf(most, r.end.x)
		var well: Rect2 = SubLayout.footprint(&"bilge")
		expect(not r.intersects(well), "the lever at %f is clear of the bilge well" % v)
	var opposite: float = SubLayout.footprint(&"engineering").position.x
	expect(opposite - most >= SubLayout.clearance("aisle_min_m"), "aisle %f m with the lever out" % (opposite - most))


func test_pilot_wheels_are_the_panels_wheels() -> void:
	var seat: PilotSeat = game.get_node("Interior/Stations/Pilot/Seat") as PilotSeat
	expect(seat.flood_valve == _panel().get_node("FloodWheel"), "the pilot's flood is the FLOOD wheel")
	expect(seat.blow_valve == _panel().get_node("BlowWheel"), "the pilot's blow is the BLOW wheel")
	expect(controller.flood_valve == _panel().get_node("FloodWheel"), "the sub controller reads the FLOOD wheel")
	expect(controller.blow_valve == _panel().get_node("BlowWheel"), "the sub controller reads the BLOW wheel")


func test_bilge_switch_runs_the_electric_pump() -> void:
	var leaks: LeakSystem = game.get_node("LeakSystem") as LeakSystem
	var sw: SwitchLever = _panel().get_node("BilgeSwitch") as SwitchLever
	expect(leaks.pump == sw, "LeakSystem.pump is the lit toggle")
	controller.model.bilge_water_t = 2.0
	await _frames(2)
	(game.get_node("Interior/PowerSystem") as PowerSystem).set_breaker(PowerSystem.Circuit.BILGE_PUMP, true)
	expect(not leaks.pump_on(), "off at the start")
	sw.host_set_value(1.0)
	await _frames(60)
	expect(leaks.pump_on(), "on with the switch")
	expect(controller.model.bilge_water_t < 1.99, "the electric pump lowers the bilge (%f)" % controller.model.bilge_water_t)
	sw.host_set_value(0.0)
	expect(not leaks.pump_on(), "off again")


func test_working_the_hand_pump_lowers_the_bilge() -> void:
	var pump: HandPump = _panel().get_node("HandPump") as HandPump
	
	controller.model.bilge_water_t = 2.0
	var before: float = controller.model.bilge_water_t
	for i: int in range(60):
		pump.step(1.0 / 60.0, true)
	expect(controller.model.bilge_water_t < before - 0.01, "a stroke removes water (%f)" % controller.model.bilge_water_t)


func test_drop_weights_release_once_per_dive_and_are_recorded() -> void:
	var drop: DropWeightsButton = _panel().get_node("DropWeights") as DropWeightsButton
	var log: SessionLog = game.get_node("SessionLog") as SessionLog
	drop.simulate_host = true
	var mass: float = controller.model.total_mass_t()
	drop.request_release()
	expect(not drop.is_released(), "the guard is closed: nothing happens")
	drop.guard.begin_interaction()
	drop.guard.drive_to(drop.guard.max_value)
	drop.guard.end_interaction()
	drop.request_release()
	expect(drop.is_released(), "released with the guard open")
	expect_near(controller.model.total_mass_t(), mass - controller.model.drop_weights_t, 0.0001, "the weights' mass is shed")
	expect_eq(log.drops_recorded, 1, "the dive record shows it")
	drop.request_release()
	expect_eq(log.drops_recorded, 1, "a second press is ignored")
	expect(drop.director == game.get_node("DiveDirector"), "re-armed by the dive director")
