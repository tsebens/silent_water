class_name ProbeModule
extends ScienceModule
## The PROBE science module: the winch. Arming it readies the winch on the [ProbeObjective]; the mouse wheel (or
## up/down keys) lowers and raises the probe. Its screen is the depth counter ([method counter_m]) and the reel
## ([method reel_angle]), with a hold ring ([method health]) and a hint. It draws from the DISPLAYS circuit:
## unpowered, it cannot run.

@export var objective: ProbeObjective

var powered: bool = true


func _init() -> void:
	module_type = ModuleLoadout.Type.PROBE


func _ready() -> void:
	PowerSink.bind(self, PowerSystem.Circuit.DISPLAYS, set_powered)
	_link()


func set_powered(on: bool) -> void:
	powered = on
	if not on:
		armed = false
		var o: ProbeObjective = _objective()
		if o != null:
			o.winch_dir = 0


func _link() -> void:
	if objective == null and is_inside_tree():
		objective = get_tree().get_first_node_in_group(&"probe_objectives") as ProbeObjective
	if objective != null:
		objective.module = self


func _objective() -> ProbeObjective:
	if objective == null or objective.module != self:
		_link()
	return objective


func toggle_armed() -> void:
	if powered:
		armed = not armed
		if not armed:
			var o: ProbeObjective = _objective()
			if o != null:
				o.winch_dir = 0


## Wheel or Up/Down: lower or raise the probe. A wheel notch moves the line a fixed step; the keys run the winch until released.
func work(event: InputEvent) -> bool:
	var o: ProbeObjective = _objective()
	if o == null or not armed:
		return false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_DOWN:
				o.nudge(1)
				return true
			MOUSE_BUTTON_WHEEL_UP:
				o.nudge(-1)
				return true
	if event is InputEventKey:
		var k: InputEventKey = event as InputEventKey
		if k.keycode == KEY_DOWN or k.keycode == KEY_UP:
			o.winch_dir = (1 if k.keycode == KEY_DOWN else -1) if k.pressed else 0
			return true
	return false


## Depth counter, metres of line out.
func counter_m() -> float:
	var o: ProbeObjective = _objective()
	return o.counter() if o != null else 0.0


## Reel rotation, radians.
func reel_angle() -> float:
	var o: ProbeObjective = _objective()
	return o.reel_angle() if o != null else 0.0


## Hold progress toward the reading, 0..1.
func health() -> float:
	var o: ProbeObjective = _objective()
	return o.hold_progress() if o != null else 0.0


func time_left() -> float:
	var o: ProbeObjective = _objective()
	if o == null or not armed or o.hold <= 0.0:
		return 0.0
	return ProbeObjective.HOLD_SEC - o.hold


func hint() -> String:
	var o: ProbeObjective = _objective()
	if o == null or o.complete or not armed:
		return ""
	var any_close: Node3D = null
	for p: Node3D in o.all_points():
		if not o.done.has(p) and o.range_to(p) <= ProbeObjective.RADIUS_M:
			any_close = p
			break
	if any_close == null:
		return "TO POINT"
	if not o.in_band(any_close):
		return "LOWER" if o.tip_depth() < o.point_depth(any_close) else "RAISE"
	if not o.is_still():
		return "HOLD STILL"
	return ""
