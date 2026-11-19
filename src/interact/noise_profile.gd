class_name NoiseProfile
extends Resource
## How loud a physical control is, as a function of how fast it moves.
## Intensity is in the game's linear noise-intensity units (proportional to
## pressure squared), so sources can be summed directly. See the noise system.

## Intensity while the control is still.
@export var idle_intensity: float = 0.0
## Intensity when moving at or above [member clank_rate].
@export var max_intensity: float = 1.0
## Normalized rate (full range per second) that produces max intensity.
@export var clank_rate: float = 2.0
## >1 keeps gentle movement quiet and makes fast movement loud.
@export var exponent: float = 2.0


func intensity_for_rate(normalized_rate: float) -> float:
	var t: float = clampf(normalized_rate / maxf(clank_rate, 0.0001), 0.0, 1.0)
	return idle_intensity + (max_intensity - idle_intensity) * pow(t, exponent)
