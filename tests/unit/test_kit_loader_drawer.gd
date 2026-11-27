extends TestCase
## The kit loader drawer: a LoaderDrawer root, a Slide node carrying the cradle and grab box, a DecoyCradle that seats a decoy.

const SCENE: String = "res://assets/models/kit/loader_drawer/loader_drawer.tscn"
const DECOY: String = "res://assets/models/furniture/decoy/decoy.tscn"


func _make() -> LoaderDrawer:
	var s: LoaderDrawer = (load(SCENE) as PackedScene).instantiate() as LoaderDrawer
	runner.add_child(s)
	return s


func _bounds(root: Node3D) -> AABB:
	var out: AABB = AABB()
	var first: bool = true
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		var mi: MeshInstance3D = c as MeshInstance3D
		if mi != null:
			var b: AABB = root.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
			out = b if first else out.merge(b)
			first = false
		stack.append_array(c.get_children())
	return out


func test_root_and_wiring() -> void:
	var s: LoaderDrawer = _make()
	expect(s != null and s.name == &"LoaderDrawer", "root is a LoaderDrawer")
	expect(s.body != null and s.body.name == &"Slide", "body is the Slide node")
	expect_near(s.travel_m, 0.65, 0.0001, "travel 0.65 m")
	expect(s.slide_axis.is_equal_approx(Vector3(0, 0, 1)), "slides along +Z")
	expect(s.get_node_or_null("Slide/Cradle") is DecoyCradle, "Slide/Cradle is a DecoyCradle")
	expect(s.get_node_or_null("Slide/Grab") != null, "grab box rides on the slide")
	s.queue_free()


func test_slides_with_cradle() -> void:
	var s: LoaderDrawer = _make()
	var cradle: Node3D = s.get_node("Slide/Cradle") as Node3D
	var z0: float = cradle.global_position.z
	s.begin_interaction()
	s.drive_to(1.0)
	s.end_interaction()
	expect(s.is_open(), "open at 1")
	expect_near(cradle.global_position.z - z0, 0.65, 0.001, "cradle travels 0.65 m with the drawer")
	s.queue_free()


func test_cradle_seats_a_decoy_inside_the_drawer() -> void:
	var s: LoaderDrawer = _make()
	var cradle: DecoyCradle = s.get_node("Slide/Cradle") as DecoyCradle
	var d: DecoyItem = (load(DECOY) as PackedScene).instantiate() as DecoyItem
	runner.add_child(d)
	expect(cradle.try_seat(d), "cradle seats the decoy")
	expect(cradle.is_occupied(), "cradle occupied")
	expect(d.global_position.is_equal_approx(cradle.global_position), "decoy sits at the cradle origin")
	# The decoy lies across the drawer: its length (550 mm) runs along X.
	var b: AABB = _bounds(d)
	var wb: AABB = d.global_transform * b
	expect(wb.size.x > 0.5 and wb.size.z < 0.2, "decoy lies across the drawer: %s" % wb.size)
	# The window shows it: the window is wider and taller than the decoy.
	expect(wb.size.x < 0.58 and wb.size.y < 0.19 + 0.0001 + 0.11, "decoy fits behind the window")
	var tray: AABB = _bounds(s.get_node("Slide/Drawer") as Node3D)
	expect(tray.grow(0.001).encloses(AABB(Vector3(wb.position.x, wb.position.y, wb.position.z), Vector3(wb.size.x, minf(wb.size.y, 0.16), wb.size.z))),
		"decoy body inside the drawer's extent")
	expect(not cradle.try_seat((load(DECOY) as PackedScene).instantiate() as DecoyItem), "second decoy refused")
	s.queue_free()
	d.queue_free()


func test_meshes_fit_the_footprint() -> void:
	var s: LoaderDrawer = _make()
	var b: AABB = _bounds(s)
	expect(b.size.x <= 0.8001 and b.size.y <= 0.3001, "at most 0.8 x 0.3 m: %s" % b)
	expect(b.position.z >= -0.0001 and b.end.z <= 0.4501, "closed: nothing behind the mount, within 0.45 m out: %s" % b)
	s.queue_free()
