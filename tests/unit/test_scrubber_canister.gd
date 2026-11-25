extends TestCase
## Scrubber canister behaviours: seating in a slot, refusal when occupied,
## release, carrying, and the light ring following capacity.


func _canister() -> ScrubberCanister:
	var c: ScrubberCanister = ScrubberCanister.new()
	runner.add_child(c)
	return c


func _slot() -> CanisterSlot:
	var s: CanisterSlot = CanisterSlot.new()
	runner.add_child(s)
	return s


func test_canister_seats_in_an_empty_slot() -> void:
	var s: CanisterSlot = _slot()
	var c: ScrubberCanister = _canister()
	expect(s.try_seat(c), "empty slot accepts")
	expect(s.is_occupied() and c.is_seated(), "both sides agree")
	expect_eq(s.canister(), c)
	s.queue_free()
	c.queue_free()


func test_occupied_slot_refuses_a_second_canister() -> void:
	var s: CanisterSlot = _slot()
	var a: ScrubberCanister = _canister()
	var b: ScrubberCanister = _canister()
	s.try_seat(a)
	expect(not s.try_seat(b), "occupied slot refuses")
	expect(not b.is_seated(), "refused canister is not seated")
	expect_eq(s.canister(), a, "first canister stays")
	s.queue_free()
	a.queue_free()
	b.queue_free()


func test_slot_releases_and_takes_again() -> void:
	var s: CanisterSlot = _slot()
	var a: ScrubberCanister = _canister()
	var b: ScrubberCanister = _canister()
	s.try_seat(a)
	expect_eq(s.release(), a)
	expect(not s.is_occupied() and not a.is_seated(), "empty after release")
	expect(s.release() == null, "releasing an empty slot gives nothing")
	expect(s.try_seat(b), "free again")
	s.queue_free()
	a.queue_free()
	b.queue_free()


func test_lift_out_and_drop_back() -> void:
	var s: CanisterSlot = _slot()
	var other: CanisterSlot = _slot()
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	var c: ScrubberCanister = _canister()
	s.try_seat(c)
	expect(c.pick_up(carrier), "picked up")
	expect(c.is_carried() and not c.is_seated(), "carried, not seated")
	expect(not s.is_occupied(), "slot freed by the lift")
	expect(not c.pick_up(carrier), "already carried")
	expect(c.drop_into(other), "dropped into another slot")
	expect(not c.is_carried() and other.canister() == c, "seated, no longer carried")
	expect(not c.drop(), "nothing to drop when seated")
	s.queue_free()
	other.queue_free()
	carrier.queue_free()
	c.queue_free()


func test_drop_into_occupied_slot_keeps_carrying() -> void:
	var s: CanisterSlot = _slot()
	var sitting: ScrubberCanister = _canister()
	s.try_seat(sitting)
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	var c: ScrubberCanister = _canister()
	c.pick_up(carrier)
	expect(not c.drop_into(s), "refused")
	expect(c.is_carried(), "still carried")
	expect(c.drop(), "can be set down")
	s.queue_free()
	sitting.queue_free()
	carrier.queue_free()
	c.queue_free()


func test_ring_lit_count_follows_capacity() -> void:
	var c: ScrubberCanister = _canister()
	var ring: CanisterRing = CanisterRing.new()
	ring.canister = c
	runner.add_child(ring)
	expect_eq(ring.segment_count_built(), ring.segment_count)
	expect_eq(ring.lit_count(), ring.segment_count, "fresh: all lit")
	c.capacity = 0.5
	expect_eq(ring.lit_count(), ring.segment_count / 2, "half: half lit")
	c.capacity = 0.1
	expect_eq(ring.lit_count(), 2, "nearly spent: a short arc")
	c.capacity = 0.0
	expect_eq(ring.lit_count(), 0, "spent: none")
	for i: int in ring.segment_count:
		expect(not ring.segment_lit(i), "segment %d dark" % i)
	c.capacity = 0.5
	var lit: int = 0
	for i: int in ring.segment_count:
		if ring.segment_lit(i):
			lit += 1
	expect_eq(lit, ring.segment_count / 2, "materials follow the count")
	expect(ring.segment_lit(0) and not ring.segment_lit(ring.segment_count - 1), "run starts at the first segment")
	ring.queue_free()
	c.queue_free()


func test_ring_colour_follows_capacity() -> void:
	var c: ScrubberCanister = _canister()
	var ring: CanisterRing = CanisterRing.new()
	ring.canister = c
	runner.add_child(ring)
	var pal: Palette = Palette.main()
	c.capacity = 1.0
	expect(ring.segment_color(0).is_equal_approx(pal.color(&"light_ok")), "fresh is green")
	c.capacity = 0.5
	expect(ring.segment_color(0).is_equal_approx(pal.color(&"light_warn")), "half is yellow")
	c.capacity = 0.1
	expect(ring.segment_color(0).is_equal_approx(pal.color(&"light_alarm")), "spent is red")
	expect_eq(ring.swatch_for(0.9), &"light_ok")
	ring.queue_free()
	c.queue_free()


func test_capacity_clamps() -> void:
	var c: ScrubberCanister = _canister()
	c.capacity = 3.0
	expect_near(c.capacity, 1.0)
	c.capacity = -1.0
	expect_near(c.capacity, 0.0)
	c.queue_free()
