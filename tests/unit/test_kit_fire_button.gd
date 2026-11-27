extends TestCase
## The kit fire_button: a push button under a hinged flip guard, gated by FireButton.

const SCENE: String = "res://assets/models/kit/fire_button/fire_button.tscn"


func _make() -> FireButton:
	var s: FireButton = (load(SCENE) as PackedScene).instantiate() as FireButton
	runner.add_child(s)
	return s


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().physics_frame


## First collider along a ray in the scene's frame, or null.
func _ray(root: Node, from: Vector3, to: Vector3) -> Node:
	var s: Node3D = root as Node3D
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
			s.to_global(from), s.to_global(to), 2)
	var hit: Dictionary = s.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.get("collider", null) as Node


func _grab_aabb(owner_node: Node3D, path: String) -> AABB:
	var shape: CollisionShape3D = owner_node.get_node(path) as CollisionShape3D
	var box: BoxShape3D = shape.shape as BoxShape3D
	return shape.global_transform * AABB(-box.size * 0.5, box.size)


func test_root_wires_guard_and_button() -> void:
	var s: FireButton = _make()
	expect(s.guard is SwitchLever, "guard is a SwitchLever")
	expect(s.button is PushButton, "button is a PushButton")
	expect(not s.guard_open(), "guard starts closed")
	s.guard.host_set_value(s.guard.max_value)
	expect(s.guard_open(), "guard open at max")
	s.queue_free()


func test_click_ray_cannot_reach_the_button_while_closed() -> void:
	var s: FireButton = _make()
	await _frames(2)
	var hit: Node = _ray(s, Vector3(0, 0, 0.3), Vector3(0, 0, 0.0))
	expect(hit != null and s.guard.is_ancestor_of(hit), "closed: a straight-on ray hits the guard")
	var slant: Node = _ray(s, Vector3(0, 0.275, 0.25), Vector3(0, 0.0, 0.016))
	expect(slant != null and s.guard.is_ancestor_of(slant), "closed: a ray from the standing eye hits the guard")
	s.guard.host_set_value(s.guard.max_value)
	await _frames(2)
	var open_hit: Node = _ray(s, Vector3(0, 0, 0.3), Vector3(0, 0, 0.0))
	expect(open_hit != null and s.button.is_ancestor_of(open_hit), "open: a straight-on ray hits the button")
	var open_slant: Node = _ray(s, Vector3(0, 0.275, 0.25), Vector3(0, 0.0, 0.016))
	expect(open_slant != null and s.button.is_ancestor_of(open_slant), "open: a ray from the standing eye hits the button")
	s.queue_free()


func test_grab_boxes_are_apart() -> void:
	var s: FireButton = _make()
	await _frames(1)
	var g: AABB = _grab_aabb(s.guard, "Pivot/Lid/Grab/Shape")
	var b: AABB = _grab_aabb(s.button, "Grab/Shape")
	expect(not g.intersects(b), "guard and button grab boxes apart (%s, %s)" % [g, b])
	s.guard.host_set_value(s.guard.max_value)
	g = _grab_aabb(s.guard, "Pivot/Lid/Grab/Shape")
	expect(not g.intersects(b), "apart when open")
	s.queue_free()


func test_footprint_and_stand_out_match_the_entry() -> void:
	var s: FireButton = _make()
	var mesh: MeshInstance3D = s.get_node("Guard/Pivot/Lid/GuardMesh").find_child("*", true, false) as MeshInstance3D
	expect(mesh != null, "guard mesh present")
	var closed: AABB = mesh.global_transform * mesh.get_aabb()
	expect_near(closed.end.z, 0.036, 0.0006, "closed guard's tab stands 36 mm out")
	expect(closed.position.z > 0.018, "closed guard is in front of the cap")
	s.guard.host_set_value(s.guard.max_value)
	var opened: AABB = mesh.global_transform * mesh.get_aabb()
	expect(opened.position.y > -0.02 or opened.end.y > 0.06, "open guard has swung up above the plate")
	s.queue_free()


func test_press_counts_only_with_guard_open_at_both_ends() -> void:
	var s: FireButton = _make()
	var fired: Array[int] = [0]
	s.pressed.connect(func() -> void: fired[0] += 1)
	# Without a tube nothing fires, so the guarded request is checked through guard_open().
	expect(not s.guard_open(), "closed end: guard closed, press does not count")
	s.guard.host_set_value(s.guard.min_value)
	expect(not s.guard_open(), "guard at min travel is closed")
	s.guard.host_set_value(s.guard.max_value)
	expect(s.guard_open(), "guard at max travel is open")
	expect(s.button is PushButton, "button is the PushButton child")
	s.queue_free()
