extends TestCase
## Stepping up at the map table leans the eye (down and toward the hologram),
## the same for everyone; observers beside the operator can pin but not drive.

const GAME_SCENE: PackedScene = preload("res://src/game/game.tscn")

var game: Game
var table: MapTable
var obs_a: MapTableObserver
var obs_b: MapTableObserver


func before_each() -> void:
	game = GAME_SCENE.instantiate() as Game
	runner.add_child(game)
	game.start_session()
	table = game.get_node("Interior/Stations/Maps/MapTable") as MapTable
	obs_a = table.get_node("ObserverA") as MapTableObserver
	obs_b = table.get_node("ObserverB") as MapTableObserver
	(game.get_node("World/Apex") as ApexMonster).set_active(false)
	(game.get_node("SubController") as SubController).enabled = false


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.end_session()
	game.free()


func _frames(n: int) -> void:
	for i: int in range(n):
		await runner.get_tree().process_frame


func _key(code: Key) -> InputEventKey:
	var e: InputEventKey = InputEventKey.new()
	e.keycode = code
	e.pressed = true
	return e


func test_lean_constants() -> void:
	expect_eq(MapTable.LEAN_DOWN, 0.25)
	expect_eq(MapTable.LEAN_TOWARD, 0.15)


func test_view_pose_is_the_standing_eye_leaned() -> void:
	await _frames(2)
	var eye: Vector3 = table.standing_eye()
	var pose: Vector3 = table.view_transform().origin
	var up: Vector3 = table.holo.global_basis.y
	expect_near((eye - pose).dot(up), MapTable.LEAN_DOWN, 0.001, "0.25 m lower")
	var flat: Vector3 = table.holo.global_position - eye
	flat -= up * flat.dot(up)
	expect_near((pose - eye).dot(flat.normalized()), MapTable.LEAN_TOWARD, 0.001, "0.15 m toward the table")


func test_observers_share_the_lean() -> void:
	await _frames(2)
	var eye: Vector3 = obs_a.seat_transform().origin + Vector3.UP * obs_a.eye_height
	var up: Vector3 = table.holo.global_basis.y
	expect_near((eye - obs_a.table_view().origin).dot(up), MapTable.LEAN_DOWN, 0.001, "observer leans down too")
	expect(obs_a.has_table_view() and obs_b.has_table_view(), "both observer points give the table view")


func test_second_player_steps_up_while_operator_does() -> void:
	await _frames(2)
	table.begin_interaction()
	obs_a.begin_interaction()
	obs_b.begin_interaction()
	await _frames(2)
	expect(table.is_held_locally() and obs_a.is_held_locally() and obs_b.is_held_locally(), "all three occupied at once")
	obs_a.end_interaction()
	expect(table.is_held_locally() and obs_b.is_held_locally() and not obs_a.is_held_locally(), "stepping back frees only that occupancy")
	table.end_interaction()
	obs_b.end_interaction()


func _click(button: MouseButton, pos: Vector2) -> InputEventMouseButton:
	var e: InputEventMouseButton = InputEventMouseButton.new()
	e.button_index = button
	e.pressed = true
	e.position = pos
	return e


func test_observer_pins_reach_the_model() -> void:
	await _frames(2)
	var model: MapModel = game.get_tree().get_first_node_in_group(&"map_model") as MapModel
	var cam: Camera3D = Camera3D.new()
	table.add_child(cam)
	cam.current = true
	cam.global_transform = table.view_transform_from(table.standing_eye())
	await _frames(2)
	var before: int = model.pins.size()
	obs_a.begin_interaction()
	obs_a._unhandled_input(_key(KEY_2))
	expect_eq(obs_a.pin_kind, MapModel.Kind.DANGER)
	var centre: Vector2 = cam.get_viewport().get_visible_rect().size * 0.5
	obs_a._unhandled_input(_click(MOUSE_BUTTON_LEFT, centre))
	expect_eq(model.pins.size(), before + 1, "observer click placed a pin")
	expect_eq(int(model.pins[model.pins.size() - 1]["kind"]), MapModel.Kind.DANGER)
	var pin_id: int = int(model.pins[model.pins.size() - 1]["id"])
	model.remove_pin(pin_id)
	expect_eq(model.pins.size(), before, "the model removes it")
	obs_a.end_interaction()
	cam.queue_free()


func test_observer_cannot_drive_the_camera() -> void:
	await _frames(2)
	table.holo.follow_sub = false
	var focus: Vector3 = table.holo.focus
	var zoom: float = table.holo.meters_per_unit
	var rot: float = table.holo.table_rotation_deg
	obs_a.begin_interaction()
	obs_a._unhandled_input(_key(KEY_F))
	obs_a._unhandled_input(_key(KEY_R))
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	obs_a._unhandled_input(wheel)
	expect(not table.holo.follow_sub, "F does nothing")
	expect_eq(table.holo.meters_per_unit, zoom)
	expect_eq(table.holo.table_rotation_deg, rot)
	expect_eq(table.holo.focus, focus)
	obs_a.end_interaction()


func test_lean_view_looks_at_the_tall_relief() -> void:
	var holo: HoloMap = table.holo
	var eye: Vector3 = obs_a.seat_transform().origin + Vector3.UP * obs_a.eye_height
	var t: Transform3D = table.view_transform_from(eye)
	var look: Vector3 = holo.global_position + holo.global_basis * Vector3(0, holo.relief_max_height() * 0.3, holo.clip_rz * 0.4)
	var fwd: Vector3 = (t.basis * Vector3.FORWARD).normalized()
	var want: Vector3 = (look - t.origin).normalized()
	expect(fwd.dot(want) > 0.999, "the view points at a spot up the relief, not at its base")
