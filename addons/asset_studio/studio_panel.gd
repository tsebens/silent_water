@tool
class_name AssetStudioPanel
extends VBoxContainer
## The Asset Studio main-screen tab: Queue on the left, Concept for the selected asset on
## the right. Thin UI over AssetQueueModel, AssetConceptModel and AssetBackendRunner; every
## action is a backend command, so this never talks to a service.

const SETTINGS_PATH: String = "user://asset_studio.cfg"
const THUMB: Vector2 = Vector2(220, 220)

var runner: AssetBackendRunner
var queue: AssetQueueModel = AssetQueueModel.new()
var concept: AssetConceptModel = AssetConceptModel.new()
var turnaround: AssetTurnaroundModel = AssetTurnaroundModel.new()
var model: AssetModelModel = AssetModelModel.new()
var cost: AssetCostModel = AssetCostModel.new()
## Runs `--estimate` commands one at a time, apart from `runner` so it never blocks real work.
var estimator: AssetBackendRunner

var _assets: Array = []
var _providers: Dictionary = {}
var _selected: Dictionary = {}
var _selected_slug: String = ""
var _tree: Tree
var _split: HSplitContainer
var _folder_menu: PopupMenu
var _folder_input: ConfirmationDialog
var _folder_input_edit: LineEdit
## What the folder-name dialog does on OK: "create" under, or "rename" of, `_menu_folder`.
var _folder_input_mode: String = ""
var _menu_folder: String = ""
## Folder paths the user collapsed; kept across refreshes.
var _collapsed: Dictionary = {}
var _grid: GridContainer
var _title: Label
var _status: Label
var _progress: ProgressBar
var _error: RichTextLabel
var _provider_pick: OptionButton
var _writer_pick: OptionButton
var _lineage: RichTextLabel
var _refresh_btn: Button
var _more_btn: Button
var _lineage_title: Label
var _tabs: TabContainer
var _turn_title: Label
var _turn_views: HBoxContainer
var _turn_provider: OptionButton
var _turn_all_btn: Button
var _brief_edit: TextEdit
var _brief_save_btn: Button
var _brief_draft_btn: Button
var _model_title: Label
var _previews: HBoxContainer
var _run_list: VBoxContainer
var _model_provider: OptionButton
var _light_btn: Button
var _wire_btn: Button
var _turntable_btn: Button
var _tri_label: Label
var _gate_title: Label
var _gate_text: RichTextLabel
var _export_btn: Button
var _model_actions: HBoxContainer
var _shown_run: String = ""
var new_asset: AssetNewAssetModel = AssetNewAssetModel.new()
var _new_btn: Button
var _new_dialog: ConfirmationDialog
var _new_slug: LineEdit
var _new_class: OptionButton
var _new_issue: LineEdit
var _new_desc: TextEdit
var _new_hint: Label
var _desc_edit: TextEdit
var _desc_save_btn: Button
var _more_hint: Label
var _cost_title: Label
var _cost_text: Label
## Action key -> [{button, base}]: paid-action buttons that show an estimate.
var _est_buttons: Dictionary = {}
var _est_queue: Array = []
var _est_stale: bool = false


func _init() -> void:
	name = "AssetStudio"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()


func _ready() -> void:
	runner = AssetBackendRunner.new()
	add_child(runner)
	runner.started.connect(_on_started)
	runner.finished.connect(_on_finished)
	runner.progress.connect(_on_progress)
	estimator = AssetBackendRunner.new()
	add_child(estimator)
	estimator.finished.connect(_on_estimate_finished)
	if Engine.is_editor_hint() and not has_meta("fixture"):
		refresh()


func refresh() -> void:
	runner.run(PackedStringArray(["list"]))


## Fill the panel from a `list` output dictionary without running the backend (tests, screenshots).
func show_listing(listing: Dictionary) -> void:
	_assets = listing.get("assets", [])
	_providers = listing.get("providers", {})
	_selected = listing.get("selected", {})
	queue.load_assets(_assets, listing.get("folders", []))
	_fill_queue()
	if _selected_slug == "" and not queue.rows.is_empty():
		_selected_slug = str(queue.rows[0]["slug"])
	_show_asset(_selected_slug)


func show_error(text: String) -> void:
	_error.visible = text != ""
	_error.clear()
	_error.append_text("[color=#ff6b6b]%s[/color]" % text.replace("[", "[lb]"))


func _build() -> void:
	var bar: HBoxContainer = HBoxContainer.new()
	add_child(bar)
	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.pressed.connect(func() -> void: refresh())
	bar.add_child(_refresh_btn)
	_new_btn = _button(bar, "New asset", open_new_asset)
	_status = Label.new()
	_status.text = "Idle"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(_status)
	_progress = ProgressBar.new()
	_progress.custom_minimum_size = Vector2(160, 0)
	_progress.indeterminate = true
	_progress.visible = false
	bar.add_child(_progress)

	var split: HSplitContainer = HSplitContainer.new()
	_split = split
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = _saved_split_offset()
	split.dragged.connect(_on_split_dragged)
	add_child(split)

	_tree = Tree.new()
	_tree.columns = 2
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Asset")
	_tree.set_column_title(1, "Stage")
	_tree.set_column_expand(0, true)
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 80)
	_tree.custom_minimum_size = Vector2(240, 0)
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_SINGLE
	_tree.item_selected.connect(_on_row_selected)
	_tree.item_collapsed.connect(_on_item_collapsed)
	_tree.item_mouse_selected.connect(_on_item_mouse_selected)
	_tree.set_drag_forwarding(_drag_data, _can_drop, _drop)
	split.add_child(_tree)
	_build_folder_menu()

	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(_tabs)
	var right: VBoxContainer = VBoxContainer.new()
	right.name = "Concept"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.add_child(right)
	_build_turnaround_tab()
	_build_model_tab()
	_title = Label.new()
	_title.text = "Concept"
	right.add_child(_title)
	var dl: Label = Label.new()
	dl.text = "Description (the concept brief, editable)"
	right.add_child(dl)
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 90)
	_desc_edit.text_changed.connect(func() -> void: _update_description_controls(runner != null and runner.busy))
	right.add_child(_desc_edit)
	_desc_save_btn = _button(right, "Save description", _on_save_description)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = 2
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	var more: HBoxContainer = HBoxContainer.new()
	right.add_child(more)
	var lbl: Label = Label.new()
	lbl.text = "Image provider"
	more.add_child(lbl)
	_provider_pick = OptionButton.new()
	_provider_pick.item_selected.connect(func(_i: int) -> void: request_estimates())
	more.add_child(_provider_pick)
	var wl: Label = Label.new()
	wl.text = "Prompt writer"
	more.add_child(wl)
	_writer_pick = OptionButton.new()
	_writer_pick.item_selected.connect(func(_i: int) -> void: request_estimates())
	more.add_child(_writer_pick)
	_more_btn = _est_button(more, "Generate more", "more", _on_generate_more)
	_more_hint = Label.new()
	more.add_child(_more_hint)

	_cost_title = Label.new()
	_cost_title.text = "Cost"
	right.add_child(_cost_title)
	_cost_text = Label.new()
	right.add_child(_cost_text)

	_lineage_title = Label.new()
	_lineage_title.text = "Lineage"
	right.add_child(_lineage_title)
	_lineage = RichTextLabel.new()
	_lineage.custom_minimum_size = Vector2(0, 110)
	_lineage.bbcode_enabled = false
	right.add_child(_lineage)

	_build_new_dialog()
	_error = RichTextLabel.new()
	_error.bbcode_enabled = true
	_error.fit_content = true
	_error.selection_enabled = true
	_error.visible = false
	add_child(_error)


func _build_new_dialog() -> void:
	_new_dialog = ConfirmationDialog.new()
	_new_dialog.title = "New asset"
	_new_dialog.ok_button_text = "Create"
	_new_dialog.min_size = Vector2i(460, 360)
	var box: VBoxContainer = VBoxContainer.new()
	_new_dialog.add_child(box)
	_new_slug = LineEdit.new()
	_new_slug.placeholder_text = "slug (lowercase letters, digits, _)"
	box.add_child(_new_slug)
	_new_class = OptionButton.new()
	for c: String in AssetNewAssetModel.CLASSES:
		_new_class.add_item(c)
	box.add_child(_new_class)
	_new_issue = LineEdit.new()
	_new_issue.placeholder_text = "Issue number (optional)"
	box.add_child(_new_issue)
	_new_desc = TextEdit.new()
	_new_desc.placeholder_text = "Description (required): what the asset is"
	_new_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_new_desc.custom_minimum_size = Vector2(0, 140)
	box.add_child(_new_desc)
	_new_hint = Label.new()
	box.add_child(_new_hint)
	_new_slug.text_changed.connect(func(_t: String) -> void: _sync_new_dialog())
	_new_issue.text_changed.connect(func(_t: String) -> void: _sync_new_dialog())
	_new_desc.text_changed.connect(_sync_new_dialog)
	_new_class.item_selected.connect(func(_i: int) -> void: _sync_new_dialog())
	_new_dialog.confirmed.connect(_on_new_confirmed)
	add_child(_new_dialog)


func _build_folder_menu() -> void:
	_folder_menu = PopupMenu.new()
	_folder_menu.add_item("New asset here", 0)
	_folder_menu.add_item("New folder", 1)
	_folder_menu.add_item("Rename", 2)
	_folder_menu.id_pressed.connect(_on_folder_menu)
	add_child(_folder_menu)
	_folder_input = ConfirmationDialog.new()
	_folder_input_edit = LineEdit.new()
	_folder_input.add_child(_folder_input_edit)
	_folder_input.confirmed.connect(_on_folder_input_confirmed)
	add_child(_folder_input)


func _on_item_mouse_selected(_pos: Vector2, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_RIGHT:
		return
	var item: TreeItem = _tree.get_selected()
	if item == null or not (item.get_metadata(0) is Dictionary):
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta["kind"] != "folder":
		return
	_menu_folder = str(meta["path"])
	_folder_menu.set_item_disabled(2, _menu_folder == "")
	_folder_menu.position = Vector2i(DisplayServer.mouse_get_position())
	_folder_menu.popup()


func _on_folder_menu(id: int) -> void:
	match id:
		0:
			open_new_asset(_menu_folder)
		1:
			_folder_input_mode = "create"
			_folder_input.title = "New folder"
			_folder_input_edit.text = ""
			_folder_input_edit.placeholder_text = "folder name"
			_folder_input.popup_centered(Vector2i(320, 100))
		2:
			_folder_input_mode = "rename"
			_folder_input.title = "Rename folder"
			_folder_input_edit.text = _menu_folder.get_file()
			_folder_input.popup_centered(Vector2i(320, 100))


func _on_folder_input_confirmed() -> void:
	var args: PackedStringArray
	if _folder_input_mode == "create":
		args = AssetQueueModel.create_folder_args(_menu_folder, _folder_input_edit.text)
	else:
		args = AssetQueueModel.rename_args(_menu_folder, _folder_input_edit.text)
	if not args.is_empty():
		_command(args)


# --- drag and drop: every move is a backend command; the plugin never touches files --------

func _drag_data(at: Vector2) -> Variant:
	var item: TreeItem = _tree.get_item_at_position(at)
	if item == null or not (item.get_metadata(0) is Dictionary):
		return null
	var meta: Dictionary = item.get_metadata(0)
	if meta["kind"] == "folder" and meta["path"] == "":
		return null
	var preview: Label = Label.new()
	preview.text = item.get_text(0)
	_tree.set_drag_preview(preview)
	return meta


func _drop_target(at: Vector2) -> Dictionary:
	var item: TreeItem = _tree.get_item_at_position(at)
	if item == null:
		# Empty space below the rows is the root folder.
		return {"kind": "folder", "path": ""}
	return item.get_metadata(0) as Dictionary


func _can_drop(at: Vector2, data: Variant) -> bool:
	_tree.drop_mode_flags = Tree.DROP_MODE_DISABLED
	return data is Dictionary and queue.can_drop(data as Dictionary, _drop_target(at))


func _drop(at: Vector2, data: Variant) -> void:
	if data is Dictionary:
		_command(queue.drop_args(data as Dictionary, _drop_target(at)))


func _selection() -> Dictionary:
	var item: TreeItem = _tree.get_selected() if _tree != null else null
	if item != null and item.get_metadata(0) is Dictionary:
		return item.get_metadata(0)
	return {}


func _saved_split_offset() -> int:
	var cfg: ConfigFile = ConfigFile.new()
	if not has_meta("fixture") and cfg.load(SETTINGS_PATH) == OK:
		return int(cfg.get_value("queue", "split_offset", 0))
	return 0


func _on_split_dragged(offset: int) -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("queue", "split_offset", offset)
	cfg.save(SETTINGS_PATH)


func _on_item_collapsed(item: TreeItem) -> void:
	var meta: Variant = item.get_metadata(0)
	if meta is Dictionary and meta["kind"] == "folder":
		if item.collapsed:
			_collapsed[meta["path"]] = true
		else:
			_collapsed.erase(meta["path"])


func open_new_asset(folder: Variant = null) -> void:
	_new_slug.text = ""
	_new_issue.text = ""
	_new_desc.text = ""
	_new_class.select(0)
	var slugs: PackedStringArray = PackedStringArray()
	for r: Dictionary in queue.rows:
		slugs.append(str(r["slug"]))
	new_asset.load_existing(slugs)
	new_asset.folder = queue.new_asset_folder(_selection()) if folder == null else str(folder)
	_sync_new_dialog()
	_new_dialog.popup_centered()


func _sync_new_dialog() -> void:
	new_asset.slug = _new_slug.text
	new_asset.asset_class = _new_class.get_item_text(_new_class.selected)
	new_asset.issue_text = _new_issue.text
	new_asset.description = _new_desc.text
	_new_hint.text = new_asset.error()
	_new_dialog.get_ok_button().disabled = not new_asset.is_valid()


func _on_new_confirmed() -> void:
	_sync_new_dialog()
	var args: PackedStringArray = new_asset.new_args()
	if args.is_empty():
		return
	_selected_slug = new_asset.slug
	_command(args)


func _update_description_controls(busy: bool = false) -> void:
	_desc_save_btn.disabled = busy or concept.describe_args(_desc_edit.text).is_empty()
	_more_btn.disabled = busy or not concept.can_generate_more(_desc_edit.text)
	_more_hint.text = concept.generate_hint(_desc_edit.text)


func _on_save_description() -> void:
	_command(concept.describe_args(_desc_edit.text))


func _build_turnaround_tab() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Turnaround"
	_tabs.add_child(box)
	_turn_title = Label.new()
	_turn_title.text = "Turnaround: no asset selected"
	box.add_child(_turn_title)
	_turn_views = HBoxContainer.new()
	_turn_views.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_turn_views)
	var bar: HBoxContainer = HBoxContainer.new()
	box.add_child(bar)
	var lbl: Label = Label.new()
	lbl.text = "Image provider"
	bar.add_child(lbl)
	_turn_provider = OptionButton.new()
	_turn_provider.item_selected.connect(func(_i: int) -> void: request_estimates())
	bar.add_child(_turn_provider)
	_turn_all_btn = _est_button(bar, "Generate turnaround", "turnaround", func() -> void: _command(turnaround.generate_args(_picked(_turn_provider))))
	var bl: Label = Label.new()
	bl.text = "Brief (brief.md, editable)"
	box.add_child(bl)
	_brief_edit = TextEdit.new()
	_brief_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_brief_edit.custom_minimum_size = Vector2(0, 160)
	_brief_edit.text_changed.connect(_on_brief_changed)
	box.add_child(_brief_edit)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	_brief_save_btn = _button(row, "Save brief", save_brief)
	_brief_draft_btn = _button(row, "Draft brief", _on_draft_brief)


func _build_model_tab() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Model"
	_tabs.add_child(box)
	_model_title = Label.new()
	_model_title.text = "Model: no asset selected"
	box.add_child(_model_title)
	var tools: HBoxContainer = HBoxContainer.new()
	box.add_child(tools)
	_light_btn = _button(tools, "Light: white", func() -> void:
		model.toggle_light()
		_refresh_model_controls())
	_wire_btn = _button(tools, "Wireframe: off", func() -> void:
		model.toggle_wireframe()
		_refresh_model_controls())
	_turntable_btn = _button(tools, "Turntable: on", func() -> void:
		model.toggle_turntable()
		_refresh_model_controls())
	_tri_label = Label.new()
	_tri_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(_tri_label)
	_previews = HBoxContainer.new()
	_previews.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_previews.custom_minimum_size = Vector2(0, 280)
	box.add_child(_previews)
	var rl: Label = Label.new()
	rl.text = "Runs (tick up to %d to compare side by side)" % AssetModelModel.MAX_COMPARE
	box.add_child(rl)
	_run_list = VBoxContainer.new()
	box.add_child(_run_list)
	_gate_title = Label.new()
	_gate_title.text = "Gate report"
	box.add_child(_gate_title)
	_gate_text = RichTextLabel.new()
	_gate_text.custom_minimum_size = Vector2(0, 120)
	_gate_text.bbcode_enabled = true
	_gate_text.selection_enabled = true
	box.add_child(_gate_text)
	_model_actions = HBoxContainer.new()
	box.add_child(_model_actions)
	var pl: Label = Label.new()
	pl.text = "3D provider"
	_model_actions.add_child(pl)
	_model_provider = OptionButton.new()
	_model_provider.item_selected.connect(func(_i: int) -> void: request_estimates())
	_model_actions.add_child(_model_provider)
	_est_button(_model_actions, "Send to provider", "send", func() -> void: _command(model.to3d_args(PackedStringArray([_picked(_model_provider)]) if _picked(_model_provider) != "" else PackedStringArray())))
	_est_button(_model_actions, "Bake-off (all)", "bakeoff", func() -> void: _command(model.to3d_args(model.three_d_providers)))
	_button(_model_actions, "Clean up", func() -> void: _command(model.cleanup_args(_shown_run)))
	_button(_model_actions, "Check", func() -> void: _command(model.check_args(_shown_run)))
	_export_btn = _button(_model_actions, "Export", func() -> void: _command(model.export_args(_shown_run)))


func _process(delta: float) -> void:
	model.advance(delta)


func _fill_queue() -> void:
	_tree.clear()
	var top: TreeItem = _tree.create_item()
	var root_item: TreeItem = _tree.create_item(top)
	root_item.set_text(0, "assets/models")
	root_item.set_metadata(0, {"kind": "folder", "path": ""})
	_fill_folder(root_item, queue.root)
	root_item.collapsed = false


func _fill_folder(parent: TreeItem, node: Dictionary) -> void:
	for f: Dictionary in node["folders"]:
		var fi: TreeItem = _tree.create_item(parent)
		fi.set_text(0, str(f["name"]))
		fi.set_metadata(0, {"kind": "folder", "path": str(f["path"])})
		fi.set_tooltip_text(0, str(f["path"]))
		_fill_folder(fi, f)
		fi.collapsed = _collapsed.has(f["path"])
	for r: Dictionary in node["assets"]:
		var item: TreeItem = _tree.create_item(parent)
		item.set_text(0, str(r["slug"]))
		item.set_text(1, str(r["stage"]))
		item.set_tooltip_text(0, AssetQueueModel.tooltip(r))
		item.set_tooltip_text(1, AssetQueueModel.tooltip(r))
		item.set_metadata(0, {"kind": "asset", "slug": str(r["slug"])})
		if bool(r["over_budget"]):
			item.set_custom_color(0, Color(1.0, 0.42, 0.42))
		if str(r["slug"]) == _selected_slug:
			item.select(0)


func _on_row_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null or not (item.get_metadata(0) is Dictionary):
		return
	var meta: Dictionary = item.get_metadata(0)
	if meta["kind"] != "asset":
		return
	_selected_slug = str(meta["slug"])
	_show_asset(_selected_slug)


func _show_asset(slug: String) -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	_provider_pick.clear()
	_writer_pick.clear()
	_lineage.text = ""
	var asset: Dictionary = {}
	for a: Variant in _assets:
		if str((a as Dictionary).get("slug", "")) == slug:
			asset = a
	if asset.is_empty():
		_title.text = "Concept: no asset selected"
		concept.load_asset({})
		_desc_edit.text = ""
		_update_description_controls()
		_show_turnaround({})
		_show_model({})
		cost.load_asset({})
		_show_cost()
		return
	cost.load_asset(asset)
	_show_cost()
	_show_turnaround(asset)
	_show_model(asset)
	concept.load_asset(asset, _providers, _selected)
	_desc_edit.text = concept.description
	_update_description_controls()
	var qrow: Dictionary = queue.find(slug)
	_title.text = "Concept: %s (%s)  issue %s  cost %s" % [concept.slug, concept.asset_class, qrow.get("issue_text", "-"), qrow.get("cost_text", "-")]
	for p: String in concept.image_providers:
		_provider_pick.add_item(p)
		if p == concept.default_provider:
			_provider_pick.select(_provider_pick.item_count - 1)
	for w: String in concept.prompt_writers:
		_writer_pick.add_item(w)
		if w == concept.default_writer:
			_writer_pick.select(_writer_pick.item_count - 1)
	for v: Dictionary in concept.variants:
		_grid.add_child(_variant_card(v))
	if not concept.variants.is_empty():
		_show_lineage(str(concept.variants[-1]["id"]))
	request_estimates()


func _variant_card(v: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)
	var tex: TextureRect = TextureRect.new()
	tex.custom_minimum_size = THUMB
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture = _load_texture(str(v["path"]))
	box.add_child(tex)
	var cap: Label = Label.new()
	cap.text = "%s [%s]" % [v["caption"], v["state"]]
	box.add_child(cap)
	var prompt: Label = Label.new()
	prompt.text = str(v["prompt"])
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.custom_minimum_size = Vector2(THUMB.x, 0)
	prompt.max_lines_visible = 4
	box.add_child(prompt)
	var notes: LineEdit = LineEdit.new()
	notes.placeholder_text = "Notes (needed to refine)"
	box.add_child(notes)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var id: String = str(v["id"])
	_button(row, "Approve", func() -> void: _command(concept.approve_args(id, notes.text)))
	_button(row, "Reject", func() -> void: _command(concept.reject_args(id, notes.text)))
	_est_button(row, "Refine", "refine", func() -> void: _command(concept.refine_args(id, notes.text, _picked_provider(), _picked(_writer_pick))))
	_button(row, "Lineage", func() -> void: _show_lineage(id))
	return card


## A button for a paid action; its label gains the backend's estimate once known.
func _est_button(parent: Control, text: String, action: String, cb: Callable) -> Button:
	var b: Button = _button(parent, text, cb)
	if not _est_buttons.has(action):
		_est_buttons[action] = []
	(_est_buttons[action] as Array).append({"button": b, "base": text})
	b.text = cost.label(action, text)
	return b


func _refresh_est_labels() -> void:
	for action: String in _est_buttons:
		var live: Array = []
		for e: Variant in _est_buttons[action]:
			var d: Dictionary = e
			if is_instance_valid(d["button"]):
				(d["button"] as Button).text = cost.label(action, str(d["base"]))
				live.append(d)
		_est_buttons[action] = live


## The estimate commands for the selected asset and current provider picks, by action.
func estimate_commands() -> Dictionary:
	var img: String = _picked_provider()
	var out: Dictionary = {
		"more": concept.generate_more_args(3, img, _picked(_writer_pick)),
		"turnaround": turnaround.generate_args(_picked(_turn_provider)),
		"view": turnaround.regenerate_args("front", _picked(_turn_provider)),
		"bakeoff": model.to3d_args(model.three_d_providers),
	}
	out["refine"] = out["more"]
	var pick: String = _picked(_model_provider)
	out["send"] = model.to3d_args(PackedStringArray([pick]) if pick != "" else PackedStringArray())
	return out


## Asks the backend what each paid action would cost now. Skipped for fixture panels.
func request_estimates() -> void:
	cost.estimates.clear()
	_est_queue.clear()
	var cmds: Dictionary = estimate_commands()
	for action: String in AssetCostModel.ACTIONS:
		var a: PackedStringArray = AssetCostModel.estimate_args(cmds.get(action, PackedStringArray()))
		if not a.is_empty():
			_est_queue.append([action, a])
	_refresh_est_labels()
	if estimator != null and not has_meta("fixture"):
		_est_stale = estimator.busy
		_next_estimate()


func _next_estimate() -> void:
	if _est_queue.is_empty() or estimator.busy:
		return
	estimator.run((_est_queue[0] as Array)[1])


func _on_estimate_finished(_args: PackedStringArray, result: AssetBackendResult) -> void:
	if _est_stale:
		_est_stale = false
		_next_estimate()
		return
	if _est_queue.is_empty():
		return
	var item: Array = _est_queue.pop_front()
	if result.ok:
		cost.set_estimate(str(item[0]), result.data)
		_refresh_est_labels()
	_next_estimate()


func _show_cost() -> void:
	_cost_title.text = "Cost: %s" % cost.total_text() if cost.slug != "" else "Cost"
	var lines: PackedStringArray = cost.panel_lines()
	if cost.warning() != "":
		lines.insert(0, "WARNING: " + cost.warning())
		_cost_text.add_theme_color_override("font_color", Color(1.0, 0.42, 0.42))
	else:
		_cost_text.remove_theme_color_override("font_color")
	_cost_text.text = "\n".join(lines)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _read_text(rel: String) -> String:
	if rel == "":
		return ""
	var abs_path: String = AssetBackendResult.project_path(ProjectSettings.globalize_path("res://"), rel)
	return FileAccess.get_file_as_string(abs_path) if FileAccess.file_exists(abs_path) else ""


func _read_json(rel: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read_text(rel))
	return parsed as Dictionary if parsed is Dictionary else {}


# --- turnaround and brief ----------------------------------------------------------------

func _show_turnaround(asset: Dictionary) -> void:
	for c: Node in _turn_views.get_children():
		c.queue_free()
	_turn_provider.clear()
	if asset.is_empty():
		_turn_title.text = "Turnaround: no asset selected"
		turnaround.load_asset({})
		_brief_edit.text = ""
		_update_brief_buttons()
		return
	var brief_rel: String = str((asset.get("brief", {}) as Dictionary).get("path", "")) if asset.get("brief") is Dictionary else ""
	turnaround.load_asset(asset, _read_text(brief_rel))
	_turn_title.text = "Turnaround: %s (%d of 4 views)" % [turnaround.slug, turnaround.present_count()]
	for p: String in concept_image_providers():
		_turn_provider.add_item(p)
		if p == _selected.get("image", ""):
			_turn_provider.select(_turn_provider.item_count - 1)
	for v: Dictionary in turnaround.views:
		_turn_views.add_child(_view_card(v))
	_brief_edit.text = turnaround.brief_text
	_update_brief_buttons()


func concept_image_providers() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: Variant in _providers.get("image", []):
		out.append(str(n))
	return out


func _view_card(v: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)
	var tex: TextureRect = TextureRect.new()
	tex.custom_minimum_size = Vector2(160, 160)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture = _load_texture(str(v["path"]))
	box.add_child(tex)
	var cap: Label = Label.new()
	cap.text = str(v["caption"])
	box.add_child(cap)
	var name: String = str(v["view"])
	_est_button(box, "Regenerate", "view", func() -> void: _command(turnaround.regenerate_args(name, _picked(_turn_provider))))
	return card


func _on_brief_changed() -> void:
	turnaround.set_brief_text(_brief_edit.text)
	_update_brief_buttons()


func _update_brief_buttons() -> void:
	_brief_save_btn.disabled = not turnaround.can_save_brief()
	_brief_draft_btn.disabled = turnaround.draft_brief_args().is_empty()
	_turn_all_btn.disabled = turnaround.generate_args().is_empty()


func _on_draft_brief() -> void:
	if turnaround.dirty:
		show_error("Save your brief edits first: drafting overwrites brief.md.")
		return
	_command(concept.brief_args(_picked(_writer_pick)) if not turnaround.draft_brief_args().is_empty() else PackedStringArray())


## Writes the edited brief back to brief.md. This edits a file in the repo; no service is called.
func save_brief() -> bool:
	if not turnaround.can_save_brief():
		return false
	var abs_path: String = AssetBackendResult.project_path(ProjectSettings.globalize_path("res://"), turnaround.target_brief_path())
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		show_error("Could not write %s (error %d)" % [abs_path, FileAccess.get_open_error()])
		return false
	f.store_string(turnaround.brief_text)
	f.close()
	turnaround.mark_saved()
	_update_brief_buttons()
	_status.text = "Saved %s" % turnaround.target_brief_path()
	return true


# --- model -------------------------------------------------------------------------------

func _show_model(asset: Dictionary) -> void:
	for c: Node in _previews.get_children():
		c.queue_free()
	for c: Node in _run_list.get_children():
		c.queue_free()
	_model_provider.clear()
	_gate_text.clear()
	_shown_run = ""
	if asset.is_empty():
		_model_title.text = "Model: no asset selected"
		model.load_asset({})
		return
	var reports: Dictionary = {}
	for c: Variant in asset.get("checks", []):
		var rel: String = str((c as Dictionary).get("report", ""))
		if rel != "" and not reports.has(rel):
			reports[rel] = _read_json(rel)
	model.load_asset(asset, _providers, _selected, reports)
	_model_title.text = "Model: %s (%d runs)" % [model.slug, model.runs.size()]
	for p: String in model.three_d_providers:
		_model_provider.add_item(p)
		if p == model.default_provider:
			_model_provider.select(_model_provider.item_count - 1)
	for r: Dictionary in model.runs:
		var cb: CheckBox = CheckBox.new()
		cb.text = "%s  [%s]  %s  %s" % [r["caption"], model.gate_summary(str(r["id"])), model.triangle_text(str(r["id"])), "(exported)" if r["exported"] else ""]
		cb.button_pressed = model.compare_ids.has(str(r["id"]))
		var rid: String = str(r["id"])
		cb.pressed.connect(func() -> void:
			if not model.toggle_compare(rid):
				cb.button_pressed = model.compare_ids.has(rid)
			_rebuild_previews())
		_run_list.add_child(cb)
	_rebuild_previews()


## Previews for every ticked run; their light, wireframe and turntable come from `model`.
func _rebuild_previews() -> void:
	for c: Node in _previews.get_children():
		_previews.remove_child(c)
		c.queue_free()
	for id: String in model.compare_ids:
		var r: Dictionary = model.run(id)
		var pv: AssetModelPreview = AssetModelPreview.new()
		pv.state = model
		_previews.add_child(pv)
		pv.show_node(_load_run_node(r), "%s  %s" % [r.get("caption", id), model.triangle_text(id)])
	_shown_run = str(model.compare_ids[0]) if not model.compare_ids.is_empty() else ""
	_refresh_model_controls()
	_show_gate(_shown_run)


func _load_run_node(r: Dictionary) -> Node3D:
	var rel: String = str(r.get("path", ""))
	if rel == "":
		return null
	return AssetModelPreview.load_glb(AssetBackendResult.project_path(ProjectSettings.globalize_path("res://"), rel))


func _refresh_model_controls() -> void:
	_light_btn.text = "Light: %s" % model.light
	_wire_btn.text = "Wireframe: %s" % ("on" if model.wireframe else "off")
	_turntable_btn.text = "Turntable: %s" % ("on" if model.turntable else "off")
	_tri_label.text = model.triangle_text(_shown_run) if _shown_run != "" else ""
	_export_btn.disabled = not model.can_export(_shown_run)


func _show_gate(id: String) -> void:
	_gate_text.clear()
	_gate_title.text = "Gate report: %s" % (model.gate_summary(id) if id != "" else "no run")
	for g: Dictionary in model.gate_rows(id):
		var colour: String = "#6bd68a" if g["ok"] else "#ff6b6b"
		_gate_text.append_text("[color=%s]%s[/color]  %s\n" % [colour, "pass" if g["ok"] else "FAIL", str(g["detail"]).replace("[", "[lb]")])


func _show_lineage(id: String) -> void:
	_lineage_title.text = "Lineage of %s" % id
	var lines: PackedStringArray = PackedStringArray()
	for r: Dictionary in concept.lineage_of(id):
		lines.append("%s  %s  %s/%s  parent: %s\n    %s" % [
			r["id"], r["kind"], r["provider"], r["model"], str(r["parent"]) if r["parent"] != null else "none", r["prompt"]
		])
	_lineage.text = "\n".join(lines)


func _load_texture(rel: String) -> Texture2D:
	var abs_path: String = AssetBackendResult.project_path(ProjectSettings.globalize_path("res://"), rel)
	if rel == "" or not FileAccess.file_exists(abs_path):
		return null
	var img: Image = Image.load_from_file(abs_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _picked(opt: OptionButton) -> String:
	return opt.get_item_text(opt.selected) if opt.item_count > 0 and opt.selected >= 0 else ""


func _picked_provider() -> String:
	if _provider_pick.item_count == 0:
		return ""
	return _provider_pick.get_item_text(_provider_pick.selected)


func _on_generate_more() -> void:
	_command(concept.generate_more_args(3, _picked_provider(), _picked(_writer_pick)))


func _command(args: PackedStringArray) -> void:
	if args.is_empty():
		show_error("Nothing to run: that action needs more input (refine notes, a locked concept, all four views or a passing gate).")
		return
	if not runner.run(args):
		show_error("A backend command is already running.")


## The latest stderr line of the running command replaces the status text.
func _on_progress(line: String) -> void:
	_status.text = line


func _on_started(args: PackedStringArray) -> void:
	show_error("")
	_status.text = "Running: asset %s" % " ".join(args)
	_progress.visible = true
	_set_busy(true)


func _on_finished(args: PackedStringArray, result: AssetBackendResult) -> void:
	_progress.visible = false
	_set_busy(false)
	if not result.ok:
		_status.text = "Failed: asset %s" % " ".join(args)
		show_error(result.error)
		return
	_status.text = "Done: asset %s" % " ".join(args)
	if args.size() > 0 and args[0] == "list":
		show_listing(result.data)
	else:
		refresh()


func _set_busy(busy: bool) -> void:
	_refresh_btn.disabled = busy
	_new_btn.disabled = busy
	for b: Button in [_turn_all_btn, _brief_save_btn, _brief_draft_btn, _export_btn]:
		b.disabled = busy or b.disabled
	_update_description_controls(busy)
	if not busy:
		_update_brief_buttons()
		_refresh_model_controls()
