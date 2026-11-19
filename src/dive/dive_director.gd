class_name DiveDirector
extends Node
## Host-side flow of a dive. For M4: losing the sub on contact and resetting.
## M5 adds objectives and surfacing.
##
## On contact everyone hears the hull give way and the lights die; after
## [constant LOST_HOLD_SEC] the host resets the sub, leaks, monster and crew.

signal dive_lost
signal dive_reset

enum Phase { RUNNING, LOST }

const LOST_HOLD_SEC: float = 6.0
## Chance a near miss's pressure wave springs a leak.
const NEAR_MISS_LEAK_CHANCE: float = 0.6

@export var game: Game
@export var controller: SubController
@export var leaks: LeakSystem
@export var apex: ApexMonster
@export var cues: ThreatCues
@export var interior_lights: Node3D

var phase: Phase = Phase.RUNNING

var _lost_timer: float = 0.0


func _ready() -> void:
	apex.contact.connect(_on_contact)
	apex.near_miss.connect(_on_near_miss)


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or phase != Phase.LOST:
		return
	_lost_timer -= delta
	if _lost_timer <= 0.0:
		reset_dive()


## Host: puts everything back to the start of the dive.
func reset_dive() -> void:
	if not multiplayer.is_server():
		return
	controller.reset_dive()
	leaks.reset()
	apex.reset_to_spawn()
	Acoustics.reset()
	game.respawn_players()
	phase = Phase.RUNNING
	_rpc_reset.rpc()


func _on_contact() -> void:
	if phase == Phase.LOST:
		return
	phase = Phase.LOST
	_lost_timer = LOST_HOLD_SEC
	controller.enabled = false
	print("[dive] sub lost")
	_rpc_lost.rpc()


func _on_near_miss(distance: float) -> void:
	print("[dive] near miss at %.1f m" % distance)
	cues.rpc_near_miss.rpc(distance)
	if randf() < NEAR_MISS_LEAK_CHANCE:
		leaks.open_random_leak()


@rpc("authority", "call_local", "reliable")
func _rpc_lost() -> void:
	phase = Phase.LOST
	interior_lights.visible = false
	for stream: AudioStream in [ProceduralSounds.roar(), ProceduralSounds.thud(), ProceduralSounds.creak()]:
		var p: AudioStreamPlayer = AudioStreamPlayer.new()
		p.stream = stream
		p.bus = AudioBuses.FELT
		p.volume_db = 0.0
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
	dive_lost.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_reset() -> void:
	phase = Phase.RUNNING
	interior_lights.visible = true
	dive_reset.emit()
