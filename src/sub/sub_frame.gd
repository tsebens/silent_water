class_name SubFrame
extends Node
## Owns the submarine's pose in the world and applies the sub-frame trick:
## the interior stays still at the origin, and the outside world is moved by
## the inverse of the sub's transform. See docs/sub_frame.md.
##
## The host is authoritative over [member sub_transform]; clients receive it
## through a MultiplayerSynchronizer and smooth toward it.

const GRAVITY: float = 9.8
## How quickly clients converge on the replicated pose (1/s).
const CLIENT_SMOOTHING: float = 12.0

## Node whose transform is set to the inverse of the sub's pose each frame.
@export var world_root: Node3D

## Replicated pose of the sub in world space. Written only by the host.
var sub_transform: Transform3D = Transform3D.IDENTITY
## Replicated linear velocity in world space, for later systems (noise, sonar).
var sub_velocity: Vector3 = Vector3.ZERO

## Pose actually used for rendering and gravity. Equals sub_transform on the
## host; smoothed toward it on clients.
var _render_transform: Transform3D = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if is_multiplayer_authority():
		_render_transform = sub_transform
	else:
		var w: float = 1.0 - exp(-CLIENT_SMOOTHING * delta)
		_render_transform = _render_transform.interpolate_with(sub_transform, w)
	if world_root != null:
		world_root.transform = _render_transform.affine_inverse()


## Pose used for rendering this frame.
func render_transform() -> Transform3D:
	return _render_transform


## World gravity expressed in the sub's local frame. A pitched or rolled sub
## tilts this vector, which is how crew feel trim without being slid around.
func gravity_in_sub() -> Vector3:
	return _render_transform.basis.inverse() * (Vector3.DOWN * GRAVITY)


## Converts a world-space point to sub-local (interior) space.
func world_to_sub(point: Vector3) -> Vector3:
	return _render_transform.affine_inverse() * point


## Converts a sub-local (interior) point to world space.
func sub_to_world(point: Vector3) -> Vector3:
	return _render_transform * point


## Host only: sets the authoritative pose.
func set_pose(new_transform: Transform3D, velocity: Vector3 = Vector3.ZERO) -> void:
	assert(is_multiplayer_authority(), "Only the host moves the sub")
	sub_transform = new_transform.orthonormalized()
	sub_velocity = velocity
