class_name ToastUI
extends Control
## Transient, non-blocking feedback strip.
##
## Shows a short-lived message whenever `SignalBus.notification_raised` fires.
## That is how the game reports things such as a rejected equip attempt without
## opening a modal dialog. Purely presentational: it reads no game state and can
## be dropped into any scene that owns a `SignalBus` connection.

const TOAST_MARGIN: float = 16.0
const TOAST_LIFETIME_SECONDS: float = 2.5
const TOAST_FADE_SECONDS: float = 0.4
const MAX_VISIBLE_TOASTS: int = 4
const TOAST_MIN_WIDTH: float = 180.0
const TOAST_FONT_SIZE: int = 14

const INFO_COLOR: Color = Color(0.623529, 0.482353, 0.921569, 0.95)
const ERROR_COLOR: Color = Color(0.921569, 0.325490, 0.325490, 0.95)

var _column: VBoxContainer = null
var _theme: Theme = null


func _ready() -> void:
	name = "ToastUI"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", TOAST_MARGIN)
	margin.add_theme_constant_override("margin_top", TOAST_MARGIN)
	margin.add_theme_constant_override("margin_right", TOAST_MARGIN)
	margin.add_theme_constant_override("margin_bottom", TOAST_MARGIN)
	add_child(margin)

	_column = VBoxContainer.new()
	_column.name = "Toasts"
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.alignment = BoxContainer.ALIGNMENT_END
	_column.add_theme_constant_override("separation", 6)
	margin.add_child(_column)

	SignalBus.notification_raised.connect(_on_notification_raised)


## Applies the shared UI theme so toasts match the rest of the interface.
func set_ui_theme(theme: Theme) -> void:
	_theme = theme
	if _column != null:
		_column.theme = theme


func _on_notification_raised(message: String, is_error: bool) -> void:
	raise_toast(message, is_error)


## Adds one toast. Exposed so tests can drive the strip without a signal.
func raise_toast(message: String, is_error: bool = false) -> void:
	if _column == null or message.is_empty():
		return

	while _column.get_child_count() >= MAX_VISIBLE_TOASTS:
		var oldest: Node = _column.get_child(0)
		_column.remove_child(oldest)
		oldest.queue_free()

	var panel: PanelContainer = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.custom_minimum_size = Vector2(TOAST_MIN_WIDTH, 0.0)
	panel.add_theme_stylebox_override("panel", _build_style(is_error))
	_column.add_child(panel)

	var label: Label = Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", TOAST_FONT_SIZE)
	panel.add_child(label)

	var tween: Tween = panel.create_tween()
	tween.tween_interval(TOAST_LIFETIME_SECONDS)
	tween.tween_property(panel, "modulate:a", 0.0, TOAST_FADE_SECONDS)
	tween.tween_callback(panel.queue_free)


func _build_style(is_error: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = GameTheme.BG_PANEL
	style.border_color = ERROR_COLOR if is_error else INFO_COLOR
	style.set_border_width_all(2)
	style.set_corner_radius_all(GameTheme.CORNER_RADIUS)
	style.set_content_margin_all(8.0)
	return style
