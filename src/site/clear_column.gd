class_name ClearColumn
extends SiteConstraint
## A vertical column kept clear: inside [member radius] the fine detail and
## rock crags are removed, so nothing rises above the smooth ground profile,
## and no boulders are placed. Eases out over the outer third of the radius.

@export var centre: Vector2 = Vector2.ZERO
@export var radius: float = 15.0


func weight(x: float, z: float) -> float:
	var d: float = Vector2(x, z).distance_to(centre)
	return 1.0 - smoothstep(radius * 0.7, radius, d)


func anchor() -> Vector2:
	return centre
