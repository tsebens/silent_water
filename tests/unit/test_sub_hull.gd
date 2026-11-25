extends TestCase
## The generated hull (assets/sub/sub_hull.glb, from tools/build_sub_hull.py) against SubLayout: envelope, step,
## hatch opening, deck height, and a player capsule walking the aisle, through the hatch and up the cockpit step.

const HULL: PackedScene = preload("res://assets/sub/sub_hull.glb")
const PARTS: PackedStringArray = [
	"hull_shell", "dome_glass", "dome_rim", "deck_cockpit", "deck_midships", "deck_bulkhead", "deck_engineering",
	"cockpit_step", "bulkhead", "hatch_frame", "tower", "tower_hatch",
]
## The program's wall_m: the hull's inner surface sits this far inside its envelope.
const WALL_M: float = 0.12
const CAPSULE_RADIUS: float = 0.3
const CAPSULE_HEIGHT: float = 1.75

var hull: Node3D


func before_each() -> void:
	hull = HULL.instantiate() as Node3D
	runner.add_child(hull)


func after_each() -> void:
	hull.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


func _mesh(part_name: String) -> MeshInstance3D:
	return hull.get_node_or_null(part_name) as MeshInstance3D


## Cast a ray in the hull's frame; returns the hit position or null.
func _ray(from: Vector3, to: Vector3) -> Variant:
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	var hit: Dictionary = (hull as Node3D).get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("position", null)


func test_every_documented_part_exists() -> void:
	for n: String in PARTS:
		expect(_mesh(n) != null, "missing part %s" % n)


func test_envelope_matches_the_program() -> void:
	var box: AABB = _mesh("hull_shell").get_aabb().merge(_mesh("dome_glass").get_aabb())
	var size: Vector3 = SubLayout.hull_size()
	expect_near(box.size.x, size.x - 2.0 * WALL_M, 0.02, "inner width")
	expect_near(box.size.y, size.y - 2.0 * WALL_M, 0.02, "inner height")
	expect_near(box.size.z, size.z, 0.05, "length")
	# the hull's centre is the program origin: in the interior frame, y is main_deck_y below it
	var centre: Vector3 = SubLayout.to_interior(Vector3.ZERO)
	expect_near(box.get_center().y, centre.y, 0.02, "centred on the program's origin")
	expect_near(box.get_center().x, 0.0, 0.02)
	expect_near(box.get_center().z, 0.0, 0.02)


func test_deck_heights_and_step() -> void:
	var main: float = _mesh("deck_midships").get_aabb().end.y
	expect_near(main, 0.0, 0.001, "main deck is the interior frame's floor")
	expect_near(_mesh("deck_engineering").get_aabb().end.y, 0.0, 0.001, "engineering deck")
	expect_near(_mesh("deck_bulkhead").get_aabb().end.y, 0.0, 0.001, "hatch sill")
	var cockpit: float = _mesh("deck_cockpit").get_aabb().end.y
	expect_near(cockpit, SubLayout.cockpit_floor_offset(), 0.001, "cockpit floor")
	expect_near(main - cockpit, 0.2, 0.001, "the step is 0.2 m")
	var step: AABB = _mesh("cockpit_step").get_aabb()
	expect_near(step.end.y, 0.0, 0.001, "the ramp tops out at the main deck")
	expect_near(step.end.z, SubLayout.compartment_span(&"cockpit").y, 0.001, "the ramp ends at the cockpit's rim")


func test_hatch_opening_matches_the_clearances() -> void:
	await _frames(2)
	var span: Vector2 = SubLayout.compartment_span(&"bulkhead")
	var w: float = SubLayout.clearance("hatch_width_m")
	var h: float = SubLayout.clearance("hatch_height_m")
	var z0: float = span.x - 0.5
	var z1: float = span.y + 0.5
	for y: float in [0.1, h * 0.5, h - 0.05]:
		expect(_ray(Vector3(0.0, y, z0), Vector3(0.0, y, z1)) == null, "open on the centreline at y=%f" % y)
		expect(_ray(Vector3(w / 2.0 - 0.02, y, z0), Vector3(w / 2.0 - 0.02, y, z1)) == null, "open just inside the right jamb")
		expect(_ray(Vector3(-w / 2.0 + 0.02, y, z0), Vector3(-w / 2.0 + 0.02, y, z1)) == null, "open just inside the left jamb")
		expect(_ray(Vector3(w / 2.0 + 0.02, y, z0), Vector3(w / 2.0 + 0.02, y, z1)) != null, "shut just outside the right jamb")
		expect(_ray(Vector3(-w / 2.0 - 0.02, y, z0), Vector3(-w / 2.0 - 0.02, y, z1)) != null, "shut just outside the left jamb")
	expect(_ray(Vector3(0.0, h - 0.02, z0), Vector3(0.0, h - 0.02, z1)) == null, "open to the head of the opening")
	expect(_ray(Vector3(0.0, h + 0.05, z0), Vector3(0.0, h + 0.05, z1)) != null, "shut above the opening")
	var box: AABB = _mesh("bulkhead").get_aabb()
	expect_near(box.position.z, span.x, 0.001, "bulkhead starts at its compartment")
	expect_near(box.end.z, span.y, 0.001, "bulkhead ends at its compartment")


func test_head_clearance_along_the_walkway() -> void:
	await _frames(2)
	var need: float = SubLayout.clearance("head_clear_m")
	var z: float = -4.2
	var hatch: Vector2 = SubLayout.compartment_span(&"bulkhead")
	while z <= 4.4:
		if z > hatch.x - 0.1 and z < hatch.y + 0.1:  # under the hatch's lintel the roof is the opening's head
			z += 0.2
			continue
		var floor_y: float = SubLayout.floor_y(&"cockpit") if z < SubLayout.compartment_span(&"cockpit").y else 0.0
		var hit: Variant = _ray(Vector3(0.0, floor_y + 0.1, z), Vector3(0.0, floor_y + 5.0, z))
		expect(hit != null, "a roof over z=%f" % z)
		if hit != null:
			expect((hit as Vector3).y - floor_y >= need, "head room %f at z=%f" % [(hit as Vector3).y - floor_y, z])
		z += 0.2


func _walker(at: Vector3) -> CharacterBody3D:
	var body: CharacterBody3D = CharacterBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var cap: CapsuleShape3D = CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = CAPSULE_HEIGHT
	shape.shape = cap
	shape.position.y = CAPSULE_HEIGHT / 2.0
	body.add_child(shape)
	runner.add_child(body)
	body.position = at
	return body


## Walk toward a z on the centreline at 2.6 m/s (the player's walk speed) for up to `seconds`.
func _walk_to(body: CharacterBody3D, z: float, seconds: float) -> void:
	var dt: float = 1.0 / 60.0
	for i: int in range(int(seconds / dt)):
		var dir: float = signf(z - body.position.z)
		body.velocity.x = 0.0
		body.velocity.z = dir * 2.6
		body.velocity.y -= 9.8 * dt
		body.move_and_slide()
		await runner.get_tree().physics_frame
		if absf(body.position.z - z) < 0.05:
			break


func test_walk_the_aisle_through_the_hatch_and_up_the_step() -> void:
	await _frames(2)
	var cockpit_z: float = -3.9
	var body: CharacterBody3D = _walker(Vector3(0.0, 0.05, cockpit_z))
	for i: int in range(60):
		body.velocity.y -= 9.8 / 60.0
		body.move_and_slide()
		await runner.get_tree().physics_frame
	expect_near(body.position.y, SubLayout.cockpit_floor_offset(), 0.03, "standing on the cockpit floor")
	# up the step, along the aisle, through the hatch and into engineering
	await _walk_to(body, -2.0, 4.0)
	expect(body.position.z > -2.1, "up the step and on, got z=%f" % body.position.z)
	expect_near(body.position.y, 0.0, 0.03, "on the main deck")
	await _walk_to(body, 3.0, 6.0)
	expect(body.position.z > 2.9, "through the hatch, got z=%f" % body.position.z)
	expect_near(body.position.y, 0.0, 0.03, "on the engineering deck")
	# and all the way back down into the cockpit
	await _walk_to(body, cockpit_z, 8.0)
	expect(body.position.z < cockpit_z + 0.1, "back to the cockpit, got z=%f" % body.position.z)
	expect_near(body.position.y, SubLayout.cockpit_floor_offset(), 0.03, "down on the cockpit floor")
	body.free()


func test_the_hull_walls_hold_a_player_in() -> void:
	await _frames(2)
	var body: CharacterBody3D = _walker(Vector3(0.0, 0.05, -1.0))
	await _frames(20)
	for i: int in range(120):
		body.velocity.x = 3.0
		body.velocity.y -= 9.8 / 60.0
		body.move_and_slide()
		await runner.get_tree().physics_frame
	expect(body.position.x < SubLayout.hull_size().x / 2.0, "stopped by the wall, x=%f" % body.position.x)
	body.free()
