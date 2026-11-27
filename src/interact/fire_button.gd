class_name FireButton
extends Node
## The guarded FIRE button of a decoy launch tube. A press of `button` counts
## only while `guard` (a two-position hinge, upper half = open) is open, and
## then asks `tube` to fire. [method LaunchTube.fire] refuses a tube that is not
## primed, so an unprimed press leaves it unchanged.
##
## Host-authoritative through the tube: [method LaunchTube.request_fire] sends a
## client's press to the host, which runs it.

## Emitted on each press that counted (guard open), whether or not the tube fired.
signal pressed

## Two-position hinge that must be open for a press to count.
@export var guard: Interactable
## The press itself (a PushButton).
@export var button: Interactable
## The tube to fire (a LaunchTube node path, set on the instance).
@export var tube: LaunchTube


func _ready() -> void:
	if button != null:
		button.value_changed.connect(_on_button_changed)


func guard_open() -> bool:
	return guard != null and guard.get_normalized() >= 0.5


## Any peer: ask the tube to fire. Ignored while the guard is closed.
func request_fire() -> void:
	if tube == null or not guard_open():
		return
	pressed.emit()
	tube.request_fire()


func _on_button_changed(value: float) -> void:
	# Only a press by the player holding the button is a request.
	if button == null or not button.is_held_locally():
		return
	if value >= (button.min_value + button.max_value) * 0.5:
		request_fire()
