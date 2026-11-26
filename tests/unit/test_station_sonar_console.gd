extends TestCase
## The generated sonar console (docs/asset_process.md): structure, wiring,
## reach and line of sight from the seated eye, and the controls' behaviours
## inside the assembled scene. The brief's constraints are the thresholds.

const SCENE: String = "res://assets/models/stations/sonar_console/sonar_console.tscn"
const REACH_M: float = 0.75


func _make() -> SonarStation:
	var st: SonarStation = (load(SCENE) as PackedScene).instantiate() as SonarStation
	runner.add_child(st)
	return st


func _eye(st: SonarStation) -> Vector3:
	var seat: SonarSeat = st.get_node("Seat") as SonarSeat
	return seat.sit_point.global_position + Vector3(0, seat.eye_height, 0)


func _controls(st: SonarStation) -> Array[Interactable]:
	var out: Array[Interactable] = []
	var stack: Array[Node] = [st.get_node("Controls")]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Interactable:
			out.append(n as Interactable)
		stack.append_array(n.get_children())
	return out


## The grab box of a control in station space.
func _grab_aabb(c: Interactable) -> AABB:
	var shape_node: CollisionShape3D = c.get_node("Grab/Shape") as CollisionShape3D
	var box: BoxShape3D = shape_node.shape as BoxShape3D
	var local: AABB = AABB(-box.size * 0.5, box.size)
	return shape_node.global_transform * local


func test_station_is_wired() -> void:
	var st: SonarStation = _make()
	expect(st.wheel is Trackball, "the hydrophone input is the trackball")
	expect(st.headset != null, "headset wired")
	var seat: SonarSeat = st.get_node_or_null("Seat") as SonarSeat
	expect(seat != null and seat.sit_point != null, "seat with a sit point")
	expect(seat != null and seat.headset == st.headset, "the seat puts on the station's headset")
	expect((st.get_node("ScreenMount/Chart") as FlatChart) != null, "bearing chart mounted")
	for g: String in ["SignalGauge", "BearingGauge", "NoiseGauge", "BearingRateGauge"]:
		expect(st.get_node_or_null("Gauges/" + g) is Gauge, "%s present" % g)
	st.queue_free()


func test_every_function_has_its_control() -> void:
	var st: SonarStation = _make()
	expect(st.get_node_or_null("Controls/ActiveSonar") is SwitchLever, "active sonar toggle")
	for k: String in ["ZoomIn", "ZoomOut", "RotateLeft", "RotateRight"]:
		expect(st.get_node_or_null("Controls/MapKeys/" + k) is PushButton, "map key %s" % k)
	st.queue_free()


func test_controls_are_in_reach_of_the_seated_eye() -> void:
	var st: SonarStation = _make()
	var eye: Vector3 = _eye(st)
	var controls: Array[Interactable] = _controls(st)
	expect_eq(controls.size(), 6, "toggle, trackball and four keys")
	for c: Interactable in controls:
		var d: float = eye.distance_to(_grab_aabb(c).get_center())
		expect(d <= REACH_M, "%s is %.2f m from the eye" % [c.name, d])
	st.queue_free()


func test_grab_boxes_do_not_overlap() -> void:
	var st: SonarStation = _make()
	var controls: Array[Interactable] = _controls(st)
	for i: int in range(controls.size()):
		for j: int in range(i + 1, controls.size()):
			expect(not _grab_aabb(controls[i]).grow(-0.0005).intersects(_grab_aabb(controls[j]).grow(-0.0005)),
				"%s and %s grab boxes overlap" % [controls[i].name, controls[j].name])
	st.queue_free()


func test_no_control_hides_another_from_the_eye() -> void:
	var st: SonarStation = _make()
	var eye: Vector3 = _eye(st)
	var controls: Array[Interactable] = _controls(st)
	for c: Interactable in controls:
		var target: Vector3 = _grab_aabb(c).get_center()
		for other: Interactable in controls:
			if other == c:
				continue
			var hit: Variant = _grab_aabb(other).intersects_segment(eye, target)
			expect(hit == null, "%s blocks the view of %s" % [other.name, c.name])
	st.queue_free()


func test_screen_and_dials_face_the_seated_eye() -> void:
	var st: SonarStation = _make()
	var eye: Vector3 = _eye(st)
	var chart: FlatChart = st.get_node("ScreenMount/Chart") as FlatChart
	# The quad's visible side faces its +Z after FlatChart turns itself.
	var n: Vector3 = chart.global_transform.basis.z.normalized()
	var to_eye: Vector3 = (eye - chart.global_position).normalized()
	expect(rad_to_deg(n.angle_to(to_eye)) <= 25.0, "screen within 25 degrees of the eye (%.0f)" % rad_to_deg(n.angle_to(to_eye)))
	for g: Node in st.get_node("Gauges").get_children():
		var gn: Vector3 = (g as Node3D).global_transform.basis.z.normalized()
		var ge: Vector3 = (eye - (g as Node3D).global_position).normalized()
		expect(rad_to_deg(gn.angle_to(ge)) <= 45.0, "%s readable from the seat" % g.name)
	st.queue_free()


func test_trackball_in_the_station_trains_the_bearing() -> void:
	var st: SonarStation = _make()
	var tb: Trackball = st.wheel as Trackball
	tb.begin_interaction()
	tb.drag(Vector2(40, 0))
	tb.end_interaction()
	expect(st.bearing_deg() > 5.0 and st.bearing_deg() < 20.0, "40 px right swings the bearing clockwise (%.1f)" % st.bearing_deg())
	st.queue_free()


func test_toggle_bat_stays_inside_its_guard() -> void:
	var st: SonarStation = _make()
	var sw: SwitchLever = st.get_node("Controls/ActiveSonar") as SwitchLever
	var bat: Node3D = sw.get_node("Pivot/Bat") as Node3D
	var mesh: MeshInstance3D = bat.get_child(0) as MeshInstance3D
	for v: float in [sw.min_value, sw.max_value]:
		sw.host_set_value(v)
		var aabb: AABB = sw.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		expect(absf(aabb.position.y) <= 0.034 and absf(aabb.end.y) <= 0.034, "bat within the 64 mm guard at %f (%s)" % [v, aabb])
	st.queue_free()


func test_active_sonar_lamp_follows_the_switch() -> void:
	var st: SonarStation = _make()
	var sw: SwitchLever = st.get_node("Controls/ActiveSonar") as SwitchLever
	expect(sw.indicator != null, "ActiveSonar has its indicator set")
	sw.host_set_value(sw.min_value)
	expect(not sw.indicator.is_lit(), "lamp dark at off")
	sw.host_set_value(sw.max_value)
	expect(sw.indicator.is_lit(), "lamp lit at on")
	st.queue_free()


## The program's sonar desk is 0.65 m across (brief constraint footprint_m): the body, collision and the
## headset on its hook all stay inside it.
func test_console_fits_the_sonar_desk_width() -> void:
	var st: SonarStation = _make()
	var coll: Node = st.get_node("Collision")
	for c: Node in coll.get_children():
		var cs: CollisionShape3D = c as CollisionShape3D
		var half: float = (cs.shape as BoxShape3D).size.x * 0.5
		expect(absf(cs.position.x) + half <= 0.325 + 0.001, "%s collision within 650 mm" % c.name)
	st.queue_free()
