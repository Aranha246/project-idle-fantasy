class_name MenuBarUI
extends PanelContainer
## Persistent menu bar listing every game window.
##
## This is the always-visible chrome of the window system: one toggle button per
## `WindowRegistry` definition, in authored order, that opens or closes that
## window. The bar itself never scrolls — the buttons live in a `HFlowContainer`
## so on a narrow screen they wrap onto another row instead of overflowing the
## viewport.
##
## The widget owns presentation only. It reports which window the player asked
## for through `window_pressed` and mirrors the authoritative state handed to it
## by `set_open`, so it can never disagree with `WindowManager`.

## Emitted when the player activates the toggle for `window_id`.
signal window_pressed(window_id: StringName)

const BUTTON_FONT_SIZE: int = 13
const BUTTON_MIN_HEIGHT: float = 26.0
const BUTTON_SEPARATION: int = 4
const PADDING_H: int = 8
const PADDING_V: int = 4

## Window id -> its toggle button.
var _toggles: Dictionary = {}

## Last authoritative open state pushed in through `set_open`, kept locally so the
## bar needs no reference to `WindowManager` to tell a real press from a mirror.
var _open: Dictionary = {}


func _ready() -> void:
	name = "MenuBar"
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _build_style())


## Builds one toggle per definition, in order. Call once, before the bar is shown.
func setup(definitions: Array[WindowData]) -> void:
	if _row() == null:
		_build_row()
	var row: HFlowContainer = _row()
	for child: Node in row.get_children():
		child.queue_free()
	_toggles.clear()

	for definition: WindowData in definitions:
		if not definition.is_valid():
			continue
		row.add_child(_build_toggle(definition))


## Mirrors the authoritative open state of `window_id` without echoing a signal
## back, so the button reflects the game instead of driving it.
func set_open(window_id: StringName, is_open: bool) -> void:
	_open[window_id] = is_open
	var toggle: Button = get_toggle(window_id)
	if toggle != null:
		toggle.set_pressed_no_signal(is_open)


## The toggle button for `window_id`, or `null` when the bar does not list it.
func get_toggle(window_id: StringName) -> Button:
	return _toggles.get(window_id) as Button


## Applies the shared UI theme so the bar matches the rest of the interface.
func set_ui_theme(ui_theme: Theme) -> void:
	theme = ui_theme


# --- Internals -------------------------------------------------------------

func _build_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = GameTheme.BG_PANEL
	style.border_color = GameTheme.BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(GameTheme.CORNER_RADIUS)
	style.content_margin_left = float(PADDING_H)
	style.content_margin_top = float(PADDING_V)
	style.content_margin_right = float(PADDING_H)
	style.content_margin_bottom = float(PADDING_V)
	return style


func _row() -> HFlowContainer:
	return get_node_or_null("Row") as HFlowContainer


func _build_row() -> void:
	var row: HFlowContainer = HFlowContainer.new()
	row.name = "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("h_separation", BUTTON_SEPARATION)
	row.add_theme_constant_override("v_separation", BUTTON_SEPARATION)
	add_child(row)


func _build_toggle(definition: WindowData) -> Button:
	var toggle: Button = Button.new()
	toggle.name = "MenuToggle_" + String(definition.window_id)
	toggle.text = definition.title
	toggle.toggle_mode = true
	# The menu bar must never hold keyboard focus: a focused button would swallow
	# typed keys, which is exactly the kind of conflict the window shortcuts have
	# to stay clear of.
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	toggle.add_theme_font_size_override("font_size", BUTTON_FONT_SIZE)
	toggle.tooltip_text = "Toggle the %s window" % definition.title
	toggle.toggled.connect(_on_toggle_toggled.bind(definition.window_id))
	_toggles[definition.window_id] = toggle
	return toggle


func _on_toggle_toggled(is_open: bool, window_id: StringName) -> void:
	# Ignore the state `set_open` pushed in: only a real press should ask for a
	# change, so the bar can mirror the game without feeding back into it.
	if bool(_open.get(window_id, false)) == is_open:
		return
	window_pressed.emit(window_id)
