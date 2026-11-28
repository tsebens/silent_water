class_name ClimbTransit
extends Interactable
## A short authored way between two sub-local points: a ladder, a trunk shaft.
## E at either end moves the player along [member path] over [member duration]
## seconds; movement is locked and the view stays free. One occupant at a time
## (the Interactable grab lock, host-decided). The owner moves and replicates
## the sub-local pose as it does for walking ([Player] drives the motion).
##
## The path is given in this node's local space. The first point is the foot,
## the last the head. A path may leave [constant Player.INTERIOR_BOUNDS]; then
## [member extra_bounds] (this node's local space) must cover the part outside.

## Foot to head, in this node's local space. At least two points.
@export var path: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(0.0, 2.5, 0.0)])
## Seconds for the whole climb.
@export_range(1.0, 4.0, 0.1) var duration: float = 2.0
## Extra sub-local bounds valid for the player while on this transit (render
## space is the sub frame here: the node is expected under the still interior).
@export var extra_bounds: AABB = AABB()
## How close (m) the player must stand to an end to use it.
@export var reach_m: float = 1.2

## Optional: returns true when the way is open. Unset means always open.
var gate: Callable = Callable()


## True when the way is open.
func is_open() -> bool:
	return not gate.is_valid() or bool(gate.call())


## Path points in sub-local space (this node's transform applied).
func world_points() -> PackedVector3Array:
	var xf: Transform3D = global_transform if is_inside_tree() else transform
	var out: PackedVector3Array = PackedVector3Array()
	for p: Vector3 in path:
		out.append(xf * p)
	return out


## Total path length (m).
func path_length() -> float:
	var total: float = 0.0
	for i: int in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## Sub-local position at fraction [param t] (0..1) of the way, going up (foot
## to head) or down. Even speed along the path.
func point_at(t: float, going_up: bool) -> Vector3:
	var pts: PackedVector3Array = world_points()
	if pts.size() == 0:
		return Vector3.ZERO
	if not going_up:
		pts.reverse()
	var want: float = clampf(t, 0.0, 1.0) * path_length()
	for i: int in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if want <= seg or i == pts.size() - 1:
			return pts[i - 1].lerp(pts[i], clampf(want / maxf(seg, 0.0001), 0.0, 1.0))
		want -= seg
	return pts[pts.size() - 1]


## Whether [param pos] (sub-local) is inside the interior bounds or this
## transit's extra bounds.
func bounds_allow(pos: Vector3) -> bool:
	if Player.INTERIOR_BOUNDS.has_point(pos):
		return true
	var xf: Transform3D = global_transform if is_inside_tree() else transform
	return extra_bounds.size != Vector3.ZERO and (xf * extra_bounds).has_point(pos)


## True when [param pos] is within reach of the foot (or head).
func near_end(pos: Vector3, at_head: bool) -> bool:
	var pts: PackedVector3Array = world_points()
	if pts.size() == 0:
		return false
	var end: Vector3 = pts[pts.size() - 1] if at_head else pts[0]
	return pos.distance_to(end) <= reach_m


## Which way a player at [param pos] would go: true when nearer the foot.
func going_up_from(pos: Vector3) -> bool:
	var pts: PackedVector3Array = world_points()
	if pts.size() == 0:
		return true
	return pos.distance_squared_to(pts[0]) <= pos.distance_squared_to(pts[pts.size() - 1])


## Asks to climb as [param peer]: refused when the gate is shut or someone else
## is climbing. On success the peer holds the transit until [method leave].
func try_enter(peer: int, pos: Vector3) -> bool:
	if not is_open():
		return false
	if not near_end(pos, not going_up_from(pos)):
		return false
	return state.try_grab(peer)


## Gives the transit up (the climb ended or was broken off).
func leave(peer: int) -> void:
	state.release(peer)


func occupant() -> int:
	return state.holder


func interaction_hint() -> String:
	return "press E to climb" if is_open() else "blocked"
