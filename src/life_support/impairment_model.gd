class_name ImpairmentModel
extends RefCounted
## Pure per-player model of bad-air effects. Feed it the cabin CO2 and O2 each
## step; read smooth effect outputs and the incapacitated state.

var params: ImpairmentParams
## Combined effect strength, 0 to 1: the larger of the CO2 and O2 sources.
var strength: float = 0.0
## True from the drop until recovery.
var incapacitated: bool = false
## Blur left from a recovery, 1 just after standing up, fading to 0.
var linger_blur: float = 0.0
var _linger_left: float = 0.0


func _init(p: ImpairmentParams = null) -> void:
	params = p if p != null else ImpairmentParams.new()


## Ladder strength at [param ppm], linear between the table points.
func strength_for_ppm(ppm: float) -> float:
	var xs: PackedFloat32Array = params.ladder_ppm
	var ys: PackedFloat32Array = params.ladder_strengths
	var n: int = mini(xs.size(), ys.size())
	if n == 0:
		return 0.0
	if ppm <= xs[0]:
		return ys[0]
	for i: int in range(1, n):
		if ppm <= xs[i]:
			var t: float = (ppm - xs[i - 1]) / maxf(xs[i] - xs[i - 1], 0.0001)
			return lerpf(ys[i - 1], ys[i], t)
	return ys[n - 1]


## The CO2 ppm whose ladder position equals what [param cabin_o2] does: the O2
## deficit mapped linearly across the ladder.
func o2_equivalent_ppm(cabin_o2: float) -> float:
	var xs: PackedFloat32Array = params.ladder_ppm
	var lo: float = xs[0]
	var hi: float = xs[xs.size() - 1]
	var deficit: float = 1.0 - clampf(cabin_o2, 0.0, 1.0)
	var span: float = maxf(params.o2_deficit_for_max - params.o2_deficit_start, 0.0001)
	var t: float = clampf((deficit - params.o2_deficit_start) / span, 0.0, 1.0)
	return lerpf(lo, hi, t)


func strength_for_o2(cabin_o2: float) -> float:
	return strength_for_ppm(o2_equivalent_ppm(cabin_o2))


## Advance by [param dt] seconds with the cabin's current air.
func step(dt: float, co2_ppm: float, cabin_o2: float) -> void:
	var equivalent: float = maxf(co2_ppm, o2_equivalent_ppm(cabin_o2))
	strength = maxf(strength_for_ppm(co2_ppm), strength_for_o2(cabin_o2))
	if incapacitated:
		if equivalent < params.recover_ppm:
			incapacitated = false
			linger_blur = params.linger_blur_start
			_linger_left = params.linger_blur_seconds
	else:
		if equivalent >= params.incapacitate_ppm:
			incapacitated = true
			linger_blur = 0.0
			_linger_left = 0.0
	if not incapacitated and _linger_left > 0.0:
		_linger_left = maxf(_linger_left - dt, 0.0)
		linger_blur = params.linger_blur_start * _linger_left / maxf(params.linger_blur_seconds, 0.0001)
		if _linger_left <= 0.0:
			linger_blur = 0.0


## Blur amount, 0 to 1: the air's blur or the lingering blur, whichever is more.
func blur() -> float:
	return clampf(maxf(strength * params.blur_at_full, linger_blur), 0.0, 1.0)


## Vignette narrowing, 0 to 1, from the edges.
func vignette() -> float:
	return _above(params.vignette_start_strength) * params.vignette_at_full


## Fraction of walking speed lost.
func movement_slowdown() -> float:
	return _above(params.movement_start_strength) * params.slowdown_at_full


## Swing of the wander added to input.
func wander_swing() -> float:
	return _above(params.movement_start_strength) * params.wander_swing_at_full


func _above(start: float) -> float:
	return clampf((strength - start) / maxf(1.0 - start, 0.0001), 0.0, 1.0)
