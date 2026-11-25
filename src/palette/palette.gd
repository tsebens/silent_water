@tool
class_name Palette
extends Resource
## The game's colours, by name (docs/palette.md). One resource, `res://assets/palette/palette.tres`.
##
## [member paint] swatches are surface colours. [member light] swatches are colours something emits: a lamp, a
## readout, a light; their brightness comes from the energy they are used at, not from the value here.
## Nothing outside this file names a colour value: materials name swatches (see [RoleMaterial]), and code asks
## for a swatch by name with [method color].

const PATH: String = "res://assets/palette/palette.tres"

@export var paint: Dictionary[StringName, Color] = {}:
	set(v):
		paint = v
		emit_changed()
@export var light: Dictionary[StringName, Color] = {}:
	set(v):
		light = v
		emit_changed()

static var _main: Palette


## The game's palette (loaded once; edits to it in the editor reach everything that asked for it).
static func main() -> Palette:
	if _main == null:
		_main = load(PATH) as Palette
	return _main


func has(swatch: StringName) -> bool:
	return paint.has(swatch) or light.has(swatch)


## A swatch's colour (sRGB, as a colour picker shows it). Magenta for a name that is not in the palette.
func color(swatch: StringName) -> Color:
	if paint.has(swatch):
		return paint[swatch]
	if light.has(swatch):
		return light[swatch]
	push_warning("Palette: no swatch '%s'" % swatch)
	return Color.MAGENTA


## Sets a swatch (paint unless the name is a light swatch) and tells every user of the palette.
func set_color(swatch: StringName, c: Color) -> void:
	if light.has(swatch):
		light[swatch] = c
	else:
		paint[swatch] = c
	emit_changed()


## True for a colour in the band reserved for information (readouts, charts): bright, saturated cyan.
static func in_information_band(c: Color) -> bool:
	return c.s >= 0.5 and c.v >= 0.6 and c.h * 360.0 >= 165.0 and c.h * 360.0 <= 195.0
