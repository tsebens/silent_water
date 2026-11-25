extends TestCase
## Spawn points and the pilot station against the program (SubLayout): players start on the deck, clear of every
## station footprint, in an aisle at least aisle_min_m wide; the pilot's controls are placed from the program.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")
## A player capsule's radius: a spawn this close to a footprint edge would clip the station.
const PLAYER_RADIUS: float = 0.3

var game: Game


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	(game.get_node("SubController") as SubController).enabled = false
	runner.add_child(game)
	game.start_session()


func after_each() -> void:
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


## Distance from a point (x across, z along) to the rectangle, 0 inside it.
func _distance_to(r: Rect2, x: float, z: float) -> float:
	var dx: float = maxf(maxf(r.position.x - x, x - r.end.x), 0.0)
	var dz: float = maxf(maxf(r.position.y - z, z - r.end.y), 0.0)
	return sqrt(dx * dx + dz * dz)


func _footprints() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for id: StringName in SubLayout.ids():
		out.append(SubLayout.footprint(id))
		out.append(SubLayout.top_footprint(id))
	return out


func test_spawn_points_are_on_the_deck_in_the_aisle() -> void:
	var midships: Vector2 = SubLayout.compartment_span(&"midships")
	for s: Vector3 in Game.SPAWN_POINTS:
		expect(s.y > 0.0 and s.y < 0.3, "just above the main deck, got %f" % s.y)
		expect(s.z > midships.x and s.z < midships.y, "in midships, z=%f" % s.z)
		expect(SubLayout.inside_hull(s.x, 1.0, s.z), "inside the hull at head height: %s" % s)


func test_spawn_points_clear_of_every_station() -> void:
	var margin: float = maxf(PLAYER_RADIUS, SubLayout.clearance("aisle_min_m") / 2.0)
	for s: Vector3 in Game.SPAWN_POINTS:
		for r: Rect2 in _footprints():
			expect(_distance_to(r, s.x, s.z) >= margin, "spawn %s within %.2f m of footprint %s" % [s, margin, r])


func test_spawn_points_are_apart() -> void:
	var pts: Array[Vector3] = Game.SPAWN_POINTS
	for i: int in range(pts.size()):
		for j: int in range(i + 1, pts.size()):
			expect(pts[i].distance_to(pts[j]) >= SubLayout.clearance("aisle_min_m") * 0.8, "spawns %d and %d too close" % [i, j])


func test_aisle_at_each_spawn_respects_aisle_min() -> void:
	var need: float = SubLayout.clearance("aisle_min_m")
	for s: Vector3 in Game.SPAWN_POINTS:
		var left: float = -10.0
		var right: float = 10.0
		for r: Rect2 in _footprints():
			if s.z < r.position.y or s.z > r.end.y:
				continue
			if r.end.x <= s.x:
				left = maxf(left, r.end.x)
			elif r.position.x >= s.x:
				right = minf(right, r.position.x)
		expect(right - left >= need, "aisle at z=%f is %.2f m, need %.2f" % [s.z, right - left, need])


func test_players_spawn_where_expected_and_stay_on_the_deck() -> void:
	game._spawn_player(2)
	game._spawn_player(3)
	game._spawn_player(4)
	await _frames(30)
	expect_eq(game.players.get_child_count(), 4, "four crew")
	for child: Node in game.players.get_children():
		var p: Player = child as Player
		expect(absf(p.position.y) < 0.2, "%s is on the deck (y=%f)" % [p.name, p.position.y])
		expect(Player.INTERIOR_BOUNDS.has_point(p.position), "%s is inside the sub" % p.name)
	var me: Player = game.local_player()
	expect(me.position.z < -0.5 and me.position.z > -3.4, "the local player stayed in the aisle (z=%f)" % me.position.z)


func test_pilot_controls_are_placed_from_the_program() -> void:
	var origin: Vector3 = SubLayout.position(&"pilot")
	var seat: Node3D = game.get_node("Interior/Stations/Pilot/Seat") as Node3D
	expect(seat.position.is_equal_approx(origin), "the seat is at the program's pilot position, got %s" % seat.position)
	expect_near(origin.z, -3.8)
	expect_near(origin.y, -0.20)
	var sit: Node3D = game.get_node("Interior/Stations/Pilot/Seat/SitPoint") as Node3D
	expect(sit.global_position.is_equal_approx(origin), "the sit point is at the pilot position")
	var placer: StationPlacement = game.get_node("Interior/Stations/Pilot") as StationPlacement
	for path: Variant in placer.placements.keys():
		var n: Node3D = placer.get_node(NodePath(String(path))) as Node3D
		expect(n.position.distance_to(origin) < 1.5, "%s is within reach of the pilot (%s)" % [path, n.position])
		expect(n.position.z < -3.0, "%s is in the cockpit (z=%f)" % [path, n.position.z])


func test_pilot_can_sit_in_the_new_seat() -> void:
	await _frames(20)
	var me: Player = game.local_player()
	var helm: PilotSeat = game.get_node("Interior/Stations/Pilot/Seat") as PilotSeat
	me.sit_in(helm)
	await _frames(5)
	expect(me.position.distance_to(helm.seat_transform().origin) < 0.05, "seated at the helm")
	expect(me.position.z < -3.0, "in the dome")
	me.stand_up()
