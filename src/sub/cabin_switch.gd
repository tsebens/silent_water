class_name CabinSwitch
extends Node
## Drives [CabinLights] from two switches: `power` turns the cabin lights on or off (the dimmer keeps setting
## the level while they are on), and `stealth_switch` sets [member CabinLights.stealth]. A switch counts as
## "on" in the upper half of its range.

@export var lights: CabinLights
@export var power: Interactable
@export var stealth_switch: Interactable


func _ready() -> void:
	update()


func _process(_delta: float) -> void:
	update()


func update() -> void:
	if lights == null:
		return
	if power != null:
		lights.enabled = power.get_normalized() >= 0.5
	if stealth_switch != null:
		var red: bool = stealth_switch.get_normalized() >= 0.5
		if lights.stealth != red:
			lights.stealth = red
