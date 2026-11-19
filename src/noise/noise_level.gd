class_name NoiseLevel
extends RefCounted
## Conversions for the noise system. Sources report linear intensity
## (proportional to pressure squared) at 1 m; intensities add directly.
## Intensity 1.0 = [constant REF_DB] dB.

const REF_DB: float = 100.0
## Floor so log10 never sees zero.
const MIN_INTENSITY: float = 1e-12
## Spreading loss exponent: 1 = cylindrical (10 log r), 2 = spherical (20 log r).
const SPREADING_EXPONENT: float = 1.5


static func to_db(intensity: float) -> float:
	return 10.0 * log(maxf(intensity, MIN_INTENSITY)) / log(10.0) + REF_DB


static func from_db(db: float) -> float:
	return pow(10.0, (db - REF_DB) / 10.0)


## Intensity after travelling [param distance] metres from the 1 m reference.
static func attenuate(intensity: float, distance: float) -> float:
	return intensity / pow(maxf(distance, 1.0), SPREADING_EXPONENT)
