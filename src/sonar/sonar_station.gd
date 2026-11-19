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

@export var headset: Wearable
@export var wheel: HydrophoneWheel


func _ready() -> void:
	add_to_group(&"sonar")
	add_to_group(&"sonar_readouts")
	headset.worn_changed.connect(func(on: bool) -> void: AudioBuses.set_headphones(on))


func is_local_operator() -> bool:
	return headset != null and headset.is_held_locally()


func bearing_deg() -> float:
	return wheel.bearing_deg() if wheel != null else 0.0


## Gauge hook.
func readout(property: StringName) -> float:
	if property == &"bearing":
		return bearing_deg()
	return 0.0


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
