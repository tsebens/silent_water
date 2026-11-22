@tool
class_name AssetStudioPanel
extends VBoxContainer
## The Asset Studio main-screen tab: Queue on the left, Concept for the selected asset on
## the right. Thin UI over AssetQueueModel, AssetConceptModel and AssetBackendRunner; every
## action is a backend command, so this never talks to a service.

const THUMB: Vector2 = Vector2(220, 220)

var runner: AssetBackendRunner
var queue: AssetQueueModel = AssetQueueModel.new()
var concept: AssetConceptModel = AssetConceptModel.new()

var _assets: Array = []
var _providers: Dictionary = {}
var _selected: Dictionary = {}
var _selected_slug: String = ""
var _tree: Tree
var _grid: GridContainer
var _title: Label
var _status: Label
var _progress: ProgressBar
var _error: RichTextLabel
var _provider_pick: OptionButton
var _lineage: RichTextLabel
var _refresh_btn: Button
var _more_btn: Button
var _lineage_title: Label


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
	if Engine.is_editor_hint() and not has_meta("fixture"):
		refresh()


func refresh() -> void:
	runner.run(PackedStringArray(["list"]))


## Fill the panel from a `list` output dictionary without running the backend (tests, screenshots).
func show_listing(listing: Dictionary) -> void:
	_assets = listing.get("assets", [])
	_providers = listing.get("providers", {})
	_selected = listing.get("selected", {})
	queue.load_assets(_assets)
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
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	_tree = Tree.new()
	_tree.columns = 5
	_tree.column_titles_visible = true
	for i: int in 5:
		_tree.set_column_title(i, ["Asset", "Class", "Stage", "Issue", "Last result"][i])
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 120)
	_tree.set_column_expand(4, true)
	_tree.custom_minimum_size = Vector2(440, 0)
	_tree.hide_root = true
	_tree.item_selected.connect(_on_row_selected)
	split.add_child(_tree)

	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	_title = Label.new()
	_title.text = "Concept"
	right.add_child(_title)
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
	more.add_child(_provider_pick)
	_more_btn = Button.new()
	_more_btn.text = "Generate more"
	_more_btn.pressed.connect(_on_generate_more)
	more.add_child(_more_btn)

	_lineage_title = Label.new()
	_lineage_title.text = "Lineage"
	right.add_child(_lineage_title)
	_lineage = RichTextLabel.new()
	_lineage.custom_minimum_size = Vector2(0, 110)
	_lineage.bbcode_enabled = false
	right.add_child(_lineage)

	_error = RichTextLabel.new()
	_error.bbcode_enabled = true
	_error.fit_content = true
	_error.selection_enabled = true
	_error.visible = false
	add_child(_error)


func _fill_queue() -> void:
	_tree.clear()
	var root: TreeItem = _tree.create_item()
	for r: Dictionary in queue.rows:
		var item: TreeItem = _tree.create_item(root)
		item.set_text(0, str(r["slug"]))
		item.set_text(1, str(r["class"]))
		item.set_text(2, str(r["stage"]))
		item.set_text(3, str(r["issue_text"]))
		item.set_text(4, str(r["last_result"]))
		item.set_metadata(0, str(r["slug"]))
		if str(r["slug"]) == _selected_slug:
			item.select(0)


func _on_row_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	_selected_slug = str(item.get_metadata(0))
	_show_asset(_selected_slug)


func _show_asset(slug: String) -> void:
	for c: Node in _grid.get_children():
		c.queue_free()
	_provider_pick.clear()
	_lineage.text = ""
	var asset: Dictionary = {}
	for a: Variant in _assets:
		if str((a as Dictionary).get("slug", "")) == slug:
			asset = a
	if asset.is_empty():
		_title.text = "Concept: no asset selected"
		return
	concept.load_asset(asset, _providers, _selected)
	_title.text = "Concept: %s (%s)" % [concept.slug, concept.asset_class]
	for p: String in concept.image_providers:
		_provider_pick.add_item(p)
		if p == concept.default_provider:
			_provider_pick.select(_provider_pick.item_count - 1)
	for v: Dictionary in concept.variants:
		_grid.add_child(_variant_card(v))
	if not concept.variants.is_empty():
		_show_lineage(str(concept.variants[-1]["id"]))


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
	_button(row, "Refine", func() -> void: _command(concept.refine_args(id, notes.text, _picked_provider())))
	_button(row, "Lineage", func() -> void: _show_lineage(id))
	return card


func _button(parent: Control, text: String, cb: Callable) -> void:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)


func _show_lineage(id: String) -> void:
	_lineage_title.text = "Lineage of %s" % id
	var lines: PackedStringArray = PackedStringArray()
	for r: Dictionary in concept.lineage_of(id):
		lines.append("%s  %s  %s/%s  parent: %s\n    %s" % [
			r["id"], r["kind"], r["provider"], r["model"], str(r["parent"]) if r["parent"] != null else "none", r["prompt"]
		])
	_lineage.text = "\n".join(lines)


func _load_texture(rel: String) -> Texture2D:
	var abs_path: String = ProjectSettings.globalize_path("res://").path_join(rel)
	if rel == "" or not FileAccess.file_exists(abs_path):
		return null
	var img: Image = Image.load_from_file(abs_path)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _picked_provider() -> String:
	if _provider_pick.item_count == 0:
		return ""
	return _provider_pick.get_item_text(_provider_pick.selected)


func _on_generate_more() -> void:
	_command(concept.generate_more_args(3, _picked_provider()))


func _command(args: PackedStringArray) -> void:
	if args.is_empty():
		show_error("Refine needs notes: write what to change in the box under the variant.")
		return
	if not runner.run(args):
		show_error("A backend command is already running.")


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
	_more_btn.disabled = busy
