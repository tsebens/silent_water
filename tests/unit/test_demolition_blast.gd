extends TestCase
## DemolitionBlast: the noise event is intensity on the bus, damage falls off with distance, the sub is hurt
## only inside the radius.

var blast: DemolitionBlast
var det: SoundDetector
var got: Array[SoundEvent] = []


func before_each() -> void:
	Acoustics.reset()
	Acoustics.seed_events(1)
	Acoustics.occlusion_override = Callable()
	got.clear()
	det = SoundDetector.new()
	det.threshold_db = 0.0
	det.world_position = Vector3(100, 0, 0)
	runner.add_child(det)
	det.heard.connect(func(e: SoundEvent) -> void: got.append(e))
	blast = DemolitionBlast.new()
	blast.blast_radius_m = 50.0
	blast.max_damage = 100.0
	blast.sub_max_damage = 40.0
	runner.add_child(blast)
	blast.sub_position_override = Vector3(500, 0, 0)


func after_each() -> void:
	Acoustics.occlusion_override = Callable()
	det.free()
	blast.free()


func test_event_is_intensity_not_db() -> void:
	blast.detonate()
	expect_eq(got.size(), 1, "heard once")
	expect_near(got[0].emitted_intensity, NoiseLevel.from_db(DemolitionBlast.BLAST_DB), 1e-6)
	expect(got[0].emitted_intensity < 1e6 and got[0].emitted_intensity > 1.0, "linear intensity, not a dB figure")
	expect_eq(got[0].kind, DemolitionBlast.KIND)


func test_blast_sums_as_intensity() -> void:
	var a: float = DemolitionBlast.blast_intensity()
	expect_near(NoiseLevel.to_db(a + a) - NoiseLevel.to_db(a), 3.0103, 0.01, "two blasts add 3 dB")


func test_damage_falls_off_with_distance() -> void:
	expect_near(blast.damage_at(0.0), 100.0)
	expect(blast.damage_at(10.0) > blast.damage_at(30.0), "nearer hurts more")
	expect_near(blast.damage_at(50.0), 0.0, 1e-6, "none at the radius")
	expect_near(blast.damage_at(80.0), 0.0, 1e-6, "none beyond")


func test_targets_damaged_by_distance() -> void:
	var near: Node3D = Node3D.new()
	near.position = Vector3(5, 0, 0)
	var far: Node3D = Node3D.new()
	far.position = Vector3(200, 0, 0)
	runner.add_child(near)
	runner.add_child(far)
	blast.targets = [near, far]
	var hits: Dictionary = {}
	blast.target_damaged.connect(func(t: Node3D, amt: float) -> void: hits[t] = amt)
	blast.detonate()
	expect(hits.has(near) and float(hits[near]) > 0.0, "near target hurt")
	expect(not hits.has(far), "far target untouched")
	near.free()
	far.free()


func test_sub_outside_radius_takes_none() -> void:
	var hurt: Array[float] = []
	blast.sub_damaged.connect(func(a: float) -> void: hurt.append(a))
	blast.detonate()
	expect(hurt.is_empty(), "sub 500 m away is safe")


func test_sub_inside_radius_takes_damage() -> void:
	var hurt: Array[float] = []
	blast.sub_damaged.connect(func(a: float) -> void: hurt.append(a))
	blast.sub_position_override = Vector3(10, 0, 0)
	blast.detonate()
	expect_eq(hurt.size(), 1)
	expect_near(hurt[0], 40.0 * 0.8, 1e-4)


func test_detonates_with_objective_once() -> void:
	var o: DemolitionObjective = DemolitionObjective.new()
	o.fuse_sec = 1.0
	runner.add_child(o)
	o.set_physics_process(false)
	blast.objective = o
	o.set_reactor_on(false)
	for i: int in o.charge_count:
		o.arm_charge(i)
	o.step(2.0)
	expect_eq(got.size(), 1, "one event on detonation")
	expect_eq(blast.detonate(), 0, "no second blast")
	expect_eq(got.size(), 1)
	o.free()
