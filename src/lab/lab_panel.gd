class_name LabPanel
extends PanelContainer
## The terrain lab's parameter panel: a developer tool, not an in-world
## instrument. It builds one bound control for every exported property of the
## [SiteSpec] being edited (and the specs, shelves and constraints inside it)
## and of the [CanyonSite] tunables, by reflection, so a new export shows up
## here without touching this file.

signal changed
signal regenerate_requested
signal lighting_toggled
signal back_requested

const SECTION_SPEC: String = "spec"
const SECTION_SITE: String = "site"
const ROW_LABEL_WIDTH: float = 150.0
const NUMBER_LIMIT: float = 100000.0
## Constraint kinds the "add" button offers.
static var constraint_kinds: Array[Script] = [FlatPad, Corridor, ClearColumn]

var spec: SiteSpec
## A CanyonSite that is never added to a tree: it holds the tunables the lab
## copies onto each site it generates.
var tunables: CanyonSite

var _controls: Dictionary = {}
var _readout: Label
var _auto: CheckBox
var _body: VBoxContainer


## Exported properties of [param obj]'s own scripts (base classes included), in
## declaration order. Group markers are not properties and are left out.
static func exported_properties(obj: Object) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p: Dictionary in obj.get_property_list():
		var usage: int = p["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE != 0 and usage & PROPERTY_USAGE_EDITOR != 0:
			out.append(p)
	return out


func setup(new_spec: SiteSpec, new_tunables: CanyonSite) -> void:
	spec = new_spec
	tunables = new_tunables
	_controls.clear()
	for child: Node in get_children():
		child.queue_free()
	custom_minimum_size = Vector2(400.0, 0.0)
	var root: VBoxContainer = VBoxContainer.new()
	add_child(root)
	root.add_child(_build_header())
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_body.add_child(_heading("Site spec"))
	_build_properties(_body, spec, SECTION_SPEC, ["seed"])
	_body.add_child(_heading("Canyon tunables"))
	_build_properties(_body, tunables, SECTION_SITE, ["spec"])


## The control bound to [param prop] of the [param section] ([constant
## SECTION_SPEC] or [constant SECTION_SITE]), or null.
func control_for(section: String, prop: String) -> Control:
	return _controls.get(section + "/" + prop) as Control


func set_readout(text: String) -> void:
	if _readout != null:
		_readout.text = text


func auto_regenerate() -> bool:
	return _auto != null and _auto.button_pressed


# --- construction -----------------------------------------------------------

func _build_header() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var title: Label = Label.new()
	title.text = "Terrain lab"
	box.add_child(title)
	var seed_prop: Dictionary = {}
	for p: Dictionary in exported_properties(spec):
		if p["name"] == "seed":
			seed_prop = p
	var seed_row: HBoxContainer = _row("seed", seed_prop, spec, SECTION_SPEC + "/seed")
	var rnd: Button = Button.new()
	rnd.text = "Random"
	rnd.pressed.connect(func() -> void:
		(control_for(SECTION_SPEC, "seed") as SpinBox).value = randi() % 1000000
	)
	seed_row.add_child(rnd)
	box.add_child(seed_row)
	var buttons: HBoxContainer = HBoxContainer.new()
	var regen: Button = Button.new()
	regen.text = "Regenerate"
	regen.pressed.connect(func() -> void: regenerate_requested.emit())
	buttons.add_child(regen)
	_auto = CheckBox.new()
	_auto.text = "Auto"
	_auto.button_pressed = true
	_auto.tooltip_text = "Regenerate on every change while generation is quick"
	buttons.add_child(_auto)
	var light: Button = Button.new()
	light.text = "Day / night"
	light.pressed.connect(func() -> void: lighting_toggled.emit())
	buttons.add_child(light)
	var back: Button = Button.new()
	back.text = "Back"
	back.pressed.connect(func() -> void: back_requested.emit())
	buttons.add_child(back)
	box.add_child(buttons)
	_readout = Label.new()
	_readout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_readout)
	return box


func _heading(text: String) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.add_theme_color_override(&"font_color", Color(0.9, 0.8, 0.4))
	return l


## One row per exported property of [param obj], with a bound control each.
## Controls of top-level objects are registered under section/name.
func _build_properties(parent: Control, obj: Object, section: String, skip: Array[String]) -> void:
	for p: Dictionary in obj.get_property_list():
		var usage: int = p["usage"]
		if usage & PROPERTY_USAGE_GROUP != 0 and usage & PROPERTY_USAGE_EDITOR == 0 and p["name"] != "":
			var g: Label = _heading("— " + str(p["name"]))
			parent.add_child(g)
			continue
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		if skip.has(p["name"]):
			continue
		var key: String = "" if section == "" else section + "/" + str(p["name"])
		parent.add_child(_row(str(p["name"]), p, obj, key))


func _row(label_text: String, prop: Dictionary, obj: Object, key: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(ROW_LABEL_WIDTH, 0.0)
	label.clip_text = true
	label.tooltip_text = label_text
	row.add_child(label)
	var editor: Control = _make_editor(obj, prop)
	editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(editor)
	if key != "":
		_controls[key] = editor
	return row


func _make_editor(obj: Object, prop: Dictionary) -> Control:
	var pname: StringName = prop["name"]
	var value: Variant = obj.get(pname)
	match int(prop["type"]):
		TYPE_BOOL:
			var cb: CheckBox = CheckBox.new()
			cb.button_pressed = value
			cb.toggled.connect(func(on: bool) -> void: _apply(obj, pname, on))
			return cb
		TYPE_INT:
			var sb: SpinBox = _spin(float(value), 1.0, prop)
			sb.value_changed.connect(func(v: float) -> void: _apply(obj, pname, int(v)))
			return sb
		TYPE_FLOAT:
			var sb: SpinBox = _spin(float(value), 0.01, prop)
			sb.value_changed.connect(func(v: float) -> void: _apply(obj, pname, v))
			return sb
		TYPE_STRING:
			var le: LineEdit = LineEdit.new()
			le.text = value
			le.text_changed.connect(func(t: String) -> void: _apply(obj, pname, t))
			return le
		TYPE_COLOR:
			var cp: ColorPickerButton = ColorPickerButton.new()
			cp.color = value
			cp.color_changed.connect(func(c: Color) -> void: _apply(obj, pname, c))
			return cp
		TYPE_VECTOR2:
			return _vector_editor(obj, pname, 2, prop)
		TYPE_VECTOR3:
			return _vector_editor(obj, pname, 3, prop)
		TYPE_AABB:
			return _aabb_editor(obj, pname, prop)
		TYPE_PACKED_VECTOR2_ARRAY:
			return _points_editor(obj, pname)
		TYPE_ARRAY:
			return _list_editor(obj, pname, prop)
		TYPE_OBJECT:
			if str(prop["hint_string"]) == "Curve":
				return _curve_editor(obj, pname)
	var unsupported: Label = Label.new()
	unsupported.text = "(not editable)"
	return unsupported


func _spin(value: float, step: float, prop: Dictionary) -> SpinBox:
	var sb: SpinBox = SpinBox.new()
	sb.min_value = -NUMBER_LIMIT
	sb.max_value = NUMBER_LIMIT
	if int(prop.get("hint", 0)) == PROPERTY_HINT_RANGE:
		var parts: PackedStringArray = str(prop["hint_string"]).split(",")
		if parts.size() >= 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			sb.min_value = float(parts[0])
			sb.max_value = float(parts[1])
	if int(prop["type"]) == TYPE_INT:
		sb.max_value = minf(sb.max_value, 2147483647.0)
		sb.min_value = maxf(sb.min_value, -2147483647.0)
	sb.step = step
	sb.value = value
	return sb


func _vector_editor(obj: Object, pname: StringName, dims: int, prop: Dictionary) -> Control:
	var box: HBoxContainer = HBoxContainer.new()
	var axes: PackedStringArray = PackedStringArray(["x", "y", "z"])
	var boxes: Array[SpinBox] = []
	var current: Variant = obj.get(pname)
	for i: int in range(dims):
		var sb: SpinBox = _spin(current[i], 0.01, {"type": TYPE_FLOAT})
		sb.prefix = axes[i]
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(sb)
		boxes.append(sb)
	for sb: SpinBox in boxes:
		sb.value_changed.connect(func(_v: float) -> void:
			var v: Variant = Vector2() if dims == 2 else Vector3()
			for i: int in range(dims):
				v[i] = boxes[i].value
			_apply(obj, pname, v)
		)
	return box


func _aabb_editor(obj: Object, pname: StringName, _prop: Dictionary) -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	var boxes: Array[SpinBox] = []
	var current: AABB = obj.get(pname)
	var prefixes: PackedStringArray = PackedStringArray(["x ", "y ", "z ", "w ", "h ", "d "])
	var values: Array[float] = [current.position.x, current.position.y, current.position.z, current.size.x, current.size.y, current.size.z]
	for r: int in range(2):
		var row: HBoxContainer = HBoxContainer.new()
		for c: int in range(3):
			var sb: SpinBox = _spin(values[r * 3 + c], 0.01, {"type": TYPE_FLOAT})
			sb.prefix = prefixes[r * 3 + c]
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(sb)
			boxes.append(sb)
		box.add_child(row)
	for sb: SpinBox in boxes:
		sb.value_changed.connect(func(_v: float) -> void:
			_apply(obj, pname, AABB(
				Vector3(boxes[0].value, boxes[1].value, boxes[2].value),
				Vector3(boxes[3].value, boxes[4].value, boxes[5].value)))
		)
	return box


## "x,z; x,z; ..." text for a list of points.
static func points_to_text(points: PackedVector2Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for p: Vector2 in points:
		parts.append("%s,%s" % [String.num(p.x, 3), String.num(p.y, 3)])
	return "; ".join(parts)


## Inverse of [method points_to_text]; malformed entries are skipped.
static func text_to_points(text: String) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	for entry: String in text.split(";", false):
		var xy: PackedStringArray = entry.strip_edges().split(",", false)
		if xy.size() == 2 and xy[0].strip_edges().is_valid_float() and xy[1].strip_edges().is_valid_float():
			out.append(Vector2(float(xy[0]), float(xy[1])))
	return out


func _points_editor(obj: Object, pname: StringName) -> Control:
	var le: LineEdit = LineEdit.new()
	le.text = points_to_text(obj.get(pname))
	le.placeholder_text = "x,z; x,z; ..."
	le.tooltip_text = "Points as x,z pairs separated by semicolons. Enter to apply."
	le.text_submitted.connect(func(t: String) -> void: _apply(obj, pname, text_to_points(t)))
	le.focus_exited.connect(func() -> void: _apply(obj, pname, text_to_points(le.text)))
	return le


## A curve is edited as "t,value; t,value" points (empty = no curve).
func _curve_editor(obj: Object, pname: StringName) -> Control:
	var le: LineEdit = LineEdit.new()
	var existing: Curve = obj.get(pname) as Curve
	if existing != null:
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in range(existing.point_count):
			pts.append(existing.get_point_position(i))
		le.text = points_to_text(pts)
	le.placeholder_text = "none (t,value; t,value; t 0..1)"
	le.tooltip_text = "Curve points as t,value pairs, t along the canyon from 0 (south) to 1 (north). Empty means no curve. Enter to apply."
	var apply: Callable = func(t: String) -> void:
		var pts: PackedVector2Array = text_to_points(t)
		if pts.is_empty():
			_apply(obj, pname, null)
			return
		var c: Curve = Curve.new()
		c.min_value = 0.0
		c.max_value = 4.0
		for p: Vector2 in pts:
			c.add_point(Vector2(clampf(p.x, 0.0, 1.0), clampf(p.y, 0.0, 4.0)))
		_apply(obj, pname, c)
	le.text_submitted.connect(apply)
	le.focus_exited.connect(func() -> void: apply.call(le.text))
	return le


## A list of sub-resources (shelves or constraints) with add and remove.
func _list_editor(obj: Object, pname: StringName, prop: Dictionary) -> Control:
	var hint: String = str(prop["hint_string"])
	var kinds: Array[Script] = []
	if hint.ends_with("ShelfSpec"):
		kinds = [ShelfSpec]
	elif hint.ends_with("SiteConstraint"):
		kinds = constraint_kinds
	var box: VBoxContainer = VBoxContainer.new()
	if kinds.is_empty():
		var unsupported: Label = Label.new()
		unsupported.text = "(not editable)"
		box.add_child(unsupported)
		return box
	var items: VBoxContainer = VBoxContainer.new()
	box.add_child(items)
	var add_row: HBoxContainer = HBoxContainer.new()
	var kind_pick: OptionButton = OptionButton.new()
	for k: Script in kinds:
		kind_pick.add_item(str(k.get_global_name()))
	add_row.add_child(kind_pick)
	var add: Button = Button.new()
	add.text = "Add"
	add_row.add_child(add)
	box.add_child(add_row)
	var rebuild: Callable = func() -> void: pass
	rebuild = func() -> void:
		for child: Node in items.get_children():
			items.remove_child(child)
			child.queue_free()
		var arr: Array = obj.get(pname)
		for i: int in range(arr.size()):
			items.add_child(_element_editor(arr, i, rebuild))
	add.pressed.connect(func() -> void:
		var arr: Array = obj.get(pname)
		arr.append(kinds[kind_pick.selected].new())
		rebuild.call()
		changed.emit()
	)
	rebuild.call()
	return box


func _element_editor(arr: Array, index: int, rebuild: Callable) -> Control:
	var element: Object = arr[index]
	var frame: PanelContainer = PanelContainer.new()
	var v: VBoxContainer = VBoxContainer.new()
	frame.add_child(v)
	var head: HBoxContainer = HBoxContainer.new()
	var title: Label = Label.new()
	title.text = "%d · %s" % [index, str((element.get_script() as Script).get_global_name())]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var remove: Button = Button.new()
	remove.text = "Remove"
	remove.pressed.connect(func() -> void:
		arr.remove_at(index)
		rebuild.call()
		changed.emit()
	)
	head.add_child(remove)
	v.add_child(head)
	_build_properties(v, element, "", [])
	return frame


func _apply(obj: Object, pname: StringName, value: Variant) -> void:
	obj.set(pname, value)
	changed.emit()
