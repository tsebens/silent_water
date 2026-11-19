class_name OutsideAudio
extends Node
## Plays sounds from outside the hull on every peer, two ways:
## - Through the hull: everyone hears it, heavily muffled and quiet, panned
##   from where it really is.
## - Hydrophone: only the sonar operator hears it, through the beam.
##
## Continuous sources are nodes in group `outside_sources` (Node3D under the
## world root) with `outside_db() -> float` (level at 1 m) and
## `outside_stream() -> AudioStream`. One-shots use [method play_at].
## Levels follow the noise model: spreading loss, then a fixed hull loss or
## the beam gain, then dB -> dBFS.

## Outside sound lost through the hull (dB).
const HULL_LOSS_DB: float = 35.0
## Level at the hydrophone that plays at full scale.
const HYDRO_FULL_SCALE_DB: float = 95.0
## How strongly the sub's own noise reaches its hydrophone (dB offset).
const SELF_NOISE_OFFSET_DB: float = -4.0

var _sources: Dictionary = {}  # instance id -> [node, hull player, hydro player]
var _ocean: AudioStreamPlayer
var _self_noise: AudioStreamPlayer
var _sonar: SonarStation


func _ready() -> void:
	add_to_group(&"outside_audio")
	_ocean = _flat(ProceduralSounds.hiss())
	_self_noise = _flat(ProceduralSounds.engine_hum())


func _process(_delta: float) -> void:
	if _sonar == null:
		_sonar = get_tree().get_first_node_in_group(&"sonar") as SonarStation
	var operator: bool = _sonar != null and _sonar.is_local_operator()
	var trained: float = _sonar.bearing_deg() if _sonar != null else 0.0
	_track_sources()
	for id: int in _sources.keys():
		var entry: Array = _sources[id]
		var node: Node3D = entry[0] as Node3D
		if not is_instance_valid(node):
			(entry[1] as Node).queue_free()
			(entry[2] as Node).queue_free()
			_sources.erase(id)
			continue
		var level: float = float(node.call(&"outside_db"))
		_drive_pair(entry[1] as AudioStreamPlayer3D, entry[2] as AudioStreamPlayer, node.global_position, level, operator, trained)
	# Ocean background and the sub's own noise, on the hydrophone only.
	_drive_flat(_ocean, Acoustics.ambient_db() - HYDRO_FULL_SCALE_DB, operator)
	_drive_flat(_self_noise, Acoustics.sub_db() + SELF_NOISE_OFFSET_DB - HYDRO_FULL_SCALE_DB, operator)


## Plays a one-shot from [param source] (a Node3D in the world) at
## [param source_db] measured at 1 m.
func play_at(stream: AudioStream, source: Node3D, source_db: float) -> void:
	var hull: AudioStreamPlayer3D = _hull_player(stream, source)
	var hydro: AudioStreamPlayer = AudioStreamPlayer.new()
	hydro.stream = stream
	hydro.bus = AudioBuses.HYDROPHONE
	add_child(hydro)
	var operator: bool = _sonar != null and _sonar.is_local_operator()
	var trained: float = _sonar.bearing_deg() if _sonar != null else 0.0
	_set_levels(hull, hydro, source.global_position, source_db, operator, trained)
	hull.finished.connect(hull.queue_free)
	hydro.finished.connect(hydro.queue_free)
	hull.play()
	if operator:
		hydro.play()
	else:
		hydro.queue_free()


## Level (dB) at the sub of a source [param source_db] at 1 m, from render
## position [param p] (the sub is at the origin).
static func level_at_sub(source_db: float, p: Vector3) -> float:
	return NoiseLevel.to_db(NoiseLevel.attenuate(NoiseLevel.from_db(source_db), p.length()))


func _track_sources() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"outside_sources"):
		var id: int = node.get_instance_id()
		if _sources.has(id):
			continue
		var n3: Node3D = node as Node3D
		var stream: AudioStream = node.call(&"outside_stream") as AudioStream
		var hull: AudioStreamPlayer3D = _hull_player(stream, n3)
		var hydro: AudioStreamPlayer = AudioStreamPlayer.new()
		hydro.stream = stream
		hydro.bus = AudioBuses.HYDROPHONE
		add_child(hydro)
		_sources[id] = [n3, hull, hydro]


func _drive_pair(hull: AudioStreamPlayer3D, hydro: AudioStreamPlayer, p: Vector3, source_db: float, operator: bool, trained: float) -> void:
	_set_levels(hull, hydro, p, source_db, operator, trained)
	_keep_playing(hull, hull.volume_db > -70.0)
	_keep_playing(hydro, operator and hydro.volume_db > -70.0)


func _set_levels(hull: AudioStreamPlayer3D, hydro: AudioStreamPlayer, p: Vector3, source_db: float, operator: bool, trained: float) -> void:
	var at_sub: float = level_at_sub(source_db, p)
	hull.volume_db = minf(at_sub - HULL_LOSS_DB - NoiseLevel.REF_DB, 0.0)
	if operator:
		var beam: float = SonarStation.beam_gain_db(SonarStation.bearing_of(p), trained)
		hydro.volume_db = minf(at_sub + beam - HYDRO_FULL_SCALE_DB, 0.0)


func _drive_flat(player: AudioStreamPlayer, db: float, operator: bool) -> void:
	player.volume_db = minf(db, 0.0)
	_keep_playing(player, operator and db > -70.0)


func _keep_playing(player: Node, want: bool) -> void:
	var playing: bool = bool(player.get(&"playing"))
	if want and not playing:
		player.call(&"play", randf() * 0.5)
	elif not want and playing:
		player.call(&"stop")


func _hull_player(stream: AudioStream, at: Node3D) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = AudioBuses.HULL
	# Distance is handled by the noise model; the 3D player only pans.
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.max_distance = 0.0
	at.add_child(p)
	return p


func _flat(stream: AudioStream) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = AudioBuses.HYDROPHONE
	add_child(p)
	return p
