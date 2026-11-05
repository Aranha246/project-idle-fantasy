extends Node
## Autoload that owns the runtime state of the game's floating windows.
##
## It remembers which windows are open, reacts to the per-window toggle actions
## registered by `InputActions` (one action per window, named `window_<id>`), and
## persists every change through `SettingsManager`, so the layout survives a
## restart.
##
## The widgets themselves live in the scene, not here: they follow
## `SignalBus.window_visibility_changed` instead of reaching into this singleton,
## which keeps the UI decoupled from the state that drives it.

## Window id -> whether it is currently open.
var _open: Dictionary = {}


func _ready() -> void:
	# Window shortcuts are ignored while the pause overlay is up, matching how
	# the rest of the game stops responding to gameplay input when paused.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	sync_from_settings()


## Re-reads the persisted open/closed state of every window and applies it.
##
## Called once at boot. It is also the hook the automated tests use to simulate a
## client restart: reloading `settings.cfg` and calling this restores exactly the
## window states the game would have started with.
func sync_from_settings() -> void:
	for definition: WindowData in WindowRegistry.get_definitions():
		var layout: Dictionary = SettingsManager.get_window_layout(definition.window_id)
		set_open(definition.window_id, bool(layout.get("open", definition.open_by_default)))
	_ensure_a_window_is_open()


## Reopens the authored default windows when a restored layout hides all of them.
##
## With every window closed the interface collapses to a bare menu bar over an
## empty work area, which is indistinguishable from the game failing to render
## its panels. That state is easy to reach by accident because the Character
## window is the only one open out of the box, so it must never survive a boot.
## Only the windows that opted into opening by default are reopened; every
## dragged position and size is left exactly as it was.
func _ensure_a_window_is_open() -> void:
	if not get_open_window_ids().is_empty():
		return
	for definition: WindowData in WindowRegistry.get_definitions():
		if definition.open_by_default:
			set_open(definition.window_id, true)


func _unhandled_input(event: InputEvent) -> void:
	# `is_action_pressed` ignores key-echo by default, so holding a shortcut does
	# not repeat the toggle. A focused `LineEdit` consumes its keys first, which
	# is what stops rebinding a key from also opening a window.
	for window_id: StringName in WindowRegistry.get_window_ids():
		if event.is_action_pressed(InputActions.window_action(window_id)):
			toggle_window(window_id)
			get_viewport().set_input_as_handled()
			return


## Returns whether `window_id` is currently open.
func is_open(window_id: StringName) -> bool:
	return bool(_open.get(window_id, false))


## Every currently open window id, in menu-bar order.
func get_open_window_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for window_id: StringName in WindowRegistry.get_window_ids():
		if is_open(window_id):
			ids.append(window_id)
	return ids


## Opens or closes `window_id`, persists the change and notifies the UI. Unknown
## ids and no-op requests are ignored so callers can fire blindly.
func set_open(window_id: StringName, is_open: bool) -> void:
	if not WindowRegistry.has_window(window_id):
		return
	if is_open == self.is_open(window_id):
		return

	_open[window_id] = is_open
	SettingsManager.set_window_open(window_id, is_open)
	SignalBus.window_visibility_changed.emit(window_id, is_open)


## Flips the open state of `window_id`.
func toggle_window(window_id: StringName) -> void:
	set_open(window_id, not is_open(window_id))


## Restores the authored open/closed state of every window.
func reset_to_defaults() -> void:
	for definition: WindowData in WindowRegistry.get_definitions():
		set_open(definition.window_id, definition.open_by_default)


## Snapshot of every window's open state, used by the automated tests.
func get_state() -> Dictionary:
	return _open.duplicate()
