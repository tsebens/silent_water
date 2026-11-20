extends TestCase


func test_beam_is_sharp() -> void:
	expect_near(SonarStation.beam_gain_db(90.0, 90.0), 0.0, 0.001, "on bearing")
	var at_30: float = SonarStation.beam_gain_db(30.0, 0.0)
	var at_60: float = SonarStation.beam_gain_db(60.0, 0.0)
	var at_90: float = SonarStation.beam_gain_db(90.0, 0.0)
	expect(at_30 > -4.0 and at_30 < -1.0, "30° off: %f dB" % at_30)
	expect(at_60 > -12.0 and at_60 < -8.0, "60° off: %f dB" % at_60)
	expect(at_90 < -20.0, "abeam: %f dB" % at_90)
	expect(SonarStation.beam_gain_db(180.0, 0.0) < -80.0, "astern")


func test_beam_wraps_around() -> void:
	expect_near(SonarStation.beam_gain_db(350.0, 10.0), SonarStation.beam_gain_db(0.0, 20.0), 0.001)


func test_bearing_of_points() -> void:
	expect_near(SonarStation.bearing_of(Vector3(0, 0, -10)), 0.0, 0.001, "dead ahead")
	expect_near(SonarStation.bearing_of(Vector3(10, 0, 0)), 90.0, 0.001, "starboard")
	expect_near(SonarStation.bearing_of(Vector3(0, 5, 10)), 180.0, 0.001, "astern")
	expect_near(SonarStation.bearing_of(Vector3(-10, 0, 0)), 270.0, 0.001, "port")


func test_wheel_turns_bearing() -> void:
	var w: HydrophoneWheel = HydrophoneWheel.new()
	w.degrees_per_turn = 120.0
	var v: float = 0.0
	var r: float = 120.0
	for i: int in range(64):
		var a0: float = TAU * float(i) / 64.0
		var a1: float = TAU * float(i + 1) / 64.0
		v = w._drag_to_value(v, Vector2(cos(a1), sin(a1)) * r - Vector2(cos(a0), sin(a0)) * r)
	# The first mouse step only sets the direction, so one step is uncounted.
	expect_near(v, 120.0, 3.0, "one clockwise turn = 120°")
	w.free()


func test_outside_level_at_sub() -> void:
	# A 135 dB call 100 m away arrives at 105 dB (30 dB of spreading).
	expect_near(OutsideAudio.level_at_sub(135.0, Vector3(0, 0, 100)), 105.0, 0.01)


func _tilted_disc() -> MeshInstance3D:
	# A thin disc whose axle is tilted 15° off +Z, like the exported wheel.
	var tilt: Basis = Basis(Vector3.RIGHT, deg_to_rad(15.0))
	var verts: PackedVector3Array = PackedVector3Array()
	var idx: PackedInt32Array = PackedInt32Array()
	for i: int in range(16):
		var a: float = TAU * float(i) / 16.0
		verts.append(tilt * Vector3(cos(a) * 0.16, sin(a) * 0.16, 0.05))
		verts.append(tilt * Vector3(cos(a) * 0.16, sin(a) * 0.16, -0.05))
	for i: int in range(32):
		idx.append_array([i, (i + 1) % 32, (i + 2) % 32])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func test_wheel_mesh_spins_about_its_axle() -> void:
	var mi: MeshInstance3D = _tilted_disc()
	var w: HydrophoneWheel = HydrophoneWheel.new()
	w.wheel = mi
	var axle: Vector3 = HydrophoneWheel.axle_of(mi)
	var tilt_axis: Vector3 = Basis(Vector3.RIGHT, deg_to_rad(15.0)) * Vector3.BACK
	expect(axle.dot(tilt_axis) > 0.999, "axle found: %s" % str(axle))
	w._apply_visual(0.0)
	var b0: Basis = mi.transform.basis
	w._apply_visual(30.0)  # a quarter of a 120° turn... of bearing: 90° of wheel
	var rel: Basis = b0.inverse() * mi.transform.basis
	# Rotation relative to the start is purely about the axle.
	var q: Quaternion = rel.get_rotation_quaternion()
	expect(q.get_axis().cross(axle).length() < 0.001 or absf(q.get_angle()) < 0.001, "rotation about axle only")
	expect_near(absf(q.get_angle()), deg_to_rad(90.0), 0.001, "angle")
	# Increasing bearing turns clockwise seen from the operator (axle toward them).
	expect(q.get_axis().dot(axle) < -0.999, "clockwise: sign matches bearing")
	expect(is_equal_approx(w.bearing_deg(), 0.0), "bearing_deg untouched by visual")
	w.free()
	mi.free()
