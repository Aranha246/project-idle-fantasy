class_name WindowHostUI
extends Control
## Container that hosts every floating game window.
##
## Each window is wrapped in a `GameWindow` (draggable, minimizable, maximizable,
## closable) and registered here. The host owns no window state of its own: it
## mirrors `WindowManager`, restores each window's persisted geometry through
## `SettingsManager`, and reports geometry changes back so they survive a restart.
##
## Windows are created up front and simply hidden while closed, so opening a
## window never stalls on building its content and every window keeps its
## position for the whole session.

## Gap kept between the host edges and the work area windows may occupy.
const WORK_AREA_MARGIN: float = 6.0

## Window id -> its `GameWindow`.
var _windows: Dictionary = {}

var _work_area: Rect2 = Rect2()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The host itself is transparent to the mouse so clicks on empty space reach
	# the game; its window children still receive their own input normally.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

	SignalBus.window_visibility_changed.connect(_on_window_visibility_changed)
	resized.connect(_refresh_work_area)
	_refresh_work_area()


## Wraps `content` in a floating window and takes ownership of it. Returns the
## created window, or `null` when `window_id` is not a known window.
func register_window(window_id: StringName, content: Control) -> GameWindow:
	var definition: WindowData = WindowRegistry.get_definition(window_id)
	if definition == null:
		push_error("WindowHostUI: '%s' is not a registered window." % window_id)
		if content != null:
			content.queue_free()
		return null

	var window: GameWindow = GameWindow.new()
	add_child(window)
	window.setup(window_id, definition.title, content, _work_area)
	window.close_requested.connect(_on_window_close_requested)
	window.state_changed.connect(_on_window_state_changed)
	window.apply_layout(SettingsManager.get_window_layout(window_id))
	window.visible = WindowManager.is_open(window_id)

	_windows[window_id] = window
	return window


## The floating window bound to `window_id`, or `null` when it was never
## registered. Named to avoid clashing with `Node.get_window()`.
func get_game_window(window_id: StringName) -> GameWindow:
	return _windows.get(window_id) as GameWindow


## Every registered window id, in registration order.
func get_window_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for window_id: Variant in _windows.keys():
		ids.append(StringName(window_id))
	return ids


## The rectangle in local coordinates that windows are allowed to occupy.
func get_work_area() -> Rect2:
	return _work_area


## Applies the shared UI theme to every window, keeping them visually consistent
## with the rest of the HUD.
func set_ui_theme(ui_theme: Theme) -> void:
	for window: GameWindow in _windows.values():
		window.theme = ui_theme


# --- Internals -------------------------------------------------------------

func _refresh_work_area() -> void:
	var area: Rect2 = Rect2(
		Vector2(WORK_AREA_MARGIN, WORK_AREA_MARGIN),
		(size - Vector2(WORK_AREA_MARGIN, WORK_AREA_MARGIN) * 2.0).max(Vector2.ZERO)
	)
	if area == _work_area:
		return
	_work_area = area
	for window: GameWindow in _windows.values():
		window.set_work_area(area)


func _on_window_visibility_changed(window_id: StringName, is_open: bool) -> void:
	var window: GameWindow = get_game_window(window_id)
	if window != null:
		window.visible = is_open


func _on_window_close_requested(window_id: StringName) -> void:
	WindowManager.set_open(window_id, false)


func _on_window_state_changed(window_id: StringName) -> void:
	var window: GameWindow = get_game_window(window_id)
	if window == null:
		return
	var layout: Dictionary = window.get_layout()
	SettingsManager.set_window_position(window_id, layout.get("position", window.position))
	SettingsManager.set_window_minimized(window_id, bool(layout.get("minimized", false)))
	SettingsManager.set_window_maximized(window_id, bool(layout.get("maximized", false)))
