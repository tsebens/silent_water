class_name SuspicionModel
extends RefCounted
## What the apex monster believes about the sub. Pure logic, no scene.
##
## Ladder: Unaware → Curious → Hunting → Committed → Contact, plus a
## heightened Patrol state after any arousal. Aroused states fade fast (~30 s
## after the last conclusive signal); patrol lingers for a minute or two.

enum State { UNAWARE, PATROL, CURIOUS, HUNTING, COMMITTED, CONTACT }

const STATE_NAMES: PackedStringArray = ["UNAWARE", "PATROL", "CURIOUS", "HUNTING", "COMMITTED", "CONTACT"]

var tuning: SuspicionTuning
var suspicion: float = 0.0
## 1 right after arousal, falls to 0 over patrol_linger_sec.
var alertness: float = 0.0
var state: State = State.UNAWARE
var has_heard: bool = false
## Estimated world position of the last conclusive signal.
var last_heard: Vector3 = Vector3.ZERO
var time_since_conclusive: float = INF
## Last computed SNR, for debugging and cues.
var last_snr_db: float = -INF

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(p_tuning: SuspicionTuning = null, seed_value: int = 0) -> void:
	tuning = p_tuning if p_tuning != null else SuspicionTuning.new()
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()


static func state_name(s: State) -> String:
	return STATE_NAMES[s]


## SNR (dB) of the sub at the monster, given what reaches it and the
## background there, both as linear intensity.
func snr_db(heard_intensity: float, background_intensity: float) -> float:
	return NoiseLevel.to_db(heard_intensity) + tuning.hearing_gain_db - NoiseLevel.to_db(background_intensity)


## Advances the model. [param snr]: from [method snr_db]. [param sub_pos]: true
## sub position (used only to place the noisy last-heard estimate).
## [param monster_pos]: for the commit range check.
func update(delta: float, snr: float, sub_pos: Vector3, monster_pos: Vector3) -> void:
	if state == State.CONTACT:
		return
	last_snr_db = snr
	if snr > 0.0:
		suspicion = minf(suspicion + tuning.gain_per_db * snr * delta, tuning.max_suspicion)
	if snr >= tuning.conclusive_snr_db:
		time_since_conclusive = 0.0
		has_heard = true
		var err: float = maxf(tuning.position_error_at_0db - tuning.position_error_per_db * snr, tuning.position_error_min)
		last_heard = sub_pos + _random_offset(err)
	else:
		time_since_conclusive += delta
		if time_since_conclusive > tuning.grace_sec:
			var rate: float = tuning.aroused_decay_per_sec if suspicion >= tuning.hunting_at - tuning.hysteresis else tuning.calm_decay_per_sec
			suspicion = maxf(suspicion - rate * delta, 0.0)
	if suspicion >= tuning.hunting_at:
		alertness = 1.0
	elif alertness > 0.0:
		alertness = maxf(alertness - delta / tuning.patrol_linger_sec, 0.0)
	state = _next_state(monster_pos)


## Called by the body when it reaches the sub.
func make_contact() -> void:
	state = State.CONTACT


func reset() -> void:
	suspicion = 0.0
	alertness = 0.0
	state = State.UNAWARE
	has_heard = false
	time_since_conclusive = INF
	last_snr_db = -INF


func is_aroused() -> bool:
	return state == State.HUNTING or state == State.COMMITTED


func _next_state(monster_pos: Vector3) -> State:
	var t: SuspicionTuning = tuning
	var h: float = t.hysteresis
	var s: float = suspicion
	match state:
		State.COMMITTED:
			if s < t.abandon_charge_below:
				return State.HUNTING
			return State.COMMITTED
		State.HUNTING:
			if s >= t.committed_at and _in_commit_range(monster_pos):
				return State.COMMITTED
			if s < t.hunting_at - h:
				return State.CURIOUS
			return State.HUNTING
		State.CURIOUS:
			if s >= t.hunting_at:
				return State.HUNTING
			if s < t.curious_at - h:
				return State.PATROL if alertness > 0.0 else State.UNAWARE
			return State.CURIOUS
		_:  # UNAWARE or PATROL
			if s >= t.hunting_at:
				return State.HUNTING
			if s >= t.curious_at:
				return State.CURIOUS
			return State.PATROL if alertness > 0.0 else State.UNAWARE


func _in_commit_range(monster_pos: Vector3) -> bool:
	return has_heard and monster_pos.distance_to(last_heard) <= tuning.commit_range


func _random_offset(radius: float) -> Vector3:
	var dir: Vector3 = Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-0.3, 0.3), _rng.randf_range(-1, 1))
	return dir.normalized() * _rng.randf() * radius if dir.length_squared() > 0.0 else Vector3.ZERO
