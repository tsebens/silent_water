extends TestCase
## PauseMenu: Escape order, session actions, schema-built tabs, input lock.

const PLAYER_SCENE: PackedScene = preload("res://src/player/player.tscn")
const TMP: String = "user://test_pause_settings_tmp.cfg"


class StubSession:
	extends PauseMenu.Session
	var host: bool = false
	var calls: Array[String] = []

	func is_host() -> bool:
		return host

	func end_run() -> void:
		calls.append("end_host" if host else "leave")

	func quit_game(_tree: SceneTree) -> void:
		calls.append("quit")


var _settings: GameSettings
var _menu: PauseMenu
var _player: Player
var _stub: StubSession


func before_each() -> void:
	_settings = GameSettings.new()
	_settings.path = TMP
	runner.add_child(_settings)
	_menu = PauseMenu.new()
	runner.add_child(_menu)
	_menu.build_tabs(_settings)
	_stub = StubSession.new()
	_menu.session = _stub
	_player = PLAYER_SCENE.instantiate() as Player
	_player.name = "1"
	runner.add_child(_player)


func after_each() -> void:
	# Freed at once: the player finds the menu by group.
	_player.free()
	_menu.free()
	_settings.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))


func _escape() -> void:
	var e: InputEventAction = InputEventAction.new()
	e.action = &"release_mouse"
	e.pressed = true
	_player._unhandled_input(e)


func test_escape_order() -> void:
	var held: Interactable = Interactable.new()
	runner.add_child(held)
	_player._held = held
	_escape()
	expect(not _menu.is_open(), "first Escape lets go of the held control")
	expect(_player.held_control() == null)
	_escape()
	expect(_menu.is_open(), "then it opens the menu")
	_menu.open_settings()
	expect_eq(_menu.page(), PauseMenu.Page.SETTINGS)
	_escape()
	expect_eq(_menu.page(), PauseMenu.Page.MAIN, "Settings backs out to the menu")
	_escape()
	expect(not _menu.is_open(), "then closes it")
	held.queue_free()


func test_escape_cancels_confirmation() -> void:
	_menu.open()
	_menu.request_end_run()
	expect_eq(_menu.page(), PauseMenu.Page.CONFIRM)
	_escape()
	expect_eq(_menu.page(), PauseMenu.Page.MAIN)
	expect(_stub.calls.is_empty())


func test_host_end_run_and_quit() -> void:
	_stub.host = true
	_menu.open()
	_menu.request_end_run()
	expect_eq(_menu.confirm_text(), "End the run for everyone?")
	_menu.accept()
	_menu.open()
	_menu.request_quit()
	expect("everyone" in _menu.confirm_text(), "host quit warns")
	_menu.accept()
	expect_eq(_stub.calls, ["end_host", "quit"] as Array[String])


func test_client_leave_and_quit_text() -> void:
	_menu.open()
	_menu.request_end_run()
	expect_eq(_menu.confirm_text(), "Leave the run?")
	_menu.accept()
	_menu.open()
	_menu.request_quit()
	expect(not ("everyone" in _menu.confirm_text()), "client quit text has no host wording")
	_menu.back()
	expect_eq(_stub.calls, ["leave"] as Array[String], "declining quits nothing")


func test_tabs_from_schema() -> void:
	expect_eq(_menu.tab_names(), ["Game", "Graphics", "Audio"] as Array[String])
	expect_eq(_menu.tab_entries("Game").size(), 1)
	expect(_menu.empty_label("Game") == null)
	expect(_menu.empty_label("Graphics") != null, "Graphics is empty")
	expect(_menu.empty_label("Audio") != null, "Audio is empty")
	var sl: HSlider = _menu.slider(&"fov_horizontal")
	expect(sl != null)
	sl.value = 100.0
	expect_near(float(_settings.get_value(&"fov_horizontal")), 100.0, 0.001, "slider writes the setting")


func test_menu_blocks_input_and_does_not_pause() -> void:
	_menu.open()
	var before: float = _player.rotation.y
	var m: InputEventMouseMotion = InputEventMouseMotion.new()
	m.relative = Vector2(100, 0)
	_player._unhandled_input(m)
	expect_near(_player.rotation.y, before, 0.00001, "look ignored")
	expect(not runner.get_tree().paused, "tree not paused")
	_menu.close()
	expect(not _menu.is_open())
