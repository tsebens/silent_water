class_name SubAudio
extends Node
## In-sub sound, driven by the same intensities the noise system sums, so the
## mix tells the truth: what the crew hears matches what the ocean hears.
##
## Volume mapping: a source of intensity I plays at to_db(I) - REF_DB dBFS
## (100 dB = full scale), within a few metres of the source.

## Dial to trim the whole in-sub mix without changing the noise model.
const MIX_TRIM_DB: float = 0.0
## Distance inside which a sound plays at its reference volume (m).
const UNIT_SIZE: float = 4.0
## Below this, a looping source is stopped to save mixing.
const SILENT_DB: float = -70.0
## A control has to be moving this loudly to clank (intensity).
const CLANK_THRESHOLD: float = 0.03
const CLANK_COOLDOWN: float = 0.35

@export var controller: SubController
@export var players: Node3D
@export var engine_point: Node3D
@export var blow_point: Node3D
@export var flood_point: Node3D

var _engine: AudioStreamPlayer3D
var _blow: AudioStreamPlayer3D
var _flood: AudioStreamPlayer3D
var _strike: AudioStreamPlayer
var _clank_cooldowns: Dictionary = {}
var _connected_players: Dictionary = {}


static func volume_for(intensity: float) -> float:
	return NoiseLevel.to_db(intensity) - NoiseLevel.REF_DB + MIX_TRIM_DB


func _ready() -> void:
	_engine = _loop(ProceduralSounds.engine_hum(), engine_point)
	_blow = _loop(ProceduralSounds.hiss(), blow_point)
	_flood = _loop(ProceduralSounds.gurgle(), flood_point)
	_strike = AudioStreamPlayer.new()
	_strike.stream = ProceduralSounds.thud()
	add_child(_strike)
	if controller != null:
		controller.hull_strike.connect(_on_hull_strike)


func _process(delta: float) -> void:
	if controller == null:
		return
	_drive(_engine, controller.engine_intensity())
	_engine.pitch_scale = 0.8 + 0.5 * absf(controller.engine_output)
	_drive(_blow, controller.blow_intensity())
	_drive(_flood, controller.flood_intensity())
	_update_clanks(delta)
	_connect_players()


## Keeps a looping source playing at the volume its intensity calls for.
func _drive(player: AudioStreamPlayer3D, intensity: float) -> void:
	var db: float = volume_for(intensity)
	if db < SILENT_DB:
		if player.playing:
			player.stop()
		return
	player.volume_db = db
	if not player.playing:
		player.play(randf() * 0.5)


func _update_clanks(delta: float) -> void:
	for key: Variant in _clank_cooldowns.keys():
		_clank_cooldowns[key] = maxf(float(_clank_cooldowns[key]) - delta, 0.0)
	for node: Node in get_tree().get_nodes_in_group(&"interactables"):
		var it: Interactable = node as Interactable
		var intensity: float = it.get_noise_intensity()
		var id: int = it.get_instance_id()
		if intensity > CLANK_THRESHOLD and float(_clank_cooldowns.get(id, 0.0)) <= 0.0:
			_clank_cooldowns[id] = CLANK_COOLDOWN
			_one_shot(ProceduralSounds.clank(), it.global_position, intensity)


func _connect_players() -> void:
	if players == null:
		return
	for node: Node in players.get_children():
		var p: Player = node as Player
		if p == null or _connected_players.has(p.get_instance_id()):
			continue
		_connected_players[p.get_instance_id()] = true
		p.footstep.connect(_on_footstep.bind(p))


func _on_footstep(loudness: float, p: Player) -> void:
	if not is_instance_valid(p):
		return
	var intensity: float = Player.FOOTSTEP_INTENSITY * pow(loudness, 3.0)
	_one_shot(ProceduralSounds.step(), p.global_position, intensity, randf_range(0.9, 1.1))


func _on_hull_strike(speed: float) -> void:
	_rpc_strike.rpc(speed)


@rpc("authority", "call_local", "reliable")
func _rpc_strike(speed: float) -> void:
	_strike.volume_db = volume_for(SubController.STRIKE_INTENSITY * speed * speed)
	_strike.play()


func _loop(stream: AudioStream, at: Node3D) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = UNIT_SIZE
	p.max_db = 6.0
	if at != null:
		at.add_child(p)
	else:
		add_child(p)
	return p


func _one_shot(stream: AudioStream, at: Vector3, intensity: float, pitch: float = 1.0) -> void:
	var db: float = volume_for(intensity)
	if db < SILENT_DB:
		return
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = UNIT_SIZE
	p.max_db = 6.0
	p.volume_db = db
	p.pitch_scale = pitch
	add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()
