class_name CameraModule
extends ScienceModule
## The CAMERA science module: the external camera. Arming it opens the viewfinder on the [PhotoObjective]; moving the
## mouse aims ([method work]), the left button is the shutter and the right button toggles the flash. Its screen shows a
## light meter ([method light_meter]) and a stillness indicator ([method stillness_meter]) live, with a hint for the
## weakest of range, light and stillness. It draws from the DISPLAYS circuit: unpowered, it cannot run.

## Radians of aim per pixel of mouse motion.
const AIM_SENSITIVITY: float = 0.002

@export var objective: PhotoObjective

var powered: bool = true


func _init() -> void:
	module_type = ModuleLoadout.Type.CAMERA


func _ready() -> void:
	add_to_group(&"camera_modules")
	PowerSink.bind(self, PowerSystem.Circuit.DISPLAYS, set_powered)
	_link()


func set_powered(on: bool) -> void:
	powered = on
	if not on:
		armed = false


func _link() -> void:
	if objective == null and is_inside_tree():
		objective = get_tree().get_first_node_in_group(&"photo_objectives") as PhotoObjective
	if objective != null:
		objective.module = self


func _objective() -> PhotoObjective:
	if objective == null or objective.module != self:
		_link()
	return objective


func toggle_armed() -> void:
	if powered:
		armed = not armed


## Mouse aims the camera, left button is the shutter, right button the flash.
func work(event: InputEvent) -> bool:
	var o: PhotoObjective = _objective()
	if o == null or not armed:
		return false
	if event is InputEventMouseMotion:
		var m: InputEventMouseMotion = event as InputEventMouseMotion
		o.aim = o.aim.rotated(Vector3.UP, -m.relative.x * AIM_SENSITIVITY)
		var right: Vector3 = o.aim.cross(Vector3.UP)
		if not right.is_zero_approx():
			o.aim = o.aim.rotated(right.normalized(), -m.relative.y * AIM_SENSITIVITY)
		return true
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				o.take_shot()
				return true
			MOUSE_BUTTON_RIGHT:
				o.flash_enabled = not o.flash_enabled
				return true
	return false


## Light meter reading, 0..1.
func light_meter() -> float:
	var o: PhotoObjective = _objective()
	return o.light_level(o.flash_enabled) if o != null else 0.0


## Stillness indicator, 0..1.
func stillness_meter() -> float:
	var o: PhotoObjective = _objective()
	return o.stillness() if o != null else 0.0


## Quality the shutter would give now.
func health() -> float:
	var o: PhotoObjective = _objective()
	return o.live_quality() if o != null else 0.0


func time_left() -> float:
	return 0.0


func hint() -> String:
	var o: PhotoObjective = _objective()
	if o == null or o.complete or not armed:
		return ""
	var t: Node3D = o.target()
	if t == null:
		return "AIM"
	var c: float = o.closeness(o.range_to(t))
	var l: float = o.light_level(o.flash_enabled)
	var s: float = o.stillness()
	if c <= l and c <= s:
		return "CLOSER"
	if l <= s:
		return "LIGHT"
	return "HOLD STILL"


## Named readout for a kit gauge: `light` and `stillness`, 0..1; unknown names give 0.
func readout(readout_name: StringName) -> float:
	match readout_name:
		&"light":
			return light_meter()
		&"stillness":
			return stillness_meter()
	return 0.0
