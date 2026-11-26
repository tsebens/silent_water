class_name JunctionBox
extends Interactable
## A fixed junction box on one circuit's cable tray. While the line is damaged
## here it sparks and crackles (positional audio, found by ear) until a crew
## member repairs it: occupy it (interact) and hold for [member PowerConfig.repair_time].
##
## The value of this Interactable is repair progress (0..1), so other crew see
## someone working on it. Damage itself lives in [PowerSystem].

signal repaired(box: JunctionBox)

## Spark crackle, linear intensity (about 70 dB).
const CRACKLE_INTENSITY: float = 1e-3

@export var circuit: PowerSystem.Circuit = PowerSystem.Circuit.MOTOR
## Which of the line's boxes this is (0-based).
@export var box_index: int = 0
@export var power: PowerSystem
@export var sparks: CPUParticles3D
@export var grab_shape: CollisionShape3D

var is_damaged: bool = false

var _held_time: float = 0.0
var _crackle: AudioStreamPlayer3D


func _init() -> void:
	super._init()
	min_value = 0.0
	max_value = 1.0


func _ready() -> void:
	super._ready()
	_crackle = AudioStreamPlayer3D.new()
	_crackle.stream = ProceduralSounds.crackle()
	_crackle.unit_size = SubAudio.UNIT_SIZE
	_crackle.bus = AudioBuses.INSIDE
	add_child(_crackle)
	if power == null and is_inside_tree():
		power = get_tree().get_first_node_in_group(PowerSystem.GROUP) as PowerSystem
	if power != null:
		power.box_damage_changed.connect(_on_box_damage_changed)
		set_damaged(power.box_damaged(circuit, box_index))
	else:
		set_damaged(false)


func _on_box_damage_changed(c: PowerSystem.Circuit, box: int, damaged: bool) -> void:
	if c == circuit and box == box_index:
		set_damaged(damaged)


func set_damaged(damaged: bool) -> void:
	is_damaged = damaged
	if sparks != null:
		sparks.emitting = damaged
	if grab_shape != null:
		grab_shape.disabled = not damaged
	if damaged:
		_crackle.volume_db = SubAudio.volume_for(CRACKLE_INTENSITY)
		_crackle.play(randf())
	else:
		_crackle.stop()
		if is_held_locally():
			end_interaction()


func begin_interaction() -> void:
	if not is_damaged:
		return
	_held_time = 0.0
	super.begin_interaction()


## Mouse movement does nothing: the repair is a plain hold.
func drag(_relative: Vector2) -> void:
	pass


func end_interaction() -> void:
	if is_held_locally() and get_value() < 1.0:
		drive_to(0.0)  # Let go early: the repair starts over.
	super.end_interaction()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_held_locally() or not is_damaged:
		return
	var needed: float = power.config.repair_time if power != null else 4.0
	_held_time += delta
	drive_to(minf(_held_time / needed, 1.0))
	if _held_time >= needed:
		end_interaction()
		complete_repair()


## The holder finished: ask the host to clear the damage.
func complete_repair() -> void:
	if power != null:
		power.request_repair(circuit, box_index)
	repaired.emit(self)


## Sparking is counted by the sound, not the noise system's polled controls.
func noise_intensity() -> float:
	return 0.0


func interaction_hint() -> String:
	return "hold interact to repair the line"
