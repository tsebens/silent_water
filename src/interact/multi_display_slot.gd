class_name MultiDisplaySlot
extends Resource
## One widget slot of a [MultiDisplay]: what to draw, which readout feeds it and
## how it is formatted and coloured. All of the logic that turns a readout into
## text, a fraction or a colour is here, so it can be tested without drawing.

enum Kind { EMPTY, NUMBER, TEXT, PIE, DIAL, BAR }

@export var kind: Kind = Kind.EMPTY
## Readout name asked of the source group.
@export var readout: StringName = &""
@export var label: String = ""
@export var units: String = ""
@export var min_value: float = 0.0
@export var max_value: float = 100.0
## printf format for the number (`%.1f`, `%d`).
@export var format: String = "%.1f"
## For a [constant TEXT] slot: the readout, rounded, picks the entry. Out of range shows the number.
@export var texts: PackedStringArray = []
## Palette swatch of the widget in its normal state.
@export var swatch: StringName = &"light_readout"
## Warning thresholds in readout units. [constant INF] switches one off.
@export var warn_at: float = INF
@export var alarm_at: float = INF
## When true the thresholds trip as the value falls to or below them (oxygen, charge).
@export var low_is_bad: bool = false
@export var warn_swatch: StringName = &"light_warn"
@export var alarm_swatch: StringName = &"light_alarm"


## 0 normal, 1 warning, 2 alarm.
func level_for(v: float) -> int:
	if low_is_bad:
		if v <= alarm_at:
			return 2
		return 1 if v <= warn_at else 0
	if v >= alarm_at:
		return 2
	return 1 if v >= warn_at else 0


func swatch_for(v: float) -> StringName:
	match level_for(v):
		2:
			return alarm_swatch
		1:
			return warn_swatch
	return swatch


## Redundant cue so a warning never relies on colour: `!` for warning, `!!` for alarm.
func marker_for(v: float) -> String:
	return "!".repeat(level_for(v))


## The value as text: the number with its format, or the matching entry of [member texts].
func text_for(v: float) -> String:
	if kind == Kind.TEXT:
		var i: int = roundi(v)
		if i >= 0 and i < texts.size():
			return texts[i]
	return format % v


## Value with units, as shown by number slots.
func number_for(v: float) -> String:
	var s: String = format % v
	return s if units.is_empty() else "%s %s" % [s, units]


## Position of [param v] along the range, 0..1.
func fraction_for(v: float) -> float:
	if is_equal_approx(max_value, min_value):
		return 0.0
	return clampf(inverse_lerp(min_value, max_value, v), 0.0, 1.0)


## Share of a pie that is filled (0..1).
func pie_for(v: float) -> float:
	return fraction_for(v)


## Where a bar's fill runs, as (from, to) positions on the track, 0 bottom, 1 top.
## A range that spans zero grows from the zero line, so negatives go down.
func bar_span(v: float) -> Vector2:
	var t: float = fraction_for(v)
	if min_value < 0.0 and max_value > 0.0:
		var zero: float = fraction_for(0.0)
		return Vector2(minf(zero, t), maxf(zero, t))
	return Vector2(0.0, t)
