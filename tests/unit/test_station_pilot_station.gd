extends TestCase
## The generated pilot station, shell and seat (docs/asset_process.md, #481): the scene loads, the seat resolves,
## every instrument anchor exists in the order Tristan set, the strip leaves the apex clear, and every anchor faces up
## toward the seated eye. The instruments themselves are the next arc's.

const SCENE: String = "res://assets/models/stations/pilot_station/pilot_station.tscn"
const GAP_M: float = 0.6
const EYE: Vector3 = Vector3(0.0, 1.15, 0.0)
const LEFT: Array[String] = ["DepthFinder", "Multidisplay", "SpeedGauge"]
const RIGHT: Array[String] = ["Navball", "ExternalLightSwitch", "ExternalColourSwitch", "CabinLightSwitch",
		"CabinColourSwitch", "BilgeLamp", "Co2Lamp", "LowO2Lamp", "NoiseRepeater"]


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
	for name: String in LEFT + RIGHT + ["HologramAnchor"]:
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
	var df: Node3D = _anchor(st, "DepthFinder")
	expect(holo.global_position.y > df.global_position.y + 0.1, "the hologram stands above the depth finder")
	expect(absf(holo.global_position.x - df.global_position.x) < 0.15, "the hologram is over the depth finder")
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
