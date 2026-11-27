extends TestCase
## Periodic and one-off emitters, the sub's combined event, shared sound types.

var det: SoundDetector
var got: Array[SoundEvent] = []


class FakeSource:
	extends Node
	var value: float = 0.0
	var label: String = "fake"

	func noise_intensity() -> float:
		return value


func before_each() -> void:
	Acoustics.reset()
	Acoustics.seed_events(1)
	Acoustics.occlusion_override = Callable()
	got.clear()
	det = SoundDetector.new()
	det.world_position = Vector3.ZERO
	runner.add_child(det)
	det.heard.connect(func(e: SoundEvent) -> void: got.append(e))


func after_each() -> void:
	det.free()


func _type(intensity: float, period: float) -> SoundType:
	var t: SoundType = SoundType.new()
	t.intensity = intensity
	t.period = period
	return t


func _emitter(t: SoundType) -> SoundEmitter:
	var e: SoundEmitter = SoundEmitter.new()
	e.sound_type = t
	e.world_position = Vector3(10, 0, 0)
	runner.add_child(e)
	return e


func test_periodic_rate_independent_of_frame_rate() -> void:
	var t: SoundType = _type(NoiseLevel.from_db(130.0), 1.0)
	var e: SoundEmitter = _emitter(t)
	var n_fast: int = 0
	for i: int in range(600):
		n_fast += e.advance(1.0 / 60.0)
	var e2: SoundEmitter = _emitter(t)
	var n_slow: int = 0
	for i: int in range(10):
		n_slow += e2.advance(1.0)
	expect_eq(n_fast, 10)
	expect_eq(n_slow, 10)
	expect_eq(got.size(), 20)
	e.free()
	e2.free()


func test_one_off_type_never_ticks_and_fires_once() -> void:
	var e: SoundEmitter = _emitter(_type(NoiseLevel.from_db(130.0), 0.0))
	expect_eq(e.advance(5.0), 0)
	expect_eq(got.size(), 0)
	e.fire()
	expect_eq(got.size(), 1)
	e.free()


func test_sub_combined_event_equals_sum_of_systems() -> void:
	var a: FakeSource = FakeSource.new()
	var b: FakeSource = FakeSource.new()
	a.value = 0.01
	b.value = 0.025
	Acoustics._physics_process(0.01)
	var base: float = Acoustics.sub_intensity
	got.clear()
	runner.add_child(a)
	runner.add_child(b)
	a.add_to_group(&"noise_sources")
	b.add_to_group(&"noise_sources")
	# Run the physics tick until the first combined event goes out.
	var ticks: int = 0
	while got.is_empty() and ticks < 200:
		Acoustics._physics_process(0.1)
		ticks += 1
	expect_eq(got.size(), 1)
	expect_near(Acoustics.last_sub_event_load, base + 0.035, 1e-9)
	expect_near(got[0].emitted_intensity, (base + 0.035) * Acoustics.SUB_COMBINED_TYPE.intensity, 1e-9)
	expect_near(Acoustics.sub_intensity, base + 0.035, 1e-9)
	expect_near(float(Acoustics.breakdown["fake"]), 0.035, 1e-9)
	a.free()
	b.free()


func test_impulse_emits_exactly_once_immediately() -> void:
	Acoustics.add_impulse(0.5, 1.5)
	expect_eq(got.size(), 1)
	expect_near(got[0].emitted_intensity, 0.5 * Acoustics.IMPACT_TYPE.intensity, 1e-9)
	expect(got[0].kind == &"impact")
	for i: int in range(30):
		Acoustics._physics_process(0.1)
	var impacts: int = 0
	for ev: SoundEvent in got:
		if ev.kind == &"impact":
			impacts += 1
	expect_eq(impacts, 1)


func test_gauges_unchanged_by_events() -> void:
	var a: FakeSource = FakeSource.new()
	a.value = 0.02
	Acoustics._physics_process(0.01)
	var base: float = Acoustics.sub_intensity
	runner.add_child(a)
	a.add_to_group(&"noise_sources")
	Acoustics._physics_process(0.05)
	expect_near(Acoustics.sub_intensity, base + 0.02, 1e-9)
	expect_near(float(Acoustics.breakdown["fake"]), 0.02, 1e-9)
	expect(Acoustics.top_text.contains("fake %.0f" % NoiseLevel.to_db(0.02)))
	a.free()


func test_changing_a_type_changes_every_emitter() -> void:
	var t: SoundType = _type(NoiseLevel.from_db(130.0), 1.0)
	var e1: SoundEmitter = _emitter(t)
	var e2: SoundEmitter = _emitter(t)
	e1.fire()
	e2.fire()
	var before: float = got[0].emitted_intensity
	t.intensity *= 2.0
	e1.fire()
	e2.fire()
	expect_near(got[2].emitted_intensity, before * 2.0, 1e-9)
	expect_near(got[3].emitted_intensity, before * 2.0, 1e-9)
	e1.free()
	e2.free()


func test_changing_sub_types_changes_sub_events() -> void:
	var t: SoundType = Acoustics.SUB_COMBINED_TYPE
	var old: float = t.intensity
	Acoustics.emit_load(t, Vector3(10, 0, 0), 0.01)
	t.intensity = old * 2.0
	Acoustics.emit_load(t, Vector3(10, 0, 0), 0.01)
	t.intensity = old
	expect_near(got[1].emitted_intensity, got[0].emitted_intensity * 2.0, 1e-12)
