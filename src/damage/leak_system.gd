class_name LeakSystem
extends Node
## Host-side leak director. Opens one leak at a time at a random point, at a
## depth-scaled random rate and after hull strikes. Water comes in while it's
## open. A patch closes it for a time that scales with patch quality; then it
## reopens (the prototype has one recurring leak). Also runs the bilge pump.

signal leak_opened(where: String)
signal leak_patched(quality: float, hold_sec: float)

## Hiss of an open leak (~73 dB).
const LEAK_INTENSITY: float = 2e-3
## Bilge pump running (~78 dB).
const PUMP_INTENSITY: float = 6e-3
## Quiet time at the start of a dive (and after a reset) before spontaneous
## leaks can begin.
const START_QUIET_SEC: float = 45.0
## Depth multiplier on the spontaneous rate: SURFACE_FACTOR at the surface,
## FLOOR_FACTOR at FLOOR_DEPTH (the canyon floor), linear between, flat beyond.
const SURFACE_FACTOR: float = 0.25
const FLOOR_FACTOR: float = 2.0
const FLOOR_DEPTH: float = 230.0
const PATCH_HOLD_SEC: Vector2 = Vector2(45.0, 240.0)  # zero vs perfect quality
## A strike this hard (m/s) always opens a leak; softer ones scale the chance.
const STRIKE_FOR_CERTAIN_LEAK: float = 1.2

## Mean seconds between spontaneous leaks at depth factor 1.0 (about double the
## old 60-120 s first-leak delay).
@export var mean_interval_sec: float = 180.0
## Tonnes/s in through an open leak. One unattended leak should leave the sub
## unable to surface in 3-5 minutes (see docs/damage.md).
@export var leak_flow: float = 0.04
## Tonnes/s out with the pump on: between 1x and 2x `leak_flow`, so one pump
## beats one leak but not two.
@export var pump_flow: float = 0.06
@export var controller: SubController
@export var leaks_root: Node3D
@export var pump: Lever
@export var pump_point: Node3D

var open_index: int = -1
## Dev switch (host decides, synced): no spontaneous leaks. Hull strikes still leak.
var spontaneous_disabled: bool = false

var _leaks: Array[Leak] = []
var _timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _pump_audio: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group(&"noise_sources")
	add_to_group(&"leak_system")
	for child: Node in leaks_root.get_children():
		var leak: Leak = child as Leak
		if leak != null:
			_leaks.append(leak)
			leak.patch_completed.connect(_on_patch_completed)
	_rng.randomize()
	_timer = START_QUIET_SEC
	spontaneous_disabled = OS.get_cmdline_user_args().has("--no-leaks")
	if controller != null:
		controller.hull_strike.connect(_on_hull_strike)
	Net.peer_joined.connect(_on_peer_joined)
	_pump_audio = AudioStreamPlayer3D.new()
	_pump_audio.stream = ProceduralSounds.gurgle()
	_pump_audio.unit_size = SubAudio.UNIT_SIZE
	_pump_audio.bus = AudioBuses.INSIDE
	_pump_audio.pitch_scale = 1.6
	(pump_point if pump_point != null else self as Node).add_child(_pump_audio)


## True when the electric pump runs: its switch is on and the BILGE PUMP
## circuit has power (no [PowerSystem] counts as powered).
func pump_on() -> bool:
	return pump_switched_on() and pump_powered()


func pump_switched_on() -> bool:
	return pump != null and pump.get_value() > 0.5


func pump_powered() -> bool:
	var power: PowerSystem = get_tree().get_first_node_in_group(PowerSystem.GROUP) as PowerSystem if is_inside_tree() else null
	return power == null or power.is_powered(PowerSystem.Circuit.BILGE_PUMP)


## Tonnes/s the electric pump removes now: 0 when unpowered.
func current_pump_flow() -> float:
	return pump_flow if pump_on() else 0.0


## Host: the manual lever pump bails `tonnes`, whatever the power.
func manual_bail(tonnes: float) -> void:
	if multiplayer.is_server() and controller != null:
		controller.model.change_bilge(-absf(tonnes))


func noise_intensity() -> float:
	var total: float = LEAK_INTENSITY if open_index != -1 else 0.0
	if pump_on():
		total += PUMP_INTENSITY
	return total


func noise_breakdown() -> Dictionary:
	return {
		"leak hiss": LEAK_INTENSITY if open_index != -1 else 0.0,
		"bilge pump": PUMP_INTENSITY if pump_on() else 0.0,
	}


func _process(_delta: float) -> void:
	var want: bool = pump_on()
	if want and not _pump_audio.playing:
		_pump_audio.volume_db = SubAudio.volume_for(PUMP_INTENSITY)
		_pump_audio.play()
	elif not want and _pump_audio.playing:
		_pump_audio.stop()


func _physics_process(delta: float) -> void:
	var power: PowerSystem = get_tree().get_first_node_in_group(PowerSystem.GROUP) as PowerSystem
	if power != null:
		power.set_bilge_pump_running(pump_switched_on())
	if not multiplayer.is_server() or controller == null or not controller.enabled:
		return
	if open_index != -1:
		controller.model.change_bilge(leak_flow * delta)
	controller.model.change_bilge(-current_pump_flow() * delta)
	_timer -= delta
	if _timer <= 0.0 and open_index == -1 and spontaneous_roll(delta, controller.depth):
		open_random_leak()


## Multiplier on the spontaneous leak rate at this depth (m). Monotonic
## non-decreasing: rare at the surface, commonest at the canyon floor.
static func depth_factor(depth: float) -> float:
	return lerpf(SURFACE_FACTOR, FLOOR_FACTOR, clampf(depth / FLOOR_DEPTH, 0.0, 1.0))


## Spontaneous leaks per second at this depth.
func spontaneous_rate(depth: float) -> float:
	return depth_factor(depth) / maxf(mean_interval_sec, 0.001)


## Host: one Poisson draw for a step of `delta` seconds. False while the dev
## switch is on or the quiet period (`_timer`) has not run out.
func spontaneous_roll(delta: float, depth: float) -> bool:
	if spontaneous_disabled or _timer > 0.0:
		return false
	return _rng.randf() < 1.0 - exp(-spontaneous_rate(depth) * delta)


## Any peer: ask the host to switch spontaneous leaks off or on.
func request_spontaneous_disabled(off: bool) -> void:
	if multiplayer.is_server():
		_set_spontaneous_disabled.rpc(off)
	else:
		_rpc_request_spontaneous_disabled.rpc_id(1, off)


@rpc("any_peer", "reliable")
func _rpc_request_spontaneous_disabled(off: bool) -> void:
	if multiplayer.is_server() and DevOverlay.allowed():
		_set_spontaneous_disabled.rpc(off)


@rpc("authority", "call_local", "reliable")
func _set_spontaneous_disabled(off: bool) -> void:
	spontaneous_disabled = off
	print("[leaks] spontaneous leaks %s by developer" % ("disabled" if off else "enabled"))


## Host: closes everything and restarts the leak clock.
func reset() -> void:
	if not multiplayer.is_server():
		return
	_set_leak.rpc(-1)
	if pump != null:
		pump.host_set_value(0.0)
	_timer = START_QUIET_SEC


## Host: opens a leak at a random point (if none is open).
func open_random_leak() -> void:
	if not multiplayer.is_server() or _leaks.is_empty() or open_index != -1:
		return
	_set_leak.rpc(_rng.randi_range(0, _leaks.size() - 1))
	leak_opened.emit(String(_leaks[open_index].name))


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
	leak_patched.emit(quality, _timer)


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
		_set_spontaneous_disabled.rpc_id(peer_id, spontaneous_disabled)
