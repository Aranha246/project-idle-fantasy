class_name PauseMenu
extends CanvasLayer
## In-game pause overlay.
##
## Purely presentational: it reports intent through signals and leaves pausing,
## saving and quitting to the scene controller. The overlay runs while the tree
## is paused so it stays interactive.
##
## Contains no `ScrollContainer` so the project-wide no-scroll guarantee holds.

signal resume_requested
signal settings_requested
signal credits_requested
signal save_requested
signal quit_requested

const PANEL_MIN_WIDTH: float = 280.0
const BUTTON_MIN_HEIGHT: float = 44.0
const TITLE_FONT_SIZE: int = 22

var _root: Control = null
var _status_label: Label = null
var _first_button: Button = null


func _init() -> void:
	name = "PauseMenu"
	layer = 100
	visible = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## Applies the shared UI theme to the overlay's control tree.
func set_ui_theme(ui_theme: Theme) -> void:
	if _root != null:
		_root.theme = ui_theme


## Shows or hides the overlay and moves focus to the first action when opening.
func set_paused(paused: bool) -> void:
	visible = paused
	_clear_status()
	if paused and _first_button != null:
		# Defer so the button is laid out before focus is granted.
		_first_button.call_deferred("grab_focus")


## Displays a short confirmation line (used by "Save Now").
func set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "PausePanel"
	panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0.0)
	center.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var title: Label = Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	column.add_child(title)

	_first_button = _make_button("Resume", func() -> void: resume_requested.emit())
	column.add_child(_first_button)
	column.add_child(_make_button("Save Now", func() -> void: save_requested.emit()))
	column.add_child(_make_button("Settings", func() -> void: settings_requested.emit()))
	column.add_child(_make_button("Credits", func() -> void: credits_requested.emit()))
	column.add_child(_make_button("Quit to Desktop", func() -> void: quit_requested.emit()))

	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.modulate = Color(0.6, 1.0, 0.6, 1.0)
	column.add_child(_status_label)


func _make_button(button_label: String, on_pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.text = button_label
	button.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(on_pressed)
	return button


func _clear_status() -> void:
	if _status_label != null:
		_status_label.text = ""
