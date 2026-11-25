extends TestCase
## The scrubber canister scene: modelled body with ScrubberCanister bound and a CanisterRing on its cap.

const SCENE: String = "res://assets/models/furniture/scrubber_canister/scrubber_canister.tscn"


func _make() -> ScrubberCanister:
	var c: ScrubberCanister = (load(SCENE) as PackedScene).instantiate() as ScrubberCanister
	runner.add_child(c)
	return c


func _body_box(c: ScrubberCanister) -> AABB:
	var box: AABB = AABB()
	var first: bool = true
	for n: Node in c.get_node("Body").find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = n as MeshInstance3D
		var b: AABB = c.global_transform.affine_inverse() * m.global_transform * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func test_scripts_are_bound() -> void:
	var c: ScrubberCanister = _make()
	expect(c != null, "root is a ScrubberCanister")
	var ring: CanisterRing = c.get_node("Ring") as CanisterRing
	expect(ring != null, "Ring is a CanisterRing")
	expect(ring.canister == c, "ring is bound to the canister")
	c.queue_free()


func test_size_and_base() -> void:
	var c: ScrubberCanister = _make()
	var b: AABB = _body_box(c)
	expect_near(b.position.y, 0.0, 1e-4, "base on Y=0")
	expect(b.end.y > 0.28 and b.end.y < 0.32, "about 30 cm tall: %f" % b.end.y)
	expect(b.size.x > 0.135 and b.size.x < 0.16 and b.size.z > 0.135 and b.size.z < 0.16, "about 15 cm across: %s" % b.size)
	c.queue_free()


func test_ring_sits_on_the_cap_inside_its_edge() -> void:
	var c: ScrubberCanister = _make()
	var ring: CanisterRing = c.get_node("Ring") as CanisterRing
	expect_eq(ring.segment_count_built(), 12)
	var top: float = _body_box(c).end.y
	for i: int in ring.segment_count_built():
		var seg: Node3D = ring.get_node("Segment%d" % i) as Node3D
		var p: Vector3 = c.to_local(seg.global_position)
		expect(p.y > 0.25 and p.y < top, "segment %d on the cap top" % i)
		expect(Vector2(p.x, p.z).length() + 0.009 < 0.075, "segment %d inside the cap edge" % i)
	c.queue_free()


func test_ring_responds_to_capacity() -> void:
	var c: ScrubberCanister = _make()
	var ring: CanisterRing = c.get_node("Ring") as CanisterRing
	expect_eq(ring.lit_count(), 12)
	c.capacity = 0.5
	expect_eq(ring.lit_count(), 6)
	expect(ring.segment_lit(5) and not ring.segment_lit(6), "first six lit")
	c.capacity = 0.0
	expect_eq(ring.lit_count(), 0)
	c.queue_free()


func test_it_carries_a_grab_box() -> void:
	var c: ScrubberCanister = _make()
	var g: StaticBody3D = c.get_node("Grab") as StaticBody3D
	expect(g != null and g.collision_layer == 2, "grab body on the interaction layer")
	c.queue_free()
