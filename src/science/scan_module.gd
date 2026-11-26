class_name ScanModule
extends ScienceModule
## The SCAN science module: arms the [ScanObjective] in place of the engineering wall switch. The screen shows a
## progress ring ([method ring]), the range to the array ([method range_m]) and a CLOSER hint. The scan's noise is the
## objective's, unchanged. The module draws from the DISPLAYS circuit: unpowered, it cannot run.

## The objective this module drives. Found in group [code]scan_objectives[/code] when not set.
@export var objective: ScanObjective

## The arm switch on the face, if any: thrown on arms the scan, thrown off stops it, and the module's own state
## drives the switch back (a power loss throws it off).
@export var arm_switch: SwitchLever

var powered: bool = true


func _init() -> void:
	module_type = ModuleLoadout.Type.SCAN


func _ready() -> void:
	PowerSink.bind(self, PowerSystem.Circuit.DISPLAYS, set_powered)
	_link()
	if arm_switch != null:
		arm_switch.value_changed.connect(_on_switch_changed)
		armed_changed.connect(_on_armed_changed)


func _switch_on() -> bool:
	return arm_switch.get_value() >= (arm_switch.min_value + arm_switch.max_value) * 0.5


func _set_switch(on: bool) -> void:
	if multiplayer.is_server():
		arm_switch.host_set_value(arm_switch.max_value if on else arm_switch.min_value)


func _on_switch_changed(_value: float) -> void:
	var on: bool = _switch_on()
	if on and not powered:
		_set_switch(false)
	elif on != armed:
		armed = on


func _on_armed_changed(on: bool) -> void:
	if arm_switch != null and _switch_on() != on:
		_set_switch(on)


func set_powered(on: bool) -> void:
	powered = on
	if not on:
		armed = false


func _link() -> void:
	if objective == null and is_inside_tree():
		objective = get_tree().get_first_node_in_group(&"scan_objectives") as ScanObjective
	if objective != null:
		objective.module = self


func _objective() -> ScanObjective:
	if objective == null or objective.module != self:
		_link()
	return objective


func toggle_armed() -> void:
	if powered:
		armed = not armed


## Progress ring fill, 0..1.
func ring() -> float:
	var o: ScanObjective = _objective()
	return o.progress if o != null else 0.0


func health() -> float:
	return ring()


## Distance to the array in metres (-1 when unknown).
func range_m() -> float:
	var o: ScanObjective = _objective()
	return o.range_to_target() if o != null else -1.0


func time_left() -> float:
	var o: ScanObjective = _objective()
	if o == null or not armed:
		return 0.0
	return (1.0 - o.progress) * ScanObjective.SCAN_TIME_SEC


func hint() -> String:
	var o: ScanObjective = _objective()
	if o == null or o.complete:
		return ""
	if o.range_to_target() > ScanObjective.MAX_RANGE_M:
		return "CLOSER"
	if not o.in_position():
		return "HOLD STILL"
	return ""
