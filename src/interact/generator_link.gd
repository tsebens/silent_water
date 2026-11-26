class_name GeneratorLink
extends Node
## Ties a [SwitchLever] to the generator. Throwing the switch (held by the local
## player) asks [PowerSystem] to start or stop it; when the generator's running
## state changes by itself (a trip or heat shutdown, a finished start) the switch
## is moved to match, without sending a request.

## Node with `readout` and `request_generator` (a [PowerSystem]).
## Unset: the first node in the power group.
@export var power: Node
@export var switch_lever: SwitchLever

var _running: bool = false
var _syncing: bool = false
## The last request sent, so one throw (which reports its value more than once) is one request.
var _requested: bool = false


func _ready() -> void:
	if power == null and is_inside_tree():
		power = get_tree().get_first_node_in_group(PowerSystem.GROUP)
	if switch_lever != null:
		switch_lever.value_changed.connect(_on_switch_changed)
	_running = generator_running()
	_follow(true)


func _process(_delta: float) -> void:
	var now: bool = generator_running()
	if now != _running:
		_running = now
		_follow(false)


func generator_running() -> bool:
	if power == null or not power.has_method(&"readout"):
		return false
	return float(power.call(&"readout", &"generator_running")) >= 0.5


## Moves the switch to the generator's state, sending nothing.
func _follow(force: bool) -> void:
	if switch_lever == null or switch_lever.is_held_locally():
		return
	var target: float = switch_lever.max_value if _running else switch_lever.min_value
	if not force and is_equal_approx(switch_lever.get_value(), target):
		return
	_syncing = true
	if switch_lever.multiplayer.is_server():
		# Host: the value goes out to every peer; clients just receive it.
		switch_lever.host_set_value(target)
	else:
		switch_lever.state.set_value_silent(target)
		switch_lever._apply_visual(target)
	_requested = target >= (switch_lever.min_value + switch_lever.max_value) * 0.5
	_syncing = false


func _on_switch_changed(_value: float) -> void:
	# Only a throw by the player holding the switch is a request.
	if _syncing or power == null or switch_lever == null or not switch_lever.is_held_locally():
		return
	if not power.has_method(&"request_generator"):
		return
	var mid: float = (switch_lever.min_value + switch_lever.max_value) * 0.5
	var on: bool = switch_lever.get_value() >= mid
	if on == _requested:
		return
	_requested = on
	power.call(&"request_generator", on)
