class_name GameWindow
extends PanelContainer
## One floating, player-managed window: a draggable title bar with minimize,
## maximize and close buttons, plus a scrollable body that hosts a single content
## control.
##
## The widget owns presentation and geometry only. It never talks to a manager
## directly; it reports intent through `close_requested` / `state_changed`, and
## the scene decides what to persist. That keeps the window UI free of any game
## or settings state.
##
## Window frames use the same colours and corner radius as every other panel in
## the game, so floating windows stay visually consistent with the HUD.

## Emitted when the player presses the close button.
signal close_requested(window_id: StringName)

## Emitted after a drag, a minimize or a maximize completes, so the owner can
## persist the new geometry. Not emitted continuously while dragging.
signal state_changed(window_id: StringName)

const BODY_MARGIN: float = 8.0
const TITLE_MARGIN_H: float = 10.0
const TITLE_MARGIN_V: float = 4.0
const TITLE_FONT_SIZE: int = 14
const MIN_WIDTH: float = 220.0
const MIN_VISIBLE_TITLE: float = 64.0
const MAX_WORK_AREA_RATIO: float = 0.95
const BUTTON_MIN_SIZE: Vector2 = Vector2(26.0, 22.0)

## Stable id of this window, matching `WindowRegistry`.
var window_id: StringName = &""

var _title_bar: PanelContainer = null
var _title_label: Label = null
var _body: MarginContainer = null
var _scroll: ScrollContainer = null
var _content: Control = null

var _work_area: Rect2 = Rect2()

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _restore_rect: Rect2 = Rect2()
var _minimized: bool = false
var _maximized: bool = false


func _ready() -> void:
	_fit_to_content()


## Builds the window around `content` and remembers the area it may occupy.
## Call once, right after the node is added to the window host.
func setup(p_window_id: StringName, title: String, content: Control, work_area: Rect2) -> void:
	window_id = p_window_id
	name = "GameWindow_" + String(p_window_id)
	_work_area = work_area
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(MIN_WIDTH, 0.0)

	var frame: StyleBoxFlat = StyleBoxFlat.new()
	frame.bg_color = GameTheme.BG_PANEL
	frame.border_color = GameTheme.BORDER
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(GameTheme.CORNER_RADIUS)
	frame.set_content_margin_all(0.0)
	add_theme_stylebox_override("panel", frame)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	add_child(column)

	_title_bar = _build_title_bar(title)
	column.add_child(_title_bar)

	_body = MarginContainer.new()
	_body.name = "Body"
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("margin_left", BODY_MARGIN)
	_body.add_theme_constant_override("margin_top", BODY_MARGIN)
	_body.add_theme_constant_override("margin_right", BODY_MARGIN)
	_body.add_theme_constant_override("margin_bottom", BODY_MARGIN)
	column.add_child(_body)

	# The body scrolls so content stays reachable on very small screens while the
	# chrome (title bar, and the menu bar outside) never scrolls. On desktop
	# resolutions the content fits and no scrollbar is drawn at all.
	_scroll = ScrollContainer.new()
	_scroll.name = "ContentScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.add_child(_scroll)

	if content != null:
		set_content(content)


## Replaces the hosted content, releasing the previous one.
func set_content(content: Control) -> void:
	if _content != null and is_instance_valid(_content):
		_content.queue_free()
		_content = null
	if content == null:
		return

	# The window already draws the frame, so a content root that draws its own
	# would double it. Keep its padding but drop its background and border.
	var content_panel: PanelContainer = content as PanelContainer
	if content_panel != null:
		var margins: StyleBoxFlat = StyleBoxFlat.new()
		margins.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		margins.set_border_width_all(0)
		margins.set_content_margin_all(GameTheme.PANEL_MARGIN)
		content_panel.add_theme_stylebox_override("panel", margins)

	_content = content
	_scroll.add_child(content)
	_fit_to_content()


## Applies a persisted layout entry: position, minimized and maximized flags.
func apply_layout(entry: Dictionary) -> void:
	_restore_rect = Rect2(entry.get("position", position), size)
	_minimized = bool(entry.get("minimized", false))
	_maximized = bool(entry.get("maximized", false))
	_apply_geometry()


## The layout entry this window currently represents, ready for persistence.
func get_layout() -> Dictionary:
	return {
		"minimized": _minimized,
		"maximized": _maximized,
		"position": _restore_rect.position,
	}


## Updates the area this window may occupy. Called when the host is resized so a
## maximized window follows the screen, no window ends up off-screen, and the
## content-driven size is recapped so a window never grows past the work area.
func set_work_area(work_area: Rect2) -> void:
	if work_area == _work_area:
		return
	_work_area = work_area
	if _maximized:
		_apply_geometry()
		return
	# Size follows the content, so a new work area can change how much fits.
	_fit_to_content()


func is_minimized() -> bool:
	return _minimized


func is_maximized() -> bool:
	return _maximized


## Collapses the window to its title bar, or restores it.
func set_minimized(minimized: bool) -> void:
	if minimized == _minimized:
		return
	if minimized:
		_restore_rect = Rect2(_restore_rect.position, size)
		_maximized = false
	_minimized = minimized
	_apply_geometry()
	state_changed.emit(window_id)


## Fills the work area with the window, or restores its previous geometry.
func set_maximized(maximized: bool) -> void:
	if maximized == _maximized:
		return
	if maximized:
		_restore_rect = Rect2(_restore_rect.position, size)
		_minimized = false
	_maximized = maximized
	_apply_geometry()
	state_changed.emit(window_id)


# --- Internals -------------------------------------------------------------

func _build_title_bar(title: String) -> PanelContainer:
	var bar: PanelContainer = PanelContainer.new()
	bar.name = "TitleBar"
	bar.mouse_filter = Control.MOUSE_FILTER_STOP

	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = GameTheme.BG_PANEL
	style.border_color = GameTheme.BORDER
	style.border_width_bottom = 2
	style.corner_radius_top_left = GameTheme.CORNER_RADIUS
	style.corner_radius_top_right = GameTheme.CORNER_RADIUS
	style.content_margin_left = TITLE_MARGIN_H
	style.content_margin_top = TITLE_MARGIN_V
	style.content_margin_right = TITLE_MARGIN_H
	style.content_margin_bottom = TITLE_MARGIN_V
	bar.add_theme_stylebox_override("panel", style)
	bar.gui_input.connect(_on_title_bar_gui_input)

	var row: HBoxContainer = HBoxContainer.new()
	row.name = "TitleRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.text = title
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	row.add_child(_title_label)

	row.add_child(_make_title_button("_", "Minimize", _on_minimize_pressed))
	row.add_child(_make_title_button("+", "Maximize", _on_maximize_pressed))
	row.add_child(_make_title_button("X", "Close", _on_close_pressed))
	return bar


func _make_title_button(text: String, tooltip: String, handler: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = BUTTON_MIN_SIZE
	button.pressed.connect(handler)
	return button


func _on_minimize_pressed() -> void:
	set_minimized(not _minimized)


func _on_maximize_pressed() -> void:
	set_maximized(not _maximized)


func _on_close_pressed() -> void:
	close_requested.emit(window_id)


## Restores the position, size and visibility implied by the current flags.
func _apply_geometry() -> void:
	if _maximized:
		position = _work_area.position
		size = _work_area.size
		_body.visible = true
		return

	position = _clamp_position(_restore_rect.position)
	_body.visible = not _minimized
	size = Vector2(_restore_rect.size.x, _title_height()) if _minimized else _restore_rect.size


func _title_height() -> float:
	if _title_bar == null:
		return 0.0
	return _title_bar.get_combined_minimum_size().y


## Sizes the window to its content, capped so it always fits the work area.
func _fit_to_content() -> void:
	if _title_bar == null:
		return

	var content_min: Vector2 = Vector2.ZERO
	if _content != null and is_instance_valid(_content):
		content_min = _content.get_combined_minimum_size()
	var title_min: Vector2 = _title_bar.get_combined_minimum_size()

	var desired: Vector2 = Vector2(
		maxf(content_min.x + BODY_MARGIN * 2.0 + 4.0, maxf(title_min.x, MIN_WIDTH)),
		title_min.y + content_min.y + BODY_MARGIN * 2.0 + 4.0
	)
	var limit: Vector2 = _work_area.size * MAX_WORK_AREA_RATIO
	if limit.x > 0.0 and limit.y > 0.0:
		desired = desired.min(limit)
	_restore_rect = Rect2(_restore_rect.position, desired)
	if not _maximized:
		_apply_geometry()


## Keeps the window inside the work area. A window small enough to fit is kept
## entirely on screen; one wider than the work area is allowed to hang over the
## edges but always keeps `MIN_VISIBLE_TITLE` pixels of its title bar reachable,
## so it can still be grabbed and dragged back.
func _clamp_position(candidate: Vector2) -> Vector2:
	if _work_area.size == Vector2.ZERO:
		return candidate

	var min_x: float
	var max_x: float
	if _restore_rect.size.x <= _work_area.size.x:
		min_x = _work_area.position.x
		max_x = _work_area.position.x + _work_area.size.x - _restore_rect.size.x
	else:
		min_x = _work_area.position.x - (_restore_rect.size.x - MIN_VISIBLE_TITLE)
		max_x = _work_area.position.x + _work_area.size.x - MIN_VISIBLE_TITLE

	var max_y: float = _work_area.position.y + _work_area.size.y - _title_height()
	return Vector2(
		clampf(candidate.x, min_x, maxf(max_x, min_x)),
		clampf(candidate.y, _work_area.position.y, maxf(max_y, _work_area.position.y))
	)


func _on_title_bar_gui_input(event: InputEvent) -> void:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button != null:
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_button.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			move_to_front()
		elif _dragging:
			_dragging = false
			state_changed.emit(window_id)
		return

	var motion: InputEventMouseMotion = event as InputEventMouseMotion
	if motion != null and _dragging:
		var parent: Control = get_parent() as Control
		if parent == null:
			return
		_restore_rect.position = _clamp_position(parent.get_local_mouse_position() - _drag_offset)
		position = _restore_rect.position
