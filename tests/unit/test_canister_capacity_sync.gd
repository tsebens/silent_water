extends TestCase
## Canister capacity replicates host to client in every state (seated, carried,
## stored): the client applies what the host's snapshot carries.


func _pair() -> Array[ScrubberCanister]:
	var host: ScrubberCanister = ScrubberCanister.new()
	var client: ScrubberCanister = ScrubberCanister.new()
	client.simulate_client = true
	runner.add_child(host)
	runner.add_child(client)
	var out: Array[ScrubberCanister] = [host, client]
	return out


func _sync(host: ScrubberCanister, client: ScrubberCanister) -> void:
	client.apply_snapshot(host.snapshot())


func test_client_matches_host_when_seated() -> void:
	var p: Array[ScrubberCanister] = _pair()
	var slot: CanisterSlot = CanisterSlot.new()
	runner.add_child(slot)
	slot.try_seat(p[0])
	p[0].capacity = 0.42
	_sync(p[0], p[1])
	expect_near(p[1].capacity, 0.42, 0.0001, "seated")
	slot.queue_free()
	p[0].queue_free()
	p[1].queue_free()


func test_client_matches_host_when_carried() -> void:
	var p: Array[ScrubberCanister] = _pair()
	var who: Node3D = Node3D.new()
	runner.add_child(who)
	p[0].pick_up(who)
	p[0].capacity = 0.3
	_sync(p[0], p[1])
	expect_near(p[1].capacity, 0.3, 0.0001, "carried")
	who.queue_free()
	p[0].queue_free()
	p[1].queue_free()


func test_client_matches_host_when_stored() -> void:
	var p: Array[ScrubberCanister] = _pair()
	var slot: CanisterSlot = CanisterSlot.new()
	slot.name = &"StorageHole"
	runner.add_child(slot)
	slot.try_seat(p[0])
	p[0].capacity = 0.0
	_sync(p[0], p[1])
	expect_near(p[1].capacity, 0.0, 0.0001, "stored")
	slot.queue_free()
	p[0].queue_free()
	p[1].queue_free()


func test_client_ring_follows_replicated_capacity() -> void:
	var p: Array[ScrubberCanister] = _pair()
	var ring: CanisterRing = CanisterRing.new()
	ring.canister = p[1]
	runner.add_child(ring)
	p[0].capacity = 0.0
	_sync(p[0], p[1])
	expect_eq(ring.lit_count(), 0, "spent canister lights nothing on the client")
	ring.queue_free()
	p[0].queue_free()
	p[1].queue_free()
