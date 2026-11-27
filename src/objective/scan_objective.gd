class_name ScanObjective
extends Node
## Host-side scan of the sensor array. With the scanner switched on, progress
## builds while the sub is close to the array and nearly stopped; it drains
## slowly if either breaks. The scanner is loud whether or not it's making
## progress, so the crew has to choose their moment.

signal scan_started
signal scan_completed

## Scanner running (~83 dB): the loud final step.
const SCAN_INTENSITY: float = 0.02
const SCAN_TIME_SEC: float = 25.0
const MAX_RANGE_M: float = 30.0
const MAX_SPEED: float = 0.6
const DRAIN_PER_SEC: float = 1.0 / 60.0

@export var controller: SubController
@export var switch: Lever
## A SCAN science module that may arm the scan instead of the switch (set by the module).
var module: ScienceModule
@export var target: Node3D
@export var scanner_point: Node3D

# Replicated for the gauge and the status board.
var progress: float = 0.0
var complete: bool = false

var _audio: AudioStreamPlayer3D
var _was_on: bool = false


func _ready() -> void:
	add_to_group(&"noise_sources")
	add_to_group(&"scan_readouts")
	add_to_group(&"scan_objectives")
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = ProceduralSounds.scanner()
	_audio.bus = AudioBuses.INSIDE
	_audio.unit_size = SubAudio.UNIT_SIZE
	(scanner_point if scanner_point != null else self as Node).add_child(_audio)


func scanner_on() -> bool:
	if complete:
		return false
	return (switch != null and switch.get_value() > 0.5) or (module != null and module.armed)


## Distance from the sub to the array, metres (-1 when unknown).
func range_to_target() -> float:
	if controller == null or target == null:
		return -1.0
	return controller.model.position.distance_to(target.position)


## True when the sub is placed to make progress.
func in_position() -> bool:
	if controller == null or target == null:
		return false
	return controller.model.position.distance_to(target.position) <= MAX_RANGE_M and absf(controller.speed) <= MAX_SPEED


func noise_intensity() -> float:
	return SCAN_INTENSITY if scanner_on() else 0.0


func noise_breakdown() -> Dictionary:
	return {"scanner running": noise_intensity()}


## Gauge hook.
func readout(property: StringName) -> float:
	return progress if property == &"progress" else 0.0


func reset() -> void:
	progress = 0.0
	complete = false
	_was_on = false
	if module != null:
		module.armed = false
	if switch != null and multiplayer.is_server():
		switch.host_set_value(0.0)


func _process(_delta: float) -> void:
	var on: bool = scanner_on()
	if on and not _audio.playing:
		_audio.volume_db = SubAudio.volume_for(SCAN_INTENSITY)
		_audio.play()
	elif not on and _audio.playing:
		_audio.stop()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or complete:
		return
	var on: bool = scanner_on()
	if on and not _was_on:
		scan_started.emit()
	_was_on = on
	if on and in_position():
		progress = minf(progress + delta / SCAN_TIME_SEC, 1.0)
	else:
		progress = maxf(progress - DRAIN_PER_SEC * delta, 0.0)
	if progress >= 1.0:
		complete = true
		if switch != null:
			switch.host_set_value(0.0)
		if module != null:
			module.armed = false
		if module != null:
			module.armed = false
		scan_completed.emit()
