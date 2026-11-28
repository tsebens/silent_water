extends TestCase
## ClimbTransit: foot to head along an authored path, gate, one occupant,
## bounds and replicated pose rate.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")
const DT: float = 1.0 / 60.0

var _made: Array[Node] = []


func after_each() -> void:
	for n: Node in _made:
		if is_instance_valid(n):
			n.free()
	_made.clear()


## A shaft from the deck up through the ceiling bounds.
func _transit() -> ClimbTransit:
	var t: ClimbTransit = ClimbTransit.new()
	t.path = PackedVector3Array([Vector3(0, 0.1, 0), Vector3(0, 2.0, 0), Vector3(0, 3.4, 0.3)])
	t.duration = 2.0
	t.extra_bounds = AABB(Vector3(-0.5, 2.5, -0.5), Vector3(1.0, 1.5, 1.5))
	runner.add_child(t)
	t.set_physics_process(false)
	_made.append(t)
	return t


func _player(id: int, at: Vector3) -> Player:
	var p: Player = PLAYER_SCENE.instantiate() as Player
	p.name = str(id)
	runner.add_child(p)
	_made.append(p)
	p.set_physics_process(false)
	p.set_process(false)
	p.get_node("Impairment").set_physics_process(false)
	p.position = at
	return p


func test_foot_to_head_within_duration() -> void:
	var t: ClimbTransit = _transit()
	var p: Player = _player(1, Vector3(0.2, 0.1, 0))
	expect(p.start_climb(t), "entry accepted at the foot")
	expect(p.is_climbing())
	var steps: int = int(ceil(t.duration / DT)) + 1
	for i: int in steps:
		p._simulate(DT)
	expect(not p.is_climbing(), "climb over within the duration")
	expect_near(p.position.distance_to(t.world_points()[2]), 0.0, 0.001, "arrived at the head")
	expect_eq(t.occupant(), InteractableState.NO_HOLDER, "transit free again")


func test_head_to_foot() -> void:
	var t: ClimbTransit = _transit()
	var p: Player = _player(1, t.world_points()[2] + Vector3(0.1, 0, 0))
	expect(p.start_climb(t))
	for i: int in int(ceil(t.duration / DT)) + 1:
		p._simulate(DT)
	expect_near(p.position.distance_to(t.world_points()[0]), 0.0, 0.001, "arrived at the foot")


func test_every_path_point_in_bounds() -> void:
	var t: ClimbTransit = _transit()
	for i: int in 101:
		var pos: Vector3 = t.point_at(float(i) / 100.0, true)
		expect(t.bounds_allow(pos), "sample %d inside interior or extra bounds: %s" % [i, pos])
	for pos: Vector3 in t.world_points():
		expect(Player.INTERIOR_BOUNDS.has_point(pos) or t.extra_bounds.has_point(pos), "path point %s" % pos)


func test_bounds_without_extra_are_refused() -> void:
	var t: ClimbTransit = _transit()
	t.extra_bounds = AABB()
	expect(not t.bounds_allow(Vector3(0, 3.4, 0.3)), "outside the interior and no extra bounds")
	expect(t.bounds_allow(Vector3(0, 1.0, 0)))


func test_closed_gate_refuses() -> void:
	var t: ClimbTransit = _transit()
	var open: Array[bool] = [false]
	t.gate = func() -> bool: return open[0]
	var p: Player = _player(1, Vector3(0.2, 0.1, 0))
	expect(not p.start_climb(t), "gate shut")
	expect(not p.is_climbing())
	open[0] = true
	expect(p.start_climb(t), "gate open")


func test_second_player_refused_while_first_climbs() -> void:
	var t: ClimbTransit = _transit()
	var a: Player = _player(1, Vector3(0.2, 0.1, 0))
	var b: Player = _player(2, Vector3(-0.2, 0.1, 0))
	expect(a.start_climb(t))
	expect(not b.start_climb(t), "occupied")
	for i: int in int(ceil(t.duration / DT)) + 1:
		a._simulate(DT)
	expect(b.start_climb(t), "free after the first arrives")


func test_too_far_from_either_end_refused() -> void:
	var t: ClimbTransit = _transit()
	var p: Player = _player(1, Vector3(1.9, 0.1, 0))
	expect(not p.start_climb(t))


func test_pose_never_exceeds_teleport_speed() -> void:
	var t: ClimbTransit = _transit()
	var p: Player = _player(1, Vector3(0.2, 0.1, 0))
	expect(p.start_climb(t))
	var last: Vector3 = p.position
	var worst: float = 0.0
	for i: int in int(ceil(t.duration / DT)) + 1:
		p._simulate(DT)
		p.sync_position = p.position
		worst = maxf(worst, p.sync_position.distance_to(last) / DT)
		last = p.sync_position
	expect(worst < Player.TELEPORT_SPEED, "peak pose speed %.2f m/s" % worst)
	expect(worst > 0.1, "it does move")


func test_climbing_is_quieter_than_a_footstep() -> void:
	var t: ClimbTransit = _transit()
	var p: Player = _player(1, Vector3(0.2, 0.1, 0))
	expect(p.start_climb(t))
	p._simulate(DT)
	expect(p.sync_climbing, "replicated flag set")
	expect(p.noise_intensity() > 0.0, "climbing is audible")
	expect(p.noise_intensity() < Player.FOOTSTEP_INTENSITY, "quieter than walking")
	p.end_climb()
	expect(not p.sync_climbing)


func test_collapse_breaks_off_the_climb() -> void:
	var t: ClimbTransit = _transit()
	var p: Player = _player(1, Vector3(0.2, 0.1, 0))
	expect(p.start_climb(t))
	p.collapse()
	expect(not p.is_climbing())
	expect_eq(t.occupant(), InteractableState.NO_HOLDER)
