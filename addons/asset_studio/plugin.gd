@tool
extends EditorPlugin
## Adds the Asset Studio main-screen tab. The editor-only UI lives in studio_panel.gd;
## all logic is in the view models and BackendRunner, which the unit tests drive.

const StudioPanel: GDScript = preload("res://addons/asset_studio/studio_panel.gd")

var _panel: Control


func _enter_tree() -> void:
	_panel = StudioPanel.new() as Control
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_make_visible(false)


func _exit_tree() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible


func _get_plugin_name() -> String:
	return "Asset Studio"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("Node", "EditorIcons")
