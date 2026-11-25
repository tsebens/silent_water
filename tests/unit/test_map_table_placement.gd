extends TestCase
## The generated map table station is placed from the program (SubLayout) in the port bay, and its console drives
## the chart: trackball pans, lever zooms, toggle follows the sub, the lamp matches; Q and R rotate it.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var table: MapTable


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	table = game.get_node("Interior/Stations/Maps/MapTable") as MapTable
	(game.get_node("World/Apex") as ApexMonster).set_active(false)
	(game.get_node("SubController") as SubController).enabled = false


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().process_frame


## Footprint of the station's collision on the floor plan (x across the hull, y along it).
func _footprint() -> Rect2:
	var body: Node3D = table.get_node("Station/Collision") as Node3D
	var out: Rect2 = Rect2()
	var first: bool = true
	for child: Node in body.get_children():
		var cs: CollisionShape3D = child as CollisionShape3D
		var box: BoxShape3D = cs.shape as BoxShape3D
		var b: AABB = cs.global_transform * AABB(-box.size * 0.5, box.size)
		var r: Rect2 = Rect2(b.position.x, b.position.z, b.size.x, b.size.z)
		out = r if first else out.merge(r)
		first = false
	return out


func _key(code: Key, pressed: bool) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	return e


func test_station_is_at_the_program_position() -> void:
	var top: Rect2 = SubLayout.top_footprint(&"map_table")
	expect_near(table.position.y, 0.0, 0.001, "on the floor")
	expect_near(table.position.z, (top.position.y + top.end.y) / 2.0, 0.001, "centred along the bay")
	expect_near(table.position.x, top.position.x, 0.001, "back at the hull end of the bay")
	# The operator's side faces the aisle: station +Z is the interior's +X.
	expect((table.global_basis * Vector3.BACK).dot(Vector3.RIGHT) > 0.99, "operator side faces the aisle")
	var fp: Rect2 = _footprint()
	expect(fp.position.y >= top.position.y - 0.001 and fp.end.y <= top.end.y + 0.001, "table inside the bay along the hull")
	expect(fp.position.x >= top.position.x - 0.001, "table not past the hull")
	expect(table.get_node_or_null("StandPoint") == null, "the old slab's stand point is gone")
	expect(table.sit_point == table.get_node("Station/OperatorPoint"), "the operator stands at the station's point")


func test_station_keeps_the_aisle_clear() -> void:
	var fp: Rect2 = _footprint()
	var aisle: float = SubLayout.clearance("aisle_min_m")
	for id: StringName in SubLayout.ids():
		if id == &"map_table" or not SubLayout.record(id).has("floor_box"):
			continue
		var other: Rect2 = SubLayout.footprint(id)
		if other.position.y >= fp.end.y or other.end.y <= fp.position.y:
			continue  # not alongside the table
		var gap: float = other.position.x - fp.end.x if other.position.x >= fp.end.x else fp.position.x - other.end.x
		expect(gap >= aisle - 1e-3, "%s is %.2f m from the table's console (aisle_min_m %.2f)" % [id, gap, aisle])


func test_trackball_pans() -> void:
	await _frames(2)
	table.holo.follow_sub = false
	table.holo.focus = Vector3(0, -100, -200)
	var before: Vector3 = table.holo.focus
	table.pan_ball.rolled.emit(Vector2(5, 0))
	expect(table.holo.focus.distance_to(before) > 1.0, "rolling the ball moved the focus")
	expect(not table.holo.follow_sub, "panning does not turn following on")


func test_trackball_pan_takes_the_view_off_the_sub() -> void:
	await _frames(2)
	table.holo.follow_sub = true
	table.pan_ball.rolled.emit(Vector2(0, 5))
	expect(not table.holo.follow_sub, "panning stops following")
	expect(not table.follow_lamp.is_lit(), "lamp goes out")


func test_lever_zooms() -> void:
	await _frames(2)
	var before: float = table.holo.meters_per_unit
	table.zoom_lever.state.set_value(1.0)
	table._process(0.5)
	expect(table.holo.meters_per_unit < before, "lever up zooms in")
	table.zoom_lever.state.set_value(-1.0)
	var mid: float = table.holo.meters_per_unit
	table._process(0.5)
	expect(table.holo.meters_per_unit > mid, "lever down zooms out")
	table.zoom_lever.state.set_value(0.0)
	var rest: float = table.holo.meters_per_unit
	table._process(0.5)
	expect_eq(table.holo.meters_per_unit, rest, "a centred lever does nothing")


func test_toggle_sets_follow_and_lamp_matches() -> void:
	await _frames(2)
	expect(not table.holo.follow_sub and not table.follow_lamp.is_lit(), "starts not following, lamp out")
	table.follow_toggle._set_local(1.0)
	expect(table.holo.follow_sub, "toggle on follows the sub")
	table._process(0.0)
	expect(table.follow_lamp.is_lit(), "lamp lit")
	table.follow_toggle._set_local(0.0)
	expect(not table.holo.follow_sub, "toggle off stops following")
	table._process(0.0)
	expect(not table.follow_lamp.is_lit(), "lamp out")


func test_f_key_flips_the_toggle() -> void:
	await _frames(2)
	table.begin_interaction()
	table._unhandled_input(_key(KEY_F, true))
	expect(table.holo.follow_sub, "F follows")
	await _frames(2)
	expect(table.follow_toggle.get_value() > 0.5, "the toggle moved with it")
	table.end_interaction()


func test_rotation_keys_turn_the_chart() -> void:
	await _frames(2)
	var start: float = table.holo.table_rotation_deg
	table.begin_interaction()
	table._unhandled_input(_key(KEY_R, true))
	table._process(0.5)
	table._unhandled_input(_key(KEY_R, false))
	var turned: float = table.holo.table_rotation_deg
	expect(not is_equal_approx(turned, start), "R turns the chart")
	table._unhandled_input(_key(KEY_Q, true))
	table._process(0.5)
	table._unhandled_input(_key(KEY_Q, false))
	expect_near(table.holo.table_rotation_deg, start, 0.01, "Q turns it back")
	table._process(0.5)
	expect_near(table.holo.table_rotation_deg, start, 0.01, "released keys stop the turn")
	table.end_interaction()


func test_middle_drag_rotates() -> void:
	await _frames(2)
	var start: float = table.holo.table_rotation_deg
	table.begin_interaction()
	var down: InputEventMouseButton = InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_MIDDLE
	down.pressed = true
	table._unhandled_input(down)
	var move: InputEventMouseMotion = InputEventMouseMotion.new()
	move.relative = Vector2(20, 0)
	table._unhandled_input(move)
	expect(not is_equal_approx(table.holo.table_rotation_deg, start), "dragging turns the chart")
	table.end_interaction()


func test_hint_names_the_rotation_keys() -> void:
	expect(table.seated_hint().contains("Q/R"), "the seated hint shows the rotation keys")


func test_work_lamps_are_cabin_lights() -> void:
	for n: String in ["WorkLampPort", "WorkLampStarboard"]:
		var l: OmniLight3D = game.get_node("Interior/Lights/" + n) as OmniLight3D
		expect(l != null, n + " exists")
		var pl: PaletteLight = l.get_node("PaletteLight") as PaletteLight
		expect_eq(pl.swatch, &"light_cabin")
		var table_fp: Rect2 = SubLayout.top_footprint(&"map_table")
		expect(table_fp.grow(0.3).has_point(Vector2(l.position.x, l.position.z)), n + " is over the table")


func test_old_projector_is_gone() -> void:
	expect(table.holo.get_node_or_null("TableProjector") == null, "no projector on the table hologram")
