class_name ThreatCues
extends Node
## Felt-before-heard cues from the apex, on every peer, from its replicated
## position. Nothing here affects the simulation.
##
## - Low rumble that grows as it closes (Felt bus, never ducked)
## - Within RATTLE_RANGE: the view shakes, lights flicker, the hull creaks
## - Near misses (from the host): a hard jolt and a thud

const RUMBLE_RANGE: float = 220.0
const RATTLE_RANGE: float = 70.0
const MAX_SHAKE: float = 0.025

@export var lights: Node3D
@export var players: Node3D

var _apex: ApexMonster
var _rumble: AudioStreamPlayer
var _creak_timer: float = 3.0
var _jolt: float = 0.0
var _cabin: CabinLights


func _ready() -> void:
	_rumble = AudioStreamPlayer.new()
	_rumble.stream = ProceduralSounds.rumble()
	_rumble.bus = AudioBuses.FELT
	add_child(_rumble)


## Distance (m) from the sub to the nearest part of the apex, or INF.
func apex_distance() -> float:
	if _apex == null or not _apex.active:
		return INF
	# In render space the sub sits at the origin.
	return maxf(_apex.global_position.length() - ApexMonster.LENGTH_M * 0.4, 0.0)


## 0 when far, 1 when on top of us.
func proximity() -> float:
	return clampf(1.0 - apex_distance() / RUMBLE_RANGE, 0.0, 1.0)


func _process(delta: float) -> void:
	if _apex == null:
		_apex = get_tree().get_first_node_in_group(&"apex") as ApexMonster
		if _apex == null:
			return
	var d: float = apex_distance()
	var near: float = proximity()
	var speed_factor: float = clampf(_apex.speed / 6.0, 0.4, 1.5)
	if near > 0.0:
		_rumble.volume_db = lerpf(-50.0, -2.0, pow(near, 1.5)) + 6.0 * (speed_factor - 1.0)
		if not _rumble.playing:
			_rumble.play()
	elif _rumble.playing:
		_rumble.stop()
	var rattle: float = clampf(1.0 - d / RATTLE_RANGE, 0.0, 1.0)
	_jolt = maxf(_jolt - delta * 1.5, 0.0)
	_shake_players(maxf(rattle * speed_factor, _jolt))
	_flicker(rattle)
	_creak_timer -= delta
	if rattle > 0.0 and _creak_timer <= 0.0:
		_creak_timer = randf_range(2.0, 5.0) * (1.2 - rattle)
		var creak: AudioStreamPlayer = AudioStreamPlayer.new()
		creak.stream = ProceduralSounds.creak()
		creak.bus = AudioBuses.FELT
		creak.volume_db = lerpf(-24.0, -4.0, rattle)
		creak.pitch_scale = randf_range(0.8, 1.2)
		add_child(creak)
		creak.finished.connect(creak.queue_free)
		creak.play()


## Host -> everyone: the apex passed very close.
@rpc("authority", "call_local", "reliable")
func rpc_near_miss(distance: float) -> void:
	_jolt = clampf(1.0 - distance / ApexMonster.NEAR_MISS_RADIUS, 0.3, 1.0)
	var thud: AudioStreamPlayer = AudioStreamPlayer.new()
	thud.stream = ProceduralSounds.thud()
	thud.bus = AudioBuses.FELT
	thud.volume_db = -2.0
	add_child(thud)
	thud.finished.connect(thud.queue_free)
	thud.play()


func _shake_players(amount: float) -> void:
	if players == null:
		return
	for node: Node in players.get_children():
		var p: Player = node as Player
		if p != null and p.is_multiplayer_authority():
			p.set_shake(amount * MAX_SHAKE)


func _flicker(amount: float) -> void:
	if _cabin == null:
		_cabin = get_tree().get_first_node_in_group(&"cabin_lights") as CabinLights
		if _cabin == null:
			return
	for light: Light3D in _cabin.cabin_lights():
		var id: int = light.get_instance_id()
		var current: float = float(_cabin.flicker.get(id, 1.0))
		if amount > 0.0 and randf() < amount * 0.25:
			_cabin.flicker[id] = randf_range(0.2, 0.9)
		else:
			_cabin.flicker[id] = lerpf(current, 1.0, 0.3)
