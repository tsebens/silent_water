class_name PaletteLight
extends Node
## Sets its parent light's colour from a light swatch (docs/palette.md), at `_ready` and whenever the palette
## changes, so a swatch edit reaches the light. Energy is the light's own and is left alone.

## Light swatch the parent light takes its colour from.
@export var swatch: StringName = &"light_cabin"
## Swatch used instead while [member stealth] is on; empty for a light that ignores stealth mode.
@export var stealth_swatch: StringName = &""

var stealth: bool = false:
	set(v):
		stealth = v
		apply()


func _ready() -> void:
	var pal: Palette = Palette.main()
	if pal != null and not pal.changed.is_connected(apply):
		pal.changed.connect(apply)
	apply()


func apply() -> void:
	var light: Light3D = get_parent() as Light3D
	var pal: Palette = Palette.main()
	if light == null or pal == null:
		return
	var swatch_name: StringName = stealth_swatch if stealth and stealth_swatch != &"" else swatch
	light.light_color = pal.color(swatch_name)
