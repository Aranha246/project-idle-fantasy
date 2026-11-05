class_name InputActions
extends RefCounted
## Registers the game's action map at runtime.
##
## Godot already ships the `ui_*` navigation actions, which cover keyboard
## (arrows / Enter / Escape) and gamepad (d-pad / stick / A / B) menu navigation
## out of the box. This helper only adds the actions the game itself needs, and
## does so in code so the mapping survives project settings edits and can be
## asserted by the automated tests.
##
## Registering here instead of in `project.godot` keeps the serialized
## `InputEvent` structures out of the config file, where a hand edit would be
## easy to corrupt.

## Toggles the pause overlay. Esc on keyboard, Start on a gamepad.
const PAUSE_ACTION: StringName = &"pause"

## Prefix shared by every window-toggle action (e.g. `window_character`).
const WINDOW_ACTION_PREFIX: String = "window_"

## Every action this helper owns statically, so tests can verify the map in one
## place. Per-window actions are created on demand from `WindowRegistry`.
const MANAGED_ACTIONS: Array[StringName] = [PAUSE_ACTION]


## Adds any missing action, leaving existing user bindings untouched.
static func ensure_default_actions() -> void:
	_ensure_pause()


## Returns the input action name that toggles the window `window_id`.
static func window_action(window_id: StringName) -> StringName:
	return StringName(WINDOW_ACTION_PREFIX + String(window_id))


## Rewrites every window-toggle action so exactly `bindings` (window id ->
## keycode) is bound. Entries without a usable key are skipped so a partially
## loaded settings file can never leave a window unreachable.
static func apply_window_bindings(bindings: Dictionary) -> void:
	for window_id: Variant in bindings.keys():
		var keycode: int = int(bindings[window_id])
		if keycode == KEY_NONE:
			continue
		_set_single_key_binding(window_action(StringName(window_id)), keycode)


static func _set_single_key_binding(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.35)
	else:
		# Rebindings must fully replace the old key, not add to it.
		InputMap.action_erase_events(action)

	var new_event: InputEventKey = InputEventKey.new()
	new_event.physical_keycode = keycode
	InputMap.action_add_event(action, new_event)


static func _ensure_pause() -> void:
	if not InputMap.has_action(PAUSE_ACTION):
		InputMap.add_action(PAUSE_ACTION, 0.5)

	_add_key_if_missing(PAUSE_ACTION, KEY_ESCAPE)
	_add_joypad_button_if_missing(PAUSE_ACTION, JOY_BUTTON_START)


static func _add_key_if_missing(action: StringName, keycode: Key) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.physical_keycode == keycode:
			return
	var new_event: InputEventKey = InputEventKey.new()
	new_event.physical_keycode = keycode
	InputMap.action_add_event(action, new_event)


static func _add_joypad_button_if_missing(action: StringName, button_index: JoyButton) -> void:
	for event: InputEvent in InputMap.action_get_events(action):
		var button_event: InputEventJoypadButton = event as InputEventJoypadButton
		if button_event != null and button_event.button_index == button_index:
			return
	var new_event: InputEventJoypadButton = InputEventJoypadButton.new()
	new_event.button_index = button_index
	InputMap.action_add_event(action, new_event)
