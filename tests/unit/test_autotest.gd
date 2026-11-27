extends TestCase
## The autotest host's report timing (#86): the snapshot waits for fresh voice
## reports from every peer so a dropped packet or a stall can't be read as
## silence, but never waits past the grace.

const AT: float = Autotest.REPORT_AT
const FRESH: float = Autotest.VOICE_FRESH
const GRACE: float = Autotest.REPORT_GRACE


func after_each() -> void:
	Acoustics.reset()


func test_fresh_threshold_is_under_voice_timeout() -> void:
	expect(FRESH < Acoustics.VOICE_TIMEOUT, "waiting for fresh reports only helps below the timeout")
	expect_eq(Acoustics.VOICE_TIMEOUT, 0.5, "the game's voice timeout is not the autotest's to change")


func test_not_due_before_report_time() -> void:
	var fresh: Array[float] = [0.0, 0.0]
	expect(not Autotest.report_due(AT - 0.01, fresh))
	expect(not Autotest.report_due(0.0, []))


func test_due_at_report_time_when_every_voice_is_fresh() -> void:
	var fresh: Array[float] = [0.0, FRESH * 0.5]
	expect(Autotest.report_due(AT, fresh))


func test_due_at_report_time_with_no_peers() -> void:
	expect(Autotest.report_due(AT, []))


func test_held_while_any_voice_is_stale() -> void:
	var one_stale: Array[float] = [0.0, FRESH]
	expect(not Autotest.report_due(AT, one_stale), "a report exactly at the threshold is stale")
	var timed_out: Array[float] = [0.0, Acoustics.VOICE_TIMEOUT + 0.1]
	expect(not Autotest.report_due(AT + GRACE * 0.5, timed_out))
	var never: Array[float] = [INF]
	expect(not Autotest.report_due(AT, never))


func test_due_once_grace_runs_out_even_if_stale() -> void:
	var never: Array[float] = [INF, 0.0]
	expect(not Autotest.report_due(AT + GRACE - 0.01, never))
	expect(Autotest.report_due(AT + GRACE, never))
	expect(Autotest.report_due(AT + GRACE + 5.0, never))


func test_acoustics_voice_age() -> void:
	var me: int = Acoustics.multiplayer.get_unique_id()
	expect_eq(Acoustics.voice_age(me), INF, "never reported")
	Acoustics.report_voice(NoiseLevel.from_db(75.0))
	expect_near(Acoustics.voice_age(me), 0.0, 1e-6, "just reported")
	expect_near(NoiseLevel.to_db(Acoustics.voice_intensity(me)), 75.0, 0.01)
	expect_eq(Acoustics.voice_age(me + 1), INF, "another peer never reported")
	Acoustics.reset()
	expect_eq(Acoustics.voice_age(me), INF, "reset forgets the report")


func test_tour_covers_every_placed_station_and_stands_clear_of_it() -> void:
	expect_eq(Autotest.TOUR.size(), 6, "pilot, sonar, map table, electrical, engineering, life support")
	for id: StringName in Autotest.TOUR:
		expect(SubLayout.has(id), "%s is in the program" % id)
		var p: Vector3 = Autotest.stand_point(id)
		expect(SubLayout.inside_hull(p.x, p.y + 1.0, p.z), "%s stand point %s is inside the hull" % [id, p])
		expect(p.distance_to(SubLayout.position(id)) <= Autotest.TOUR_REACH, "%s stand point is within reach" % id)
	expect(Autotest.TOUR_START + Autotest.TOUR_STEP * float(Autotest.TOUR.size()) < Autotest.REPORT_AT, "the tour ends before the report")
