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
const HULL_SIZE: Vector3 = Vector3(4.0, 4.0, 10.0)
const HULL_CENTER: Vector3 = Vector3(0, 0.98, 0)
## Longest ray for the altitude readout (m). Reported when nothing is below.
const ALTITUDE_MAX: float = 200.0
## Minimum impact speed that counts as a strike.
const STRIKE_THRESHOLD: float = 0.15

# Noise at 1 m (linear intensity; 1.0 = 100 dB). See docs/noise.md.
## The electric motor at full output (~73 dB); falls off with the square of output.
const ENGINE_FULL_INTENSITY: float = 0.002
## Machinery hum whenever the engine is turning (~50 dB).
const ENGINE_IDLE_INTENSITY: float = 1e-5
## Blowing ballast with the valve fully open (~90 dB). Compressed air is loud.
const BLOW_INTENSITY: float = 0.1
## Flooding with the vent fully open (~70 dB).
const FLOOD_INTENSITY: float = 0.001
## Side thrusters at full turn (~73 dB).
const THRUSTER_INTENSITY: float = 0.002
## Hull strike impulse per (m/s)² of impact (~95 dB at 1 m/s).
const STRIKE_INTENSITY: float = 0.3

@export var sub_frame: SubFrame
## Pilot throttle, -1 (full astern) .. 1 (full ahead).
@export var throttle: SpringAxis
## Fraction of lever travel either side of centre where the ordered engine is 0.
@export_range(0.0, 0.9) var throttle_dead_zone: float = 0.15
@export var rudder: SpringAxis
@export var planes: SpringAxis
@export var flood_valve: Interactable
@export var blow_valve: Interactable
## Starting position in the world.
@export var start_position: Vector3 = CanyonSite.START_POSITION
## Ballast water at the start of a dive (tonnes). Empty: the sub floats.
@export var start_tank_t: float = 0.0
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
var bilge_water_t: float = 0.0
var surfaced: bool = false
## Net vertical acceleration from buoyancy (m/s²): + rises, − sinks.
var buoyancy: float = 0.0
var vertical_speed: float = 0.0

var model: SubPhysicsModel = SubPhysicsModel.new()

var _hull_shape: BoxShape3D = BoxShape3D.new()
var _power: PowerSystem


func _ready() -> void:
	model.position = start_position
	model.tank_water_t = start_tank_t
	_hull_shape.size = HULL_SIZE
	add_to_group(&"sub_readouts")
	add_to_group(&"sub_controller")
	add_to_group(&"noise_sources")


## Host: back to the start of the dive with every control at rest.
func reset_dive() -> void:
	model = SubPhysicsModel.new()
	model.position = start_position
	model.tank_water_t = start_tank_t
	for control: Interactable in [throttle, rudder, planes, flood_valve, blow_valve]:
		if control != null:
			control.host_set_value(0.0)
	sub_frame.set_pose(model.transform(), Vector3.ZERO)
	_update_readouts()
	enabled = true


func _physics_process(delta: float) -> void:
	if not enabled or not is_multiplayer_authority() or sub_frame == null:
		return
	var before: Vector3 = model.position
	var ordered: float = SubPhysicsModel.throttle_order(throttle.get_value(), throttle_dead_zone) if throttle != null else 0.0
	var rudder_input: float = rudder.get_value() if rudder != null else 0.0
	var power: PowerSystem = power_system()
	if power != null:
		power.set_engine_output(ordered)
		ordered = power.effective_engine_output()
		power.set_thruster_demand(rudder_input)
		model.thrusters_powered = power.is_powered(PowerSystem.Circuit.THRUSTERS)
	model.step(
		delta,
		ordered,
		rudder_input,
		planes.get_value() if planes != null else 0.0,
		flood_valve.get_normalized() if flood_valve != null else 0.0,
		blow_valve.get_normalized() if blow_valve != null else 0.0,
	)
	_resolve_collision(before)
	sub_frame.set_pose(model.transform(), model.velocity)
	_update_readouts()


## The sub's [PowerSystem], found lazily (it lives in the interior). Null if none.
func power_system() -> PowerSystem:
	if _power == null or not is_instance_valid(_power):
		_power = get_tree().get_first_node_in_group(PowerSystem.GROUP) as PowerSystem if is_inside_tree() else null
	return _power


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
		Acoustics.add_impulse(STRIKE_INTENSITY * impact * impact, 1.5)


func _update_readouts() -> void:
	depth = model.depth()
	surfaced = model.is_surfaced()
	buoyancy = model.buoyancy_accel()
	vertical_speed = model.velocity.y
	speed = model.forward_speed()
	heading_deg = fposmod(-rad_to_deg(model.angles.y), 360.0)
	pitch_deg = rad_to_deg(model.angles.x)
	engine_output = model.engine
	tank_fraction = model.tank_water_t / model.tank_capacity_t
	air_fraction = model.air_t / model.air_capacity_t
	bilge_water_t = model.bilge_water_t


## Engine noise (linear intensity). Valid on every peer from replicated readouts.
func engine_intensity() -> float:
	var e: float = absf(engine_output)
	if e < 0.01:
		return 0.0
	return ENGINE_IDLE_INTENSITY + ENGINE_FULL_INTENSITY * e * e


func blow_intensity() -> float:
	return BLOW_INTENSITY * (blow_valve.get_normalized() if blow_valve != null and model.air_t > 0.0 else 0.0)


func flood_intensity() -> float:
	return FLOOD_INTENSITY * (flood_valve.get_normalized() if flood_valve != null else 0.0)


## Noise system hook (polled on the host).
## With a [PowerSystem] present, the motor and generator noise are that
## system's own source, so the engine term is left out here (no double count).
func noise_intensity() -> float:
	var engine: float = engine_intensity() if power_system() == null else 0.0
	return engine + blow_intensity() + flood_intensity() + thruster_intensity()


func noise_breakdown() -> Dictionary:
	var parts: Dictionary = {
		"blowing ballast": blow_intensity(),
		"flooding ballast": flood_intensity(), "thrusters": thruster_intensity(),
	}
	var power: PowerSystem = power_system()
	if power == null:
		parts["engine"] = engine_intensity()
	else:
		parts.merge(power.noise_breakdown())
	return parts


## Side thrusters whirring while the pilot turns (~73 dB at full). Silent
## when the THRUSTERS circuit is unpowered.
func thruster_intensity() -> float:
	if rudder == null:
		return 0.0
	var power: PowerSystem = power_system()
	if power != null and not power.is_powered(PowerSystem.Circuit.THRUSTERS):
		return 0.0
	return THRUSTER_INTENSITY * absf(rudder.get_value())


## Height above the terrain straight below the sub (m), clamped to
## [constant ALTITUDE_MAX]. Computed locally on every peer from the terrain it
## already has, so nothing is replicated. In render space the sub sits at the
## origin and world-down is the inverse of the sub's rotation applied to down.
func altitude() -> float:
	if sub_frame == null or not sub_frame.is_inside_tree():
		return ALTITUDE_MAX
	var space: PhysicsDirectSpaceState3D = sub_frame.get_viewport().world_3d.direct_space_state
	if space == null:
		return ALTITUDE_MAX
	var down: Vector3 = sub_frame.render_transform().basis.inverse() * Vector3.DOWN
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		Vector3.ZERO, down.normalized() * ALTITUDE_MAX, LAYER_EXTERIOR)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return ALTITUDE_MAX
	return (hit["position"] as Vector3).length()


## Reads a readout by name, for gauges. Altitude is computed on demand; the
## rest are replicated.
func readout(property: StringName) -> float:
	if property == &"altitude":
		return altitude()
	if property == &"top_speed":
		return model.top_forward_speed()
	if property == &"bilge_limit":
		return model.max_surfaceable_bilge_t()
	return float(get(property))
