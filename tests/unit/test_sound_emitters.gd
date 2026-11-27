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


func _stream_type(period: float) -> SoundType:
	var t: SoundType = _type(NoiseLevel.from_db(130.0), period)
	t.stream = AudioStreamGenerator.new()
	return t


func _players(e: Node) -> Array[AudioStreamPlayer3D]:
	var out: Array[AudioStreamPlayer3D] = []
	for c: Node in e.get_children():
		if c is AudioStreamPlayer3D:
			out.append(c)
	return out


func test_one_off_plays_stream_at_position() -> void:
	var t: SoundType = _stream_type(0.0)
	t.volume_db = -6.0
	var e: SoundEmitter = _emitter(t)
	e.fire()
	var ps: Array[AudioStreamPlayer3D] = _players(e)
	expect_eq(ps.size(), 1)
	expect(ps[0].stream == t.stream)
	expect_near(ps[0].global_position.x, 10.0, 1e-6)
	expect_near(ps[0].volume_db, -6.0, 1e-6)
	expect_near(ps[0].unit_size, SubAudio.UNIT_SIZE, 1e-6)
	expect(ps[0].bus == AudioBuses.INSIDE)
	e.free()


func test_loop_player_runs_while_active_without_restart() -> void:
	var e: SoundEmitter = _emitter(_stream_type(1.0))
	e._physics_process(0.1)
	var p: AudioStreamPlayer3D = e.loop_player()
	expect(p != null)
	expect(p.playing)
	for i: int in range(30):
		e._physics_process(0.1)
	expect(e.loop_player() == p)
	expect_eq(_players(e).size(), 1)
	e.active = false
	e._physics_process(0.1)
	expect(e.loop_player() == null)
	e.free()


func test_no_stream_means_no_player() -> void:
	var e: SoundEmitter = _emitter(_type(NoiseLevel.from_db(130.0), 1.0))
	e._physics_process(0.1)
	e.fire()
	expect(e.loop_player() == null)
	expect_eq(_players(e).size(), 0)
	var e2: SoundEmitter = _emitter(_type(NoiseLevel.from_db(130.0), 0.0))
	e2.fire()
	expect_eq(_players(e2).size(), 0)
	e.free()
	e2.free()


func test_type_volume_change_reaches_every_emitter() -> void:
	var t: SoundType = _stream_type(1.0)
	var e1: SoundEmitter = _emitter(t)
	var e2: SoundEmitter = _emitter(t)
	e1._physics_process(0.1)
	e2._physics_process(0.1)
	t.volume_db = -12.0
	e1._physics_process(0.1)
	e2._physics_process(0.1)
	expect_near(e1.loop_player().volume_db, -12.0, 1e-6)
	expect_near(e2.loop_player().volume_db, -12.0, 1e-6)
	e1.free()
	e2.free()


func test_field_events_false_plays_but_emits_nothing() -> void:
	var t: SoundType = _stream_type(1.0)
	var e: SoundEmitter = _emitter(t)
	e.field_events = false
	e.fire()
	expect_eq(e.advance(3.0), 3)
	expect_eq(got.size(), 0)
	expect_eq(_players(e).size(), 1)
	e.field_events = true
	e.fire()
	expect_eq(got.size(), 1)
	e.free()
