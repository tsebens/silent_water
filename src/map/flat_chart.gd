class_name FlatChart
extends MeshInstance3D
## The sonar bearing chart as a flat screen: a 2D, top-down, heading-up
## rendering (sub at the centre, bow up, starboard right) drawn by a
## [SubViewport] and shown as the texture of a quad. The quad faces local -Z,
## so mount it on a panel facing the viewer. Reads the shared [MapModel]
## (pins, fading sonar marks) and the manned hydrophone's bearing; it owns no
## chart data. The 3D [HoloMap] is unchanged and still serves the pilot and
## the map table.

## Screen quad edge length (m).
@export var screen_size: float = 0.4
## Render target edge length (px).
@export var resolution: int = 512
## World metres from the centre to the edge of the chart.
@export var range_m: float = 320.0
@export var game: Game

var viewport: SubViewport
var canvas: FlatChartCanvas


func _ready() -> void:
	if game == null:
		var n: Node = get_parent()
		while n != null and not (n is Game):
			n = n.get_parent()
		game = n as Game
	viewport = SubViewport.new()
	viewport.name = "Viewport"
	viewport.size = Vector2i(resolution, resolution)
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	canvas = FlatChartCanvas.new()
	canvas.name = "Canvas"
	canvas.chart = self
	canvas.size = Vector2(resolution, resolution)
	viewport.add_child(canvas)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(screen_size, screen_size)
	mesh = quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	material_override = mat
	# Quads face +Z; this one faces the seat.
	rotation.y = PI


## Pixels per world metre.
func pixels_per_m() -> float:
	return float(resolution) * 0.5 * 0.92 / range_m


## Screen position (px) of a world point: sub at the centre, bow up.
func to_display(world_p: Vector3) -> Vector2:
	if game == null:
		return Vector2.ZERO
	var t: Transform3D = game.sub_frame.sub_transform
	var rel: Vector3 = t.basis.inverse() * (world_p - t.origin)
	return Vector2(resolution, resolution) * 0.5 + Vector2(rel.x, rel.z) * pixels_per_m()


## Screen direction (unit) of a world direction.
func dir_to_display(world_dir: Vector3) -> Vector2:
	var rel: Vector3 = game.sub_frame.sub_transform.basis.inverse() * world_dir
	return Vector2(rel.x, rel.z).normalized()


func _process(_delta: float) -> void:
	if canvas != null:
		canvas.queue_redraw()


class FlatChartCanvas:
	extends Control

	var chart: FlatChart
	var _map_model: MapModel

	func _draw() -> void:
		if chart == null or chart.game == null:
			return
		var pal: Palette = Palette.main()
		var c: Color = pal.color(&"light_readout")
		var mid: Vector2 = Vector2(chart.resolution, chart.resolution) * 0.5
		var r: float = float(chart.resolution) * 0.5 * 0.96
		draw_circle(mid, r, pal.color(&"info_black"))
		var ppm: float = chart.pixels_per_m()
		for ring: int in range(1, 4):
			draw_arc(mid, chart.range_m * ppm * float(ring) / 3.0, 0.0, TAU, 64, _alpha(c, 0.28), 2.0)
		draw_arc(mid, r, 0.0, TAU, 96, _alpha(c, 0.8), 4.0)
		draw_line(mid + Vector2(0, -r), mid + Vector2(0, r), _alpha(c, 0.18), 1.5)
		draw_line(mid + Vector2(-r, 0), mid + Vector2(r, 0), _alpha(c, 0.18), 1.5)
		if _map_model == null:
			_map_model = chart.get_tree().get_first_node_in_group(&"map_model") as MapModel
		_draw_cone(c)
		if _map_model != null:
			_draw_marks()
			_draw_pins()
		var target: Node3D = chart.game.get_node_or_null("World/ScanTarget") as Node3D
		if target != null:
			_diamond(chart.to_display(target.position), 9.0, pal.color(&"light_marker"), mid, r)
		# The sub: an arrow, bow up.
		draw_colored_polygon(
			PackedVector2Array([mid + Vector2(0, -16), mid + Vector2(10, 12), mid + Vector2(0, 6), mid + Vector2(-10, 12)]),
			c.lightened(0.5)
		)

	## [param c] with alpha [param a].
	static func _alpha(c: Color, a: float) -> Color:
		var o: Color = c
		o.a = a
		return o

	func _inside(p: Vector2, mid: Vector2, r: float) -> bool:
		return p.distance_to(mid) <= r

	func _diamond(p: Vector2, s: float, col: Color, mid: Vector2, r: float) -> void:
		if not _inside(p, mid, r):
			return
		draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), col)

	func _draw_cone(readout: Color) -> void:
		var sonar: SonarStation = chart.get_tree().get_first_node_in_group(&"sonar") as SonarStation
		if sonar == null or sonar.headset == null or sonar.headset.state.holder == InteractableState.NO_HOLDER:
			return
		var mid: Vector2 = Vector2(chart.resolution, chart.resolution) * 0.5
		var dir_world: Vector3 = SonarStation.bearing_to_world(chart.game.sub_frame.sub_transform, sonar.bearing_deg())
		var centre_angle: float = chart.dir_to_display(dir_world).angle()
		var half: float = deg_to_rad(HoloMap.SONAR_CONE_HALF_ANGLE_DEG)
		var len_px: float = HoloMap.SONAR_CONE_RANGE_M * chart.pixels_per_m()
		var pts: PackedVector2Array = PackedVector2Array([mid])
		for i: int in range(13):
			var a: float = centre_angle - half + 2.0 * half * float(i) / 12.0
			pts.append(mid + Vector2.from_angle(a) * len_px)
		draw_colored_polygon(pts, _alpha(readout, 0.35))
		draw_polyline(PackedVector2Array([pts[1], mid, pts[pts.size() - 1]]), _alpha(readout, 0.9), 2.5)

	func _draw_marks() -> void:
		var mid: Vector2 = Vector2(chart.resolution, chart.resolution) * 0.5
		var r: float = float(chart.resolution) * 0.5 * 0.96
		var now: int = Time.get_ticks_msec()
		for m: Dictionary in _map_model.marks:
			var k: float = MapModel.mark_intensity(MapModel.mark_age_s(m, now), _map_model.mark_fade_s)
			if k <= 0.0:
				continue
			var p: Vector2 = chart.to_display(m["pos"] as Vector3)
			if _inside(p, mid, r):
				var col: Color = MapModel.kind_color(MapModel.Kind.CONTACT)
				draw_circle(p, lerpf(5.0, 14.0, k), _alpha(col, 0.85 * k))

	func _draw_pins() -> void:
		var mid: Vector2 = Vector2(chart.resolution, chart.resolution) * 0.5
		var r: float = float(chart.resolution) * 0.5 * 0.96
		for pin: Dictionary in _map_model.pins:
			var p: Vector2 = chart.to_display(pin["pos"] as Vector3)
			if not _inside(p, mid, r):
				continue
			var col: Color = MapModel.kind_color(int(pin["kind"]))
			var kind: int = int(pin["kind"])
			if kind == MapModel.Kind.CONTACT:
				draw_arc(p, 9.0, 0.0, TAU, 20, col, 3.0)
			elif kind == MapModel.Kind.DANGER or kind == MapModel.Kind.APEX:
				# Threats are triangles, so they differ from markers by shape as well as colour.
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -10), p + Vector2(9, 7), p + Vector2(-9, 7)]), col)
			else:
				_diamond(p, 8.0, col, mid, r)
