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
	&"dev_overlay": [KEY_F1],
	&"dev_toggle_apex": [KEY_F4],
	&"dev_single_player": [KEY_F5],
	&"activate": [KEY_E],
	&"pilot_planes_rise": [KEY_R],
	&"pilot_planes_dive": [KEY_F],
	&"pilot_blow": [KEY_KP_8],
	&"pilot_flood": [KEY_KP_2],
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
