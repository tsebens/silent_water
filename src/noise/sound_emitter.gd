class_name SoundEmitter
extends Node
## A non-sub sound source. References a shared [SoundType] (never inline sound
## parameters): a continuous type (period > 0) emits one event per period while
## [member active]; a one-off type emits only through [method fire].
## The owner keeps [member world_position] current (world space).

@export var sound_type: SoundType
@export var active: bool = true
## Bounded per-emitter multiplier on the type's intensity (see [SoundType]).
@export var scale: float = 1.0
## When false the emitter only plays its sound and never calls
## [method Acoustics.emit_event].
@export var field_events: bool = true
var world_position: Vector3 = Vector3.ZERO

var _accum: float = 0.0
var _loop_player: AudioStreamPlayer3D = null


func _physics_process(delta: float) -> void:
	advance(delta)
	_update_loop()


## Advances the emitter's clock by [param delta] and emits every event that
## falls due. Returns how many were emitted. Frame-rate independent: the count
## over a span depends only on the type's period.
func advance(delta: float) -> int:
	if not active or sound_type == null or sound_type.is_one_off():
		return 0
	_accum += delta
	var n: int = 0
	while _accum >= sound_type.period:
		_accum -= sound_type.period
		_emit()
		n += 1
	return n


func _emit() -> void:
	if field_events:
		Acoustics.emit_event(sound_type, world_position, self, scale)


## Emits once, now, at [member world_position].
func fire() -> void:
	if sound_type == null:
		return
	_emit()
	if sound_type.has_stream():
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		sound_type.apply_to(p)
		add_child(p)
		_place(p)
		p.finished.connect(p.queue_free)
		p.play()


func _place(p: AudioStreamPlayer3D) -> void:
	if p.is_inside_tree():
		p.global_position = world_position
	else:
		p.position = world_position


## The looping player of an active continuous emitter, or null.
func loop_player() -> AudioStreamPlayer3D:
	return _loop_player


## Starts, refreshes or stops the looping player to match [member active] and
## the type. The player is started once and left running between periods.
func _update_loop() -> void:
	var want: bool = active and sound_type != null and sound_type.has_stream() and not sound_type.is_one_off()
	if not want:
		if _loop_player != null:
			_loop_player.stop()
			_loop_player.queue_free()
			_loop_player = null
		return
	if _loop_player == null:
		_loop_player = AudioStreamPlayer3D.new()
		add_child(_loop_player)
		_loop_player.finished.connect(_on_loop_finished)
	var restart: bool = _loop_player.stream != sound_type.stream
	sound_type.apply_to(_loop_player)
	_place(_loop_player)
	if restart or not _loop_player.playing:
		_loop_player.play()


func _on_loop_finished() -> void:
	# A non-looping stream ends; keep the loop going while still wanted.
	if _loop_player != null and active:
		_loop_player.play()
