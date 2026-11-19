class_name DiveDirector
extends Node
## Host-side flow of a dive, mirrored to every peer for the status board.
##
##   DIVING     from the surface, tanks empty: flood to go down, find the array,
##              scan it, then come back up
##   COMPLETE   the array is scanned and the sub reached the surface
##   LOST       the apex made contact: crunch, lights die
## After COMPLETE or LOST the host resets everything for another run.
## The in-world status board (aft bulkhead) shows orders and state. No HUD.

signal dive_lost
signal dive_complete
signal dive_reset

enum Phase { DIVING, COMPLETE, LOST }

const LOST_HOLD_SEC: float = 6.0
const COMPLETE_HOLD_SEC: float = 12.0
## How long the sub must stay surfaced for recovery.
const SURFACED_HOLD_SEC: float = 3.0
## Chance a near miss's pressure wave springs a leak.
const NEAR_MISS_LEAK_CHANCE: float = 0.6

const ORDERS: String = """RAINDROP DIVE ORDERS
SITE  KESTREL CANYON
1. SCAN SENSOR ARRAY S-7
   SHELF 2, EAST WALL, ~140 m
   ARRAY PINGER ON. RED BEACON.
2. SURFACE FOR RECOVERY
"""

@export var game: Game
@export var controller: SubController
@export var leaks: LeakSystem
@export var apex: ApexMonster
@export var cues: ThreatCues
@export var interior_lights: Node3D
@export var scan: ScanObjective
@export var status_board: Label3D

var phase: Phase = Phase.DIVING
## Seconds since the dive started (host clock, replicated with phase changes).
var dive_time: float = 0.0
var max_depth: float = 0.0

var _hold_timer: float = 0.0
var _surfaced_timer: float = 0.0


func _ready() -> void:
	apex.contact.connect(_on_contact)
	apex.near_miss.connect(_on_near_miss)
	_update_board()


func _process(_delta: float) -> void:
	_update_board()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	match phase:
		Phase.DIVING:
			dive_time += delta
			max_depth = maxf(max_depth, controller.depth)
			if scan.complete and controller.surfaced:
				_surfaced_timer += delta
				if _surfaced_timer >= SURFACED_HOLD_SEC:
					_finish()
			else:
				_surfaced_timer = 0.0
		Phase.LOST, Phase.COMPLETE:
			_hold_timer -= delta
			if _hold_timer <= 0.0:
				reset_dive()


## Host: puts everything back to the start of the dive.
func reset_dive() -> void:
	if not multiplayer.is_server():
		return
	controller.reset_dive()
	leaks.reset()
	apex.reset_to_spawn()
	scan.reset()
	var chart: MapModel = get_tree().get_first_node_in_group(&"map_model") as MapModel
	if chart != null:
		chart.clear()
	Acoustics.reset()
	game.respawn_players()
	dive_time = 0.0
	max_depth = 0.0
	_surfaced_timer = 0.0
	_rpc_reset.rpc()


func status_text() -> String:
	var status: String
	match phase:
		Phase.LOST:
			status = "STATUS  CONTACT LOST"
		Phase.COMPLETE:
			status = "STATUS  DIVE COMPLETE. RECOVERED.\nARRAY DATA RECEIVED."
		_:
			if scan != null and scan.complete:
				status = "STATUS  ARRAY SCANNED. SURFACE."
			elif scan != null and scan.progress > 0.0:
				status = "STATUS  SCANNING %d%%" % int(scan.progress * 100.0)
			else:
				status = "STATUS  DIVING"
	return ORDERS + "\n" + status


func _finish() -> void:
	phase = Phase.COMPLETE
	_hold_timer = COMPLETE_HOLD_SEC
	_rpc_complete.rpc()


func _on_contact() -> void:
	if phase != Phase.DIVING:
		return
	phase = Phase.LOST
	_hold_timer = LOST_HOLD_SEC
	controller.enabled = false
	_rpc_lost.rpc()


func _on_near_miss(distance: float) -> void:
	cues.rpc_near_miss.rpc(distance)
	if randf() < NEAR_MISS_LEAK_CHANCE:
		leaks.open_random_leak()


func _update_board() -> void:
	if status_board != null:
		status_board.text = status_text()


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
func _rpc_complete() -> void:
	phase = Phase.COMPLETE
	dive_complete.emit()


@rpc("authority", "call_local", "reliable")
func _rpc_reset() -> void:
	phase = Phase.DIVING
	interior_lights.visible = true
	dive_reset.emit()
