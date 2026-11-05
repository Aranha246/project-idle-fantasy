class_name Credits
extends CanvasLayer
## Post-game credits sequence.
##
## A static, non-scrolling card so it fits every supported resolution without a
## `ScrollContainer`. Closes itself via the Back button (or the cancel action
## handled by the scene controller) and reports completion through a signal.

signal closed

const PANEL_MIN_WIDTH: float = 300.0
const TITLE_FONT_SIZE: int = 24
const LINE_FONT_SIZE: int = 15
const BUTTON_MIN_HEIGHT: float = 44.0

const TITLE: String = "Project Idle Fantasy"
const SUBTITLE: String = "Idle Fantasy RPG"

## Kept short on purpose: a long crawl would not fit short landscape viewports.
const CREDIT_LINES: Array[String] = [
	"Design & Engineering",
	"  TraeCode",
	"",
	"Game Systems",
	"  Zones, Combat & Loot",
	"  Inventory & Equipment",
	"  Persistence & Settings",
	"",
	"Built with Godot Engine 4.7",
	"Thank you for playing!",
]

var _root: Control = null
var _back_button: Button = null


func _init() -> void:
	name = "Credits"
	layer = 102
	visible = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


## Applies the shared UI theme to the overlay's control tree.
func set_ui_theme(ui_theme: Theme) -> void:
	if _root != null:
		_root.theme = ui_theme


func set_shown(shown: bool) -> void:
	visible = shown
	if shown and _back_button != null:
		_back_button.call_deferred("grab_focus")


## Hides the card and reports that the sequence finished.
func close() -> void:
	if not visible:
		return
	set_shown(false)
	closed.emit()
	SignalBus.credits_finished.emit()


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.02, 0.02, 0.04, 0.94)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "CreditsPanel"
	panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0.0)
	center.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var title: Label = Label.new()
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	column.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = SUBTITLE
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.7, 0.72, 0.8, 1.0)
	column.add_child(subtitle)

	for line: String in CREDIT_LINES:
		var label: Label = Label.new()
		label.text = line
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", LINE_FONT_SIZE)
		column.add_child(label)

	_back_button = Button.new()
	_back_button.name = "BackButton"
	_back_button.text = "Back"
	_back_button.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	_back_button.pressed.connect(close)
	column.add_child(_back_button)
