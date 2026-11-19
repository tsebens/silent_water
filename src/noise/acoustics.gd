extends Node
## Noise system (autoload `Acoustics`). Host-authoritative.
##
## Every source reports **linear intensity** (proportional to pressure squared)
## measured 1 m from the sub. Intensities add; decibels and pascals don't. The
## host sums all sources into one number for the whole sub, because the sub is
## tiny next to what's listening.
##
## Scale and conversions are in [NoiseLevel]. See docs/noise.md for typical
## levels of each source.
##
## Sources:
## - Nodes in group `noise_sources` implementing `noise_intensity() -> float`,
##   polled every physics tick on the host.
## - Impulses ([method add_impulse]): short decaying bursts such as hull strikes.
## - Voices: each client reports its own mic loudness ([method report_voice]).

signal levels_changed(sub_db: float, ambient_db: float)

## Background ocean level everywhere, before ambient zones.
const OCEAN_BASE_DB: float = 62.0
## Extra loss when terrain lies between the sub and a listener (dB).
const OCCLUSION_LOSS_DB: float = 15.0
const LAYER_EXTERIOR: int = 1 << 3
## Client update rate for replicated levels (Hz).
const BROADCAST_HZ: float = 10.0
## Voice reports older than this are treated as silence (s).
const VOICE_TIMEOUT: float = 0.5

## Total noise of the sub (linear intensity). Authoritative on the host,
## replicated to clients for gauges.
var sub_intensity: float = 0.0
## Ocean background at the sub (linear intensity).
var ambient_intensity: float = NoiseLevel.from_db(OCEAN_BASE_DB)

## Per-peer voice intensity and when it was last reported (host only).
var _voices: Dictionary = {}
var _voice_times: Dictionary = {}
## Active impulses: [intensity, remaining, duration].
var _impulses: Array[PackedFloat32Array] = []
var _broadcast_accum: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	add_to_group(&"acoustics_readouts")


## Gauge hook: `sub_db` or `ambient_db`.
func readout(property: StringName) -> float:
	match property:
		&"sub_db":
			return sub_db()
		&"ambient_db":
			return ambient_db()
	return 0.0


func sub_db() -> float:
	return NoiseLevel.to_db(sub_intensity)


func ambient_db() -> float:
	return NoiseLevel.to_db(ambient_intensity)


## True when the sub is quieter than the ocean around it.
func is_masked() -> bool:
	return sub_intensity < ambient_intensity


## Host only: a short burst, e.g. a hull strike or a dropped tool.
func add_impulse(intensity: float, duration: float = 1.0) -> void:
	if not multiplayer.is_server():
		return
	_impulses.append(PackedFloat32Array([intensity, duration, duration]))


## Called on every peer by its local mic meter. Forwards to the host.
func report_voice(intensity: float) -> void:
	if multiplayer.is_server():
		_set_voice(multiplayer.get_unique_id(), intensity)
	elif Net.is_online():
		_rpc_voice.rpc_id(1, intensity)


func voice_intensity(peer_id: int) -> float:
	return float(_voices.get(peer_id, 0.0))


## Sub noise as heard at [param world_point] (linear intensity), with spreading
## loss and terrain occlusion. Host only; used by creatures.
func heard_at(world_point: Vector3, sub_frame: SubFrame) -> float:
	var sub_pos: Vector3 = sub_frame.sub_transform.origin
	var heard: float = NoiseLevel.attenuate(sub_intensity, sub_pos.distance_to(world_point))
	if _occluded(sub_frame, sub_pos, world_point):
		heard *= NoiseLevel.from_db(NoiseLevel.REF_DB - OCCLUSION_LOSS_DB)
	return heard


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() and Net.is_online():
		return
	_time += delta
	var total: float = 0.0
	for node: Node in get_tree().get_nodes_in_group(&"noise_sources"):
		total += maxf(float(node.call(&"noise_intensity")), 0.0)
	for i: int in range(_impulses.size() - 1, -1, -1):
		var imp: PackedFloat32Array = _impulses[i]
		total += imp[0] * (imp[1] / imp[2])
		imp[1] -= delta
		if imp[1] <= 0.0:
			_impulses.remove_at(i)
		else:
			_impulses[i] = imp
	for peer: int in _voices.keys():
		if _time - float(_voice_times.get(peer, 0.0)) > VOICE_TIMEOUT:
			_voices[peer] = 0.0
		total += float(_voices[peer])
	sub_intensity = total
	ambient_intensity = _ambient_at_sub()
	levels_changed.emit(sub_db(), ambient_db())
	if Net.is_online():
		_broadcast_accum += delta
		if _broadcast_accum >= 1.0 / BROADCAST_HZ:
			_broadcast_accum = 0.0
			_rpc_levels.rpc(sub_intensity, ambient_intensity)


func _ambient_at_sub() -> float:
	var frame: SubFrame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
	if frame == null:
		return NoiseLevel.from_db(OCEAN_BASE_DB)
	return ambient_at(frame.sub_transform.origin)


## Background noise at a world point: base ocean plus nearby ambient zones.
func ambient_at(world_point: Vector3) -> float:
	var total: float = NoiseLevel.from_db(OCEAN_BASE_DB)
	for zone: Node in get_tree().get_nodes_in_group(&"ambient_zones"):
		total += float(zone.call(&"intensity_at", world_point))
	return total


func _occluded(sub_frame: SubFrame, from_world: Vector3, to_world: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = sub_frame.get_viewport().world_3d.direct_space_state
	if space == null:
		return false
	# Physics runs in render space: world points map through the world root,
	# which is the inverse of the sub's pose.
	var inv: Transform3D = sub_frame.sub_transform.affine_inverse()
	var q: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(inv * from_world, inv * to_world, LAYER_EXTERIOR)
	return not space.intersect_ray(q).is_empty()


func _set_voice(peer: int, intensity: float) -> void:
	_voices[peer] = maxf(intensity, 0.0)
	_voice_times[peer] = _time


@rpc("any_peer", "unreliable_ordered")
func _rpc_voice(intensity: float) -> void:
	if multiplayer.is_server():
		_set_voice(multiplayer.get_remote_sender_id(), intensity)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_levels(sub: float, ambient: float) -> void:
	sub_intensity = sub
	ambient_intensity = ambient
	levels_changed.emit(sub_db(), ambient_db())


## Clears transient state between sessions.
func reset() -> void:
	_voices.clear()
	_voice_times.clear()
	_impulses.clear()
	sub_intensity = 0.0
	ambient_intensity = NoiseLevel.from_db(OCEAN_BASE_DB)
