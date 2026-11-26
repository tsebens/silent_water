class_name PauseMenu
extends CanvasLayer
## The Escape menu: Resume, Settings, End run, Quit game. Screen-space and
## local only; it never pauses the tree, so the sim and other peers carry on.
## While it is open the local [Player] ignores movement and look input.
##
## Escape is routed here by the player ([method Player._unhandled_input]):
## [method back] closes a confirmation, then Settings, then the menu itself.

const GROUP: StringName = &"pause_menu"
## Settings tabs, in order. Entries come from the [GameSettings] schema.
const TABS: Array[String] = ["Game", "Graphics", "Audio"]
const EMPTY_TEXT: String = "Nothing here yet."

enum Page { CLOSED, MAIN, SETTINGS, CONFIRM }

## What the menu does to the session. Replaceable so tests never really quit.
class Session:
	extends RefCounted

	func is_host() -> bool:
		return Net.is_host()

	## Ends the run: the host's peers are dropped with it, a client just leaves.
	func end_run() -> void:
		Net.leave()

	func quit_game(tree: SceneTree) -> void:
		if Net.is_online():
			Net.leave()
		tree.quit()

var session: Session = Session.new()
var settings: GameSettings = null

var _page: Page = Page.CLOSED
var _root: Control
var _main_box: VBoxContainer
var _settings_box: VBoxContainer
var _confirm_box: VBoxContainer
var _tabs: TabContainer
var _confirm_label: Label
var _confirm_action: Callable
var _sliders: Dictionary = {}


func _ready() -> void:
	layer = 20
	add_to_group(GROUP)
	_build()
	_show_page(Page.CLOSED)


func is_open() -> bool:
	return _page != Page.CLOSED


func page() -> Page:
	return _page


func open() -> void:
	if _page != Page.CLOSED:
		return
	_show_page(Page.MAIN)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	if _page == Page.CLOSED:
		return
	_show_page(Page.CLOSED)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Escape with the menu open: one step back.
func back() -> void:
	match _page:
		Page.CONFIRM:
			_show_page(Page.MAIN)
		Page.SETTINGS:
			if settings != null:
				settings.save_settings()
			_show_page(Page.MAIN)
		Page.MAIN:
			close()


func tab_names() -> Array[String]:
	return TABS.duplicate()


## Rows (schema entries) shown on a tab; empty means the empty state.
func tab_entries(tab: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if settings == null:
		return out
	for e: Dictionary in settings.schema:
		if e["tab"] == tab:
			out.append(e)
	return out


func slider(key: StringName) -> HSlider:
	return _sliders.get(key) as HSlider


func empty_label(tab: String) -> Label:
	var t: Control = _tabs.get_node_or_null(tab) as Control
	return t.get_node_or_null("Empty") as Label if t != null else null


func confirm_text() -> String:
	return _confirm_label.text


func confirm_end_run_text() -> String:
	return "End the run for everyone?" if session.is_host() else "Leave the run?"


func confirm_quit_text() -> String:
	if session.is_host():
		return "Quit the game? This ends the session for everyone."
	return "Quit the game?"


func request_end_run() -> void:
	_ask(confirm_end_run_text(), func() -> void: session.end_run())


func request_quit() -> void:
	_ask(confirm_quit_text(), func() -> void: session.quit_game(get_tree()))


func accept() -> void:
	if _page != Page.CONFIRM:
		return
	var action: Callable = _confirm_action
	_show_page(Page.CLOSED)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	action.call()


func open_settings() -> void:
	if _page == Page.MAIN:
		_show_page(Page.SETTINGS)


func _ask(text: String, action: Callable) -> void:
	_confirm_label.text = text
	_confirm_action = action
	_show_page(Page.CONFIRM)


func _show_page(p: Page) -> void:
	_page = p
	_root.visible = p != Page.CLOSED
	_main_box.visible = p == Page.MAIN
	_settings_box.visible = p == Page.SETTINGS
	_confirm_box.visible = p == Page.CONFIRM


func _color(swatch: StringName) -> Color:
	return Palette.main().color(swatch)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim: ColorRect = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(_color(&"sub_black"), 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var centre: CenterContainer = CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)
	var panel: PanelContainer = PanelContainer.new()
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = _color(&"sub_grey_dark")
	style.border_color = _color(&"sub_orange")
	style.set_border_width_all(2)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override(&"panel", style)
	panel.custom_minimum_size = Vector2(380, 0)
	centre.add_child(panel)
	var stack: VBoxContainer = VBoxContainer.new()
	panel.add_child(stack)

	_main_box = _box(stack, "Paused")
	_button(_main_box, "Resume", close)
	_button(_main_box, "Settings", open_settings)
	_button(_main_box, "End run", request_end_run)
	_button(_main_box, "Quit game", request_quit)

	_settings_box = _box(stack, "Settings")
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(340, 160)
	_settings_box.add_child(_tabs)
	_button(_settings_box, "Back", back)

	_confirm_box = _box(stack, "")
	_confirm_label = _confirm_box.get_child(0) as Label
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(_confirm_box, "Yes", accept)
	_button(_confirm_box, "No", back)


func build_tabs(s: GameSettings) -> void:
	settings = s
	for c: Node in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	_sliders.clear()
	for tab: String in TABS:
		var box: VBoxContainer = VBoxContainer.new()
		box.name = tab
		_tabs.add_child(box)
		var entries: Array[Dictionary] = tab_entries(tab)
		if entries.is_empty():
			var l: Label = Label.new()
			l.name = "Empty"
			l.text = EMPTY_TEXT
			l.add_theme_color_override(&"font_color", _color(&"sub_control_grey"))
			box.add_child(l)
			continue
		for e: Dictionary in entries:
			_add_row(box, e)


func _add_row(box: VBoxContainer, e: Dictionary) -> void:
	if int(e["type"]) != TYPE_FLOAT and int(e["type"]) != TYPE_INT:
		return
	var key: StringName = e["key"]
	var l: Label = Label.new()
	box.add_child(l)
	var sl: HSlider = HSlider.new()
	sl.min_value = float(e["min"])
	sl.max_value = float(e["max"])
	sl.step = 1.0 if int(e["type"]) == TYPE_INT else 0.5
	sl.value = float(settings.get_value(key))
	sl.custom_minimum_size = Vector2(300, 24)
	var refresh: Callable = func(v: float) -> void: l.text = "%s: %d" % [e["label"], roundi(v)]
	refresh.call(sl.value)
	sl.value_changed.connect(
		func(v: float) -> void:
			settings.set_value(key, v)  # live while dragging
			refresh.call(v)
	)
	sl.drag_ended.connect(func(_changed: bool) -> void: settings.save_settings())
	box.add_child(sl)
	_sliders[key] = sl


func _box(parent: Control, title: String) -> VBoxContainer:
	var b: VBoxContainer = VBoxContainer.new()
	b.add_theme_constant_override(&"separation", 10)
	var t: Label = Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override(&"font_size", 22)
	t.add_theme_color_override(&"font_color", _color(&"sub_orange"))
	b.add_child(t)
	parent.add_child(b)
	return b


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)
	return b
