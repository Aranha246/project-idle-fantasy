class_name InventorySlotUI
extends ItemSlotUI
## A single inventory grid slot.
##
## Displays the item stored at the matching inventory index and supports drag &
## drop: items can be dragged out of the slot, and an item dragged here from an
## equipment slot is unequipped back into the inventory.

const SLOT_SIZE: float = 48.0

var _icon: TextureRect


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


## Updates the slot to display `new_item`, or clears it when `new_item` is null.
func set_item(new_item: ItemData) -> void:
	item = new_item
	if new_item != null:
		_icon.texture = resolve_item_icon(new_item)
		tooltip_text = format_item_tooltip(new_item)
	else:
		_icon.texture = null
		tooltip_text = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	attach_drag_preview(item)
	return {"item": item, "source": "inventory", "slot": ""}


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
