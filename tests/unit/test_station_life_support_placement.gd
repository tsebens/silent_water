extends TestCase
## The life support station is placed from the program (SubLayout) on the port wall of engineering and is bound to
## the sub's life support readouts and alarm driver (arc #579, concept #577).

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")
const STATION: String = "Stations/LifeSupport/Station"

var interior: Node3D
var readouts: LifeSupportReadouts


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)
	readouts = interior.get_node("LifeSupportReadouts") as LifeSupportReadouts


func after_each() -> void:
	interior.free()


func _station() -> Node3D:
	return interior.get_node(STATION) as Node3D


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


func test_exactly_one_station_at_the_program_position() -> void:
	var found: Array[Node] = interior.find_children("O2Gauge", "", true, false)
	expect_eq(found.size(), 1, "one life support station")
	var fp: Rect2 = SubLayout.footprint(&"life_support")
	var p: Vector3 = _station().global_position
	expect_near(p.z, SubLayout.position(&"life_support").z, 0.001, "along the hull at the program's z")
	expect_near(p.y, 0.0, 0.001, "on the floor")
	expect(p.x < 0.0, "port")
	expect(fp.grow(0.3).has_point(Vector2(p.x, p.z)), "the back is at the footprint")
	expect(_station().global_basis.z.is_equal_approx(Vector3(1, 0, 0)), "the operator faces the aisle (+X)")


func test_body_is_inside_the_hull_and_clear_of_neighbours() -> void:
	var fp: Rect2 = _plan(_station().get_node("Body"))
	for id: StringName in [&"ballast", &"engineering", &"lockers", &"scanner", &"bilge"]:
		expect(not fp.intersects(SubLayout.footprint(id).grow(-0.001)), "body clear of %s" % id)
	var aisle: float = SubLayout.footprint(&"engineering").position.x - fp.end.x
	expect(aisle >= SubLayout.clearance("aisle_min_m"), "aisle %f m" % aisle)
	# The crew-height part of the unit's back is against the hull's inner surface. Its top block (2.26 m) reaches
	# into the curving hull above 2 m, as a built-in wall unit does; its operator-side face is wholly inside.
	var p: Vector3 = _station().global_position
	for dy: float in [0.3, 1.0, 1.8]:
		for dz: float in [-0.5, 0.0, 0.5]:
			expect(SubLayout.inside_hull(p.x + 0.001, p.y + dy, p.z + dz), "back inside the hull at y %f dz %f" % [dy, dz])
	for dz: float in [-0.5, 0.0, 0.5]:
		expect(SubLayout.inside_hull(fp.end.x, 2.0, p.z + dz), "the face is inside the hull at dz %f" % dz)


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().process_frame


func test_bars_follow_the_readouts() -> void:
	var a: LinearGauge = _station().get_node("SaturationA") as LinearGauge
	readouts.saturation_a = 0.0
	await _frames(90)
	expect_near(a.shown_fraction(), 1.0, 0.05, "a fresh canister is a full bar")
	readouts.saturation_a = 0.6
	await _frames(90)
	expect_near(a.shown_fraction(), 0.4, 0.05, "the bar drops with the capacity (%f)" % a.shown_fraction())
	for n: String in ["O2Gauge", "Co2LevelGauge", "Co2RateGauge"]:
		expect((_station().get_node(n) as Gauge).source_group == LifeSupportReadouts.GROUP, "%s reads the readouts group" % n)
	expect_near(readouts.readout(&"capacity_a"), 0.4, 1e-6, "capacity readout")


func test_gauge_needles_move_with_o2_and_co2() -> void:
	var o2: Gauge = _station().get_node("O2Gauge") as Gauge
	var co2: Gauge = _station().get_node("Co2LevelGauge") as Gauge
	readouts.o2_level = 1.0
	readouts.co2_ppm = 400.0
	await _frames(90)
	var o2_full: float = o2._needle.rotation.z
	var co2_low: float = co2._needle.rotation.z
	readouts.o2_level = 0.2
	readouts.co2_ppm = 30000.0
	await _frames(90)
	expect(not is_equal_approx(o2._needle.rotation.z, o2_full), "the O2 needle moved")
	expect(not is_equal_approx(co2._needle.rotation.z, co2_low), "the CO2 needle moved")


func test_alarm_lamps_follow_the_alarm_driver() -> void:
	var o2: IndicatorLamp = _station().get_node("O2AlarmLamp") as IndicatorLamp
	var co2: IndicatorLamp = _station().get_node("Co2AlarmLamp") as IndicatorLamp
	var driver: LifeSupportAlarmDriver = interior.get_node("LifeSupportAlarmDriver") as LifeSupportAlarmDriver
	expect(driver.get_tree().get_first_node_in_group(LifeSupportReadouts.GROUP) == readouts, "the driver reads the sub readouts")
	readouts.o2_level = 1.0
	readouts.co2_ppm = 400.0
	driver.advance(0.1)
	expect(not o2.is_lit() and not co2.is_lit(), "both dark when the air is good")
	readouts.co2_ppm = 1.0e6
	readouts.o2_level = 0.0
	driver.advance(0.0)
	var c: LifeSupportAlarmLevels.Level = readouts.co2_alarm()
	var o: LifeSupportAlarmLevels.Level = readouts.o2_alarm()
	expect(c != LifeSupportAlarmLevels.Level.OFF and o != LifeSupportAlarmLevels.Level.OFF, "both alarms are raised")
	if c == LifeSupportAlarmLevels.Level.STEADY:
		expect(co2.is_lit(), "CO2 lamp steady")
	if o == LifeSupportAlarmLevels.Level.STEADY:
		expect(o2.is_lit(), "O2 lamp steady")
	readouts.co2_ppm = 400.0
	readouts.o2_level = 1.0
	driver.advance(0.1)
	expect(not o2.is_lit() and not co2.is_lit(), "dark again when the air clears")


func test_fan_switch_drives_the_fan_state() -> void:
	var sw: SwitchLever = _station().get_node("FanToggle") as SwitchLever
	expect(readouts.fans_on and readouts.fans_running(), "the fans run on a new sub")
	sw.host_set_value(0.0)
	expect(not readouts.fans_on, "switched off")
	expect(not readouts.fans_running(), "the fans stop")
	expect_near(readouts.readout(&"fans_running"), 0.0, 1e-6, "readout follows")
	sw.host_set_value(1.0)
	expect(readouts.fans_on and readouts.fans_running(), "switched on again")
	readouts.set_fans_powered(false)
	expect(not readouts.fans_running(), "no power, no fans, even with the switch on")
