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
var choice: AssetProviderChoice = AssetProviderChoice.new()
## Runs `--estimate` commands one at a time, apart from `runner` so it never blocks real work.
var estimator: AssetBackendRunner

var _assets: Array = []
var _providers: Dictionary = {}
var _three_d_max_views: Dictionary = {}
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
var _menu_asset: String = ""
## Selection to adopt once the running rename/delete succeeds ("-" is no slug: nothing selected).
var _pending_slug: String = ""
var _menu_kind: String = ""
var _menu_ids: Array[String] = []
var _rename_dialog: ConfirmationDialog
var _rename_edit: LineEdit
var _rename_hint: Label
var _delete_dialog: ConfirmationDialog
var rename: AssetRenameModel = AssetRenameModel.new()
var import_cad: AssetImportModel = AssetImportModel.new()
var _import_row: HBoxContainer
var _import_dialog: FileDialog
var _import_pivot: LineEdit
var _import_hint: Label
## Folder paths the user collapsed; kept across refreshes.
var _collapsed: Dictionary = {}
var _sections: Dictionary = {}
var _section_boxes: Dictionary = {}
var _desc_toggle: Button
const REFERENCE_MODE_ORDER: Array[String] = ["paint-over", "inspire"]
var _ref_dialog: FileDialog
var _ref_row: HBoxContainer
var _ref_mode: OptionButton
var _presentation_pick: OptionButton
var _lineage_toggle: Button
var _desc_body: Control
var _lineage_body: Control
var textures: AssetTextureCache = AssetTextureCache.new()
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
var _lineage_ref: TextureRect
var _tabs: TabContainer
var _turn_title: Label
var _turn_views: GridContainer
var _turn_scroll: ScrollContainer
var _turn_overlay: PopupPanel
var _turn_cell: float = 160.0
var _turn_asset: Dictionary = {}
var _turn_provider: OptionButton
var _turn_all_btn: Button
var _brief_edit: TextEdit
var _brief_save_btn: Button
var _brief_draft_btn: Button
var _model_title: Label
var _previews: HBoxContainer
var _run_list: VBoxContainer
var _model_provider: OptionButton
var _model_views: HBoxContainer
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
var _cost_title: Button
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
		choice.load_saved()
		refresh()


func refresh() -> void:
	if not has_meta("fixture"):
		var env_path: String = ProjectSettings.globalize_path("res://tools/asset_pipeline/.env")
		choice.keys_set = AssetProviderChoice.keys_from(FileAccess.get_file_as_string(env_path) if FileAccess.file_exists(env_path) else "")
	runner.run(PackedStringArray(["list"]))


## Fill the panel from a `list` output dictionary without running the backend (tests, screenshots).
func show_listing(listing: Dictionary) -> void:
	_assets = listing.get("assets", [])
	_providers = listing.get("providers", {})
	_three_d_max_views = listing.get("three_d_max_views", {})
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
	var cols: HBoxContainer = HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(cols)
	# Left column (~1/3): the description and the lineage, each collapsible.
	var left: VBoxContainer = VBoxContainer.new()
	left.size_flags_stretch_ratio = 1.0
	left.custom_minimum_size = Vector2(260, 0)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var desc_box: VBoxContainer = VBoxContainer.new()
	_desc_toggle = _toggle_header(left, "Description (the concept brief, editable)", desc_box, true)
	left.add_child(desc_box)
	_desc_body = desc_box
	_desc_edit = TextEdit.new()
	_desc_edit.custom_minimum_size = Vector2(0, 160)
	_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc_edit.text_changed.connect(func() -> void: _update_description_controls(runner != null and runner.busy))
	desc_box.add_child(_desc_edit)
	_desc_save_btn = _button(desc_box, "Save description", _on_save_description)
	var lin_box: VBoxContainer = VBoxContainer.new()
	lin_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lineage_toggle = _toggle_header(left, "Lineage: the full prompt, model and parent behind the selected image", lin_box, true)
	left.add_child(lin_box)
	_lineage_body = lin_box
	_lineage_title = Label.new()
	_lineage_title.text = "Select an image and press Lineage"
	_lineage_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lin_box.add_child(_lineage_title)
	_lineage = RichTextLabel.new()
	_lineage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_lineage.custom_minimum_size = Vector2(0, 110)
	_lineage.bbcode_enabled = false
	_lineage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lin_box.add_child(_lineage)
	_lineage_ref = TextureRect.new()
	_lineage_ref.name = "LineageReference"
	_lineage_ref.custom_minimum_size = Vector2(0, 96)
	_lineage_ref.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lineage_ref.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_lineage_ref.visible = false
	lin_box.add_child(_lineage_ref)

	# Right column (~2/3): one image per row in Pending / Accepted / Rejected.
	var side: VBoxContainer = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.size_flags_stretch_ratio = 2.0
	cols.add_child(side)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(scroll)
	var secs: VBoxContainer = VBoxContainer.new()
	secs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(secs)
	for sec: String in ["pending", "accepted", "rejected"]:
		var body: VBoxContainer = VBoxContainer.new()
		_section_boxes[sec] = body
		_sections[sec] = _toggle_header(secs, sec.capitalize(), body, sec != "rejected")
		secs.add_child(body)

	_build_reference_picker(side)
	var more: HBoxContainer = HBoxContainer.new()
	side.add_child(more)
	var lbl: Label = Label.new()
	lbl.text = "Image provider"
	more.add_child(lbl)
	_provider_pick = OptionButton.new()
	_provider_pick.item_selected.connect(func(_i: int) -> void: _remember("concept_image", _provider_pick))
	more.add_child(_provider_pick)
	var wl: Label = Label.new()
	wl.text = "Prompt writer"
	more.add_child(wl)
	_writer_pick = OptionButton.new()
	_writer_pick.item_selected.connect(func(_i: int) -> void: _remember("concept_writer", _writer_pick))
	more.add_child(_writer_pick)
	_more_btn = _est_button(more, "Generate more", "more", _on_generate_more)
	_more_hint = Label.new()
	more.add_child(_more_hint)

	var cost_box: VBoxContainer = VBoxContainer.new()
	_cost_title = _toggle_header(left, "Cost", cost_box, false)
	left.add_child(cost_box)
	_cost_text = Label.new()
	cost_box.add_child(_cost_text)

	_build_new_dialog()
	_error = RichTextLabel.new()
	_error.bbcode_enabled = true
	_error.fit_content = true
	_error.selection_enabled = true
	_error.visible = false
	add_child(_error)


## The reference picker above "Generate more": Add reference…, thumbnails with remove
## buttons, and the Paint-over / Inspire toggle.
func _build_reference_picker(parent: Control) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	parent.add_child(row)
	var add: Button = _button(row, "Add reference…", func() -> void: _ref_dialog.popup_centered_ratio(0.6))
	add.name = "AddReference"
	_ref_mode = OptionButton.new()
	_ref_mode.name = "ReferenceMode"
	_ref_mode.add_item("Paint-over (keep composition)")
	_ref_mode.set_item_metadata(0, "paint-over")
	_ref_mode.add_item("Inspire (loose start)")
	_ref_mode.set_item_metadata(1, "inspire")
	_ref_mode.item_selected.connect(func(i: int) -> void:
		concept.set_reference_mode(str(_ref_mode.get_item_metadata(i)))
		request_estimates())
	row.add_child(_ref_mode)
	_presentation_pick = OptionButton.new()
	_presentation_pick.name = "Presentation"
	_presentation_pick.add_item("Subject (one object)")
	_presentation_pick.set_item_metadata(0, "subject")
	_presentation_pick.add_item("Scene (full environment)")
	_presentation_pick.set_item_metadata(1, "scene")
	_presentation_pick.item_selected.connect(func(i: int) -> void:
		concept.set_presentation(str(_presentation_pick.get_item_metadata(i)))
		request_estimates())
	row.add_child(_presentation_pick)
	_ref_row = HBoxContainer.new()
	_ref_row.name = "ReferenceThumbs"
	parent.add_child(_ref_row)
	_ref_dialog = FileDialog.new()
	_ref_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	_ref_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_ref_dialog.title = "Reference images"
	_ref_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	_ref_dialog.files_selected.connect(func(paths: PackedStringArray) -> void:
		for p: String in paths:
			concept.add_reference(p)
		_fill_references())
	add_child(_ref_dialog)
	_fill_references()


func _fill_references() -> void:
	for c: Node in _ref_row.get_children():
		_ref_row.remove_child(c)
		c.queue_free()
	_ref_mode.visible = not concept.references.is_empty()
	_ref_mode.select(maxi(REFERENCE_MODE_ORDER.find(concept.reference_mode), 0))
	for i: int in concept.references.size():
		var path: String = concept.references[i]
		var cell: VBoxContainer = VBoxContainer.new()
		var t: TextureRect = TextureRect.new()
		t.custom_minimum_size = Vector2(64, 64)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.tooltip_text = path.get_file()
		t.texture = textures.get_texture(path)
		cell.add_child(t)
		var idx: int = i
		_button(cell, "Remove", func() -> void:
			concept.remove_reference(idx)
			_fill_references()
			request_estimates())
		_ref_row.add_child(cell)
	if is_node_ready():
		request_estimates()


## A flat button that shows or hides `body`. Its label is `title`, with a triangle.
func _toggle_header(parent: Control, title: String, body: Control, open: bool) -> Button:
	var b: Button = Button.new()
	b.flat = true
	b.clip_text = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("title", title)
	body.visible = open
	_set_toggle_text(b, open)
	b.pressed.connect(func() -> void:
		body.visible = not body.visible
		_set_toggle_text(b, body.visible))
	parent.add_child(b)
	return b


func _set_toggle_text(b: Button, open: bool) -> void:
	b.text = "%s %s" % ["▼" if open else "▶", str(b.get_meta("title"))]


## Rebuild the three sections from the concept model; titles carry their counts.
func _fill_sections() -> void:
	for sec: String in _section_boxes:
		var body: Control = _section_boxes[sec]
		for c: Node in body.get_children():
			body.remove_child(c)
			c.queue_free()
		for v: Dictionary in concept.group(sec):
			body.add_child(_variant_card(v))
		if sec == "pending":
			for i: int in concept.in_flight:
				body.add_child(_placeholder_card())
		var btn: Button = _sections[sec]
		btn.set_meta("title", concept.section_title(sec))
		_set_toggle_text(btn, body.visible)


func _placeholder_card() -> Control:
	var card: PanelContainer = PanelContainer.new()
	var l: Label = Label.new()
	l.text = "Generating…"
	l.custom_minimum_size = Vector2(0, 120)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_child(l)
	return card


func _decide(id: String, approve: bool, notes: String) -> void:
	if approve:
		concept.approve(id)
	else:
		concept.reject(id)
	_fill_sections()
	_command(concept.approve_args(id, notes) if approve else concept.reject_args(id, notes))


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
	_folder_menu.id_pressed.connect(_on_folder_menu)
	add_child(_folder_menu)
	_folder_input = ConfirmationDialog.new()
	_folder_input_edit = LineEdit.new()
	_folder_input.add_child(_folder_input_edit)
	_folder_input.confirmed.connect(_on_folder_input_confirmed)
	add_child(_folder_input)
	_rename_dialog = ConfirmationDialog.new()
	_rename_dialog.title = "Rename asset"
	_rename_dialog.ok_button_text = "Rename"
	var rbox: VBoxContainer = VBoxContainer.new()
	_rename_dialog.add_child(rbox)
	_rename_edit = LineEdit.new()
	rbox.add_child(_rename_edit)
	_rename_hint = Label.new()
	rbox.add_child(_rename_hint)
	_rename_edit.text_changed.connect(func(_t: String) -> void: _sync_rename_dialog())
	_rename_dialog.confirmed.connect(_on_rename_confirmed)
	add_child(_rename_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Delete"
	_delete_dialog.ok_button_text = "Delete"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_dialog)


func _on_item_mouse_selected(_pos: Vector2, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_RIGHT:
		return
	var item: TreeItem = _tree.get_selected()
	if item == null or not (item.get_metadata(0) is Dictionary):
		return
	var meta: Dictionary = item.get_metadata(0)
	_menu_kind = str(meta["kind"])
	if _menu_kind == "folder":
		_menu_folder = str(meta["path"])
	else:
		_menu_asset = str(meta["slug"])
	var busy: bool = runner != null and runner.busy
	_folder_menu.clear()
	_menu_ids.clear()
	for entry: Dictionary in AssetQueueModel.menu_items(_menu_kind, _menu_kind == "folder" and _menu_folder == "", busy):
		_folder_menu.add_item(str(entry["label"]), _menu_ids.size())
		_folder_menu.set_item_disabled(_menu_ids.size(), bool(entry["disabled"]))
		_menu_ids.append(str(entry["id"]))
	_folder_menu.position = Vector2i(DisplayServer.mouse_get_position())
	_folder_menu.popup()


func _on_folder_menu(id: int) -> void:
	match _menu_ids[id]:
		"new_here":
			open_new_asset(_menu_folder)
		"new_folder":
			_folder_input_mode = "create"
			_folder_input.title = "New folder"
			_folder_input_edit.text = ""
			_folder_input_edit.placeholder_text = "folder name"
			_folder_input.popup_centered(Vector2i(320, 100))
		"rename_folder":
			_folder_input_mode = "rename"
			_folder_input.title = "Rename folder"
			_folder_input_edit.text = _menu_folder.get_file()
			_folder_input.popup_centered(Vector2i(320, 100))
		"rename":
			var slugs: PackedStringArray = PackedStringArray()
			for r: Dictionary in queue.rows:
				slugs.append(str(r["slug"]))
			rename.open(_menu_asset, slugs)
			_rename_edit.text = _menu_asset
			_sync_rename_dialog()
			_rename_dialog.popup_centered(Vector2i(360, 120))
		"delete":
			if _menu_kind == "asset":
				var asset: Dictionary = {}
				for a: Variant in _assets:
					if str((a as Dictionary).get("slug", "")) == _menu_asset:
						asset = a
				var present: PackedStringArray = PackedStringArray()
				for f: String in AssetQueueModel.exported_files(asset):
					if FileAccess.file_exists(AssetBackendResult.project_path(ProjectSettings.globalize_path("res://"), f)):
						present.append(f)
				_delete_dialog.dialog_text = AssetQueueModel.delete_summary(asset, present)
			else:
				_delete_dialog.dialog_text = queue.delete_folder_summary(_menu_folder)
			_delete_dialog.popup_centered(Vector2i(420, 200))


func _sync_rename_dialog() -> void:
	rename.new_slug = _rename_edit.text
	_rename_hint.text = rename.error()
	_rename_dialog.get_ok_button().disabled = not rename.is_valid()


func _on_rename_confirmed() -> void:
	_sync_rename_dialog()
	var args: PackedStringArray = rename.rename_args()
	if args.is_empty():
		return
	_pending_slug = rename.new_slug if _selected_slug == rename.old_slug else ""
	_command(args)


func _on_delete_confirmed() -> void:
	var args: PackedStringArray
	if _menu_kind == "asset":
		args = AssetQueueModel.delete_args(_menu_asset)
		_pending_slug = "-" if _selected_slug == _menu_asset else ""
	else:
		args = AssetQueueModel.folder_delete_args(_menu_folder)
		_pending_slug = "-" if _folder_holds(queue.find_folder(_menu_folder), _selected_slug) else ""
	_command(args)


func _folder_holds(node: Dictionary, slug: String) -> bool:
	var slugs: PackedStringArray = PackedStringArray()
	queue._collect_slugs(node, slugs)
	return slugs.has(slug)


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


## Hide the Turnaround and 3D model tabs for classes that are not built from a turnaround.
func _sync_build_tabs() -> void:
	var cad: bool = concept.hides_concept_and_to3d()
	var hide_tabs: bool = concept.hides_build_tabs() and not cad
	if _import_row != null:
		_import_row.visible = cad
	if _model_actions != null:
		_model_actions.visible = not cad
	var concept_tab: Control = _tabs.get_node_or_null("Concept") as Control
	if concept_tab != null:
		_tabs.set_tab_hidden(_tabs.get_tab_idx_from_control(concept_tab), cad)
	var turn_tab: Control = _tabs.get_node_or_null("Turnaround") as Control
	if turn_tab != null:
		_tabs.set_tab_hidden(_tabs.get_tab_idx_from_control(turn_tab), hide_tabs or cad)
	for tab_name: String in ["Model"]:
		var tab: Control = _tabs.get_node_or_null(tab_name) as Control
		if tab != null:
			_tabs.set_tab_hidden(_tabs.get_tab_idx_from_control(tab), hide_tabs)
	if cad:
		_tabs.current_tab = _tabs.get_tab_idx_from_control(_tabs.get_node("Model"))
	elif hide_tabs:
		_tabs.current_tab = 0


func _build_turnaround_tab() -> void:
	var box: VBoxContainer = VBoxContainer.new()
	box.name = "Turnaround"
	_tabs.add_child(box)
	_turn_title = Label.new()
	_turn_title.text = "Turnaround: no asset selected"
	box.add_child(_turn_title)
	_turn_scroll = ScrollContainer.new()
	_turn_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_turn_scroll.size_flags_stretch_ratio = 8.0
	_turn_scroll.custom_minimum_size = Vector2(0, 240)
	_turn_scroll.resized.connect(_fit_turnaround)
	box.add_child(_turn_scroll)
	_turn_views = GridContainer.new()
	_turn_views.columns = AssetTurnaroundModel.GRID_SIZE.x
	_turn_views.add_theme_constant_override("h_separation", 4)
	_turn_views.add_theme_constant_override("v_separation", 4)
	_turn_views.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_turn_scroll.add_child(_turn_views)
	_turn_overlay = PopupPanel.new()
	add_child(_turn_overlay)
	var bar: HBoxContainer = HBoxContainer.new()
	box.add_child(bar)
	var lbl: Label = Label.new()
	lbl.text = "Image provider"
	bar.add_child(lbl)
	_turn_provider = OptionButton.new()
	_turn_provider.item_selected.connect(func(_i: int) -> void: _remember("turnaround_image", _turn_provider))
	bar.add_child(_turn_provider)
	_turn_all_btn = _est_button(bar, "Generate turnaround", "turnaround", func() -> void: _command(turnaround.generate_args(_picked(_turn_provider))))
	var bl: Label = Label.new()
	bl.text = "Brief (brief.md, editable)"
	box.add_child(bl)
	_brief_edit = TextEdit.new()
	_brief_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_brief_edit.size_flags_stretch_ratio = 1.0
	_brief_edit.custom_minimum_size = Vector2(0, 80)
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
	_import_row = HBoxContainer.new()
	_import_row.visible = false
	box.add_child(_import_row)
	var pv: Label = Label.new()
	pv.text = "Pivot part"
	_import_row.add_child(pv)
	_import_pivot = LineEdit.new()
	_import_pivot.placeholder_text = "part name (optional)"
	_import_pivot.custom_minimum_size = Vector2(160, 0)
	_import_row.add_child(_import_pivot)
	_button(_import_row, "Import CAD…", _on_import_cad)
	_import_hint = Label.new()
	_import_row.add_child(_import_hint)
	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.title = "Import CAD export (glTF)"
	_import_dialog.filters = PackedStringArray(["*.gltf, *.glb ; glTF export"])
	_import_dialog.file_selected.connect(_on_import_file_selected)
	add_child(_import_dialog)
	_model_actions = HBoxContainer.new()
	box.add_child(_model_actions)
	var pl: Label = Label.new()
	pl.text = "3D provider"
	_model_actions.add_child(pl)
	_model_provider = OptionButton.new()
	_model_provider.item_selected.connect(func(_i: int) -> void:
		_remember("model_three_d", _model_provider)
		_fill_view_picker())
	_model_actions.add_child(_model_provider)
	_model_views = HBoxContainer.new()
	_model_actions.add_child(_model_views)
	_est_button(_model_actions, "Send to provider", "send", func() -> void: _command(model.to3d_args(PackedStringArray([_picked(_model_provider)]) if _picked(_model_provider) != "" else PackedStringArray())))
	_est_button(_model_actions, "Bake-off (all)", "bakeoff", func() -> void: _command(model.to3d_args(model.three_d_providers)))
	_button(_model_actions, "Clean up", func() -> void: _command(model.cleanup_args(_shown_run)))
	_button(_model_actions, "Check", func() -> void: _command(model.check_args(_shown_run)))
	_export_btn = _button(_model_actions, "Export", func() -> void: _command(model.export_args(_shown_run)))


func _on_import_cad() -> void:
	import_cad.open(_selected_slug)
	import_cad.pivot = _import_pivot.text
	_import_hint.text = ""
	_import_dialog.popup_centered_ratio(0.6)


func _on_import_file_selected(path: String) -> void:
	import_cad.export_path = path
	import_cad.pivot = _import_pivot.text
	var args: PackedStringArray = import_cad.import_args()
	if args.is_empty():
		_import_hint.text = import_cad.error()
		return
	_command(args)


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
	if str(meta["slug"]) != _selected_slug:
		concept.references = PackedStringArray()
		_fill_references()
	_selected_slug = str(meta["slug"])
	_show_asset(_selected_slug)


func _show_asset(slug: String) -> void:
	_provider_pick.clear()
	_writer_pick.clear()
	_lineage.text = ""
	_lineage_title.text = "Select an image and press Lineage"
	var asset: Dictionary = {}
	for a: Variant in _assets:
		if str((a as Dictionary).get("slug", "")) == slug:
			asset = a
	if asset.is_empty():
		_title.text = "Concept: no asset selected"
		concept.load_asset({})
		_fill_sections()
		_desc_edit.text = ""
		_update_description_controls()
		_show_turnaround({})
		_show_model({})
		_sync_build_tabs()
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
	_presentation_pick.select(maxi(AssetConceptModel.PRESENTATIONS.find(concept.presentation), 0))
	_sync_build_tabs()
	var qrow: Dictionary = queue.find(slug)
	_title.text = "Concept: %s (%s)  issue %s  cost %s" % [concept.slug, concept.asset_class, qrow.get("issue_text", "-"), qrow.get("cost_text", "-")]
	_fill_pick(_provider_pick, "concept_image", concept.image_providers, concept.default_provider)
	_fill_pick(_writer_pick, "concept_writer", concept.prompt_writers, concept.default_writer)
	_fill_sections()
	if not concept.variants.is_empty():
		_show_lineage(str(concept.variants[-1]["id"]))
	request_estimates()


func _variant_card(v: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)
	var path: String = _abs_image_path(str(v["path"]))
	var tex_rect: TextureRect = TextureRect.new()
	tex_rect.custom_minimum_size = Vector2(0, 200)
	tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex_rect.texture = textures.get_texture(path) if str(v["path"]) != "" else null
	box.add_child(tex_rect)
	var why: String = textures.error_for(path)
	if why != "":
		var bad: Label = Label.new()
		bad.text = "unreadable image: %s" % why
		bad.add_theme_color_override("font_color", Color("#ff6b6b"))
		box.add_child(bad)
	var ref: Dictionary = v.get("reference", {})
	if not ref.is_empty():
		var rt: TextureRect = TextureRect.new()
		rt.name = "ReferenceThumb"
		rt.custom_minimum_size = Vector2(48, 48)
		rt.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rt.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rt.tooltip_text = "Reference (%s): %s" % [v.get("mode", ""), ref.get("name", "")]
		rt.texture = _load_texture(str(ref.get("path", "")))
		box.add_child(rt)
	var cap: Label = Label.new()
	var mark: String = " [Locked]" if v["state"] == "locked" else ""
	cap.text = "%s%s" % [v["caption"], mark]
	box.add_child(cap)
	var notes: LineEdit = LineEdit.new()
	notes.placeholder_text = "Notes (needed to refine)"
	box.add_child(notes)
	var row: HBoxContainer = HBoxContainer.new()
	box.add_child(row)
	var id: String = str(v["id"])
	_button(row, "Approve", func() -> void: _decide(id, true, notes.text))
	_button(row, "Reject", func() -> void: _decide(id, false, notes.text))
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
	# A refine re-passes its variant's own reference, so the picker does not apply to it.
	out["refine"] = concept.generate_more_args(3, img, _picked(_writer_pick), false, false)
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
	_cost_title.set_meta("title", "Cost: %s" % cost.total_text() if cost.slug != "" else "Cost")
	_set_toggle_text(_cost_title, _cost_text.get_parent().visible)
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
		_turn_views.remove_child(c)
		c.queue_free()
	_turn_provider.clear()
	if asset.is_empty():
		_turn_title.text = "Turnaround: no asset selected"
		turnaround.load_asset({})
		_brief_edit.text = ""
		_update_brief_buttons()
		return
	var brief_rel: String = str((asset.get("brief", {}) as Dictionary).get("path", "")) if asset.get("brief") is Dictionary else ""
	_turn_asset = asset
	turnaround.load_asset(asset, _read_text(brief_rel))
	_turn_title.text = "Turnaround: %s (%d of %d views)" % [turnaround.slug, turnaround.present_count(), turnaround.views.size()]
	_fill_pick(_turn_provider, "turnaround_image", concept_image_providers(), str(_selected.get("image", "")))
	for row: int in AssetTurnaroundModel.GRID_SIZE.y:
		for col: int in AssetTurnaroundModel.GRID_SIZE.x:
			var name: String = turnaround.view_at(Vector2i(col, row))
			if name == "":
				var spacer: Control = Control.new()
				spacer.name = "Corner_%d_%d" % [col, row]
				_turn_views.add_child(spacer)
			else:
				_turn_views.add_child(_view_card(turnaround.view(name)))
	_fit_turnaround.call_deferred()
	_brief_edit.text = turnaround.brief_text
	_update_brief_buttons()


func concept_image_providers() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for n: Variant in _providers.get("image", []):
		out.append(str(n))
	return out


## Square image size for the cross from the scroll area (the grid scrolls below a minimum).
func _fit_turnaround() -> void:
	if _turn_scroll == null:
		return
	_turn_cell = maxf(48.0, AssetTurnaroundModel.fit_cell_size(_turn_scroll.size - Vector2(8, 8)))
	for card: Node in _turn_views.get_children():
		var tex: Node = card.find_child("Image", true, false)
		if tex is Control:
			(tex as Control).custom_minimum_size = Vector2(_turn_cell, _turn_cell)


func _view_card(v: Dictionary) -> Control:
	var card: PanelContainer = PanelContainer.new()
	var name: String = str(v["view"])
	card.name = "View_" + name
	var box: VBoxContainer = VBoxContainer.new()
	card.add_child(box)
	var tex: TextureRect = TextureRect.new()
	tex.name = "Image"
	tex.custom_minimum_size = Vector2(_turn_cell, _turn_cell)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(tex)
	var cap: Label = Label.new()
	cap.text = str(v["caption"])
	cap.clip_text = true
	box.add_child(cap)
	if bool(v["present"]):
		tex.texture = _load_texture(str(v["path"]))
		tex.mouse_filter = Control.MOUSE_FILTER_STOP
		tex.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tex.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				show_view_overlay(name))
		var btns: HBoxContainer = HBoxContainer.new()
		box.add_child(btns)
		_est_button(btns, "Regenerate", "view", func() -> void: _command(turnaround.regenerate_args(name, _picked(_turn_provider))))
		var lin: Button = _button(btns, "Lineage", func() -> void: _show_view_lineage(name))
		lin.name = "Lineage"
	else:
		_est_button(box, "Generate", "view", func() -> void: _command(turnaround.regenerate_args(name, _picked(_turn_provider))))
	return card


## Opens a view larger in a simple overlay.
func show_view_overlay(name: String) -> void:
	var v: Dictionary = turnaround.view(name)
	if v.is_empty() or not bool(v["present"]):
		return
	for c: Node in _turn_overlay.get_children():
		_turn_overlay.remove_child(c)
		c.queue_free()
	var box: VBoxContainer = VBoxContainer.new()
	var tex: TextureRect = TextureRect.new()
	var side: float = 512.0
	tex.custom_minimum_size = Vector2(side, side)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tex.texture = _load_texture(str(v["path"]))
	box.add_child(tex)
	var cap: Label = Label.new()
	cap.text = str(v["caption"])
	box.add_child(cap)
	_turn_overlay.add_child(box)
	if is_inside_tree() and not has_meta("fixture"):
		_turn_overlay.popup_centered()


func _show_view_lineage(name: String) -> void:
	var v: Dictionary = turnaround.view(name)
	_status.text = "%s: %s (parent %s)" % [name, v.get("id", ""), _lineage_parent(str(v.get("id", "")))]


func _lineage_parent(id: String) -> String:
	for e: Variant in _turn_asset.get("lineage", []):
		var d: Dictionary = e
		if str(d.get("id", "")) == id:
			return str(d.get("parent", "-"))
	return "-"


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

func _views_key() -> String:
	return "model_views:%s" % model.slug


## Thumbnails of the turnaround views beside the provider dropdown: a radio choice for a
## single-image provider, an ordered multi-select otherwise. None picked means defaults.
func _fill_view_picker() -> void:
	for c: Node in _model_views.get_children():
		_model_views.remove_child(c)
		c.queue_free()
	var provider: String = _picked(_model_provider)
	var lbl: Label = Label.new()
	var single: bool = model.is_single(provider)
	lbl.text = "View (one):" if single else "Views (up to %d, in order):" % model.limit_for(provider)
	lbl.tooltip_text = "None picked: the provider's default views."
	_model_views.add_child(lbl)
	for v: Dictionary in model.turnaround_views:
		var name: String = str(v["view"])
		var order: int = model.picked_views.find(name)
		var b: Button = Button.new()
		b.toggle_mode = true
		b.button_pressed = order >= 0
		b.icon = _load_texture(str(v["path"]))
		b.expand_icon = true
		b.custom_minimum_size = Vector2(56, 56)
		b.text = ("%d " % (order + 1) if order >= 0 and not single else "") + name
		b.tooltip_text = name
		b.pressed.connect(func() -> void:
			model.toggle_view(name, _picked(_model_provider))
			choice.remember(_views_key(), model.picked_text(), true)
			_fill_view_picker()
			request_estimates())
		_model_views.add_child(b)


func _show_model(asset: Dictionary) -> void:
	for c: Node in _previews.get_children():
		c.queue_free()
	for c: Node in _run_list.get_children():
		c.queue_free()
	_model_provider.clear()
	for c: Node in _model_views.get_children():
		_model_views.remove_child(c)
		c.queue_free()
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
	model.load_asset(asset, _providers, _selected, reports, _three_d_max_views)
	model.restore_picks(str(choice.remembered.get(_views_key(), "")))
	_model_title.text = "Model: %s (%d runs)" % [model.slug, model.runs.size()]
	_fill_pick(_model_provider, "model_three_d", model.three_d_providers, model.default_provider)
	_fill_view_picker()
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
	_lineage_ref.texture = null
	_lineage_ref.visible = false
	for r: Dictionary in concept.lineage_of(id):
		var ref: Dictionary = r.get("reference", {})
		if not ref.is_empty():
			_lineage_ref.texture = _load_texture(str(ref.get("path", "")))
			_lineage_ref.tooltip_text = "Reference (%s): %s" % [r.get("mode", ""), ref.get("name", "")]
			_lineage_ref.visible = true
			lines.append("reference: %s (%s)" % [ref.get("name", ""), r.get("mode", "")])
			_lineage.text = "\n".join(lines)
			break


func _abs_image_path(rel: String) -> String:
	return AssetBackendResult.project_path(ProjectSettings.globalize_path("res://"), rel) if rel != "" else ""


func _load_texture(rel: String) -> Texture2D:
	return textures.get_texture(_abs_image_path(rel)) if rel != "" else null


## The provider name selected in a dropdown (item metadata: the text may carry a label).
func _picked(opt: OptionButton) -> String:
	return str(opt.get_item_metadata(opt.selected)) if opt.item_count > 0 and opt.selected >= 0 else ""


func _picked_provider() -> String:
	return _picked(_provider_pick)


## Fills a provider dropdown: remembered choice, else the effective selection, with the mock label.
func _fill_pick(opt: OptionButton, id: String, options: PackedStringArray, effective: String) -> void:
	var want: String = choice.resolve(id, options, effective)
	for p: String in options:
		opt.add_item(choice.label(p, options, effective))
		opt.set_item_metadata(opt.item_count - 1, p)
		if p == want:
			opt.select(opt.item_count - 1)


func _remember(id: String, opt: OptionButton) -> void:
	choice.remember(id, _picked(opt))
	request_estimates()


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
	if args.size() > 0 and args[0] == "concept":
		var n: int = 1
		var at: int = args.find("--n")
		if at >= 0 and at + 1 < args.size():
			n = maxi(int(args[at + 1]), 1)
		n *= maxi(args.count("--reference"), 1)  # --n variants per reference
		concept.in_flight = n
		_fill_sections()


func _on_finished(args: PackedStringArray, result: AssetBackendResult) -> void:
	_progress.visible = false
	if concept.in_flight > 0:
		concept.in_flight = 0
		_fill_sections()
	_set_busy(false)
	if not result.ok:
		_status.text = "Failed: asset %s" % " ".join(args)
		show_error(result.error)
		_pending_slug = ""
		return
	_status.text = "Done: asset %s" % " ".join(args)
	if _pending_slug != "":
		_selected_slug = _pending_slug
		_pending_slug = ""
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
