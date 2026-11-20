class_name SonarReadouts
extends RefCounted
## Pure maths for the sonar bezel gauges. Everything here uses only what a
## hydrophone can hear: received level through the beam, and the bow-relative
## bearing of that sound. No range is ever returned.


## Received level (dB) of one source on the hydrophone trained at [param trained]:
## level at the sub plus the beam gain. [param p] is in render space.
static func received_db(source_db: float, p: Vector3, trained: float) -> float:
	var at_sub: float = OutsideAudio.level_at_sub(source_db, p)
	return at_sub + SonarStation.beam_gain_db(SonarStation.bearing_of(p), trained)


## Sums received levels (dB) as intensity. Returns [param floor_db] when empty.
static func sum_db(levels_db: PackedFloat32Array, floor_db: float) -> float:
	var total: float = 0.0
	for l: float in levels_db:
		total += NoiseLevel.from_db(l)
	if total <= 0.0:
		return floor_db
	return maxf(NoiseLevel.to_db(total), floor_db)


## Bearing rate in deg/min between two bow-relative bearings (degrees,
## clockwise) [param dt] seconds apart. Positive = bearing increasing
## (clockwise, to starboard). Takes the short way round the circle.
static func rate_deg_per_min(prev_bearing: float, cur_bearing: float, dt: float) -> float:
	if dt <= 0.0:
		return 0.0
	var d: float = fposmod(cur_bearing - prev_bearing + 180.0, 360.0) - 180.0
	return d / dt * 60.0
