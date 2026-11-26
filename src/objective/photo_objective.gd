class_name PhotoObjective
extends Node
## Host-side photo job. The operator aims the external camera at a subject (a Node3D in group [code]photo_subjects[/code],
## or listed in [member subjects]) and takes the shot. A shot's quality is the product of three things, each 0..1:
## closeness (full inside [constant CLOSE_M], none beyond [constant MAX_RANGE_M]), light (the external lights, or the
## flash, which is brightest) and stillness (full at rest, none at [constant MAX_SPEED] and over). Without EXT LTS or a
## flash the light is only the dim [constant AMBIENT_LIGHT], so shots come out poor. The flash is bright: it adds a
## short burst of noise (the capacitor whine and discharge) that the noise system hears. A shot of a subject in range
## and in frame logs its reading; a subject counts as photographed at [constant GOOD_QUALITY] or better. The job is
## complete when every subject is.

signal shot_taken(subject: Node3D, quality: float)
signal photos_completed

## Closer than this is full range quality.
const CLOSE_M: float = 8.0
## Farther than this the subject is too small to count; no shot is logged.
const MAX_RANGE_M: float = 40.0
## Light from the dark water alone.
const AMBIENT_LIGHT: float = 0.1
const EXT_LIGHT: float = 0.7
const FLASH_LIGHT: float = 1.0
## At or above this speed the shot is blurred to nothing.
const MAX_SPEED: float = 2.0
## Quality that counts as a usable photograph.
const GOOD_QUALITY: float = 0.5
## Half-angle of the frame, degrees: how far off-axis a subject may sit and still be in the shot.
const FRAME_HALF_ANGLE_DEG: float = 8.0
## Flash discharge: loud (~80 dB) for a moment.
const FLASH_INTENSITY: float = 0.01
const FLASH_NOISE_SEC: float = 1.5

@export var controller: SubController
## The sub's external light (EXT LTS); lit when it is visible in the tree. Unset means no external light.
@export var headlight: Light3D
@export var subjects: Array[Node3D] = []
## A CAMERA science module that arms the viewfinder (set by the module).
var module: ScienceModule

## Where the camera points (world direction).
var aim: Vector3 = Vector3.FORWARD
var flash_enabled: bool = false
## Subjects already photographed well.
var done: Array[Node3D] = []
var complete: bool = false
var last_quality: float = 0.0

var _flash_left: float = 0.0


func _ready() -> void:
	add_to_group(&"noise_sources")
	add_to_group(&"photo_objectives")


func camera_on() -> bool:
	return not complete and module != null and module.armed


func all_subjects() -> Array[Node3D]:
	var out: Array[Node3D] = subjects.duplicate()
	if is_inside_tree():
		for n: Node in get_tree().get_nodes_in_group(&"photo_subjects"):
			if n is Node3D and not out.has(n):
				out.append(n as Node3D)
	return out


func sub_position() -> Vector3:
	return controller.model.position if controller != null else Vector3.ZERO


func range_to(s: Node3D) -> float:
	return sub_position().distance_to(s.global_position if s.is_inside_tree() else s.position)


## 0..1, full inside CLOSE_M, none at MAX_RANGE_M.
func closeness(dist: float) -> float:
	return clampf(inverse_lerp(MAX_RANGE_M, CLOSE_M, dist), 0.0, 1.0)


func ext_light_on() -> bool:
	return headlight != null and headlight.is_visible_in_tree()


## Light on the subject, 0..1: the flash when it is going off, else the external lights, else the dark.
func light_level(with_flash: bool = false) -> float:
	if with_flash:
		return FLASH_LIGHT
	return EXT_LIGHT if ext_light_on() else AMBIENT_LIGHT


## 0..1, full at rest, none at MAX_SPEED.
func stillness() -> float:
	if controller == null:
		return 1.0
	return clampf(1.0 - absf(controller.speed) / MAX_SPEED, 0.0, 1.0)


func quality_at(dist: float, with_flash: bool = false) -> float:
	return closeness(dist) * light_level(with_flash) * stillness()


## True when [param s] is inside the frame around [member aim].
func in_frame(s: Node3D) -> bool:
	var to: Vector3 = (s.global_position if s.is_inside_tree() else s.position) - sub_position()
	if to.is_zero_approx() or aim.is_zero_approx():
		return false
	return rad_to_deg(aim.angle_to(to)) <= FRAME_HALF_ANGLE_DEG


## The nearest subject in the frame and in range, or null.
func target() -> Node3D:
	var best: Node3D = null
	var best_d: float = MAX_RANGE_M
	for s: Node3D in all_subjects():
		var d: float = range_to(s)
		if d <= best_d and in_frame(s):
			best = s
			best_d = d
	return best


## Live quality the shutter would give now (0 with nothing in frame), for the meters.
func live_quality() -> float:
	var t: Node3D = target()
	return quality_at(range_to(t), flash_enabled) if t != null else 0.0


func flash_active() -> bool:
	return _flash_left > 0.0


func noise_intensity() -> float:
	return FLASH_INTENSITY if flash_active() else 0.0


func noise_breakdown() -> Dictionary:
	return {"camera flash": noise_intensity()}


func readout(property: StringName) -> float:
	return float(done.size()) / float(maxi(all_subjects().size(), 1)) if property == &"progress" else 0.0


func reset() -> void:
	done.clear()
	complete = false
	last_quality = 0.0
	_flash_left = 0.0
	if module != null:
		module.armed = false


## The shutter. Returns the quality of the shot, or -1.0 when nothing was in range and frame (no reading is logged).
func take_shot() -> float:
	if not multiplayer.is_server() or not camera_on():
		return -1.0
	var t: Node3D = target()
	if t == null:
		return -1.0
	var q: float = quality_at(range_to(t), flash_enabled)
	if flash_enabled:
		_flash_left = FLASH_NOISE_SEC
	last_quality = q
	shot_taken.emit(t, q)
	var log: Node = get_tree().get_first_node_in_group(&"session_log")
	if log != null:
		log.call(&"write", "PHOTO %s  quality %.0f%%  range %.0f m%s" % [t.name, q * 100.0, range_to(t), "  flash" if flash_enabled else ""])
	if q >= GOOD_QUALITY and not done.has(t):
		done.append(t)
		if done.size() >= all_subjects().size():
			complete = true
			module.armed = false
			photos_completed.emit()
	return q


func _physics_process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left = maxf(_flash_left - delta, 0.0)
