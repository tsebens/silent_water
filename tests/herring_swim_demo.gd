extends Node3D
## Review fixture for the rigged herring (#930): a sine wave travelling down spine1..spine4 and tail, growing toward the tail,
## with a small fin flutter. It is not the swim behaviour (#932). Open tests/herring_swim_demo.tscn in the editor and play it;
## tests/herring_swim_shot.tscn renders it as a contact sheet (tools/herring_swim_sheet.sh).

const PERIOD: float = 1.2                       ## seconds per loop
const WAVE_LAG: float = 0.16                    ## cycle fraction of delay per bone, nose to tail
const BODY_DEG: Dictionary = {"spine1": 5.0, "spine2": 10.0, "spine3": 18.0, "spine4": 26.0, "tail": 36.0}
const FLUTTER_DEG: Dictionary = {"dorsal": 3.0, "pectoral_l": 12.0, "pectoral_r": -12.0, "pelvic_l": 8.0, "pelvic_r": -8.0}

var _skel: Skeleton3D
var _rest: Dictionary = {}


func _ready() -> void:
	_skel = find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for b: String in BODY_DEG.keys() + FLUTTER_DEG.keys():
		_rest[b] = _skel.get_bone_rest(_skel.find_bone(b)).basis.get_rotation_quaternion()
	apply(0.0)


func _process(delta: float) -> void:
	apply(fmod(Time.get_ticks_msec() / 1000.0, PERIOD))


## Pose the bones for `t` seconds into the loop.
func apply(t: float) -> void:
	var phase: float = t / PERIOD
	var i: int = 0
	for b: String in BODY_DEG.keys():
		var a: float = deg_to_rad(float(BODY_DEG[b])) * sin(TAU * (phase - WAVE_LAG * i))
		_turn(b, Quaternion(Vector3.UP, a))
		i += 1
	for b: String in FLUTTER_DEG.keys():
		var a: float = deg_to_rad(float(FLUTTER_DEG[b])) * sin(TAU * (2.0 * phase - 0.3))
		_turn(b, Quaternion(Vector3.UP, a))


func _turn(bone: String, q: Quaternion) -> void:
	_skel.set_bone_pose_rotation(_skel.find_bone(bone), (_rest[bone] as Quaternion) * q)
