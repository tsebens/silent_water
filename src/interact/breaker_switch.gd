class_name BreakerSwitch
extends Interactable
## A breaker's click toggle. It shows the breaker's state from the power system's
## `breaker_<circuit>` readout: on (handle up, lamp ok), off (handle down, lamp off),
## tripped (handle mid-way, lamp warn), blown (handle limp, lamp alarm).
## A click asks [PowerSystem] to switch the breaker (a reset when tripped); a click on
## a blown one asks for a replacement, and sends nothing at 0 spares. The control
## holds no value of its own and is never grabbed: the power system is the truth.

const B := PowerSystem.BreakerState

@export var circuit: PowerSystem.Circuit = PowerSystem.Circuit.MOTOR
## Node with `readout`, `request_breaker` and `request_replace` (a [PowerSystem]).
## Unset: the first node in the power group.
@export var power: Node
## Pivots about local X.
@export var handle: Node3D
## Status lamp; its emission takes the state's swatch.
@export var lamp: MeshInstance3D
## Handle pitch (degrees) per state, indexed by [enum PowerSystem.BreakerState].
@export var handle_angles_deg: PackedFloat32Array = PackedFloat32Array([-30.0, 30.0, 0.0, -75.0])
@export var lamp_energy: float = 2.0

var _state: int = B.ON


func _ready() -> void:
	super._ready()
	if power == null and is_inside_tree():
		power = get_tree().get_first_node_in_group(PowerSystem.GROUP)
	refresh()


func _process(_delta: float) -> void:
	refresh()


## The breaker's state now (ON when there is no power system to ask).
func current_state() -> int:
	if power == null and is_inside_tree():
		# A power system later in the tree has not joined its group yet when this node's _ready ran.
		power = get_tree().get_first_node_in_group(PowerSystem.GROUP)
	if power == null or not power.has_method(&"readout"):
		return B.ON
	return int(power.call(&"readout", StringName("breaker_" + String(PowerSystem.CIRCUIT_NAMES[circuit]))))


func refresh() -> void:
	_state = current_state()
	if handle != null:
		handle.rotation.x = deg_to_rad(handle_angle_deg(_state))
	_apply_lamp(_state)


func handle_angle_deg(state: int) -> float:
	return handle_angles_deg[clampi(state, 0, handle_angles_deg.size() - 1)]


## Lamp swatch for a state; empty means dark.
static func lamp_swatch(state: int) -> StringName:
	match state:
		B.ON:
			return &"light_ok"
		B.TRIPPED:
			return &"light_warn"
		B.BLOWN:
			return &"light_alarm"
	return &""


## A click: no grab, just the request the state calls for.
func begin_interaction() -> void:
	if power == null:
		return
	match current_state():
		B.ON:
			power.call(&"request_breaker", circuit, false)
		B.OFF, B.TRIPPED:
			power.call(&"request_breaker", circuit, true)
		B.BLOWN:
			if float(power.call(&"readout", &"spares_remaining")) >= 1.0:
				power.call(&"request_replace", circuit)


func drag(_relative: Vector2) -> void:
	pass


func end_interaction() -> void:
	pass


func noise_intensity() -> float:
	return 0.0


func interaction_hint() -> String:
	match _state:
		B.TRIPPED:
			return "click to reset"
		B.BLOWN:
			return "click to replace from spares"
	return "click to switch"


func _apply_lamp(state: int) -> void:
	if lamp == null:
		return
	var swatch: StringName = lamp_swatch(state)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	if swatch == &"":
		mat.emission_enabled = false
	else:
		var pal: Palette = Palette.main()
		var c: Color = pal.color(swatch) if pal != null else Color.WHITE
		mat.albedo_color = c
		mat.emission_enabled = true
		mat.emission = c
		mat.emission_energy_multiplier = lamp_energy
	lamp.material_override = mat
