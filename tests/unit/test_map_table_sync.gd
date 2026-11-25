extends TestCase
## The map table's chart view is the operator's, shared with everyone (#432):
## requests go to the host, which applies them and sends the view to every
## peer. Two Game scenes stand in for a host and a client, with the host's
## `view_sent` signal as the wire.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
const OPERATOR_PEER: int = 7
const OTHER_PEER: int = 9

var host_game: Game
var client_game: Game
var host: MapTable
var client: MapTable


func before_each() -> void:
	host_game = _make_game()
	client_game = _make_game()
	host = host_game.get_node("Interior/Stations/Maps/MapTable") as MapTable
	client = client_game.get_node("Interior/Stations/Maps/MapTable") as MapTable
	host.view_sent.connect(_on_view_sent)


func after_each() -> void:
	for g: Game in [host_game, client_game]:
		g.end_session()
		g.free()


func _make_game() -> Game:
	var g: Game = GAME_SCENE.instantiate() as Game
	runner.add_child(g)
	g.start_session()
	(g.get_node("World/Apex") as ApexMonster).set_active(false)
	(g.get_node("SubController") as SubController).enabled = false
	return g


## The host's wire: everything it sends reaches the client table.
func _on_view_sent(_peer: int, view: Dictionary) -> void:
	client.apply_view(view)


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().process_frame


func _view() -> Dictionary:
	return {"focus": Vector3(120, -90, -340), "mpu": 400.0, "rot": 75.0, "follow": false}


func test_operator_view_reaches_the_client_hologram() -> void:
	await _frames(2)
	host.pan_ball.state.holder = OPERATOR_PEER
	var v: Dictionary = _view()
	expect(host.host_request_view(OPERATOR_PEER, v), "the operator is heard")
	for h: HoloMap in [host.holo, client.holo]:
		expect_eq(h.focus, v["focus"], "pan")
		expect_eq(h.meters_per_unit, v["mpu"], "zoom")
		expect_eq(h.table_rotation_deg, v["rot"], "rotation")
		expect(not h.follow_sub, "follow")
	v["follow"] = true
	host.host_request_view(OPERATOR_PEER, v)
	expect(client.holo.follow_sub and host.holo.follow_sub, "follow turned on reaches both")


func test_the_hosts_own_steering_is_sent() -> void:
	await _frames(2)
	host.holo.follow_sub = false
	host.begin_interaction()
	host.rotate_table(30.0)
	host.pan_display(Vector3(1, 0, 0))
	host.zoom_to(500.0)
	host._process(0.1)
	host.end_interaction()
	expect_eq(client.holo.meters_per_unit, 500.0, "zoom")
	expect_near(client.holo.table_rotation_deg, host.holo.table_rotation_deg, 1e-4, "rotation")
	expect(client.holo.focus.is_equal_approx(host.holo.focus), "pan")


func test_a_non_operator_changes_nothing() -> void:
	await _frames(2)
	host.pan_ball.state.holder = OPERATOR_PEER
	var before: Dictionary = host.view_dict()
	var client_before: Dictionary = client.view_dict()
	expect(not host.host_request_view(OTHER_PEER, _view()), "a stranger is refused")
	expect_eq(host.view_dict(), before, "the host's chart is unchanged")
	expect_eq(client.view_dict(), client_before, "the client's chart is unchanged")
	host.pan_ball.state.holder = InteractableState.NO_HOLDER
	expect(not host.host_request_view(OPERATOR_PEER, _view()), "nobody holding means nobody is the operator")


func test_any_console_control_makes_its_holder_the_operator() -> void:
	await _frames(2)
	for c: Interactable in [host, host.pan_ball, host.zoom_lever, host.follow_toggle]:
		c.state.holder = OPERATOR_PEER
		expect(host.is_operator(OPERATOR_PEER), "%s holder" % c.name)
		expect(not host.is_operator(OTHER_PEER))
		c.state.holder = InteractableState.NO_HOLDER


func test_a_late_joiner_receives_the_current_view() -> void:
	await _frames(2)
	host.pan_ball.state.holder = OPERATOR_PEER
	host.host_request_view(OPERATOR_PEER, _view())
	client.apply_view({"focus": Vector3.ZERO, "mpu": 240.0, "rot": 0.0, "follow": true})
	host._on_peer_joined(OTHER_PEER)
	expect_eq(client.holo.focus, _view()["focus"], "joined into the operator's view")
	expect_eq(client.holo.meters_per_unit, 400.0)


func test_the_pilots_hologram_is_unaffected() -> void:
	await _frames(2)
	var pilot: HoloMap = host_game.get_node("Interior/Stations/Maps/PilotHolo") as HoloMap
	var client_pilot: HoloMap = client_game.get_node("Interior/Stations/Maps/PilotHolo") as HoloMap
	var before: Array = [pilot.focus, pilot.meters_per_unit, pilot.table_rotation_deg, pilot.follow_sub]
	host.pan_ball.state.holder = OPERATOR_PEER
	host.host_request_view(OPERATOR_PEER, _view())
	expect_eq([pilot.focus, pilot.meters_per_unit, pilot.table_rotation_deg, pilot.follow_sub], before, "host pilot")
	expect(client_pilot.follow_sub and client_pilot.meters_per_unit != 400.0, "client pilot stays on the sub")
