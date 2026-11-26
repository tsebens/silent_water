class_name PowerSink
extends Node
## Binds a consumer to one [PowerSystem] circuit. It finds the system in group
## [constant PowerSystem.GROUP], and calls [member on_change] with the circuit's
## power state now and on every change. With no power system in the tree the
## consumer stays powered. Systems react by this signal, never by a hard reference.

signal powered_changed(powered: bool)

var circuit: PowerSystem.Circuit = PowerSystem.Circuit.MOTOR
var powered: bool = true
var _power: PowerSystem


## Attach a sink for [param c] to [param owner]. [param on_change] takes a bool.
static func bind(owner: Node, c: PowerSystem.Circuit, on_change: Callable) -> PowerSink:
	var sink: PowerSink = PowerSink.new()
	sink.name = "PowerSink"
	sink.circuit = c
	sink.powered_changed.connect(on_change)
	owner.add_child(sink)
	return sink


func _ready() -> void:
	_power = get_tree().get_first_node_in_group(PowerSystem.GROUP) as PowerSystem
	if _power == null:
		return
	_power.circuit_powered.connect(_on_circuit_powered)
	_apply(_power.is_powered(circuit))


func _on_circuit_powered(c: PowerSystem.Circuit, p: bool) -> void:
	if c == circuit:
		_apply(p)


func _apply(p: bool) -> void:
	if p == powered:
		return
	powered = p
	powered_changed.emit(p)
