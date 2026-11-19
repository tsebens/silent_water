class_name HoloMap
extends Node3D
## A 3D holographic chart projected above a table or pedestal: a scaled copy
## of the dive site's terrain with height contours, the sub, the objective,
## the crew's pins and sonar contacts ([MapModel]), and the hydrophone's
## listening cone. Everything is clipped to an elliptic cylinder standing on
## this node (local +Y up).
##
## Two layouts:
## - heading-up (pilot map): centred on the sub, map turns so the bow points
##   away from the pilot
## - table (map table): north fixed to the table at [member table_rotation_deg];
##   pans and zooms (see [MapTable]); the sub arrow shows the heading

const SONAR_CONE_RANGE_M: float = 300.0
const SONAR_CONE_HALF_ANGLE_DEG: float = 30.0
## Vertical squash of the listening cone (a horizontal fan).
const CONE_FLATTEN: float = 0.25

@export var game: Game
@export var heading_up: bool = true
## World metres per display metre (zoom). Bigger shows more.
@export var meters_per_unit: float = 240.0
@export var min_meters_per_unit: float = 80.0
@export var max_meters_per_unit: float = 1000.0
@export var clip_rx: float = 0.48
@export var clip_rz: float = 0.48
@export var height: float = 0.7
## Rotation of the chart on the table (degrees about +Y), table layout only.
@export var table_rotation_deg: float = 0.0
## Centre on the sub; otherwise centre on [member focus].
@export var follow_sub: bool = true
@export var color: Color = Color(0.3, 0.85, 0.95)
## Scale of markers (display metres).
@export var marker_size: float = 0.03

## World position at the centre of the display when not following the sub.
var focus: Vector3 = Vector3(0, -110, -200)

var _content: Node3D
var _markers: Node3D
var _pins_root: Node3D
var _materials: Array[ShaderMaterial] = []
var _terrain_built: bool = false
var _sub_arrow: MeshInstance3D
var _objective: MeshInstance3D
var _cone: MeshInstance3D
var _map_model: MapModel
var _shader: Shader = preload("res://src/map/holo.gdshader")


func _ready() -> void:
	if game == null:
		var n: Node = get_parent()
		while n != null and not (n is Game):
			n = n.get_parent()
		game = n as Game
	_content = Node3D.new()
	_content.name = "Content"
	add_child(_content)
	_markers = Node3D.new()
	_markers.name = "Markers"
	add_child(_markers)
	_pins_root = Node3D.new()
	_markers.add_child(_pins_root)
	_sub_arrow = _marker(_arrow_mesh(), Color(0.85, 1.0, 1.0), 0.5)
	_objective = _marker(_diamond_mesh(), Color(1.0, 0.85, 0.3), 0.45)
	_cone = _marker(null, Color(1.0, 0.85, 0.2), 0.05)
	_cone.visible = false


## World metres represented by one display metre, clamped to the zoom range.
func set_zoom(mpu: float) -> void:
	meters_per_unit = clampf(mpu, min_meters_per_unit, max_meters_per_unit)


## Display-local position (relative to this node) of a world point.
func to_display(world_p: Vector3) -> Vector3:
	return _content.transform * world_p


## World point at a display-local position.
func to_world(display_p: Vector3) -> Vector3:
	return _content.transform.affine_inverse() * display_p


## Rotation applied to world directions on this display (yaw only).
func display_basis() -> Basis:
	var b: Basis = Basis(Vector3.UP, deg_to_rad(table_rotation_deg))
	if heading_up and game != null:
		b = Basis(Vector3.UP, -_sub_yaw()) * b
	return b


func _process(_delta: float) -> void:
	if game == null:
		return
	if not _terrain_built:
		_build_terrain()
	if _map_model == null:
		_map_model = get_tree().get_first_node_in_group(&"map_model") as MapModel
		if _map_model != null:
			_map_model.changed.connect(_rebuild_pins)
			_rebuild_pins()
	var sub_pos: Vector3 = game.sub_frame.sub_transform.origin
	var center: Vector3 = sub_pos if follow_sub else focus
	var s: float = 1.0 / meters_per_unit
	var b: Basis = display_basis()
	_content.transform = Transform3D(b.scaled(Vector3.ONE * s), Vector3(0, height * 0.5, 0) - (b * center) * s)
	_update_clip()
	_update_markers(sub_pos)


func _update_markers(sub_pos: Vector3) -> void:
	_sub_arrow.position = to_display(sub_pos)
	_sub_arrow.basis = Basis(Vector3.UP, _sub_yaw() + deg_to_rad(table_rotation_deg) - (_sub_yaw() if heading_up else 0.0))
	var target: Node3D = game.get_node_or_null("World/ScanTarget") as Node3D
	if target != null:
		_objective.position = to_display(target.position) + Vector3(0, marker_size * 1.5, 0)
	for pin_node: Node in _pins_root.get_children():
		var n3: Node3D = pin_node as Node3D
		n3.position = to_display(n3.get_meta(&"world") as Vector3)
	_update_cone(sub_pos)


## The hydrophone's listening direction while someone is on sonar.
func _update_cone(sub_pos: Vector3) -> void:
	var sonar: SonarStation = get_tree().get_first_node_in_group(&"sonar") as SonarStation
	var manned: bool = sonar != null and sonar.headset != null and sonar.headset.state.holder != InteractableState.NO_HOLDER
	_cone.visible = manned
	if not manned:
		return
	var dir_world: Vector3 = SonarStation.bearing_to_world(game.sub_frame.sub_transform, sonar.bearing_deg())
	var dir: Vector3 = (display_basis() * dir_world).normalized()
	var length: float = SONAR_CONE_RANGE_M / meters_per_unit
	var mesh: CylinderMesh = _cone.mesh as CylinderMesh
	if mesh == null:
		mesh = CylinderMesh.new()
		mesh.top_radius = 0.0
		mesh.radial_segments = 16
		mesh.rings = 1
		_cone.mesh = mesh
	mesh.height = length
	mesh.bottom_radius = length * tan(deg_to_rad(SONAR_CONE_HALF_ANGLE_DEG))
	# Cylinder +Y is the apex end: point it back at the sub.
	var y: Vector3 = -dir
	var x: Vector3 = y.cross(Vector3.UP)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	var z: Vector3 = x.cross(y).normalized()
	# The hydrophone has no vertical resolution: show a flattened fan.
	_cone.transform = Transform3D(Basis(x, y, z * CONE_FLATTEN), to_display(sub_pos) + dir * length * 0.5)


func _update_clip() -> void:
	var g: Transform3D = global_transform
	for m: ShaderMaterial in _materials:
		m.set_shader_parameter(&"clip_center", g.origin)
		m.set_shader_parameter(&"clip_up", g.basis.y.normalized())
		m.set_shader_parameter(&"clip_axis_x", g.basis.x.normalized())
		m.set_shader_parameter(&"clip_rx", clip_rx * g.basis.x.length())
		m.set_shader_parameter(&"clip_rz", clip_rz * g.basis.z.length())
		m.set_shader_parameter(&"clip_height", height * g.basis.y.length())


## Copies the dive site's visible geometry, plus a faint water surface.
func _build_terrain() -> void:
	var site: Node3D = game.get_node_or_null("World/Site") as Node3D
	if site == null:
		return
	_terrain_built = true
	var mat: ShaderMaterial = _holo_material(color, 0.025, 0.03)
	# The site offers a lighter surface for maps; the rest is copied as-is.
	if site.has_method(&"map_meshes"):
		for pair: Array in site.call(&"map_meshes"):
			var mi: MeshInstance3D = MeshInstance3D.new()
			mi.mesh = pair[0] as Mesh
			mi.transform = site.transform * (pair[1] as Transform3D)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_content.add_child(mi)
	_copy_meshes(site, site.transform, mat)
	var water: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(800, 1200)
	water.mesh = plane
	water.position = Vector3(0, 0, -200)
	water.material_override = _holo_material(Color(0.3, 0.6, 1.0), 0.02, 0.0)
	_content.add_child(water)


func _copy_meshes(node: Node, xform: Transform3D, mat: ShaderMaterial) -> void:
	for child: Node in node.get_children():
		var n3: Node3D = child as Node3D
		if n3 == null or n3.name == &"Terrain":
			continue  # The full-detail surface; maps use map_meshes().
		var t: Transform3D = xform * n3.transform
		var mi: MeshInstance3D = n3 as MeshInstance3D
		if mi != null and mi.mesh != null:
			var copy: MeshInstance3D = MeshInstance3D.new()
			copy.mesh = mi.mesh
			copy.material_override = mat
			copy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			copy.transform = t
			_content.add_child(copy)
		_copy_meshes(n3, t, mat)


func _rebuild_pins() -> void:
	for c: Node in _pins_root.get_children():
		c.queue_free()
	if _map_model == null:
		return
	for p: Dictionary in _map_model.pins:
		var kind: int = int(p["kind"])
		var mesh: Mesh = _ring_mesh() if kind == MapModel.Kind.CONTACT else _pin_mesh()
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = mesh
		mi.scale = Vector3.ONE * marker_size / 0.03
		mi.material_override = _holo_material(MapModel.kind_color(kind), 0.55, 0.0)
		mi.set_meta(&"world", p["pos"] as Vector3)
		mi.set_meta(&"pin_id", int(p["id"]))
		_pins_root.add_child(mi)


## Pin marker ids and display positions, for picking on the map table.
func pin_markers() -> Array[Node3D]:
	var out: Array[Node3D] = []
	for c: Node in _pins_root.get_children():
		if not c.is_queued_for_deletion():
			out.append(c as Node3D)
	return out


func _marker(mesh: Mesh, c: Color, a: float) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * marker_size / 0.03
	mi.material_override = _holo_material(c, a, 0.0)
	_markers.add_child(mi)
	return mi


func _holo_material(c: Color, a: float, contour: float) -> ShaderMaterial:
	var m: ShaderMaterial = ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter(&"holo_color", c)
	m.set_shader_parameter(&"alpha", a)
	m.set_shader_parameter(&"contour_spacing", contour)
	_materials.append(m)
	return m


func _sub_yaw() -> float:
	var f: Vector3 = game.sub_frame.sub_transform.basis * Vector3.FORWARD
	return atan2(-f.x, -f.z)


static func _arrow_mesh() -> Mesh:
	var m: PrismMesh = PrismMesh.new()
	m.size = Vector3(0.03, 0.06, 0.012)
	# Lay the prism flat so its point is the bow (-Z).
	var st: SurfaceTool = SurfaceTool.new()
	st.append_from(m, 0, Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3.ZERO))
	return st.commit()


static func _diamond_mesh() -> Mesh:
	var m: SphereMesh = SphereMesh.new()
	m.radius = 0.018
	m.height = 0.05
	m.radial_segments = 4
	m.rings = 2
	return m


static func _pin_mesh() -> Mesh:
	var st: SurfaceTool = SurfaceTool.new()
	var stick: CylinderMesh = CylinderMesh.new()
	stick.top_radius = 0.002
	stick.bottom_radius = 0.002
	stick.height = 0.05
	st.append_from(stick, 0, Transform3D(Basis(), Vector3(0, 0.025, 0)))
	var head: SphereMesh = SphereMesh.new()
	head.radius = 0.008
	head.height = 0.016
	st.append_from(head, 0, Transform3D(Basis(), Vector3(0, 0.055, 0)))
	return st.commit()


static func _ring_mesh() -> Mesh:
	var t: TorusMesh = TorusMesh.new()
	t.inner_radius = 0.016
	t.outer_radius = 0.02
	return t
