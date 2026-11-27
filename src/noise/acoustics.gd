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
## Speed of sound in water (m/s); a tuning constant.
const SPEED_OF_SOUND: float = 1500.0
## Position error floor (m) and growth per metre of distance at 0 dB margin.
const UNCERTAINTY_MIN: float = 2.0
const UNCERTAINTY_PER_M: float = 0.2
## Every this many dB of margin above the background halves-ish the error
## (error is divided by 1 + margin / this).
const UNCERTAINTY_DB_SCALE: float = 6.0

## The sub's combined periodic event and one-off impacts use these shared types.
## Their intensity is the unit the live load (sum of systems) is multiplied by.
const SUB_COMBINED_TYPE: SoundType = preload("res://src/noise/sound_types/sub_combined.tres")
const IMPACT_TYPE: SoundType = preload("res://src/noise/sound_types/impact.tres")

## Total noise of the sub (linear intensity). Authoritative on the host,
## replicated to clients for gauges.
var sub_intensity: float = 0.0
## Ocean background at the sub (linear intensity).
var ambient_intensity: float = NoiseLevel.from_db(OCEAN_BASE_DB)

## Loudest sources as text, e.g. "engine 78 dB, voice:2 70 dB". Built on the
## host, replicated with the levels (developer overlay).
var top_text: String = ""

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
var _sub_event_accum: float = 0.0
## Intensity of the last combined sub event's load (host only).
var last_sub_event_load: float = 0.0
## The last few emitted events (host only), newest last, for the developer
## overlay: {time, position, intensity (at the emitter), kind, heard}.
var recent_events: Array[Dictionary] = []
const RECENT_EVENTS_MAX: int = 8
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
## Tests may replace the terrain check: Callable(from_world, to_world) -> bool.
var occlusion_override: Callable = Callable()


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
	# A one-off also emits once, now, where the sub is.
	emit_load(IMPACT_TYPE, _sub_position(), intensity, self)


## Called on every peer by its local mic meter. Forwards to the host.
func report_voice(intensity: float) -> void:
	if multiplayer.is_server():
		_set_voice(multiplayer.get_unique_id(), intensity)
	elif Net.is_online():
		_rpc_voice.rpc_id(1, intensity)


func voice_intensity(peer_id: int) -> float:
	return float(_voices.get(peer_id, 0.0))


## Seconds since [param peer_id] last reported its voice (host only). INF when
## the peer has never reported. Below [constant VOICE_TIMEOUT] means the
## intensity from [method voice_intensity] is live, not the timed-out zero.
func voice_age(peer_id: int) -> float:
	if not _voice_times.has(peer_id):
		return INF
	return _time - float(_voice_times[peer_id])


## Sub noise as heard at [param world_point] (linear intensity), with spreading
## loss and terrain occlusion. Host only; used by creatures.
func heard_at(world_point: Vector3, sub_frame: SubFrame) -> float:
	var sub_pos: Vector3 = sub_frame.sub_transform.origin
	var heard: float = NoiseLevel.attenuate(sub_intensity, sub_pos.distance_to(world_point))
	if _occluded(sub_frame, sub_pos, world_point):
		heard *= NoiseLevel.from_db(NoiseLevel.REF_DB - OCCLUSION_LOSS_DB)
	return heard


## Host only. Like [method emit_event], but for a load that is computed live (the
## sub's summed systems, an impulse): the event's intensity is the type's
## intensity times [param load_intensity]. Kind comes from the type.
func emit_load(type: SoundType, position: Vector3, load_intensity: float, source: Object = null) -> int:
	return emit_raw(position, type.intensity * maxf(load_intensity, 0.0), type.kind, source)


func _sub_position() -> Vector3:
	var frame: SubFrame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
	return frame.sub_transform.origin if frame != null else Vector3.ZERO


## Advances the sub's combined-event clock; emits one event per period with the
## given continuous load. Returns the number of events emitted.
func advance_sub_events(delta: float, load_intensity: float) -> int:
	var period: float = SUB_COMBINED_TYPE.period
	if period <= 0.0:
		return 0
	_sub_event_accum += delta
	var n: int = 0
	while _sub_event_accum >= period:
		_sub_event_accum -= period
		last_sub_event_load = load_intensity
		emit_load(SUB_COMBINED_TYPE, _sub_position(), load_intensity, self)
		n += 1
	return n


## Seeds the perceived-position error, for deterministic tests.
func seed_events(seed_value: int) -> void:
	_rng.seed = seed_value


## The acoustics clock (s), advanced in the physics tick.
func now() -> float:
	return _time


## Host only. Emits a sound of a shared [SoundType] at a world position. [param scale]
## is a bounded per-emitter multiplier on the type's intensity. Returns how many
## detectors heard it.
func emit_event(type: SoundType, position: Vector3, source: Object = null, scale: float = 1.0) -> int:
	return emit_raw(position, type.scaled_intensity(scale), type.kind, source)


## Host only. Delivers a sound of raw intensity synchronously to every
## [SoundDetector] that can hear it. Nothing is retained. For tests and tools;
## emitters use [method emit_event]. Returns how many detectors heard it.
func emit_raw(position: Vector3, intensity: float, kind: StringName = &"", source: Object = null) -> int:
	if Net.is_online() and not multiplayer.is_server():
		return 0
	var heard_count: int = 0
	var occl_factor: float = NoiseLevel.from_db(NoiseLevel.REF_DB - OCCLUSION_LOSS_DB)
	for node: Node in get_tree().get_nodes_in_group(&"sound_detectors"):
		var det: SoundDetector = node as SoundDetector
		if det == null:
			continue
		var dist: float = position.distance_to(det.world_position)
		var received: float = NoiseLevel.attenuate(intensity, dist)
		var occluded: bool = _occluded_between(position, det.world_position)
		if occluded:
			received *= occl_factor
		var ambient: float = ambient_at(det.world_position)
		var margin_db: float = NoiseLevel.to_db(received) - NoiseLevel.to_db(ambient)
		if margin_db < det.threshold_db:
			continue
		var ev: SoundEvent = SoundEvent.new()
		ev.true_position = position
		ev.emitted_intensity = intensity
		ev.intensity = received
		ev.distance = dist
		ev.kind = kind
		ev.source = source
		ev.occluded = occluded
		ev.timestamp = _time + dist / SPEED_OF_SOUND
		ev.uncertainty = uncertainty_for(dist, margin_db)
		var dir: Vector3 = Vector3(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0), _rng.randfn(0.0, 1.0))
		dir = dir.normalized() if dir.length() > 0.0001 else Vector3.UP
		ev.perceived_position = position + dir * ev.uncertainty * _rng.randf()
		det.receive(ev)
		heard_count += 1
	recent_events.append({"time": _time, "position": position, "intensity": intensity, "kind": kind, "heard": heard_count})
	if recent_events.size() > RECENT_EVENTS_MAX:
		recent_events.pop_front()
	return heard_count


## Error radius (m): grows with distance, shrinks with margin above background.
func uncertainty_for(distance: float, margin_db: float) -> float:
	return UNCERTAINTY_MIN + distance * UNCERTAINTY_PER_M / (1.0 + maxf(margin_db, 0.0) / UNCERTAINTY_DB_SCALE)


func _occluded_between(from_world: Vector3, to_world: Vector3) -> bool:
	if occlusion_override.is_valid():
		return bool(occlusion_override.call(from_world, to_world))
	var frame: SubFrame = get_tree().get_first_node_in_group(&"sub_frame") as SubFrame
	if frame == null:
		return false
	return _occluded(frame, from_world, to_world)


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
	var continuous_total: float = total
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
		continuous_total += v
	sub_intensity = total
	advance_sub_events(delta, continuous_total)
	ambient_intensity = _ambient_at_sub()
	top_text = _top_text()
	levels_changed.emit(sub_db(), ambient_db())
	if Net.is_online():
		_broadcast_accum += delta
		if _broadcast_accum >= 1.0 / BROADCAST_HZ:
			_broadcast_accum = 0.0
			_rpc_levels.rpc(sub_intensity, ambient_intensity, top_text)


## The loudest contributors right now, loudest first: [[label, dB], ...].
func top_sources(count: int = 3) -> Array:
	var items: Array = []
	for label: String in breakdown:
		items.append([label, NoiseLevel.to_db(float(breakdown[label]))])
	items.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	return items.slice(0, count)


func _top_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for item: Array in top_sources(3):
		parts.append("%s %.0f" % [String(item[0]), float(item[1])])
	return ", ".join(parts)


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
func _rpc_levels(sub: float, ambient: float, top: String) -> void:
	sub_intensity = sub
	ambient_intensity = ambient
	top_text = top
	levels_changed.emit(sub_db(), ambient_db())


## Clears transient state between sessions.
func reset() -> void:
	breakdown.clear()
	_voices.clear()
	_voice_times.clear()
	_impulses.clear()
	_sub_event_accum = 0.0
	last_sub_event_load = 0.0
	recent_events.clear()
	sub_intensity = 0.0
	ambient_intensity = NoiseLevel.from_db(OCEAN_BASE_DB)
