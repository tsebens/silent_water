extends TestCase
## The sonar console is placed from the program (SubLayout): its back against the starboard hull, its screen
## facing the seated operator on the aisle side, its collision footprint inside the program's sonar desk footprint
## and clear of the science and countermeasures stations.

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
		var world: AABB = cs.global_transform * AABB(-box.size / 2.0, box.size)
		var r: Rect2 = Rect2(world.position.x, world.position.z, world.size.x, world.size.z)
		out = r if first else out.merge(r)
		first = false
	return out


func test_console_is_at_the_program_desk() -> void:
	var origin: Vector3 = SubLayout.position(&"sonar")
	var console: Node3D = interior.get_node("Stations/Sonar") as Node3D
	expect(SubLayout.footprint(&"sonar").grow(0.5).has_point(Vector2(console.position.x, console.position.z)), "console at the sonar desk (%s)" % console.position)
	expect_near(console.position.y, origin.y, 0.001, "on the floor")
	expect(console.position.z > -3.4 and console.position.z < -2.5, "starboard desk z is %f" % console.position.z)


func test_console_faces_the_program_direction() -> void:
	expect_eq(String(SubLayout.record(&"sonar")["faces"]), "starboard", "the program turns sonar to the starboard hull")
	var console: Node3D = interior.get_node("Stations/Sonar") as Node3D
	# The console's local +Z points from its back to its operator: inboard, -X, from the starboard hull.
	var screen_side: Vector3 = console.global_basis * Vector3.BACK
	expect(rad_to_deg(screen_side.angle_to(Vector3.LEFT)) < 5.0, "screen side points inboard (%s)" % screen_side)
	expect(console.position.x > 0.0, "console on the starboard side")


func test_console_back_is_on_the_hull() -> void:
	var fp: Rect2 = _console_footprint()
	var desk: Rect2 = SubLayout.top_footprint(&"sonar")
	expect(desk.end.x - fp.end.x < 0.1, "console back (x %f) within 0.1 m of the desk's wall edge (x %f)" % [fp.end.x, desk.end.x])


func test_seat_is_between_the_console_and_the_aisle_and_faces_the_screen() -> void:
	var seat: Node3D = interior.get_node("Stations/Sonar/Seat") as Node3D
	var fp: Rect2 = _console_footprint()
	var aisle_half: float = SubLayout.clearance("aisle_min_m") / 2.0
	expect(seat.global_position.x < fp.position.x, "seat x %f is inboard of the console's inboard face %f" % [seat.global_position.x, fp.position.x])
	expect(seat.global_position.x > aisle_half, "seat x %f is outside the aisle's half-width %f" % [seat.global_position.x, aisle_half])
	var chart: Node3D = interior.get_node("Stations/Sonar/ScreenMount/Chart") as Node3D
	var to_screen: Vector3 = chart.global_position - seat.global_position
	to_screen.y = 0.0
	var facing: Vector3 = -seat.global_basis.z
	facing.y = 0.0
	expect(rad_to_deg(facing.angle_to(to_screen)) < 10.0, "seat faces the screen (%s toward %s)" % [facing, to_screen])


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


func test_console_is_clear_of_science_and_countermeasures() -> void:
	var fp: Rect2 = _console_footprint()
	for id: StringName in [&"science", &"countermeasures"]:
		expect(not fp.intersects(SubLayout.footprint(id)), "console clear of %s's floor footprint" % id)
		expect(not fp.intersects(SubLayout.top_footprint(id)), "console clear of %s's top footprint" % id)


func test_seat_is_in_the_program_seat_footprint() -> void:
	var seat: Node3D = interior.get_node("Stations/Sonar/Seat") as Node3D
	var p: Vector3 = seat.global_position
	expect(SubLayout.footprint(&"sonar_seat").grow(0.3).has_point(Vector2(p.x, p.z)), "seat near the program's sonar seat (%s)" % p)
