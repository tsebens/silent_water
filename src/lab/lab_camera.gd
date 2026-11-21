class_name LabCamera
extends Camera3D
## Free-flying camera for the terrain lab. Hold the right mouse button to look
## around; while it is held, W/A/S/D fly, E/Q rise and sink, Shift is fast and
## the wheel changes the base speed. Nothing happens without the button, so
## typing into the panel never moves the camera.

const MIN_SPEED: float = 2.0
const MAX_SPEED: float = 400.0
const FAST_FACTOR: float = 4.0
const LOOK_SENSITIVITY: float = 0.003

var speed: float = 40.0
var yaw: float = 0.0
var pitch: float = 0.0
var _looking: bool = false


func _ready() -> void:
	far = 3000.0
	current = true


## Places the camera at [param pos], looking along yaw/pitch (radians; yaw 0
## faces -Z, positive pitch looks up).
func set_view(pos: Vector3, new_yaw: float, new_pitch: float) -> void:
	position = pos
	yaw = new_yaw
	pitch = clampf(new_pitch, -PI * 0.49, PI * 0.49)
	basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))


## Moves by [param input] (x right, y up, z back, local to the view) for
## [param delta] seconds.
func fly(input: Vector3, delta: float, fast: bool) -> void:
	var s: float = speed * (FAST_FACTOR if fast else 1.0)
	position += basis * input * s * delta


func _unhandled_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				_set_looking(button.pressed)
			MOUSE_BUTTON_WHEEL_UP:
				speed = minf(speed * 1.15, MAX_SPEED)
			MOUSE_BUTTON_WHEEL_DOWN:
				speed = maxf(speed / 1.15, MIN_SPEED)
		return
	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _looking:
		set_view(position, yaw - motion.relative.x * LOOK_SENSITIVITY, pitch - motion.relative.y * LOOK_SENSITIVITY)


func _process(delta: float) -> void:
	if not _looking:
		return
	var v: Vector3 = Vector3.ZERO
	v.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	v.z = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	v.y = float(Input.is_physical_key_pressed(KEY_E)) - float(Input.is_physical_key_pressed(KEY_Q))
	if v != Vector3.ZERO:
		fly(v.normalized(), delta, Input.is_physical_key_pressed(KEY_SHIFT))


func _set_looking(on: bool) -> void:
	_looking = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _exit_tree() -> void:
	if _looking:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
