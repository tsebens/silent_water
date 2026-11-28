extends Node3D
## Look-review preview for the herring rig (#930): one herring swimming in
## place with a throwaway travelling wave on its spine, so the skin deformation
## can be judged in motion. This is NOT the swim behaviour (that is #931/#932);
## it sets bone poses directly and exists only to review the rig.
##
## Keys: 1/2/3 speed (idle, cruise, flee); Left/Right hold to turn;
## Tab cycles the camera (top, side, three-quarter, front); Space pauses;
## S toggles slow motion; B toggles the bone overlay; R resets to rest.

const HERRING: PackedScene = preload("res://assets/models/organics/herring/herring.tscn")
const SPINE: Array[StringName] = [&"spine1", &"spine2", &"spine3", &"spine4", &"tail"]
## Peak yaw per spine bone (degrees) at full speed; grows toward the tail.
const AMPLITUDE_DEG: Array[float] = [4.0, 8.0, 12.0, 16.0, 24.0]
## Phase lag per bone along the body (radians): the wave travels nose to tail.
const PHASE_STEP: float = 0.9
const TURN_BEND_DEG: float = 12.0
const SPEEDS: Array[float] = [0.0, 0.45, 1.0]
const SPEED_NAMES: Array[String] = ["idle", "cruise", "flee"]
const CAMERAS: Array[String] = ["top", "side", "three-quarter", "front"]

var speed: float = 0.45
var turn: float = 0.0
var paused: bool = false
var slow: bool = false
var phase: float = 0.0

var _fish: Node3D
var _skeleton: Skeleton3D
var _camera: Camera3D
var _label: Label
var _bones: Array[int] = []
var _fins: Dictionary[StringName, int] = {}
var _camera_index: int = 0
var _speed_index: int = 1
var _show_bones: bool = false
var _bone_overlay: MeshInstance3D


func _ready() -> void:
	_build_environment()
	_fish = HERRING.instantiate() as Node3D
	add_child(_fish)
	_skeleton = _fish.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for b: StringName in SPINE:
		var i: int = _skeleton.find_bone(b)
		assert(i >= 0, "herring has no bone %s" % b)
		_bones.append(i)
	for f: StringName in [&"pectoral_l", &"pectoral_r", &"dorsal", &"pelvic_l", &"pelvic_r"]:
		_fins[f] = _skeleton.find_bone(f)
	_camera = Camera3D.new()
	_camera.near = 0.01
	_camera.fov = 40.0
	add_child(_camera)
	_camera.current = true
	_set_camera(0)
	_build_ui()
	_build_bone_overlay()


func _build_environment() -> void:
	var p: Palette = Palette.main()
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = p.color(&"env_deep")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = p.color(&"env_teal")
	env.ambient_light_energy = 0.6
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.light_color = p.color(&"light_work_white")
	sun.rotation_degrees = Vector3(-55.0, 30.0, 0.0)
	add_child(sun)
	# a faint grid of rods under the fish, so the bend reads against something straight
	var rod_mat: StandardMaterial3D = StandardMaterial3D.new()
	rod_mat.albedo_color = p.color(&"infra_metal")
	for k: int in range(-3, 4):
		var rod: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.002, 0.002, 0.4)
		box.material = rod_mat
		rod.mesh = box
		rod.position = Vector3(k * 0.03, -0.05, 0.0)
		add_child(rod)


func _build_ui() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(12.0, 8.0)
	_label.add_theme_color_override(&"font_color", Palette.main().color(&"light_readout"))
	layer.add_child(_label)


func _build_bone_overlay() -> void:
	_bone_overlay = MeshInstance3D.new()
	_bone_overlay.mesh = ImmediateMesh.new()
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = true
	m.albedo_color = Palette.main().color(&"light_marker")
	_bone_overlay.material_override = m
	_bone_overlay.visible = false
	add_child(_bone_overlay)


func _set_camera(i: int) -> void:
	_camera_index = i % CAMERAS.size()
	match CAMERAS[_camera_index]:
		"top":
			_camera.position = Vector3(0.0, 0.38, 0.0)
			_camera.look_at(Vector3.ZERO, Vector3.BACK)
		"side":
			_camera.position = Vector3(0.4, 0.0, 0.0)
			_camera.look_at(Vector3.ZERO, Vector3.UP)
		"three-quarter":
			_camera.position = Vector3(0.25, 0.2, -0.2)
			_camera.look_at(Vector3.ZERO, Vector3.UP)
		"front":
			_camera.position = Vector3(0.0, 0.05, 0.5)
			_camera.look_at(Vector3.ZERO, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	var key: InputEventKey = event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1, KEY_2, KEY_3:
			_speed_index = key.physical_keycode - KEY_1
		KEY_TAB:
			_set_camera(_camera_index + 1)
		KEY_SPACE:
			paused = not paused
		KEY_S:
			slow = not slow
		KEY_B:
			_show_bones = not _show_bones
			_bone_overlay.visible = _show_bones
		KEY_R:
			_skeleton.reset_bone_poses()
			phase = 0.0
			paused = true


func _process(delta: float) -> void:
	var target_turn: float = float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT))
	turn = move_toward(turn, target_turn, delta * 2.0)
	speed = move_toward(speed, SPEEDS[_speed_index], delta)
	if not paused:
		advance(delta * (0.25 if slow else 1.0))
	if _show_bones:
		_draw_bones()
	_label.text = "Herring rig preview (#930)   speed: %s %.2f   turn: %+.2f   camera: %s%s%s\n" % [
		SPEED_NAMES[_speed_index], speed, turn, CAMERAS[_camera_index],
		"   PAUSED" if paused else "", "   SLOW x0.25" if slow else ""]
	_label.text += "1/2/3 speed   Left/Right turn   Tab camera   Space pause   S slow-mo   B bones   R rest"


## Advances the wave by [param dt] seconds and poses the bones.
func advance(dt: float) -> void:
	var frequency_hz: float = lerpf(0.6, 3.0, speed)
	phase = fmod(phase + TAU * frequency_hz * dt, TAU * 1000.0)
	pose_at(phase, speed, turn)


## Poses the spine and fins for a wave [param at_phase], [param at_speed] (0..1)
## and [param at_turn] (-1..1).
func pose_at(at_phase: float, at_speed: float, at_turn: float) -> void:
	var gain: float = lerpf(0.25, 1.0, at_speed)
	for k: int in range(_bones.size()):
		var yaw: float = deg_to_rad(AMPLITUDE_DEG[k]) * gain * sin(at_phase - PHASE_STEP * k)
		yaw += deg_to_rad(TURN_BEND_DEG) * at_turn * float(k + 1) / float(_bones.size())
		_rotate(_bones[k], Vector3.UP, yaw)
	var flap: float = deg_to_rad(10.0 + 15.0 * absf(at_turn)) * sin(at_phase * 0.5)
	if _fins.get(&"pectoral_l", -1) >= 0:
		_rotate(_fins[&"pectoral_l"], Vector3.FORWARD, flap)
	if _fins.get(&"pectoral_r", -1) >= 0:
		_rotate(_fins[&"pectoral_r"], Vector3.FORWARD, -flap)


func _rotate(bone: int, axis: Vector3, angle: float) -> void:
	var rest: Quaternion = _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	_skeleton.set_bone_pose_rotation(bone, rest * Quaternion(axis, angle))


func _draw_bones() -> void:
	var im: ImmediateMesh = _bone_overlay.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var to_world: Transform3D = _skeleton.global_transform
	for i: int in range(_skeleton.get_bone_count()):
		var parent: int = _skeleton.get_bone_parent(i)
		if parent < 0:
			continue
		im.surface_add_vertex(to_world * _skeleton.get_bone_global_pose(parent).origin)
		im.surface_add_vertex(to_world * _skeleton.get_bone_global_pose(i).origin)
	im.surface_end()

