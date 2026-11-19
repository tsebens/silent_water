class_name Leak
extends Interactable
## One point in the hull that can spring a leak. While open it sprays, hisses
## (found by ear) and lets water into the bilge. Patching is a short mini-game:
## grab the leak and hold the patch steady for [constant PATCH_TIME] seconds.
## The steadier the hold, the better the patch and the longer it lasts.
##
## The value of this Interactable is patch progress (0..1), so other crew can
## see someone working on it. Open/closed state comes from [LeakSystem].

signal patch_completed(leak: Leak, quality: float)

const PATCH_TIME: float = 2.0
## Mouse movement (px/s) during patching that gives a zero-quality patch.
const JITTER_LIMIT: float = 600.0

@export var spray: CPUParticles3D
@export var grab_shape: CollisionShape3D

var is_open: bool = false

var _jitter_px: float = 0.0
var _held_time: float = 0.0
var _hiss: AudioStreamPlayer3D


func _init() -> void:
	super._init()
	min_value = 0.0
	max_value = 1.0


func _ready() -> void:
	super._ready()
	_hiss = AudioStreamPlayer3D.new()
	_hiss.stream = ProceduralSounds.hiss()
	_hiss.unit_size = SubAudio.UNIT_SIZE
	_hiss.pitch_scale = 1.4
	add_child(_hiss)
	set_open(false)


func set_open(open: bool) -> void:
	is_open = open
	if spray != null:
		spray.emitting = open
	if grab_shape != null:
		grab_shape.disabled = not open
	if open:
		_hiss.volume_db = SubAudio.volume_for(LeakSystem.LEAK_INTENSITY)
		_hiss.play(randf())
	else:
		_hiss.stop()
		if is_held_locally():
			end_interaction()


func begin_interaction() -> void:
	if not is_open:
		return
	_jitter_px = 0.0
	_held_time = 0.0
	super.begin_interaction()


## Mouse movement while patching shakes the patch rather than moving a value.
func drag(relative: Vector2) -> void:
	if is_held_locally():
		_jitter_px += relative.length()


func end_interaction() -> void:
	if is_held_locally() and get_value() < 1.0:
		drive_to(0.0)  # Let go early: the patch falls away.
	super.end_interaction()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not is_held_locally() or not is_open:
		return
	_held_time += delta
	drive_to(minf(_held_time / PATCH_TIME, 1.0))
	if _held_time >= PATCH_TIME:
		var quality: float = clampf(1.0 - (_jitter_px / _held_time) / JITTER_LIMIT, 0.0, 1.0)
		end_interaction()
		patch_completed.emit(self, quality)


## Holding a patch in place is quiet; the leak itself is counted by LeakSystem.
func noise_intensity() -> float:
	return 0.0
