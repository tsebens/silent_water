class_name SubPhysicsModel
extends RefCounted
## Network- and scene-free model of the submarine's handling. The host steps it
## with control inputs; it owns position, orientation and velocities in world
## space (+Y up, surface at y = 0, bow along -Z).
##
## Masses are in tonnes and forces are expressed as accelerations, which keeps
## the numbers readable. The model is deliberately simple and heavy: big
## depth changes come from ballast, the planes trim, the engine is slow to
## respond, and the hull rights itself.

const SEAWATER_DENSITY: float = 1.025  # tonnes per m³
const G: float = 9.8

# --- Hull --------------------------------------------------------------------
## Displaced mass when fully submerged (tonnes).
var displacement_t: float = 150.0
## Hull, machinery and fixed gear (tonnes). Tuned for neutral at ~half tank.
var dry_mass_t: float = 139.64
## Crew and carried cargo (tonnes). Add salvage here.
var payload_t: float = 0.36

# --- Ballast -----------------------------------------------------------------
var tank_capacity_t: float = 20.0
## Water in the main ballast tank, 0..tank_capacity_t.
var tank_water_t: float = 10.0
## Flood rate with the vent fully open (tonnes/s). Doubled again in #448: an
## empty 20 t tank now fills in about 14 s.
var flood_rate_t: float = 1.4
## Blow rate with the blow valve fully open (tonnes/s). A full 20 t tank now
## blows in about 7 s.
var blow_rate_t: float = 2.8
## High-pressure air, measured in tonnes of water it can still expel.
var air_capacity_t: float = 60.0
var air_t: float = 60.0

# --- Bilge -------------------------------------------------------------------
## Water that has leaked into the hull (tonnes). Uncapped: it adds weight and
## is pumped out, but never destroys the sub by itself.
var bilge_water_t: float = 0.0
## Footprint of the flooded interior (m²). Water height = tonnes / footprint.
const INTERIOR_FOOTPRINT_M2: float = 20.0

# --- Engine ------------------------------------------------------------------
## Normalized engine output, -1 (full astern) .. 1 (full ahead).
var engine: float = 0.0
## How fast engine output follows the ordered speed (per second).
var engine_spool_rate: float = 0.4
## Forward acceleration at full ahead (m/s²). Astern gives half.
## Thrust and fore/aft drag were both doubled in M7 (#50): same top speed,
## twice as quick to speed up and slow down.
var thrust_accel: float = 0.3

# --- Hydrodynamics -----------------------------------------------------------
## Quadratic drag coefficients in the body frame: x = sideways, y = vertical,
## z = fore/aft. Chosen for ~3 m/s top speed and ~1 m/s terminal sink rate.
var drag: Vector3 = Vector3(0.5, 0.6, 0.0333)
## Yaw acceleration per unit rudder per m/s of forward speed (rad/s² ).
var rudder_authority: float = 0.02
## Yaw acceleration from the side thrusters at full rudder input (rad/s²).
## They turn the sub even when stopped (~8.6°/s at full, steady state);
## the rudder adds more once there's way on.
var thruster_yaw_accel: float = 0.09
## Pitch acceleration per unit planes per m/s of forward speed (rad/s²).
var planes_authority: float = 0.02
## Righting (metacentric) stiffness for pitch and roll (1/s²).
var righting: float = 0.15
## Angular damping for yaw, pitch and roll (1/s).
var angular_damping: Vector3 = Vector3(0.6, 0.8, 0.8)
## Roll induced by turning (heel), per unit yaw rate × speed.
var heel_factor: float = 0.05
var max_pitch: float = deg_to_rad(30.0)

# --- State ---------------------------------------------------------------------
var position: Vector3 = Vector3.ZERO
var velocity: Vector3 = Vector3.ZERO
## Euler angles: x = pitch (nose up positive), y = yaw, z = roll.
var angles: Vector3 = Vector3.ZERO
var angular_velocity: Vector3 = Vector3.ZERO


func basis() -> Basis:
	return Basis.from_euler(angles)


func transform() -> Transform3D:
	return Transform3D(basis(), position)


func total_mass_t() -> float:
	return dry_mass_t + payload_t + tank_water_t + bilge_water_t


## Bilge tonnage at which, with the tank fully blown, buoyancy at the surface
## can no longer lift the hull above the waterline: the reserve buoyancy
## (displacement minus dry mass and payload). 10.0 t with the default hull.
func max_surfaceable_bilge_t() -> float:
	return displacement_t - dry_mass_t - payload_t


## Adds (positive) or pumps out (negative) bilge water. Returns the change.
func change_bilge(delta_t: float) -> float:
	var before: float = bilge_water_t
	bilge_water_t = maxf(bilge_water_t + delta_t, 0.0)
	return bilge_water_t - before


## Height (m) of the bilge water over the interior floor (1 t = 1 m³).
static func bilge_height_m(tonnes: float) -> float:
	return tonnes / INTERIOR_FOOTPRINT_M2


## Net vertical acceleration from buoyancy alone (positive rises).
func buoyancy_accel() -> float:
	var lift_t: float = displacement_t * submerged_fraction()
	return (lift_t - total_mass_t()) / total_mass_t() * G


## Hull extent below and above the sub's origin (m), from the program via SubLayout.
static func hull_bottom() -> float:
	return SubLayout.hull_bottom_y()


static func hull_top() -> float:
	return SubLayout.hull_top_y()


## Vertical damping while the hull is partly out of the water (1/s).
const SURFACE_DAMPING: float = 1.5


## Fraction of the hull below the surface (y = 0).
func submerged_fraction() -> float:
	return clampf((0.0 - (position.y + hull_bottom())) / (hull_top() - hull_bottom()), 0.0, 1.0)


## True when the top of the hull breaks the surface.
func is_surfaced() -> bool:
	return position.y + hull_top() > 0.0


func depth() -> float:
	return maxf(-position.y, 0.0)


## Forward speed through the water (m/s); negative when going astern.
func forward_speed() -> float:
	return (basis().inverse() * velocity).dot(Vector3.FORWARD)


## Maps the throttle lever position (-1..1) to the ordered engine (-1..1).
## Inside ±[param dead_zone] of centre the order is exactly 0; beyond it the
## order ramps linearly to ±1 at full travel, so there is no jump at the edge.
static func throttle_order(lever: float, dead_zone: float) -> float:
	var l: float = clampf(lever, -1.0, 1.0)
	var dz: float = clampf(dead_zone, 0.0, 0.99)
	var mag: float = absf(l)
	if mag <= dz:
		return 0.0
	return signf(l) * (mag - dz) / (1.0 - dz)


## Advances the model.
## [param ordered_engine]: the pilot's throttle, -1..1.
## [param rudder], [param planes]: -1..1. Positive rudder turns to starboard;
## positive planes pitch the nose down (dive).
## [param flood], [param blow]: valve openings 0..1.
func step(delta: float, ordered_engine: float, rudder: float, planes: float, flood: float, blow: float) -> void:
	_step_ballast(delta, clampf(flood, 0.0, 1.0), clampf(blow, 0.0, 1.0))
	engine = move_toward(engine, clampf(ordered_engine, -1.0, 1.0), engine_spool_rate * delta)

	var b: Basis = basis()
	var v_body: Vector3 = b.inverse() * velocity
	var fwd_speed: float = -v_body.z

	# Linear: thrust along the bow, anisotropic quadratic drag, buoyancy.
	var thrust: float = thrust_accel * (engine if engine >= 0.0 else engine * 0.5)
	var a_body: Vector3 = Vector3(0.0, 0.0, -thrust)
	a_body -= drag * v_body * v_body.abs()
	var accel: Vector3 = b * a_body + Vector3.UP * buoyancy_accel()
	velocity += accel * delta
	position += velocity * delta

	# Angular: control surfaces need water flowing over them.
	var flow: float = absf(fwd_speed)
	var flow_sign: float = signf(fwd_speed) if fwd_speed != 0.0 else 1.0
	var yaw_acc: float = -rudder * (rudder_authority * flow * flow_sign + thruster_yaw_accel)
	var pitch_acc: float = -planes * planes_authority * flow * flow_sign - righting * sin(angles.x)
	var roll_acc: float = -righting * sin(angles.z) - heel_factor * angular_velocity.y * fwd_speed
	angular_velocity += Vector3(pitch_acc, yaw_acc, roll_acc) * delta
	angular_velocity.x -= angular_velocity.x * angular_damping.y * delta
	angular_velocity.y -= angular_velocity.y * angular_damping.x * delta
	angular_velocity.z -= angular_velocity.z * angular_damping.z * delta
	angles += angular_velocity * delta
	angles.x = clampf(angles.x, -max_pitch, max_pitch)
	angles.y = wrapf(angles.y, -PI, PI)

	# Near the surface, waves and wake damp bobbing quickly.
	var awash: float = submerged_fraction()
	if awash < 1.0:
		velocity.y -= velocity.y * SURFACE_DAMPING * delta

	# Backstop: never fly out of the water.
	if position.y > 0.0:
		position.y = 0.0
		velocity.y = minf(velocity.y, 0.0)


func _step_ballast(delta: float, flood: float, blow: float) -> void:
	var flooded: float = flood * flood_rate_t * delta
	# The vent sits high on the hull: it only floods once it's under water.
	if position.y + hull_top() > 0.5:
		flooded = 0.0
	# Air only goes out with water: an empty tank uses no more air.
	var blown: float = minf(minf(blow * blow_rate_t * delta, air_t), tank_water_t + flooded)
	tank_water_t = clampf(tank_water_t + flooded - blown, 0.0, tank_capacity_t)
	air_t = maxf(air_t - blown, 0.0)


## Removes velocity into a surface with world-space [param normal] (a hull
## strike). Returns the impact speed along the normal.
func collide(normal: Vector3) -> float:
	var into: float = velocity.dot(normal)
	if into >= 0.0:
		return 0.0
	velocity -= normal * into
	velocity *= 0.8  # Scraping friction.
	return -into
