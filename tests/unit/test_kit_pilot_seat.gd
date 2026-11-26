extends TestCase
## The generated pilot seat (docs/asset_process.md): the scene loads, both joysticks
## resolve with a stick to tilt, and there is a sit point.

const SCENE: String = "res://assets/models/furniture/pilot_seat/pilot_seat.tscn"


func _seat() -> Node3D:
	var packed: PackedScene = load(SCENE) as PackedScene
	expect(packed != null, "pilot_seat.tscn loads")
	var seat: Node3D = packed.instantiate() as Node3D
	runner.add_child(seat)
	return seat


func test_scene_has_sit_point() -> void:
	var seat: Node3D = _seat()
	expect(seat.get_node_or_null("SitPoint") is Node3D, "SitPoint exists")
	seat.queue_free()


func test_both_joysticks_resolve_with_a_stick() -> void:
	var seat: Node3D = _seat()
	for jname: String in ["ThrottleJoystick", "FlightJoystick"]:
		var joy: Node3D = seat.get_node_or_null(jname) as Node3D
		expect(joy != null, "%s exists" % jname)
		if joy == null:
			continue
		expect(joy.get_node_or_null("Frame/Stick") != null, "%s has Frame/Stick" % jname)
		expect(absf(joy.position.y - 0.66) < 0.01, "%s stands on the armrest" % jname)
		# the stick rises up (+Y), the sitter facing -Z
		var up: Vector3 = joy.global_transform.basis * Vector3(0, 0, 1)
		expect(up.dot(Vector3.UP) > 0.99, "%s stick points up" % jname)
	var left: Node3D = seat.get_node("ThrottleJoystick") as Node3D
	var right: Node3D = seat.get_node("FlightJoystick") as Node3D
	expect(left.position.x < 0.0 and right.position.x > 0.0, "throttle on the left, planes and rudder on the right")
	seat.queue_free()


func test_four_switch_anchors_on_the_armrest_panels() -> void:
	var seat: Node3D = _seat()
	var names: Dictionary = {
		"ExternalLightSwitch": 1.0, "ExternalColourSwitch": 1.0,
		"CabinLightSwitch": -1.0, "CabinColourSwitch": -1.0}
	for aname: String in names:
		var a: Node3D = seat.get_node_or_null(aname) as Node3D
		expect(a != null, "%s exists" % aname)
		if a == null:
			continue
		var side: float = names[aname]
		expect(a.position.x * side > 0.3, "%s is outboard on its side" % aname)
		expect(absf(a.position.y - 0.662) < 0.005, "%s sits on the armrest panel top" % aname)
		# the toggle's face (+Z) points up; its lamp side (+Y) points toward the sitter (+Z)
		var face: Vector3 = a.transform.basis * Vector3(0, 0, 1)
		var lamp: Vector3 = a.transform.basis * Vector3(0, 1, 0)
		expect(face.dot(Vector3.UP) > 0.99, "%s toggle face is up" % aname)
		expect(lamp.dot(Vector3(0, 0, 1)) > 0.99, "%s lamp side faces the sitter" % aname)
	seat.queue_free()
