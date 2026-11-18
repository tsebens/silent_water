class_name SubTestMotion
extends Node
## Host-only placeholder motion so the sub-frame can be tested before M2's
## real handling exists: a slow forward drift with gentle pitch and roll.
## Toggle with F2 on the host, or start enabled with the `--tilt-test` arg.

@export var sub_frame: SubFrame
@export var forward_speed: float = 1.0
@export var pitch_amplitude_deg: float = 12.0
@export var roll_amplitude_deg: float = 6.0
@export var period_sec: float = 16.0

var enabled: bool = false
var _time: float = 0.0
var _position: Vector3 = Vector3.ZERO


func _ready() -> void:
	enabled = OS.get_cmdline_user_args().has("--tilt-test")


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F2:
		enabled = not enabled
		print("[sub] test motion %s" % ("on" if enabled else "off"))


func _physics_process(delta: float) -> void:
	if not enabled or sub_frame == null or not sub_frame.is_multiplayer_authority():
		return
	_time += delta
	var phase: float = TAU * _time / period_sec
	var pitch: float = deg_to_rad(pitch_amplitude_deg) * sin(phase)
	var roll: float = deg_to_rad(roll_amplitude_deg) * sin(phase * 0.5)
	var basis: Basis = Basis.from_euler(Vector3(pitch, 0.0, roll))
	var velocity: Vector3 = basis * (Vector3.FORWARD * forward_speed)
	_position += velocity * delta
	sub_frame.set_pose(Transform3D(basis, _position), velocity)
