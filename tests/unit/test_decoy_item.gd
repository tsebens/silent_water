extends TestCase
## Decoy item and cradle: pick up, seat, refuse a second, lift out.


func test_pick_up_seat_refuse_and_lift_out() -> void:
	var cradle: DecoyCradle = DecoyCradle.new()
	runner.add_child(cradle)
	var carrier: Node3D = Node3D.new()
	runner.add_child(carrier)
	var a: DecoyItem = DecoyItem.new()
	var b: DecoyItem = DecoyItem.new()
	runner.add_child(a)
	runner.add_child(b)
	var seated: Array[DecoyItem] = []
	var released: Array[DecoyItem] = []
	cradle.decoy_seated.connect(func(d: DecoyItem) -> void: seated.append(d))
	cradle.decoy_released.connect(func(d: DecoyItem) -> void: released.append(d))
	var changes: Array[Node3D] = []
	a.carried_changed.connect(func(c: Node3D) -> void: changes.append(c))

	expect(a.pick_up(carrier), "picked up")
	expect(a.is_carried() and a.carrier() == carrier, "carried by the carrier")
	expect(not a.pick_up(carrier), "already carried")
	expect(a.drop_into(cradle), "seated in empty cradle")
	expect(not a.is_carried() and a.is_seated(), "seated, not carried")
	expect_eq(cradle.decoy(), a)
	expect_eq(seated.size(), 1, "decoy_seated emitted")

	b.pick_up(carrier)
	expect(not b.drop_into(cradle), "second decoy refused")
	expect(b.is_carried() and not b.is_seated(), "refused decoy still carried")
	expect_eq(cradle.decoy(), a, "first stays")

	expect(a.pick_up(carrier), "lift out")
	expect(not cradle.is_occupied() and not a.is_seated(), "cradle released")
	expect_eq(released.size(), 1, "decoy_released emitted")
	expect_eq(changes.size(), 3, "carried_changed: carried, seated, carried")
	expect(cradle.release() == null, "releasing empty gives nothing")
	expect(b.drop() and not b.is_carried(), "set down")

	for n: Node in [cradle, carrier, a, b]:
		n.queue_free()
