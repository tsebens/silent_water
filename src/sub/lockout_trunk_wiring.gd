class_name LockoutTrunkWiring
extends Node3D
## Connects the lock-out trunk's controls, climb and noise to its [LockoutTrunk] state machine.
## Top wheel: closed seals the top hatch, open opens it. Flood valve: open floods, closed drains.
## Bottom lever: up opens the bottom hatch, down closes it. The trunk refuses what its table
## does not allow, so a control left in the wrong place does nothing until the trunk catches up.
## Noise: the pumps are a constant source while they run (intensity, never dB) and each hatch
## move fires one clank event.

## A control counts as moved to an end past this fraction of its range.
const END_FRACTION: float = 0.9

@export var trunk: LockoutTrunk
@export var top_wheel: Valve
@export var flood_valve: Valve
@export var bottom_lever: Lever
@export var transit: ClimbTransit
@export var pump_emitter: SoundEmitter
@export var clank_emitter: SoundEmitter


func _ready() -> void:
	add_to_group(&"noise_sources")
	if top_wheel != null:
		top_wheel.value_changed.connect(_on_top_wheel)
	if flood_valve != null:
		flood_valve.value_changed.connect(_on_flood_valve)
	if bottom_lever != null:
		bottom_lever.value_changed.connect(_on_bottom_lever)
	if transit != null:
		transit.gate = Callable(self, "_top_open")
	if trunk != null:
		trunk.hatch_moved.connect(_on_hatch_moved)


func _physics_process(_delta: float) -> void:
	if pump_emitter != null and trunk != null:
		pump_emitter.active = trunk.pump_running()
		pump_emitter.world_position = global_position


func _top_open() -> bool:
	return trunk != null and trunk.state == LockoutTrunk.State.DRY_OPEN


## Linear intensity of the trunk right now: zero idle, the pump type's intensity while pumping.
func noise_intensity() -> float:
	if trunk == null or pump_emitter == null or pump_emitter.sound_type == null or not trunk.pump_running():
		return 0.0
	return pump_emitter.sound_type.scaled_intensity(pump_emitter.scale)


func _on_top_wheel(v: float) -> void:
	var f: float = _fraction(top_wheel, v)
	if f >= END_FRACTION:
		trunk.seal_top()
	elif f <= 1.0 - END_FRACTION:
		trunk.open_top()


func _on_flood_valve(v: float) -> void:
	var f: float = _fraction(flood_valve, v)
	if f >= END_FRACTION:
		trunk.start_flood()
	elif f <= 1.0 - END_FRACTION:
		trunk.start_drain()


func _on_bottom_lever(v: float) -> void:
	var f: float = _fraction(bottom_lever, v)
	if f >= END_FRACTION:
		trunk.open_bottom()
	elif f <= 1.0 - END_FRACTION:
		trunk.close_bottom()


func _fraction(c: Interactable, v: float) -> float:
	return inverse_lerp(c.min_value, c.max_value, v)


func _on_hatch_moved(_hatch: StringName, _open: bool) -> void:
	if clank_emitter != null:
		clank_emitter.world_position = global_position
		clank_emitter.fire()
