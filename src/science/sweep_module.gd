class_name SweepModule
extends ScienceModule
## The SWEEP science module: the bathymetry sounder. Arms the [SweepObjective]; its screen shows the coverage grid
## ([method cell_depth_swatch] names each cell's palette swatch) and a hint to steer for unsounded ground. Pings are
## loud (the objective's noise). The module draws from the DISPLAYS circuit: unpowered, it cannot run.

@export var objective: SweepObjective

var powered: bool = true


func _init() -> void:
	module_type = ModuleLoadout.Type.SWEEP


func _ready() -> void:
	PowerSink.bind(self, PowerSystem.Circuit.DISPLAYS, set_powered)
	_link()


func set_powered(on: bool) -> void:
	powered = on
	if not on:
		armed = false


func _link() -> void:
	if objective == null and is_inside_tree():
		objective = get_tree().get_first_node_in_group(&"sweep_objectives") as SweepObjective
	if objective != null:
		objective.module = self


func _objective() -> SweepObjective:
	if objective == null or objective.module != self:
		_link()
	return objective


func toggle_armed() -> void:
	if powered:
		armed = not armed


## Fraction of the area sounded, 0..1.
func coverage() -> float:
	var o: SweepObjective = _objective()
	return o.coverage() if o != null else 0.0


func health() -> float:
	var o: SweepObjective = _objective()
	return o.progress() if o != null else 0.0


## Palette swatch for one grid cell on the screen: readout cyan when sounded, off-screen dark when not.
func cell_swatch(ix: int, iz: int) -> StringName:
	var o: SweepObjective = _objective()
	return &"light_readout" if o != null and o.is_covered(ix, iz) else &"sub_screen_off"


func time_left() -> float:
	return 0.0


func hint() -> String:
	var o: SweepObjective = _objective()
	if o == null or o.complete or controller_pos_unknown(o):
		return ""
	if not o.inside_area(o.controller.model.position):
		return "TO AREA"
	return ""


func controller_pos_unknown(o: SweepObjective) -> bool:
	return o.controller == null
