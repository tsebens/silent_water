class_name ConstraintOverlay
extends MeshInstance3D
## Wireframes for a [SiteSpec]'s constraints, drawn over the terrain in the lab:
## a [FlatPad] as a ring (with its falloff ring and a post at its height), a
## [Corridor] as its two edges and centre ramp, a [ClearColumn] as a tall
## cylinder outline. Lines only; unshaded and drawn on top.

const SEGMENTS: int = 48
const PAD_COLOR: Color = Color(1.0, 0.8, 0.2)
const CORRIDOR_COLOR: Color = Color(0.3, 0.9, 1.0)
const COLUMN_COLOR: Color = Color(1.0, 0.4, 0.8)
const FALLOFF_ALPHA: float = 0.35
const COLUMN_HEIGHT: float = 220.0

## Number of line segments in the last [method rebuild], for tests.
var line_count: int = 0


func _init() -> void:
	name = "ConstraintOverlay"
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = true
	m.render_priority = 10
	material_override = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func rebuild(spec: SiteSpec) -> void:
	var im: ImmediateMesh = ImmediateMesh.new()
	line_count = 0
	if spec != null and not spec.constraints.is_empty():
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		for c: SiteConstraint in spec.constraints:
			if c == null:
				continue
			if c is FlatPad:
				var p: FlatPad = c
				_ring(im, p.centre, p.radius, p.height, PAD_COLOR)
				_ring(im, p.centre, p.radius + p.falloff, p.height, _faint(PAD_COLOR))
				_line(im, Vector3(p.centre.x, p.height, p.centre.y), Vector3(p.centre.x, p.height + 30.0, p.centre.y), PAD_COLOR)
			elif c is Corridor:
				_corridor(im, c)
			elif c is ClearColumn:
				var cc: ClearColumn = c
				_ring(im, cc.centre, cc.radius, 0.0, COLUMN_COLOR)
				_ring(im, cc.centre, cc.radius, COLUMN_HEIGHT * -1.0, COLUMN_COLOR)
				for k: int in range(4):
					var a: float = k * TAU / 4.0
					var xz: Vector2 = cc.centre + Vector2(cos(a), sin(a)) * cc.radius
					_line(im, Vector3(xz.x, 0.0, xz.y), Vector3(xz.x, -COLUMN_HEIGHT, xz.y), COLUMN_COLOR)
		im.surface_end()
	mesh = im if line_count > 0 else null


func _faint(c: Color) -> Color:
	return Color(c.r, c.g, c.b, FALLOFF_ALPHA)


func _line(im: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	im.surface_set_color(color)
	im.surface_add_vertex(from)
	im.surface_set_color(color)
	im.surface_add_vertex(to)
	line_count += 1


func _ring(im: ImmediateMesh, centre: Vector2, radius: float, y: float, color: Color) -> void:
	for i: int in range(SEGMENTS):
		var a0: float = i * TAU / SEGMENTS
		var a1: float = (i + 1) * TAU / SEGMENTS
		_line(im,
			Vector3(centre.x + cos(a0) * radius, y, centre.y + sin(a0) * radius),
			Vector3(centre.x + cos(a1) * radius, y, centre.y + sin(a1) * radius), color)


func _corridor(im: ImmediateMesh, c: Corridor) -> void:
	var dir: Vector2 = Vector2(c.b.x - c.a.x, c.b.z - c.a.z)
	var side: Vector2 = Vector2(-dir.y, dir.x).normalized() * c.width * 0.5 if dir.length() > 0.0001 else Vector2(c.width * 0.5, 0.0)
	var a: Vector3 = c.a
	var b: Vector3 = c.b
	_line(im, a, b, CORRIDOR_COLOR)
	var al: Vector3 = a + Vector3(side.x, 0.0, side.y)
	var ar: Vector3 = a - Vector3(side.x, 0.0, side.y)
	var bl: Vector3 = b + Vector3(side.x, 0.0, side.y)
	var br: Vector3 = b - Vector3(side.x, 0.0, side.y)
	_line(im, al, bl, CORRIDOR_COLOR)
	_line(im, ar, br, CORRIDOR_COLOR)
	_line(im, al, ar, CORRIDOR_COLOR)
	_line(im, bl, br, CORRIDOR_COLOR)
