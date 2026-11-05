class_name InventorySlotUI
extends ItemSlotUI
## A single inventory grid slot.
##
## Displays the item stored at the matching inventory index and supports drag &
## drop: items can be dragged out of the slot, and an item dragged here from an
## equipment slot is unequipped back into the inventory.

## Compact slot footprint so a 48-slot grid still fits inside short landscape
## viewports (844x390) without introducing any scrolling.
const SLOT_SIZE: float = 40.0

var _icon: TextureRect
var _stack_label: Label


func _ready() -> void:
	custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP

	# The icon ignores mouse input so the slot panel receives hover and drag
	# events (tooltips and drag-start are handled by this panel).
	_icon = TextureRect.new()
	_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_icon.offset_left = SLOT_ICON_MARGIN
	_icon.offset_top = SLOT_ICON_MARGIN
	_icon.offset_right = -SLOT_ICON_MARGIN
	_icon.offset_bottom = -SLOT_ICON_MARGIN
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)
	
	_build_stack_label()


func _build_stack_label() -> void:
	# Semi-transparent background for readability
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	bg.offset_left = -24
	bg.offset_top = -18
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.set_corner_radius_all(2)
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)
	
	_stack_label = Label.new()
	_stack_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stack_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_stack_label.add_theme_font_size_override("font_size", 12)
	_stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_stack_label)
	
	# Initial state
	bg.visible = false


## Updates the slot to display the contents of an `InventorySlot`.
func set_item_slot(slot: InventorySlot) -> void:
	if slot == null or slot.is_empty():
		item = null
		_icon.texture = null
		tooltip_text = ""
		_stack_label.get_parent().visible = false
		return
		
	item = slot.item
	_icon.texture = resolve_item_icon(item)
	tooltip_text = format_item_tooltip(item)
	
	var count: int = slot.stack_count
	if count > 1:
		_stack_label.text = str(count)
		_stack_label.get_parent().visible = true
		
		# Basic font scaling for large numbers
		if count >= 1000:
			_stack_label.add_theme_font_size_override("font_size", 9)
		elif count >= 100:
			_stack_label.add_theme_font_size_override("font_size", 10)
		else:
			_stack_label.add_theme_font_size_override("font_size", 12)
	else:
		_stack_label.get_parent().visible = false


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	attach_drag_preview(item)
	return {"item": item, "source": "inventory", "slot": ""}


## Right click or left double click equips straight into the item's first valid
## slot. Single clicks are left untouched so drag & drop keeps working.
func _gui_input(event: InputEvent) -> void:
	if item == null or not is_equip_gesture(event):
		return
	accept_event()
	_try_equip()


## Equips the displayed item, reporting the precise reason through a toast when
## it cannot be equipped (wrong type, level requirement, ...).
func _try_equip() -> void:
	var candidate: ItemData = item
	if candidate == null:
		return
	var result: int = EquipmentManager.get_auto_equip_result(candidate)
	if result != EquipmentManager.EquipResult.OK:
		SignalBus.notification_raised.emit(equip_failure_message(result, candidate), true)
		return
	EquipmentManager.auto_equip(candidate)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# Only items dragged out of an equipment slot can be dropped here (unequip).
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = data
	return payload.get("source", "") == "equipment"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	var slot_name: String = payload.get("slot", "")
	if slot_name == "":
		return
	EquipmentManager.unequip_item(slot_name)
