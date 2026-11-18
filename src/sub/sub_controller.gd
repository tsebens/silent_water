class_name SubController
extends Node
## Host-side driver for the submarine. Reads the crew's controls, steps the
## [SubPhysicsModel], resolves terrain collisions, and writes the pose to the
## [SubFrame]. Instrument readouts are replicated to clients for gauges.

## Emitted on the host when the hull hits terrain. [param speed] is the
## impact speed along the contact normal (m/s).
signal hull_strike(speed: float)

const LAYER_EXTERIOR: int = 1 << 3
## Hull collision box in sub-local space (matches the interior's outer shell).
const HULL_SIZE: Vector3 = Vector3(3.8, 3.2, 12.8)
const HULL_CENTER: Vector3 = Vector3(0, 1.2, 0)
## Minimum impact speed that counts as a strike.
const STRIKE_THRESHOLD: float = 0.15

@export var sub_frame: SubFrame
@export var telegraph: Telegraph
@export var rudder: SpringAxis
@export var planes: SpringAxis
@export var flood_valve: Interactable
@export var blow_valve: Interactable
## Starting position in the world.
@export var start_position: Vector3 = Vector3(0, -15, 0)
## When false the model is not stepped (tests that drive the pose directly).
@export var enabled: bool = true

# Replicated readouts for gauges (written by the host).
var depth: float = 0.0
var speed: float = 0.0
var heading_deg: float = 0.0
var pitch_deg: float = 0.0
var engine_output: float = 0.0
var tank_fraction: float = 0.5
var air_fraction: float = 1.0

var model: SubPhysicsModel = SubPhysicsModel.new()

var _hull_shape: BoxShape3D = BoxShape3D.new()


func _ready() -> void:
	model.position = start_position
	_hull_shape.size = HULL_SIZE
	add_to_group(&"sub_readouts")


func _physics_process(delta: float) -> void:
	if not enabled or not is_multiplayer_authority() or sub_frame == null:
		return
	var before: Vector3 = model.position
	model.step(
		delta,
		telegraph.engine_order() if telegraph != null else 0.0,
		rudder.get_value() if rudder != null else 0.0,
		planes.get_value() if planes != null else 0.0,
		flood_valve.get_normalized() if flood_valve != null else 0.0,
		blow_valve.get_normalized() if blow_valve != null else 0.0,
	)
	_resolve_collision(before)
	sub_frame.set_pose(model.transform(), model.velocity)
	_update_readouts()


## Resolves the hull against the exterior. The world root is still at the
## inverse of the last pose, so in render space the hull starts at the origin
## and moves by the step's displacement expressed in sub-local axes.
## 1. Sweep the hull along the motion to stop fast moves tunnelling through.
## 2. Push the hull out of anything it still overlaps, using contact pairs.
func _resolve_collision(before: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = sub_frame.get_viewport().world_3d.direct_space_state
	if space == null:
		return
	var last_basis: Basis = sub_frame.sub_transform.basis
	var to_local: Basis = last_basis.inverse()
	var motion_local: Vector3 = to_local * (model.position - before)
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = _hull_shape
	query.collision_mask = LAYER_EXTERIOR
	query.margin = 0.02

	query.transform = Transform3D(Basis(), HULL_CENTER)
	query.motion = motion_local
	var cast: PackedFloat32Array = space.cast_motion(query)
	if cast.size() == 2 and cast[1] < 1.0:
		motion_local *= cast[0]
		model.position = before + last_basis * motion_local
	query.motion = Vector3.ZERO

	var push_total: Vector3 = Vector3.ZERO
	for i: int in range(4):
		query.transform = Transform3D(Basis(), HULL_CENTER + motion_local + push_total)
		var pairs: Array[Vector3] = space.collide_shape(query, 16)
		if pairs.is_empty():
			break
		var deepest: Vector3 = Vector3.ZERO
		for j: int in range(0, pairs.size() - 1, 2):
			var push: Vector3 = pairs[j + 1] - pairs[j]
			if push.length_squared() > deepest.length_squared():
				deepest = push
		if deepest.length_squared() < 1e-8:
			break
		push_total += deepest
	if push_total == Vector3.ZERO and cast.size() == 2 and cast[1] >= 1.0:
		return
	var normal_world: Vector3 = last_basis * push_total
	if normal_world.length_squared() < 1e-8:
		# Stopped by the sweep without overlap: the normal opposes the motion.
		normal_world = -(model.position - before)
		if normal_world.length_squared() < 1e-8:
			return
	model.position += last_basis * push_total
	var impact: float = model.collide(normal_world.normalized())
	if impact > STRIKE_THRESHOLD:
		hull_strike.emit(impact)
		print("[sub] hull strike %.2f m/s" % impact)


func _update_readouts() -> void:
	depth = model.depth()
	speed = model.forward_speed()
	heading_deg = fposmod(-rad_to_deg(model.angles.y), 360.0)
	pitch_deg = rad_to_deg(model.angles.x)
	engine_output = model.engine
	tank_fraction = model.tank_water_t / model.tank_capacity_t
	air_fraction = model.air_t / model.air_capacity_t


## Reads a replicated readout by name, for gauges.
func readout(property: StringName) -> float:
	return float(get(property))
