extends TestCase

const DT: float = 0.1
const S: SuspicionModel.State = SuspicionModel.State.UNAWARE

var m: SuspicionModel


func before_each() -> void:
	m = SuspicionModel.new(SuspicionTuning.new(), 42)


func _run(seconds: float, snr: float, monster: Vector3 = Vector3.ZERO, sub: Vector3 = Vector3(50, 0, 0)) -> void:
	for i: int in range(int(round(seconds / DT))):
		m.update(DT, snr, sub, monster)


func test_quiet_sub_stays_unheard() -> void:
	_run(60.0, -5.0)
	expect_eq(m.state, SuspicionModel.State.UNAWARE)
	expect_eq(m.suspicion, 0.0)


func test_snr_uses_hearing_gain() -> void:
	# 45 dB heard + 30 dB gain against a 62 dB ocean = 13 dB.
	expect_near(m.snr_db(NoiseLevel.from_db(45.0), NoiseLevel.from_db(62.0)), 13.0, 0.001)


func test_escalates_up_the_ladder() -> void:
	_run(2.5, 10.0)
	expect_eq(m.state, SuspicionModel.State.CURIOUS)
	_run(3.0, 10.0)
	expect_eq(m.state, SuspicionModel.State.HUNTING)
	_run(5.0, 10.0)
	expect_eq(m.state, SuspicionModel.State.COMMITTED, "close enough to charge")


func test_does_not_commit_from_far_away() -> void:
	_run(20.0, 10.0, Vector3(1000, 0, 0))
	expect_eq(m.state, SuspicionModel.State.HUNTING, "too far to charge")


func test_aroused_fades_within_about_30_s() -> void:
	_run(20.0, 15.0)
	expect_eq(m.suspicion, 100.0)
	expect(m.is_aroused())
	_run(29.0, -10.0)
	expect(m.is_aroused(), "still aroused just before 30 s (s=%f)" % m.suspicion)
	_run(5.0, -10.0)
	expect(not m.is_aroused(), "aroused should end ~30 s after the last signal (s=%f, %s)" % [m.suspicion, SuspicionModel.state_name(m.state)])


func test_patrol_lingers_then_calms() -> void:
	_run(20.0, 15.0)
	_run(90.0, -10.0)
	expect_eq(m.state, SuspicionModel.State.PATROL, "patrol lingers after arousal (s=%f)" % m.suspicion)
	_run(60.0, -10.0)
	expect_eq(m.state, SuspicionModel.State.UNAWARE, "calm within ~2 minutes of arousal ending")


func test_curious_without_arousal_returns_to_unaware_not_patrol() -> void:
	_run(2.5, 10.0)
	expect_eq(m.state, SuspicionModel.State.CURIOUS)
	_run(60.0, -10.0)
	expect_eq(m.state, SuspicionModel.State.UNAWARE)


func test_grace_period_before_decay() -> void:
	_run(3.0, 10.0)
	var s: float = m.suspicion
	_run(1.5, -10.0)
	expect_near(m.suspicion, s, 0.001, "no decay during grace")


func test_faint_noise_raises_suspicion_without_a_fix() -> void:
	_run(10.0, 3.0)
	expect(m.suspicion > 0.0)
	expect(not m.has_heard, "below conclusive SNR there's no position fix")


func test_last_heard_is_sharper_with_louder_noise() -> void:
	var errors_loud: float = 0.0
	var errors_faint: float = 0.0
	var sub: Vector3 = Vector3(100, 0, 0)
	for i: int in range(50):
		m.update(DT, 20.0, sub, Vector3.ZERO)
		errors_loud += m.last_heard.distance_to(sub)
		m.update(DT, 6.5, sub, Vector3.ZERO)
		errors_faint += m.last_heard.distance_to(sub)
	expect(errors_loud < errors_faint, "loud %f vs faint %f" % [errors_loud, errors_faint])


func test_charge_abandoned_when_suspicion_drops() -> void:
	_run(20.0, 15.0)
	expect_eq(m.state, SuspicionModel.State.COMMITTED)
	_run(25.0, -10.0)
	expect_eq(m.state, SuspicionModel.State.HUNTING)


func test_contact_is_terminal_until_reset() -> void:
	_run(20.0, 15.0)
	m.make_contact()
	_run(60.0, -10.0)
	expect_eq(m.state, SuspicionModel.State.CONTACT)
	m.reset()
	expect_eq(m.state, SuspicionModel.State.UNAWARE)
