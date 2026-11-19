extends Node

## Registers prototype actions in code so the binding list stays next to the
## systems that use them and does not depend on serialized InputEvent text.
## Keys use physical positions: WASD on a US keyboard, ZQSD on AZERTY.
## Q cycles weapons, X and V lean.
## F1 flips debug_enabled. Starts off, same as the resource labels and the zoom cap.

var debug_enabled := false

func _enter_tree() -> void:
	_bind_key(&"move_forward", KEY_W)
	_bind_key(&"move_forward", KEY_UP)
	_bind_key(&"move_back", KEY_S)
	_bind_key(&"move_back", KEY_DOWN)
	_bind_key(&"move_left", KEY_A)
	_bind_key(&"move_left", KEY_LEFT)
	_bind_key(&"move_right", KEY_D)
	_bind_key(&"move_right", KEY_RIGHT)
	_bind_key(&"lean_left", KEY_X)
	_bind_key(&"lean_right", KEY_V)
	_bind_key(&"cycle_weapon", KEY_Q)
	_bind_key(&"crouch", KEY_CTRL)
	_bind_key(&"sprint", KEY_SHIFT)
	_bind_key(&"interact", KEY_F)
	_bind_key(&"inventory", KEY_TAB)
	_bind_key(&"tech_tree", KEY_H)
	_bind_key(&"debug_toggle", KEY_F1)
	_bind_key(&"drop_item", KEY_G)
	for hotbar_index in 9:
		_bind_key(&"hotbar_%d" % (hotbar_index + 1), (KEY_1 + hotbar_index) as Key)
	_bind_key(&"camera_yaw_left", KEY_Z)
	# German QWERTZ prints Z on the US Y key. Binding both makes the labeled Z key orbit.
	_bind_key(&"camera_yaw_left", KEY_Y)
	_bind_key(&"camera_yaw_right", KEY_C)
	_bind_mouse(&"fire", MOUSE_BUTTON_LEFT)
	_bind_key(&"build_rotate", KEY_R)
	_bind_key(&"build_level_up", KEY_PAGEUP)
	_bind_key(&"build_level_down", KEY_PAGEDOWN)
	_bind_key(&"build_next", KEY_BRACKETRIGHT)
	_bind_key(&"build_prev", KEY_BRACKETLEFT)
	_bind_key(&"build_debug", KEY_F3)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_toggle"):
		debug_enabled = not debug_enabled


func _bind_key(action: StringName, keycode: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing: InputEvent in InputMap.action_get_events(action):
		if existing is InputEventKey and (existing as InputEventKey).physical_keycode == keycode:
			return
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	InputMap.action_add_event(action, event)


func _bind_mouse(action: StringName, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing: InputEvent in InputMap.action_get_events(action):
		if existing is InputEventMouseButton and (existing as InputEventMouseButton).button_index == button:
			return
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
