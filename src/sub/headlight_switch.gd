class_name HeadlightSwitch
extends Node
## Drives the external light from two switches: `power` turns it on or off, and `colour` swaps its
## [PaletteLight] between the halogen swatch (`light_work_white`) and the stealth red (`light_stealth_red`).
## A switch counts as "on" in the upper half of its range. Local on every peer; the switches replicate.

@export var light: Light3D
@export var power: Interactable
## Optional: up for red.
@export var colour: Interactable
@export var white_swatch: StringName = &"light_work_white"
@export var red_swatch: StringName = &"light_stealth_red"


func _ready() -> void:
	update()


func _process(_delta: float) -> void:
	update()


func update() -> void:
	if light == null:
		return
	if power != null:
		light.visible = power.get_normalized() >= 0.5 and _powered()
	var pl: PaletteLight = _palette_light()
	if pl == null:
		return
	pl.swatch = white_swatch
	pl.stealth_swatch = red_swatch
	var red: bool = colour != null and colour.get_normalized() >= 0.5
	if pl.stealth != red:
		pl.stealth = red


## True when EXT LTS has power (no [PowerSystem] counts as powered).
func _powered() -> bool:
	var ps: PowerSystem = get_tree().get_first_node_in_group(PowerSystem.GROUP) as PowerSystem if is_inside_tree() else null
	return ps == null or ps.is_powered(PowerSystem.Circuit.EXT_LTS)


func _palette_light() -> PaletteLight:
	for c: Node in light.get_children():
		if c is PaletteLight:
			return c as PaletteLight
	return null
