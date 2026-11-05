class_name CharacterWindowUI
extends VBoxContainer
## Content of the unified "Character" window.
##
## Consolidates the equipment grid and the player inventory into one cohesive
## layout, which is what makes item transfer seamless: the thirteen gear slots
## sit beside the bag, and an item can be dragged or double-clicked between the
## two without ever leaving the window.
##
## The panel only arranges the two game panels it is given; it reads no game
## state and owns no rules, so it stays decoupled like every other UI widget.

const COLUMN_SEPARATION: int = 10
const HEADER_FONT_SIZE: int = 15
const HINT_FONT_SIZE: int = 12

const EQUIPMENT_HEADER: String = "Equipment"
const INVENTORY_HEADER: String = "Inventory"
const HINT_TEXT: String = "Right-click or double-click an item to equip or unequip it."

var _equipment_panel: Control = null
var _inventory_panel: Control = null


## Lays out the two panels side by side. Call once, before the window is fitted.
func setup(equipment_panel: Control, inventory_panel: Control) -> void:
	_equipment_panel = equipment_panel
	_inventory_panel = inventory_panel

	add_theme_constant_override("separation", 6)

	var body: HBoxContainer = HBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", COLUMN_SEPARATION)
	add_child(body)

	body.add_child(_build_column(EQUIPMENT_HEADER, equipment_panel))
	body.add_child(_build_column(INVENTORY_HEADER, inventory_panel))

	var hint: Label = Label.new()
	hint.name = "Hint"
	hint.text = HINT_TEXT
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	add_child(hint)


## Applies the shared UI theme to the headers so the window matches the HUD.
func set_ui_theme(ui_theme: Theme) -> void:
	theme = ui_theme


# --- Internals -------------------------------------------------------------

## A titled column: a small header above the panel it hosts. Each column expands
## so the two halves stay the same width whatever the window grows to.
func _build_column(header_text: String, panel: Control) -> Control:
	var column: VBoxContainer = VBoxContainer.new()
	column.name = header_text
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)

	var header: Label = Label.new()
	header.name = "Header"
	header.text = header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	column.add_child(header)

	if panel != null:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(panel)

	return column
