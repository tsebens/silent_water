class_name SiteSpec
extends Resource
## The macro shape of a dive site: everything [CanyonSite.height_at] needs
## apart from its fine-detail tuning. Deterministic: the same spec gives the
## same ground on every peer.

## Seed for every noise layer.
@export var seed: int = 0
## Canyon centreline control points as (x, z), ordered along z. The canyon is
## centred on the line through them; empty means x = 0.
@export var centreline: PackedVector2Array = PackedVector2Array()
## Plateau height (world y) the walls top out at.
@export var rim_y: float = -15.0
## Canyon floor height (world y).
@export var floor_y: float = -230.0
## Half-width of the flat floor, where the walls begin to lean (m).
@export var wall_foot: float = 32.0
## Where the walls reach the rim, before meander (m).
@export var wall_top: float = 62.0
## How far noise pushes the walls sideways along the canyon (m).
@export var wall_meander: float = 12.0
## Optional multiplier on the wall half-widths along the canyon: x is 0 at the
## south end and 1 at the north end. Null means 1 everywhere.
@export var width_curve: Curve
## Optional multiplier on the canyon's depth (rim minus floor) along the same
## 0..1 axis. Null means 1 everywhere.
@export var depth_curve: Curve
## South and north ends of the canyon (world z); both are closed off.
@export var south_z: float = 60.0
@export var north_z: float = -460.0
## Ledges cut into the walls.
@export var shelves: Array[ShelfSpec] = []
## Rules the generated site must satisfy ([FlatPad], [Corridor], [ClearColumn]).
@export var constraints: Array[SiteConstraint] = []


## World x of the canyon centreline at [param z]: linear between control points,
## held flat beyond the first and last.
func centre_x(z: float) -> float:
	var n: int = centreline.size()
	if n == 0:
		return 0.0
	if z <= centreline[0].y:
		return centreline[0].x
	for i: int in range(1, n):
		var b: Vector2 = centreline[i]
		if z <= b.y:
			var a: Vector2 = centreline[i - 1]
			return lerpf(a.x, b.x, inverse_lerp(a.y, b.y, z))
	return centreline[n - 1].x


## Width multiplier at [param z].
func width_scale(z: float) -> float:
	return 1.0 if width_curve == null else width_curve.sample(_along(z))


## Depth multiplier at [param z].
func depth_scale(z: float) -> float:
	return 1.0 if depth_curve == null else depth_curve.sample(_along(z))


func _along(z: float) -> float:
	return clampf(inverse_lerp(south_z, north_z, z), 0.0, 1.0)


## Label of the constraint that places the scan objective.
const OBJECTIVE_LABEL: String = "scan_objective"


## Combined constraint weight (0..1) at x, z: the strongest of them.
func constraint_weight(x: float, z: float) -> float:
	var m: float = 0.0
	for c: SiteConstraint in constraints:
		m = maxf(m, c.weight(x, z))
	return m


## Where the scan objective sits, read from the constraint labelled
## [constant OBJECTIVE_LABEL]: a [FlatPad] gives its height, a [ClearColumn]
## sits on the canyon floor. Vector3.INF if the spec has none.
func objective_position() -> Vector3:
	for c: SiteConstraint in constraints:
		if c.label != OBJECTIVE_LABEL:
			continue
		var at: Vector2 = c.anchor()
		if c is FlatPad:
			return Vector3(at.x, (c as FlatPad).height, at.y)
		if c is ClearColumn:
			return Vector3(at.x, floor_y, at.y)
	return Vector3.INF


## Conflicts between constraints: pads that overlap at different heights, and
## corridors steeper than they allow. Empty when the spec is consistent.
func validate() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for i: int in range(constraints.size()):
		out.append_array(constraints[i].problems())
		var p: FlatPad = constraints[i] as FlatPad
		if p == null:
			continue
		for j: int in range(i + 1, constraints.size()):
			var q: FlatPad = constraints[j] as FlatPad
			if q == null:
				continue
			if p.centre.distance_to(q.centre) < p.radius + q.radius and absf(p.height - q.height) > 0.05:
				out.append("pads '%s' and '%s' overlap at different heights (%.1f vs %.1f)" % [p.label, q.label, p.height, q.height])
	return out
