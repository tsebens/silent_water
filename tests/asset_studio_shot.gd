extends Node
## Renders the Asset Studio panel with fixture data to PNGs (needs a display server):
##   xvfb-run -a godot --path . res://tests/asset_studio_shot.tscn -- <concept.png> [<turnaround.png> <model.png>]
## The first image is the Concept tab; with three, the Turnaround and Model tabs follow.
## Turnaround views and meshes are generated stand-ins; the manifest is the fixture's.

const SHOT_DIR: String = "res://build/asset_studio_shot/"


func _ready() -> void:
	var win: Window = get_window()
	win.size = Vector2i(1500, 780)
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var multi: bool = args.size() >= 3
	var fixture: String = "list_model.json" if multi else "list.json"
	if multi:
		_make_views()
	var panel: AssetStudioPanel = AssetStudioPanel.new()
	panel.set_meta("fixture", true)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.show_listing(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/asset_studio/" + fixture)) as Dictionary)
	if not multi:
		panel.show_error("OPENAI_API_KEY is not set (put it in tools/asset_pipeline/.env)")
	# Stubbed `--estimate` results, so the action buttons show their estimates.
	panel.cost.set_estimate("more", {"estimate": {"usd": 0.36, "calls": [{"basis": "estimated"}], "unknown": []}})
	panel.cost.set_estimate("refine", {"estimate": {"usd": 0.36, "calls": [{"basis": "estimated"}], "unknown": []}})
	panel.cost.set_estimate("bakeoff", {"estimate": {"usd": 0.75, "calls": [{"basis": "estimated"}], "unknown": []}})
	panel._refresh_est_labels()
	await _frames()
	_save(args[0] if args.size() > 0 else "asset_studio.png")
	if multi:
		panel._tabs.current_tab = 1
		await _frames()
		_save(args[1])
		panel._tabs.current_tab = 2
		_stand_in_meshes(panel)
		panel.model.angle_deg = 30.0
		panel.model.turntable = false
		await _frames()
		_save(args[2])
		panel.model.toggle_light()
		panel.model.toggle_wireframe()
		await _frames()
		_save(args[2].replace(".png", "_red_wire.png"))
	get_tree().quit()


func _frames() -> void:
	for i: int in 8:
		await get_tree().process_frame


func _save(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)


## Four silhouettes standing in for the turnaround views.
func _make_views() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOT_DIR))
	var widths: Dictionary = {"front": 90, "left": 150, "back": 90, "right": 150}
	for v: String in widths:
		var img: Image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.08, 0.12, 0.15))
		var w: int = widths[v]
		for y: int in range(80, 190):
			for x: int in range(128 - w / 2, 128 + w / 2):
				var dx: float = float(x - 128) / (w * 0.5)
				var dy: float = float(y - 135) / 55.0
				if dx * dx + dy * dy < 1.0:
					img.set_pixel(x, y, Color(0.55, 0.6, 0.62))
		img.save_png(ProjectSettings.globalize_path(SHOT_DIR + v + ".png"))


## The fixture runs have no GLB on disk; show primitives so the preview has something to light.
func _stand_in_meshes(panel: AssetStudioPanel) -> void:
	panel.model.toggle_compare("r1_tripo")
	panel.model.toggle_compare("r1_meshy")
	panel._rebuild_previews()
	var shapes: Array[Mesh] = [SphereMesh.new(), CapsuleMesh.new(), BoxMesh.new()]
	var i: int = 0
	for pv: Node in panel._previews.get_children():
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.mesh = shapes[i % shapes.size()]
		var holder: Node3D = Node3D.new()
		holder.add_child(mi)
		(pv as AssetModelPreview).show_node(holder, "%s  %d triangles" % [panel.model.compare_ids[i], AssetModelModel.count_triangles(mi.mesh)])
		i += 1
