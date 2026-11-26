extends TestCase
## The generated pilot station, shell and seat (docs/asset_process.md, #481): the scene loads, the seat resolves,
## every instrument anchor exists in the order Tristan set, the strip leaves the apex clear, and every anchor faces up
## toward the seated eye. The instruments themselves are the next arc's.

const SCENE: String = "res://assets/models/stations/pilot_station/pilot_station.tscn"
const GAP_M: float = 0.6
const EYE: Vector3 = Vector3(0.0, 1.15, 0.0)
## #605 stopgap: the depth finder is dropped, the two gauges share a facet and the lamps sit under the switches, so the
## strip fits the true hemisphere. LEFT and RIGHT are the instrument that leads each facet, from the gap outward;
## the others are listed in ALSO_LEFT and ALSO_RIGHT.
const LEFT: Array[String] = ["Multidisplay", "SpeedGauge"]
const RIGHT: Array[String] = ["Navball", "ExternalLightSwitch"]
const ALSO_LEFT: Array[String] = ["NoiseRepeater"]
const ALSO_RIGHT: Array[String] = ["ExternalColourSwitch", "CabinLightSwitch", "CabinColourSwitch", "BilgeLamp", "Co2Lamp", "LowO2Lamp"]


func _make() -> Node3D:
	var packed: PackedScene = load(SCENE) as PackedScene
	expect(packed != null, "pilot_station.tscn loads")
	var st: Node3D = packed.instantiate() as Node3D
	runner.add_child(st)
	return st


func _meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n as MeshInstance3D)
	for c: Node in n.get_children():
		_meshes(c, out)


func _anchor(st: Node3D, name: String) -> Node3D:
	var a: Node3D = st.get_node_or_null("Anchors/" + name) as Node3D
	expect(a != null, "anchor %s exists" % name)
	return a


func test_seat_resolves() -> void:
	var st: Node3D = _make()
	expect(st.get_node_or_null("Seat/SitPoint") is Node3D, "the seat's sit point resolves")
	expect(st.get_node_or_null("Seat/ThrottleJoystick/Frame/Stick") != null, "the throttle stick resolves")
	expect(st.get_node_or_null("Seat/FlightJoystick/Frame/Stick") != null, "the flight stick resolves")
	st.queue_free()


func test_every_anchor_exists_and_faces_the_eye() -> void:
	var st: Node3D = _make()
	for name: String in LEFT + RIGHT + ALSO_LEFT + ALSO_RIGHT + ["HologramAnchor"]:
		var a: Node3D = _anchor(st, name)
		if a == null:
			continue
		var out: Vector3 = a.global_transform.basis.z
		expect(out.is_equal_approx(out.normalized()), "%s has a unit +Z" % name)
		if name == "HologramAnchor":
			expect(a.global_transform.basis.y.dot(Vector3.UP) > 0.99, "the hologram anchor stands up")
			continue
		expect(out.dot(Vector3.UP) > 0.5, "%s faces up" % name)
		expect(out.dot((EYE - a.global_position).normalized()) > 0.55, "%s faces the seated eye" % name)
		expect(a.global_position.y > 0.5 and a.global_position.y < 0.95, "%s is at knee height" % name)
	st.queue_free()


func test_wings_run_from_the_gap_outward_in_order() -> void:
	var st: Node3D = _make()
	var last: float = 0.0
	for name: String in LEFT:
		var a: Node3D = _anchor(st, name)
		expect(a.global_position.x < 0.0, "%s is on the left wing" % name)
		expect(absf(a.global_position.x) > last, "%s is further out than the one before" % name)
		last = absf(a.global_position.x)
	last = 0.0
	for name: String in RIGHT:
		var a: Node3D = _anchor(st, name)
		expect(a.global_position.x > 0.0, "%s is on the right wing" % name)
		expect(a.global_position.x > last - 0.0001, "%s is no nearer the gap than the one before" % name)
		last = a.global_position.x
	var holo: Node3D = _anchor(st, "HologramAnchor")
	var md: Node3D = _anchor(st, "Multidisplay")
	expect(holo.global_position.y > md.global_position.y + 0.1, "the hologram stands above the multidisplay")
	expect(absf(holo.global_position.x - md.global_position.x) < 0.15, "the hologram is over the multidisplay")
	expect(st.get_node_or_null("Anchors/DepthFinder") == null, "the depth finder is dropped until the strip is redesigned (#633)")
	st.queue_free()


func test_nothing_crosses_the_gap_or_rises_above_the_hologram() -> void:
	var st: Node3D = _make()
	var meshes: Array[MeshInstance3D] = []
	_meshes(st.get_node("Strip"), meshes)
	expect(not meshes.is_empty(), "the strip has meshes")
	var holo_top: float = (_anchor(st, "HologramAnchor").global_position.y) + 0.2
	for m: MeshInstance3D in meshes:
		var box: AABB = m.global_transform * m.get_aabb()
		expect(box.size.y > 0.0, "the strip mesh has a size")
		expect(box.end.y <= holo_top + 0.001, "nothing on the strip is above the hologram's top")
	# per vertex: every triangle's points keep out of the apex gap
	for m: MeshInstance3D in meshes:
		var mesh: Mesh = m.mesh
		for s: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v: Vector3 in verts:
				var p: Vector3 = m.global_transform * v
				expect(absf(p.x) >= GAP_M * 0.5 - 0.001, "no strip vertex inside the gap (%.3f)" % p.x)
	st.queue_free()


# ---- the instruments (#482): every anchor is the instrument's own scene ----

const REACH_M: float = 0.75
const TOGGLES: Array[String] = ["ExternalLightSwitch", "ExternalColourSwitch", "CabinLightSwitch", "CabinColourSwitch"]
const LAMPS: Array[String] = ["BilgeLamp", "Co2Lamp", "LowO2Lamp"]


func test_instruments_resolve_with_their_behaviours() -> void:
	var st: Node3D = _make()
	expect(_anchor(st, "Multidisplay").get_node_or_null("Screen") is MultiDisplay, "the multidisplay's screen resolves")
	expect(_anchor(st, "Navball") is Navball, "the navball is a Navball")
	expect(_anchor(st, "SpeedGauge") is Gauge, "the speed gauge is a Gauge")
	expect(_anchor(st, "NoiseRepeater") is Gauge, "the noise repeater is a Gauge")
	st.queue_free()


func test_gauges_stand_off_their_facets() -> void:
	# #596: the build declares each gauge 2 mm off its facet (the mount gap), so the dial face is not coplanar with it.
	var yaml: String = FileAccess.get_file_as_string("res://assets/models/stations/pilot_station/component.yaml")
	expect(yaml.contains("Anchors/NoiseRepeater") and yaml.contains("Anchors/SpeedGauge"), "both gauges are declared mounts")
	expect(not yaml.contains("offset_mm: 0"), "no declared mount sits on its host face")


func test_toggles_and_lamps_resolve() -> void:
	var st: Node3D = _make()
	for name: String in TOGGLES:
		expect(_anchor(st, name) is SwitchLever, "%s is a switch" % name)
	for name: String in LAMPS:
		expect(_anchor(st, name) is IndicatorLamp, "%s is a lamp" % name)
	st.queue_free()


func test_speed_gauge_scale_follows_the_physics_model() -> void:
	var st: Node3D = _make()
	var g: Gauge = _anchor(st, "SpeedGauge") as Gauge
	expect(g.scale_readout == &"top_speed", "the speed scale comes from top_speed")
	expect(g.readout == &"speed" and g.readout_b == &"engine_output", "speed and throttle needles")
	st.queue_free()


func test_toggles_and_lamps_are_distinct_and_in_reach() -> void:
	var st: Node3D = _make()
	var seat: Node3D = st.get_node("Seat") as Node3D
	var joys: Array[Node3D] = [seat.get_node("ThrottleJoystick") as Node3D, seat.get_node("FlightJoystick") as Node3D]
	for name: String in TOGGLES:
		var a: Node3D = _anchor(st, name)
		var nearest: float = INF
		for j: Node3D in joys:
			nearest = minf(nearest, a.global_position.distance_to(j.global_position))
		expect(nearest <= REACH_M, "%s is within reach of the nearer joystick hand (%.2f m)" % [name, nearest])
		expect((a as SwitchLever).label != "", "%s carries a label" % name)
		expect((a as SwitchLever).indicator != null, "%s is the lit guarded toggle (its indicator is set)" % name)
	for lamp_name: String in LAMPS:
		var lamp: Node3D = _anchor(st, lamp_name)
		expect(lamp is IndicatorLamp and not (lamp is SwitchLever), "%s stays a plain warning lamp" % lamp_name)
	for i: int in LAMPS.size():
		for k: int in range(i + 1, LAMPS.size()):
			expect(_anchor(st, LAMPS[i]).global_position.distance_to(_anchor(st, LAMPS[k]).global_position) > 0.03, "the lamps are apart")
	st.queue_free()


func test_lamp_drivers_light_the_lamps() -> void:
	var st: Node3D = _make()
	var bilge: ThresholdLamp = st.get_node("Drivers/BilgeLampDriver") as ThresholdLamp
	expect(bilge.lamp == _anchor(st, "BilgeLamp"), "the bilge driver is bound to its lamp")
	expect(bilge.readout == &"bilge_water_t" and bilge.threshold_of == &"bilge_limit", "bilge reads a quarter of the limit")
	for d: String in ["Co2LampDriver", "LowO2LampDriver"]:
		var drv: ThresholdLamp = st.get_node("Drivers/" + d) as ThresholdLamp
		expect(drv != null and drv.readout == &"", "%s is unwired and never lights" % d)
		expect(not drv.is_alarm(), "%s stays dark" % d)
	st.queue_free()
