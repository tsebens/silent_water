class_name InputSetup
extends RefCounted
## Registers the game's input actions in code so project.godot stays readable.

const ACTIONS: Dictionary = {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"sneak": [KEY_SHIFT],
	&"release_mouse": [KEY_ESCAPE],
}
const MOUSE_ACTIONS: Dictionary = {
	&"interact": MOUSE_BUTTON_LEFT,
}


static func ensure_actions() -> void:
	for action: StringName in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for keycode: int in ACTIONS[action]:
			var ev: InputEventKey = InputEventKey.new()
			ev.physical_keycode = keycode as Key
			InputMap.action_add_event(action, ev)
	for action: StringName in MOUSE_ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var mb: InputEventMouseButton = InputEventMouseButton.new()
		mb.button_index = MOUSE_ACTIONS[action] as MouseButton
		InputMap.action_add_event(action, mb)
