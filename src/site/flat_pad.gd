class_name FlatPad
extends SiteConstraint
## A level disc: height blends to [member height] inside [member radius] and
## eases back to the natural ground over [member falloff].

@export var centre: Vector2 = Vector2.ZERO
@export var radius: float = 10.0
## World y the pad is levelled to.
@export var height: float = -100.0
@export var falloff: float = 12.0


func weight(x: float, z: float) -> float:
	var d: float = Vector2(x, z).distance_to(centre)
	return 1.0 - smoothstep(radius, radius + maxf(falloff, 0.001), d)


func target_y(_x: float, _z: float, _h: float) -> float:
	return height


func anchor() -> Vector2:
	return centre
