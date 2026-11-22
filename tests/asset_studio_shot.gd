extends Node
## Renders the Asset Studio panel with fixture data to a PNG (needs a display server):
##   xvfb-run godot --path . res://tests/asset_studio_shot.tscn -- out.png

func _ready() -> void:
	var win: Window = get_window()
	win.size = Vector2i(1280, 720)
	var panel: AssetStudioPanel = AssetStudioPanel.new()
	panel.set_meta("fixture", true)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	panel.show_listing(JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/asset_studio/list.json")) as Dictionary)
	panel.show_error("OPENAI_API_KEY is not set (put it in tools/asset_pipeline/.env)")
	for i: int in 5:
		await get_tree().process_frame
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "asset_studio.png"
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
