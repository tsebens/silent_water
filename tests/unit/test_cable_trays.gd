extends TestCase
## The cable-tray runs (arc #581, concept #577): they join the electrical board to every junction box, stay inside the
## hull, hang above head clearance (so the aisle and every station stay clear), and the boxes sit on them.

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")
const SAMPLE: float = 0.05
const TOUCH: float = 0.02

var interior: Node3D


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)


func after_each() -> void:
	interior.free()


func _board() -> Vector3:
	return (interior.get_node("Stations/Engineering/Panel") as Node3D).global_position


func _runs() -> Array[PackedVector3Array]:
	return CableTrays.runs(_board())


func _boxes() -> Array[JunctionBox]:
	var out: Array[JunctionBox] = []
	for n: Node in interior.get_node("JunctionBoxes").get_children():
		out.append(n as JunctionBox)
	return out


## Every point along every run, sampled finely.
func _samples() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for run: PackedVector3Array in _runs():
		for i: int in range(run.size() - 1):
			var n: int = maxi(1, ceili(run[i].distance_to(run[i + 1]) / SAMPLE))
			for k: int in n + 1:
				out.append(run[i].lerp(run[i + 1], float(k) / float(n)))
	return out


func _find(nodes: Array[Vector3], p: Vector3) -> int:
	for i: int in nodes.size():
		if nodes[i].distance_to(p) <= TOUCH:
			return i
	return -1


func test_the_board_joins_every_junction_box() -> void:
	# Vertices of every run are graph nodes; consecutive vertices are edges. Runs join where they share a vertex.
	var nodes: Array[Vector3] = []
	var edges: Array[Vector2i] = []
	for run: PackedVector3Array in _runs():
		var prev: int = -1
		for p: Vector3 in run:
			var id: int = _find(nodes, p)
			if id < 0:
				nodes.append(p)
				id = nodes.size() - 1
			if prev >= 0:
				edges.append(Vector2i(prev, id))
			prev = id
	var reached: Dictionary = {0: true}
	var grew: bool = true
	while grew:
		grew = false
		for e: Vector2i in edges:
			if reached.has(e.x) != reached.has(e.y):
				reached[e.x] = true
				reached[e.y] = true
				grew = true
	expect(nodes[0].distance_to(_board()) <= 1.0, "the run starts at the electrical board")
	var boxes: Array[JunctionBox] = _boxes()
	expect(boxes.size() >= PowerSystem.Circuit.size() * 2, "boxes exist (%d)" % boxes.size())
	for jb: JunctionBox in boxes:
		var id: int = _find(nodes, jb.position)
		expect(id >= 0, "%s sits on a tray vertex" % jb.name)
		if id >= 0:
			expect(reached.has(id), "%s is joined to the board" % jb.name)
	expect_eq(reached.size(), nodes.size(), "the whole network is one piece")


func test_trays_stay_inside_the_hull() -> void:
	var half: float = CableTrays.TRAY_WIDTH / 2.0
	var h: float = CableTrays.TRAY_HEIGHT / 2.0
	for p: Vector3 in _samples():
		for dx: float in [-half, half]:
			for dy: float in [-h, h]:
				expect(SubLayout.inside_hull(p.x + dx, p.y + dy, p.z), "tray corner at %s inside the hull" % (p + Vector3(dx, dy, 0)))


func test_trays_clear_the_aisle_and_stations() -> void:
	var head: float = SubLayout.clearance("head_clear_m")
	for run: PackedVector3Array in _runs().slice(1):
		for p: Vector3 in run:
			expect(p.y - CableTrays.TRAY_HEIGHT / 2.0 >= head, "tray at %s is above head clearance %f" % [p, head])
	# Stations and features stand on the deck below head clearance, except the ladder that climbs to the conning tower:
	# the trays also stay out of its plan footprint.
	var ladder: Rect2 = SubLayout.footprint(&"tower_ladder")
	for p: Vector3 in _samples():
		expect(not ladder.grow(CableTrays.TRAY_WIDTH / 2.0 - 0.001).has_point(Vector2(p.x, p.z)), "tray at %s clear of the ladder" % p)
	# The feed rises from the board's top within the board's own height.
	var feed: PackedVector3Array = _runs()[0]
	expect_near(feed[0].y, _board().y + CableTrays.FEED_RISE, 0.001, "the feed leaves the top of the board")


func test_boxes_sit_on_the_trunks_in_circuit_order() -> void:
	for jb: JunctionBox in _boxes():
		expect_near(jb.position.z, CableTrays.box_z(jb.circuit), 0.001, "%s z" % jb.name)
		expect((jb.position.x > 0.0) == (jb.box_index == 1), "%s on the %s trunk" % [jb.name, "starboard" if jb.box_index == 1 else "port"])
		expect_near(jb.position.y, CableTrays.TRAY_Y, 0.001, "%s on the tray" % jb.name)
