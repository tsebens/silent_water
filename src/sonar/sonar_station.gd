class_name SonarStation
extends Node3D
## Minimal passive sonar. The operator wears the headset and trains the
## hydrophone with the handwheel; only they hear the hydrophone. Outside
## sources are heard through a sharp beam: a source dead on the bearing is
## clear, 60° off is about 10 dB down, abeam is nearly gone.
##
## Expect heavy iteration: all numbers are here and in [OutsideAudio].

## Beam sharpness: gain = ((1 + cos Δ) / 2) ^ BEAM_POWER.
const BEAM_POWER: float = 8.0

## Signal strength gauge range (dB received on the current bearing).
@export var signal_min_db: float = 40.0
@export var signal_max_db: float = 110.0
## Bearing-rate gauge range, +/- deg/min (right = clockwise).
@export var rate_range_deg_min: float = 120.0
## Below this received level (dB) the strongest contact is too faint to track
## and the bearing rate rests at 0.
@export var rate_threshold_db: float = 55.0
## Smoothing of the measured bearing rate (1/s).
@export var rate_response: float = 2.0
## Host to client replication rate of the readouts.
@export var readout_hz: float = 10.0

@export var headset: Wearable
@export var wheel: HydrophoneWheel

var signal_db: float = 0.0
var bearing_rate: float = 0.0
var _track_id: int = 0
var _track_bearing: float = 0.0
var _accum: float = 0.0


func _ready() -> void:
	add_to_group(&"sonar")
	add_to_group(&"sonar_readouts")
	if headset != null:
		headset.worn_changed.connect(func(on: bool) -> void: AudioBuses.set_headphones(on))


func is_local_operator() -> bool:
	return headset != null and headset.is_held_locally()


func bearing_deg() -> float:
	return wheel.bearing_deg() if wheel != null else 0.0


## Gauge hook.
func readout(property: StringName) -> float:
	if property == &"bearing":
		return bearing_deg()
	if property == &"signal":
		return signal_db
	if property == &"bearing_rate":
		return bearing_rate
	return 0.0


func _physics_process(delta: float) -> void:
	if Net.is_online() and not multiplayer.is_server():
		return
	_measure(delta)
	if Net.is_online():
		_accum += delta
		if _accum >= 1.0 / readout_hz:
			_accum = 0.0
			_rpc_readouts.rpc(signal_db, bearing_rate)


## Host: sums every outside source through the beam for the signal strength, and
## tracks the bow-relative bearing of the strongest one for the bearing rate.
func _measure(delta: float) -> void:
	var trained: float = bearing_deg()
	var levels: PackedFloat32Array = PackedFloat32Array()
	var best_db: float = -INF
	var best_id: int = 0
	var best_bearing: float = 0.0
	for node: Node in get_tree().get_nodes_in_group(&"outside_sources"):
		var n3: Node3D = node as Node3D
		if n3 == null or not node.has_method(&"outside_db"):
			continue
		var p: Vector3 = n3.global_position
		var rx: float = SonarReadouts.received_db(float(node.call(&"outside_db")), p, trained)
		levels.append(rx)
		if rx > best_db:
			best_db = rx
			best_id = node.get_instance_id()
			best_bearing = SonarStation.bearing_of(p)
	signal_db = SonarReadouts.sum_db(levels, 0.0)
	var raw: float = 0.0
	if best_id != 0 and best_db >= rate_threshold_db:
		if best_id == _track_id:
			raw = SonarReadouts.rate_deg_per_min(_track_bearing, best_bearing, delta)
		else:
			raw = bearing_rate  # new contact: hold until two samples exist
		_track_id = best_id
		_track_bearing = best_bearing
		bearing_rate = lerpf(bearing_rate, raw, 1.0 - exp(-rate_response * delta))
	else:
		_track_id = 0
		bearing_rate = 0.0


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_readouts(sig: float, rate: float) -> void:
	signal_db = sig
	bearing_rate = rate


## Gain (dB) of the beam for a source at [param source_bearing] (degrees,
## relative to the bow) when trained on [param trained] degrees.
static func beam_gain_db(source_bearing: float, trained: float) -> float:
	var delta: float = deg_to_rad(source_bearing - trained)
	var g: float = pow((1.0 + cos(delta)) * 0.5, BEAM_POWER)
	return NoiseLevel.to_db(maxf(g, 1e-9)) - NoiseLevel.REF_DB


## World direction (horizontal, unit) of a bearing relative to the bow.
static func bearing_to_world(sub_transform: Transform3D, bearing: float) -> Vector3:
	var fwd: Vector3 = sub_transform.basis * Vector3.FORWARD
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		fwd = Vector3.FORWARD
	# Clockwise seen from above is a negative turn about +Y.
	return Basis(Vector3.UP, -deg_to_rad(bearing)) * fwd.normalized()


## Bearing (degrees, clockwise from the bow) of a point in render space,
## where the sub sits at the origin facing -Z.
static func bearing_of(render_point: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(render_point.x, -render_point.z)), 360.0)
