class_name LeakSystem
extends Node
## Host-side leak director. Opens one leak at a time at a random point, now and
## then and after hull strikes. Water comes in while it's open. A patch closes
## it for a time that scales with patch quality; then it reopens (the prototype
## has one recurring leak). Also runs the bilge pump.

## Hiss of an open leak (~73 dB).
const LEAK_INTENSITY: float = 2e-3
## Bilge pump running (~78 dB).
const PUMP_INTENSITY: float = 6e-3
const LEAK_FLOW_T: float = 0.02   # tonnes/s in through an open leak
const PUMP_FLOW_T: float = 0.05   # tonnes/s out with the pump on
const FIRST_LEAK_DELAY: Vector2 = Vector2(60.0, 120.0)
const PATCH_HOLD_SEC: Vector2 = Vector2(45.0, 240.0)  # zero vs perfect quality
## A strike this hard (m/s) always opens a leak; softer ones scale the chance.
const STRIKE_FOR_CERTAIN_LEAK: float = 1.2

@export var controller: SubController
@export var leaks_root: Node3D
@export var pump: Lever
@export var pump_point: Node3D

var open_index: int = -1

var _leaks: Array[Leak] = []
var _timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pump_audio: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(&"noise_sources")
	for child: Node in leaks_root.get_children():
		var leak: Leak = child as Leak
		if leak != null:
			_leaks.append(leak)
			leak.patch_completed.connect(_on_patch_completed)
	_rng.randomize()
	_timer = _rng.randf_range(FIRST_LEAK_DELAY.x, FIRST_LEAK_DELAY.y)
	if controller != null:
		controller.hull_strike.connect(_on_hull_strike)
	Net.peer_joined.connect(_on_peer_joined)
	_pump_audio = AudioStreamPlayer3D.new()
	_pump_audio.stream = ProceduralSounds.gurgle()
	_pump_audio.unit_size = SubAudio.UNIT_SIZE
	_pump_audio.pitch_scale = 1.6
	(pump_point if pump_point != null else self as Node).add_child(_pump_audio)


func pump_on() -> bool:
	return pump != null and pump.get_value() > 0.5


func noise_intensity() -> float:
	var total: float = LEAK_INTENSITY if open_index != -1 else 0.0
	if pump_on():
		total += PUMP_INTENSITY
	return total


func _process(_delta: float) -> void:
	var want: bool = pump_on()
	if want and not _pump_audio.playing:
		_pump_audio.volume_db = SubAudio.volume_for(PUMP_INTENSITY)
		_pump_audio.play()
	elif not want and _pump_audio.playing:
		_pump_audio.stop()


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server() or controller == null or not controller.enabled:
		return
	if open_index != -1:
		controller.model.change_bilge(LEAK_FLOW_T * delta)
	if pump_on():
		controller.model.change_bilge(-PUMP_FLOW_T * delta)
	_timer -= delta
	if _timer <= 0.0 and open_index == -1:
		open_random_leak()


## Host: opens a leak at a random point (if none is open).
func open_random_leak() -> void:
	if not multiplayer.is_server() or _leaks.is_empty() or open_index != -1:
		return
	_set_leak.rpc(_rng.randi_range(0, _leaks.size() - 1))
	print("[leak] opened at %s" % _leaks[open_index].name)


## Host: called with patch requests from whoever held the leak.
@rpc("any_peer", "call_local", "reliable")
func _rpc_request_patch(index: int, quality: float) -> void:
	if not multiplayer.is_server() or index != open_index:
		return
	var leak: Leak = _leaks[index]
	var sender: int = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = Net.local_id()
	# Only the player who held the patch may finish it.
	if leak.state.holder != sender and leak.state.holder != InteractableState.NO_HOLDER:
		return
	_timer = lerpf(PATCH_HOLD_SEC.x, PATCH_HOLD_SEC.y, clampf(quality, 0.0, 1.0))
	_set_leak.rpc(-1)
	leak.host_set_value(0.0)
	print("[leak] patched, quality %.2f, holds %.0f s" % [quality, _timer])


@rpc("authority", "call_local", "reliable")
func _set_leak(index: int) -> void:
	open_index = index
	for i: int in range(_leaks.size()):
		_leaks[i].set_open(i == index)


func _on_patch_completed(leak: Leak, quality: float) -> void:
	_rpc_request_patch.rpc_id(1, _leaks.find(leak), quality)


func _on_hull_strike(speed: float) -> void:
	if open_index != -1:
		return
	if _rng.randf() < clampf(speed / STRIKE_FOR_CERTAIN_LEAK, 0.0, 1.0):
		open_random_leak()


func _on_peer_joined(peer_id: int) -> void:
	if multiplayer.is_server():
		_set_leak.rpc_id(peer_id, open_index)
