class_name SiteConstraint
extends Resource
## Base class for a rule a dive site must satisfy (a flat pad for an objective,
## a clear lane, a hiding place). Concrete kinds ([FlatPad], [Corridor],
## [ClearColumn]) are listed in [member SiteSpec.constraints]. The generator
## applies each as a soft mask: [method weight] says how strongly the
## constraint owns a point, [method target_y] what height it pulls toward.

## Short label for the terrain lab and logs.
@export var label: String = ""


## 0..1 influence at world x, z: 1 inside the constraint, easing to 0 across its
## falloff.
func weight(_x: float, _z: float) -> float:
	return 0.0


## Height (world y) this constraint pulls the ground toward at x, z, given the
## unconstrained height [param h]. The default leaves the ground alone.
func target_y(_x: float, _z: float, h: float) -> float:
	return h


## Problems with this constraint on its own, as human-readable lines.
func problems() -> PackedStringArray:
	return PackedStringArray()


## Horizontal anchor (x, z) of the constraint, for the lab and objectives.
func anchor() -> Vector2:
	return Vector2.ZERO
