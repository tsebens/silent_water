extends TestCase
## The generated life-support wall unit, first half (docs/asset_process.md): every instance resolves, a canister
## seats in each cradle, and the cradles and gauges are within reach of the standing eye.

const SCENE: String = "res://assets/models/stations/life_support/life_support.tscn"
const REACH_M: float = 0.75


func _make() -> Node3D:
	var st: Node3D = (load(SCENE) as PackedScene).instantiate() as Node3D
	runner.add_child(st)
	return st


func test_scene_loads_and_every_instance_resolves() -> void:
	var st: Node3D = _make()
	expect(st != null, "scene loads")
	for n: String in ["CradleA", "CradleB"]:
		expect(st.get_node_or_null(n) is CanisterSlot, "%s is a CanisterSlot" % n)
	for n: String in ["CanisterA", "CanisterB"]:
		expect(st.get_node_or_null(n) is ScrubberCanister, "%s is a ScrubberCanister" % n)
	for n: String in ["SaturationA", "SaturationB"]:
		expect(st.get_node_or_null(n) is LinearGauge, "%s is a LinearGauge" % n)
	expect(st.get_node_or_null("UpperPanelAnchor") != null, "UpperPanelAnchor")
	expect(st.get_script() == null, "the station adds no script")
	st.queue_free()


func test_a_canister_seats_in_each_cradle() -> void:
	var st: Node3D = _make()
	for n: String in ["A", "B"]:
		var slot: CanisterSlot = st.get_node("Cradle" + n) as CanisterSlot
		var c: ScrubberCanister = st.get_node("Canister" + n) as ScrubberCanister
		expect(slot.try_seat(c), "canister %s seats" % n)
		expect(slot.is_occupied() and c.is_seated(), "cradle %s occupied" % n)
		expect_near(c.global_position.distance_to(slot.global_position), 0.0, 1e-4, "canister %s stands at its cradle" % n)
		expect(not slot.try_seat(c), "a second seating is refused")
	st.queue_free()


func test_cradles_and_gauges_within_reach_of_the_standing_eye() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).global_position
	expect_near(eye.y, 1.65, 0.001, "standing eye height")
	for n: String in ["CradleA", "CradleB", "SaturationA", "SaturationB"]:
		var d: float = eye.distance_to((st.get_node(n) as Node3D).global_position)
		expect(d <= REACH_M, "%s is %.2f m from the eye" % [n, d])
	st.queue_free()


func test_footprint_and_floor() -> void:
	var st: Node3D = _make()
	var box: AABB = AABB()
	var first: bool = true
	for n: Node in st.get_node("Body").find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n as MeshInstance3D
		var b: AABB = st.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	expect_near(box.position.y, 0.0, 0.001, "floor at Y=0")
	expect(box.position.z >= -0.001, "nothing behind Z=0")
	expect(box.size.x <= 1.001 and box.size.z <= 0.55, "footprint %s within about 1.0 x 0.5 m" % box.size)
	st.queue_free()
