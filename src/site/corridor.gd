class_name Corridor
extends SiteConstraint
## A lane from [member a] to [member b] (x, y, z; y is the surface height at
## each end). Inside [member width] the ground follows the straight ramp
## between the ends, so its slope is |dy| / length everywhere along it. That
## must not exceed [member max_slope] (rise over run).

@export var a: Vector3 = Vector3.ZERO
@export var b: Vector3 = Vector3(0, 0, -50)
## Full width of the lane (m).
@export var width: float = 12.0
## Maximum allowed slope, rise over run.
@export var max_slope: float = 0.5
@export var falloff: float = 10.0


## Closest point parameter t (0..1) along the path to x, z.
func _along(x: float, z: float) -> float:
	var pa: Vector2 = Vector2(a.x, a.z)
	var ab: Vector2 = Vector2(b.x, b.z) - pa
	var len2: float = ab.length_squared()
	if len2 < 0.000001:
		return 0.0
	return clampf((Vector2(x, z) - pa).dot(ab) / len2, 0.0, 1.0)


func horizontal_length() -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


## Slope of the ramp, rise over run.
func slope() -> float:
	var run: float = horizontal_length()
	return INF if run < 0.000001 else absf(b.y - a.y) / run


func weight(x: float, z: float) -> float:
	var t: float = _along(x, z)
	var on: Vector2 = Vector2(a.x, a.z).lerp(Vector2(b.x, b.z), t)
	var d: float = Vector2(x, z).distance_to(on)
	return 1.0 - smoothstep(width * 0.5, width * 0.5 + maxf(falloff, 0.001), d)


func target_y(x: float, z: float, _h: float) -> float:
	return lerpf(a.y, b.y, _along(x, z))


func problems() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if slope() > max_slope:
		out.append("corridor '%s' slope %.2f exceeds max %.2f" % [label, slope(), max_slope])
	return out


func anchor() -> Vector2:
	return Vector2(a.x, a.z)
