class_name DepthFinder
extends MeshInstance3D
## A small digital echo sounder: a 2D side-on trace of the sea floor under and ahead of the sub.
## Each update samples the terrain height (`height_at(x, z)` of the node in [member site_group], normally
## [CanyonSite]) at evenly spaced points along the sub's horizontal heading, from [member range_behind] behind
## it to [member range_ahead] ahead, and draws them into a texture on a quad. The vertical window is
## [member depth_span] metres centred on the sub's depth, so the sub marker sits at mid-height and the floor
## rises or falls past it as the sub climbs or dives. Computed locally on every peer; nothing is replicated.
##
## The quad faces local +Z. Colours are palette swatches.

@export var site_group: StringName = &"terrain_site"
@export var frame_group: StringName = &"sub_frame"
## Metres of sea floor drawn ahead of and behind the sub, along its heading.
@export var range_ahead: float = 120.0
@export var range_behind: float = 30.0
## Vertical metres across the whole trace, centred on the sub's depth.
@export var depth_span: float = 80.0
## Samples along the trace (at least 2).
@export var columns: int = 64
@export var resolution: Vector2i = Vector2i(256, 128)
## Size of the named screen quad (m).
@export var screen_size: Vector2 = Vector2(0.24, 0.12)
@export var trace_swatch: StringName = &"light_readout"
@export var face_swatch: StringName = &"info_black"

## Floor height at each column relative to the sub's depth (m, positive above the sub).
var heights: PackedFloat32Array = PackedFloat32Array()
## Image drawn each update, and the texture shown.
var image: Image
var texture: ImageTexture
## Overrides the site lookup when set: `(x: float, z: float) -> float`.
var height_source: Callable = Callable()

var _quad: QuadMesh
var _sub_frame: SubFrame
var _site: Node
## Last non-degenerate horizontal heading, kept when the sub points straight up or down.
var _heading: Vector3 = Vector3(0, 0, -1)


func _ready() -> void:
	image = Image.create(resolution.x, resolution.y, false, Image.FORMAT_RGBA8)
	texture = ImageTexture.create_from_image(image)
	_quad = QuadMesh.new()
	_quad.size = screen_size
	mesh = _quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = texture
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	draw()


func _process(_delta: float) -> void:
	if _sub_frame == null or not is_instance_valid(_sub_frame):
		_sub_frame = get_tree().get_first_node_in_group(frame_group) as SubFrame
	if _sub_frame == null:
		return
	if not height_source.is_valid():
		if _site == null or not is_instance_valid(_site):
			_site = get_tree().get_first_node_in_group(site_group)
		if _site == null:
			return
	update_from_pose(_sub_frame.render_transform())


## Sample the floor for the sub pose [param pose] (world space) and redraw.
func update_from_pose(pose: Transform3D) -> void:
	var source: Callable = height_source
	if not source.is_valid():
		if _site == null:
			return
		source = Callable(_site, &"height_at")
	sample(pose, source)
	if image != null:
		draw()


## Horizontal unit heading of [param pose]; the previous one when the sub points straight up or down.
func heading_of(pose: Transform3D) -> Vector3:
	var fwd: Vector3 = -pose.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 1e-6:
		_heading = fwd.normalized()
	return _heading


## Fill [member heights] from [param source] for [param pose].
func sample(pose: Transform3D, source: Callable) -> void:
	var n: int = maxi(columns, 2)
	var dir: Vector3 = heading_of(pose)
	heights.resize(n)
	for i: int in range(n):
		var d: float = column_distance(i)
		var p: Vector3 = pose.origin + dir * d
		heights[i] = float(source.call(p.x, p.z)) - pose.origin.y


## Distance along the heading of column [param i] (negative behind the sub).
func column_distance(i: int) -> float:
	var n: int = maxi(columns, 2)
	return lerpf(-range_behind, range_ahead, float(i) / float(n - 1))


## Pixel x of the sub marker.
func marker_x() -> float:
	var span: float = range_ahead + range_behind
	return range_behind / span * float(resolution.x - 1) if span > 0.0 else 0.0


## Pixel row of the sub marker: mid-height.
func marker_y() -> float:
	return float(resolution.y - 1) * 0.5


## Pixel row for a height [param rel] metres above the sub, clamped into the image.
func row_for(rel: float) -> int:
	var f: float = 0.5 - rel / depth_span
	return clampi(roundi(f * float(resolution.y - 1)), 0, resolution.y - 1)


## Pixel x of column [param i].
func pixel_x(i: int) -> int:
	return roundi(float(i) / float(maxi(columns, 2) - 1) * float(resolution.x - 1))


## Redraw [member image] from [member heights] and upload it.
func draw() -> void:
	var pal: Palette = Palette.main()
	var face: Color = pal.color(face_swatch)
	var trace: Color = pal.color(trace_swatch)
	var fill: Color = Color(trace.r, trace.g, trace.b, 0.25)
	image.fill(face)
	var n: int = heights.size()
	var w: int = resolution.x
	var prev_row: int = -1
	for x: int in range(w):
		if n < 2:
			break
		var t: float = float(x) / float(w - 1) * float(n - 1)
		var i: int = mini(int(t), n - 2)
		var rel: float = lerpf(heights[i], heights[i + 1], t - float(i))
		var row: int = row_for(rel)
		for y: int in range(row + 1, resolution.y):
			image.set_pixel(x, y, face.blend(fill))
		# Join steep steps so the line stays unbroken.
		var from_row: int = row if prev_row < 0 else prev_row
		for y: int in range(mini(from_row, row), maxi(from_row, row) + 1):
			image.set_pixel(x, y, trace)
		prev_row = row
	# Sub marker: a short horizontal tick and a vertical tick at mid-height.
	var mx: int = roundi(marker_x())
	var my: int = roundi(marker_y())
	for d: int in range(-3, 4):
		image.set_pixel(clampi(mx + d, 0, w - 1), my, trace)
		image.set_pixel(mx, clampi(my + d, 0, resolution.y - 1), trace)
	texture.update(image)
