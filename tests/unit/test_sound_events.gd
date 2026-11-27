extends TestCase
## Sound events: delivery maths, thresholds, no residue, fading memories.

var det: SoundDetector
var got: Array[SoundEvent] = []


func before_each() -> void:
	Acoustics.reset()
	Acoustics.seed_events(1)
	Acoustics.occlusion_override = Callable()
	got.clear()
	det = _detector(0.0, Vector3.ZERO)


func after_each() -> void:
	Acoustics.occlusion_override = Callable()
	det.free()


func _detector(threshold: float, pos: Vector3) -> SoundDetector:
	var d: SoundDetector = SoundDetector.new()
	d.threshold_db = threshold
	d.world_position = pos
	runner.add_child(d)
	d.heard.connect(func(e: SoundEvent) -> void: got.append(e))
	return d


func test_received_intensity_falls_with_distance() -> void:
	var loud: float = NoiseLevel.from_db(130.0)
	Acoustics.emit_raw(Vector3(10, 0, 0), loud)
	Acoustics.emit_raw(Vector3(100, 0, 0), loud)
	expect_eq(got.size(), 2)
	expect_near(got[0].intensity, NoiseLevel.attenuate(loud, 10.0), 1e-9)
	expect_near(got[1].intensity, NoiseLevel.attenuate(loud, 100.0), 1e-9)
	expect(got[1].intensity < got[0].intensity)


func test_uncertainty_vs_distance_and_background() -> void:
	expect(Acoustics.uncertainty_for(200.0, 10.0) > Acoustics.uncertainty_for(50.0, 10.0), "grows with distance")
	expect(Acoustics.uncertainty_for(100.0, 30.0) < Acoustics.uncertainty_for(100.0, 3.0), "shrinks with margin")
	var loud: float = NoiseLevel.from_db(175.0)
	Acoustics.emit_raw(Vector3(50, 0, 0), loud)
	var ev: SoundEvent = got[0]
	expect(ev.perceived_position.distance_to(ev.true_position) <= ev.uncertainty + 0.001, "error within uncertainty")
	var quiet_margin: float = NoiseLevel.to_db(ev.intensity) - NoiseLevel.to_db(Acoustics.ambient_at(Vector3.ZERO))
	expect_near(ev.uncertainty, Acoustics.uncertainty_for(50.0, quiet_margin), 1e-6)
	# A louder background (an ambient zone) widens the error for the same sound.
	got.clear()
	var zone: AmbientZone = AmbientZone.new()
	zone.source_db = 125.0
	zone.max_range = 500.0
	runner.add_child(zone)
	zone.add_to_group(&"ambient_zones")
	Acoustics.emit_raw(Vector3(50, 0, 0), loud)
	expect_eq(got.size(), 1)
	expect(got[0].uncertainty > ev.uncertainty, "louder background, bigger error")
	zone.free()


func test_timestamp_is_emission_plus_travel() -> void:
	Acoustics.emit_raw(Vector3(300, 0, 0), NoiseLevel.from_db(150.0))
	expect_near(got[0].timestamp, Acoustics.now() + 300.0 / Acoustics.SPEED_OF_SOUND, 1e-6)


func test_occlusion_costs_the_loss() -> void:
	var i: float = NoiseLevel.from_db(150.0)
	Acoustics.emit_raw(Vector3(40, 0, 0), i)
	Acoustics.occlusion_override = func(_a: Vector3, _b: Vector3) -> bool: return true
	Acoustics.emit_raw(Vector3(40, 0, 0), i)
	expect_eq(got.size(), 2)
	expect(not got[0].occluded)
	expect(got[1].occluded)
	expect_near(NoiseLevel.to_db(got[0].intensity) - NoiseLevel.to_db(got[1].intensity), Acoustics.OCCLUSION_LOSS_DB, 0.001)


func test_threshold_filters_faint_events() -> void:
	var deaf: SoundDetector = _detector(40.0, Vector3.ZERO)
	var ambient_db: float = NoiseLevel.to_db(Acoustics.ambient_at(Vector3.ZERO))
	# 20 dB above background at the detector: heard by threshold 0, missed by 40.
	var received_db: float = ambient_db + 20.0
	var emitted: float = NoiseLevel.from_db(received_db) * pow(10.0, 1.5)
	var n: int = Acoustics.emit_raw(Vector3(10, 0, 0), emitted)
	expect_eq(n, 1, "only the sensitive detector hears it")
	expect_eq(got.size(), 1)
	deaf.free()


func test_nothing_alive_after_emit() -> void:
	var before: int = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	var nodes: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var d2: SoundDetector = det
	d2.heard.disconnect(d2.heard.get_connections()[0]["callable"])
	for i: int in range(20):
		Acoustics.emit_raw(Vector3(20, 0, 0), NoiseLevel.from_db(150.0))
	expect_eq(int(Performance.get_monitor(Performance.OBJECT_COUNT)), before)
	expect_eq(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), nodes)


func test_memories_fade_and_drop() -> void:
	Acoustics.emit_raw(Vector3(10, 0, 0), NoiseLevel.from_db(150.0))
	var store: SoundMemory.Store = SoundMemory.Store.new()
	store.lifetime = 10.0
	var m: SoundMemory = store.add(got[0], 100.0)
	expect_near(store.freshness(m, 100.0), 1.0)
	expect_near(store.freshness(m, 105.0), 0.5)
	expect(store.weight(m, 105.0) < store.weight(m, 100.0))
	expect(store.loudest(105.0) == m)
	expect(store.loudest(111.0) == null, "stale memory dropped")
	expect_eq(store.memories.size(), 0)


func test_recent_louder_memory_wins() -> void:
	var store: SoundMemory.Store = SoundMemory.Store.new()
	var old: SoundEvent = SoundEvent.new()
	old.intensity = 1.0
	var fresh: SoundEvent = SoundEvent.new()
	fresh.intensity = 0.8
	store.add(old, 0.0)
	var f: SoundMemory = store.add(fresh, 15.0)
	expect(store.loudest(16.0) == f)


func test_emitters_sharing_a_type_follow_it() -> void:
	var t: SoundType = SoundType.new()
	t.intensity = NoiseLevel.from_db(130.0)
	var a: Object = Object.new()
	var b: Object = Object.new()
	Acoustics.emit_event(t, Vector3(10, 0, 0), a)
	Acoustics.emit_event(t, Vector3(20, 0, 0), b)
	var a1: float = got[0].intensity
	var b1: float = got[1].intensity
	t.intensity *= 2.0
	Acoustics.emit_event(t, Vector3(10, 0, 0), a)
	Acoustics.emit_event(t, Vector3(20, 0, 0), b)
	expect_near(got[2].intensity, a1 * 2.0, 1e-9)
	expect_near(got[3].intensity, b1 * 2.0, 1e-9)
	expect(got[2].source == a and got[3].source == b)
	a.free()
	b.free()


func test_type_scale_is_bounded() -> void:
	var t: SoundType = SoundType.new()
	t.intensity = 1.0
	expect_near(t.scaled_intensity(100.0), SoundType.SCALE_MAX)
	expect_near(t.scaled_intensity(0.0), SoundType.SCALE_MIN)
