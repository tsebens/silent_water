extends TestCase
## The sonar console is placed from the program (SubLayout): its collision footprint sits inside the program's
## sonar desk footprint and clear of countermeasures'.

const INTERIOR_SCENE: PackedScene = preload("res://src/sub/interior.tscn")

var interior: Node3D


func before_each() -> void:
	interior = INTERIOR_SCENE.instantiate() as Node3D
	runner.add_child(interior)


func after_each() -> void:
	interior.free()


## The console's collision footprint on the floor plan: x across the hull, y along it (the Rect2 convention of SubLayout).
func _console_footprint() -> Rect2:
	var body: Node3D = interior.get_node("Stations/Sonar/Collision") as Node3D
	var out: Rect2 = Rect2()
	var first: bool = true
	for child: Node in body.get_children():
		var cs: CollisionShape3D = child as CollisionShape3D
		var box: BoxShape3D = cs.shape as BoxShape3D
		var c: Vector3 = cs.global_position
		var r: Rect2 = Rect2(c.x - box.size.x / 2.0, c.z - box.size.z / 2.0, box.size.x, box.size.z)
		out = r if first else out.merge(r)
		first = false
	return out


func test_console_is_at_the_program_desk() -> void:
	var origin: Vector3 = SubLayout.position(&"sonar")
	var console: Node3D = interior.get_node("Stations/Sonar") as Node3D
	expect_near(console.position.x, origin.x, 0.2, "x at the sonar desk")
	expect_near(console.position.y, origin.y, 0.001, "on the floor")
	expect(absf(console.position.z - SubLayout.footprint(&"sonar").position.y) < 0.001, "back at the desk's forward edge (z=%f)" % console.position.z)
	expect(console.global_basis.is_equal_approx(Basis.IDENTITY), "facing aft")
	expect(console.position.z > -3.4 and console.position.z < -3.0, "starboard desk z is %f" % console.position.z)


func test_console_footprint_is_inside_the_sonar_desk_along_the_hull() -> void:
	var fp: Rect2 = _console_footprint()
	var desk: Rect2 = SubLayout.top_footprint(&"sonar")
	expect(fp.position.y >= desk.position.y - 0.001 and fp.end.y <= desk.end.y + 0.001,
		"console z %f..%f inside the desk's %f..%f" % [fp.position.y, fp.end.y, desk.position.y, desk.end.y])


func test_console_footprint_is_inside_the_sonar_desk_across_the_hull() -> void:
	var fp: Rect2 = _console_footprint()
	var desk: Rect2 = SubLayout.top_footprint(&"sonar")
	expect(fp.position.x >= desk.position.x - 0.001 and fp.end.x <= desk.end.x + 0.001,
		"console x %f..%f inside the desk's %f..%f" % [fp.position.x, fp.end.x, desk.position.x, desk.end.x])


func test_console_is_clear_of_countermeasures() -> void:
	var fp: Rect2 = _console_footprint()
	expect(not fp.intersects(SubLayout.footprint(&"countermeasures")), "console clear of countermeasures' floor footprint")
	expect(not fp.intersects(SubLayout.top_footprint(&"countermeasures")), "console clear of countermeasures' top footprint")


func test_seat_is_in_the_program_seat_footprint() -> void:
	var seat: Node3D = interior.get_node("Stations/Sonar/Seat") as Node3D
	var p: Vector3 = seat.global_position
	expect(SubLayout.footprint(&"sonar_seat").grow(0.3).has_point(Vector2(p.x, p.z)), "seat near the program's sonar seat (%s)" % p)
