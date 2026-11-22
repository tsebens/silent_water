@tool
class_name AssetModelPreview
extends SubViewportContainer
## One 3D preview of a mesh in a SubViewport, lit like the game: the game's dark ambient and
## fog (values copied from src/game/game.tscn) and the marine snow shader, with a white or
## red light chosen by AssetModelModel. Turntable angle, wireframe and light come from the
## shared model, so several previews stay in step.

const SNOW_SHADER: Shader = preload("res://src/world/marine_snow.gdshader")
const FLAKES: int = 1200
const BOX: float = 10.0

var state: AssetModelModel
var caption: String = ""

var _viewport: SubViewport
var _pivot: Node3D
var _light: OmniLight3D
var _camera: Camera3D
var _radius: float = 1.0
var _label: Label
var _model_root: Node3D


func _init() -> void:
	stretch = true
	custom_minimum_size = Vector2(300, 260)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(300, 260)
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	add_child(_viewport)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.015, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.1, 0.16, 0.2)
	env.ambient_light_energy = 0.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.01, 0.04, 0.05)
	env.fog_density = 0.035
	env.fog_sky_affect = 0.0
	var we: WorldEnvironment = WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	_pivot = Node3D.new()
	_viewport.add_child(_pivot)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_light = OmniLight3D.new()
	_light.light_energy = 6.0
	_viewport.add_child(_light)
	_viewport.add_child(_snow())
	_label = Label.new()
	_label.position = Vector2(6, 4)
	add_child(_label)
	set_process(true)


func _process(_delta: float) -> void:
	apply_state()


## Shows `node` (an instantiated GLB or any Node3D) and frames the camera on it.
func show_node(node: Node3D, text: String = "") -> void:
	if _model_root != null:
		_model_root.queue_free()
		_model_root = null
	caption = text
	_label.text = text
	if node == null:
		return
	_model_root = node
	_pivot.add_child(node)
	var box: AABB = _bounds(node)
	node.position -= box.get_center()
	_radius = maxf(box.size.length() * 0.5, 0.01)
	_camera.position = Vector3(0.6, 0.35, 1.0).normalized() * _radius * 2.6
	_camera.look_at(Vector3.ZERO)
	_camera.far = maxf(_radius * 40.0, 50.0)
	_light.omni_range = _radius * 12.0
	_light.position = _camera.position + Vector3(0.0, _radius * 0.5, 0.0)
	apply_state()


func has_model() -> bool:
	return _model_root != null


## Pushes the shared model state (light colour, wireframe, turntable angle) into the viewport.
func apply_state() -> void:
	if state == null:
		return
	_light.light_color = state.light_color()
	_viewport.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME if state.wireframe else Viewport.DEBUG_DRAW_DISABLED
	_pivot.rotation_degrees.y = state.angle_deg


## Loads a GLB or glTF from an absolute path (raw provider meshes live outside res://).
static func load_glb(path: String) -> Node3D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var doc: GLTFDocument = GLTFDocument.new()
	var gstate: GLTFState = GLTFState.new()
	if doc.append_from_file(path, gstate) != OK:
		return null
	return doc.generate_scene(gstate) as Node3D


static func _bounds(node: Node3D) -> AABB:
	var found: Array[AABB] = []
	_collect(node, Transform3D.IDENTITY, found)
	if found.is_empty():
		return AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
	var box: AABB = found[0]
	for b: AABB in found:
		box = box.merge(b)
	return box


static func _collect(node: Node3D, parent_xf: Transform3D, out: Array[AABB]) -> void:
	var xf: Transform3D = parent_xf * node.transform
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null and mi.mesh != null:
		out.append(xf * mi.mesh.get_aabb())
	for c: Node in node.get_children():
		var c3: Node3D = c as Node3D
		if c3 != null:
			_collect(c3, xf, out)


## Marine snow: the game's shader on a small cube of flakes, with the hull clip and the
## surface cut-off turned off (there is no sub or water surface here).
static func _snow() -> MeshInstance3D:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	var verts: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var corners: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	for i: int in FLAKES:
		var p: Vector3 = Vector3(rng.randf(), rng.randf(), rng.randf()) * BOX
		var start: int = verts.size()
		for c: Vector2 in corners:
			verts.append(p)
			uvs.append(c)
		indices.append_array([start, start + 1, start + 2, start, start + 2, start + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SNOW_SHADER
	mat.set_shader_parameter(&"box_size", BOX)
	mat.set_shader_parameter(&"surface_y", 1000.0)
	mat.set_shader_parameter(&"hull_half_extents", Vector3.ZERO)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3.ONE * -BOX, Vector3.ONE * BOX * 2.0)
	return mi
