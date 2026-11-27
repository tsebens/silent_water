extends TestCase
## The generated decoy rack: six DecoyCradle anchors, each seating a decoy; a decoy lifted out leaves its cradle empty
## and can be put back; the root carries no script.

const SCENE: String = "res://assets/models/furniture/decoy_rack/decoy_rack.tscn"


func _make() -> Node3D:
	var r: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(r)
	return r


func _cradle(r: Node3D, i: int) -> DecoyCradle:
	return r.get_node("Cradle%d" % i) as DecoyCradle


func _decoy(r: Node3D, i: int) -> DecoyItem:
	return r.get_node("Decoy%d" % i) as DecoyItem


func test_six_cradles_and_six_decoys() -> void:
	var r: Node3D = _make()
	expect(r.get_script() == null, "the root carries no script")
	for i: int in range(1, 7):
		expect(r.get_node_or_null("Cradle%d" % i) is DecoyCradle, "Cradle%d is a DecoyCradle" % i)
		expect(r.get_node_or_null("Decoy%d" % i) is DecoyItem, "Decoy%d is a DecoyItem" % i)
	expect(r.get_node_or_null("Cradle7") == null, "exactly six cradles")
	r.queue_free()


func test_all_six_seat_a_decoy() -> void:
	var r: Node3D = _make()
	for i: int in range(1, 7):
		var c: DecoyCradle = _cradle(r, i)
		var d: DecoyItem = _decoy(r, i)
		expect(c.try_seat(d), "decoy %d seats" % i)
		expect(c.is_occupied() and d.is_seated(), "cradle %d occupied" % i)
		expect_near(d.global_position.distance_to(c.global_position), 0.0, 1e-4, "decoy %d at its cradle" % i)
		expect(not c.try_seat(d), "a second seating is refused")
	r.queue_free()


func test_a_decoy_taken_out_leaves_the_cradle_empty_and_can_go_back() -> void:
	var r: Node3D = _make()
	var c: DecoyCradle = _cradle(r, 3)
	var d: DecoyItem = _decoy(r, 3)
	expect(c.try_seat(d), "seated")
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	expect(d.pick_up(carrier), "lifted out")
	expect(not c.is_occupied() and c.decoy() == null, "the cradle is empty")
	expect(d.is_carried() and not d.is_seated(), "the decoy is carried")
	expect(d.drop_into(c), "the carried decoy goes back into the empty cradle")
	expect(c.is_occupied() and c.decoy() == d, "the cradle holds it again")
	carrier.queue_free()
	r.queue_free()


func test_cradles_are_apart_and_inside_the_column() -> void:
	var r: Node3D = _make()
	for i: int in range(1, 6):
		var gap: float = _cradle(r, i + 1).position.y - _cradle(r, i).position.y
		expect(gap > 0.2, "cradle %d is clear above cradle %d (%f)" % [i + 1, i, gap])
	for i: int in range(1, 7):
		var p: Vector3 = _cradle(r, i).position
		expect(absf(p.x) < 0.01 and p.z > 0.0 and p.z < 0.45, "cradle %d inside the footprint" % i)
	r.queue_free()
