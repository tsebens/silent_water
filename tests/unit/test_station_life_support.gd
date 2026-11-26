extends TestCase
## The generated life-support wall unit (docs/asset_process.md): every instance resolves, a canister seats in each
## cradle and in all six storage holes, and the cradles, gauges, fan toggle and storage tops are within reach of the
## standing eye.

const SCENE: String = "res://assets/models/stations/life_support/life_support.tscn"
const REACH_M: float = 0.75
const SHELF_DEG: float = 42.0
## A point on the shelf surface (m) and the shelf's outward normal: the base's front edge, up and back.
const SHELF_EDGE: Vector3 = Vector3(0.0, 1.02503, 0.5)


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
	for n: String in ["O2Gauge", "Co2LevelGauge", "Co2RateGauge", "NoiseRepeater"]:
		expect(st.get_node_or_null(n) is Gauge, "%s is a Gauge" % n)
	expect((st.get_node("Co2RateGauge") as Gauge).readout_b != &"", "the CO2 rate gauge has a second needle")
	expect(st.get_node_or_null("FanToggle") is SwitchLever, "FanToggle is a SwitchLever")
	expect(st.get_node_or_null("FanLamp") is IndicatorLamp, "FanLamp is an IndicatorLamp")
	for n: String in ["O2AlarmLamp", "Co2AlarmLamp"]:
		expect(st.get_node_or_null(n) is IndicatorLamp, "%s is an IndicatorLamp" % n)
	expect_near((st.get_node("FanToggle") as SwitchLever).initial_value, 1.0, 1e-6, "the fan toggle is on by default")
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


func test_a_canister_seats_in_all_six_storage_holes() -> void:
	var st: Node3D = _make()
	var filled: int = 0
	for i: int in range(1, 7):
		var slot: CanisterSlot = st.get_node("Storage%d" % i) as CanisterSlot
		expect(slot != null, "Storage%d is a CanisterSlot" % i)
		var stored: ScrubberCanister = st.get_node_or_null("Stored%d" % i) as ScrubberCanister
		var c: ScrubberCanister = stored
		if c == null:
			c = (load("res://assets/models/furniture/scrubber_canister/scrubber_canister.tscn") as PackedScene).instantiate() as ScrubberCanister
			st.add_child(c)
		else:
			filled += 1
		expect(slot.try_seat(c), "a canister seats in hole %d" % i)
		# Seated, the canister's axis is the shelf's normal and its top sits just below the surface.
		var up: Vector3 = c.global_transform.basis.y
		var n: Vector3 = Vector3(0.0, cos(deg_to_rad(SHELF_DEG)), sin(deg_to_rad(SHELF_DEG)))
		expect(up.dot(n) > 0.999, "hole %d: canister stands along the shelf normal" % i)
		var top: Vector3 = c.global_position + up * 0.3
		expect_near((top - SHELF_EDGE).dot(n), -0.015, 0.003, "hole %d: the canister top just below the shelf" % i)
	expect(filled == 4, "four holes hold a canister on a new sub (%d)" % filled)
	st.queue_free()


func test_the_carriages_are_at_crew_eye_level() -> void:
	var st: Node3D = _make()
	for n: String in ["CanisterA", "CanisterB"]:
		var c: Node3D = st.get_node(n) as Node3D
		var mid: float = c.global_position.y + 0.15
		expect_near(mid, 1.65, 0.05, "%s stands at eye level (%.2f m)" % [n, mid])
	st.queue_free()


func test_fan_toggle_and_storage_tops_within_reach() -> void:
	var st: Node3D = _make()
	var eye: Vector3 = (st.get_node("OperatorEye") as Node3D).global_position
	var tog: float = eye.distance_to((st.get_node("FanToggle") as Node3D).global_position)
	expect(tog <= REACH_M, "the fan toggle is %.2f m from the eye" % tog)
	for i: int in range(1, 7):
		var slot: Node3D = st.get_node("Storage%d" % i) as Node3D
		var top: Vector3 = slot.global_position + slot.global_transform.basis.y * 0.3
		var d: float = eye.distance_to(top)
		expect(d <= REACH_M, "storage top %d is %.2f m from the eye" % [i, d])
	st.queue_free()


func test_saturation_bars_are_on_the_housing_beside_the_pockets() -> void:
	var st: Node3D = _make()
	var a: Node3D = st.get_node("SaturationA") as Node3D
	var b: Node3D = st.get_node("SaturationB") as Node3D
	var ca: Node3D = st.get_node("CanisterA") as Node3D
	var cb: Node3D = st.get_node("CanisterB") as Node3D
	expect(a.global_position.x < ca.global_position.x - 0.1, "bar A is outside canister A's pocket, on its own side")
	expect(b.global_position.x > cb.global_position.x + 0.1, "bar B is outside canister B's pocket, on its own side")
	expect_near(a.global_position.y + 0.116, 1.65, 0.01, "bar A is centred on eye level")
	# The bars stand on the carriage face, in front of the pockets' back walls.
	expect(a.global_position.z > ca.global_position.z, "bar A is in front of its canister's axis, on the face")
	st.queue_free()


func test_saturation_bars_read_remaining_capacity_descending() -> void:
	var st: Node3D = _make()
	for n: String in ["SaturationA", "SaturationB"]:
		var bar: Node = st.get_node(n)
		var want: StringName = &"capacity_a" if n == "SaturationA" else &"capacity_b"
		expect_eq(bar.get("readout"), want, "%s reads %s" % [n, want])
		expect(bar.get("descending") as bool, "%s is descending" % n)
		expect_near(bar.get("warn_at") as float, 0.5, 0.0001, "%s warn_at" % n)
		expect_near(bar.get("alarm_at") as float, 0.15, 0.0001, "%s alarm_at" % n)
		expect_eq(bar.call("swatch_for", 1.0), &"light_ok", "%s: a fresh canister is green" % n)
		expect_eq(bar.call("swatch_for", 0.3), &"light_warn", "%s: half spent is amber" % n)
		expect_eq(bar.call("swatch_for", 0.1), &"light_alarm", "%s: nearly spent is red" % n)
	st.queue_free()


func test_fan_toggle_is_in_the_shelf_corner_with_its_lamp() -> void:
	var st: Node3D = _make()
	var tog: Node3D = st.get_node("FanToggle") as Node3D
	var lamp: Node3D = st.get_node("FanLamp") as Node3D
	expect(tog.global_position.x > 0.25, "the toggle is on the right")
	expect(lamp.global_position.x > tog.global_position.x, "the run lamp is beside it, outboard")
	expect(tog.global_position.y < 1.4, "the toggle is on the shelf, below the carriage pockets")
	expect(tog.global_transform.basis.z.dot(Vector3(0.0, cos(deg_to_rad(SHELF_DEG)), sin(deg_to_rad(SHELF_DEG)))) > 0.999,
			"the toggle faces out of the shelf surface")
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
	expect(box.size.x <= 1.001 and box.size.z <= 0.61, "footprint %s: 0.5 m base, overhanging top block" % box.size)
	st.queue_free()
