extends TestCase
## The kit breaker module: a BreakerSwitch on a grey plate with a hinged handle and a status lamp.

const SCENE: String = "res://assets/models/kit/breaker_module/breaker_module.tscn"
const B := PowerSystem.BreakerState


func _make() -> BreakerSwitch:
	var s: BreakerSwitch = (load(SCENE) as PackedScene).instantiate() as BreakerSwitch
	runner.add_child(s)
	return s


func _bounds(n: Node3D, root: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null:
			var b: AABB = root.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(c.get_children())
	return out


func test_wiring_is_present() -> void:
	var s: BreakerSwitch = _make()
	expect(s != null, "root is a BreakerSwitch")
	expect(s.handle != null and s.handle == s.get_node_or_null("Hinge/Handle"), "handle is the Handle node")
	expect(s.lamp != null and s.lamp == s.get_node_or_null("IndicatorLamp/Lens/IndicatorLampLens"),
		"lamp is the indicator lamp's lens")
	expect(s.get_node_or_null("Body") != null, "plate body present")
	s.queue_free()


func test_handle_reaches_up_mid_and_limp() -> void:
	var s: BreakerSwitch = _make()
	var tip: Callable = func() -> Vector3:
		return s.global_transform.affine_inverse() * (s.handle.global_transform * Vector3(0, 0, 0.04))
	s.handle.rotation.x = deg_to_rad(s.handle_angle_deg(B.ON))
	var up: Vector3 = tip.call()
	s.handle.rotation.x = deg_to_rad(s.handle_angle_deg(B.TRIPPED))
	var mid: Vector3 = tip.call()
	s.handle.rotation.x = deg_to_rad(s.handle_angle_deg(B.BLOWN))
	var limp: Vector3 = tip.call()
	s.handle.rotation.x = deg_to_rad(s.handle_angle_deg(B.OFF))
	var down: Vector3 = tip.call()
	expect(up.y > 0.015, "on: handle tip is up: %s" % up)
	expect(absf(mid.y) < 0.001 and mid.z > up.z, "tripped: handle straight out: %s" % mid)
	expect(limp.y < -0.03, "blown: handle hangs limp, down: %s" % limp)
	expect(down.y < -0.015, "off: handle tip is down: %s" % down)
	s.queue_free()


func test_lamp_takes_a_state_colour() -> void:
	var s: BreakerSwitch = _make()
	s.refresh()
	var mat: BaseMaterial3D = s.lamp.material_override as BaseMaterial3D
	expect(mat != null and mat.emission_enabled, "on with no power system: lamp lit")
	s.queue_free()


func test_footprint_and_stand_out_match_the_entry() -> void:
	var s: BreakerSwitch = _make()
	var worst: AABB = _bounds(s, s)
	for st: int in [B.OFF, B.ON, B.TRIPPED, B.BLOWN]:
		s.handle.rotation.x = deg_to_rad(s.handle_angle_deg(st))
		worst = worst.merge(_bounds(s, s))
	expect(worst.size.x <= 0.1501 and worst.size.y <= 0.1501, "within 150 x 150 mm: %s" % worst)
	expect(worst.position.z >= -0.0001, "nothing behind the mount face: %s" % worst)
	expect(worst.end.z <= 0.0601, "no more than 60 mm out, handle extremes included: %s" % worst)
	s.queue_free()
