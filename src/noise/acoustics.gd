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

## What made up the last sum (host only): label -> intensity. Labels are the
## node name for sources, "voice:<peer>" for voices, "impact" for bursts.
var breakdown: Dictionary = {}

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
	breakdown.clear()
	for node: Node in get_tree().get_nodes_in_group(&"noise_sources"):
		var i_src: float = maxf(float(node.call(&"noise_intensity")), 0.0)
		total += i_src
		if i_src <= 0.0:
			continue
		# Composite sources can name their parts for the session log.
		if node.has_method(&"noise_breakdown"):
			var parts: Dictionary = node.call(&"noise_breakdown")
			for part: String in parts:
				if float(parts[part]) > 0.0:
					breakdown[part] = float(breakdown.get(part, 0.0)) + float(parts[part])
		else:
			var label: String = _label_for(node)
			breakdown[label] = float(breakdown.get(label, 0.0)) + i_src
	var impulse_total: float = 0.0
	for i: int in range(_impulses.size() - 1, -1, -1):
		var imp: PackedFloat32Array = _impulses[i]
		impulse_total += imp[0] * (imp[1] / imp[2])
		imp[1] -= delta
		if imp[1] <= 0.0:
			_impulses.remove_at(i)
		else:
			_impulses[i] = imp
	if impulse_total > 0.0:
		breakdown["impact"] = impulse_total
	total += impulse_total
	for peer: int in _voices.keys():
		if _time - float(_voice_times.get(peer, 0.0)) > VOICE_TIMEOUT:
			_voices[peer] = 0.0
		var v: float = float(_voices[peer])
		if v > 0.0:
			breakdown["voice:%d" % peer] = v
		total += v
	sub_intensity = total
	ambient_intensity = _ambient_at_sub()
	levels_changed.emit(sub_db(), ambient_db())
	if Net.is_online():
		_broadcast_accum += delta
		if _broadcast_accum >= 1.0 / BROADCAST_HZ:
			_broadcast_accum = 0.0
			_rpc_levels.rpc(sub_intensity, ambient_intensity)


## The loudest contributors right now, loudest first: [[label, dB], ...].
func top_sources(count: int = 3) -> Array:
	var items: Array = []
	for label: String in breakdown:
		items.append([label, NoiseLevel.to_db(float(breakdown[label]))])
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return items.slice(0, count)


func _label_for(node: Node) -> String:
	var label: Variant = node.get(&"label")
	if label is String and (label as String) != "":
		return label as String
	if node is Player:
		return "footsteps:%s" % node.name
	return String(node.name)


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
	breakdown.clear()
	_voices.clear()
	_voice_times.clear()
	_impulses.clear()
	sub_intensity = 0.0
	ambient_intensity = NoiseLevel.from_db(OCEAN_BASE_DB)
