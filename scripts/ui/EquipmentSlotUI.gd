class_name EquipmentSlotUI
extends ItemSlotUI
## A single equipment slot widget.
##
## Shows the slot label plus the equipped item's icon and name, and supports
## drag & drop: the equipped item can be dragged back to the inventory and a
## compatible inventory item can be dropped here to equip it.

const SLOT_MIN_SIZE: Vector2 = Vector2(232.0, 56.0)
const SLOT_ICON_SIZE: float = 40.0
const SLOT_CONTENT_MARGIN: float = 8.0
const EMPTY_BACKGROUND_MODULATE: Color = Color(1.0, 1.0, 1.0, 0.25)

## Canonical slot name (e.g. "WEAPON") understood by `EquipmentManager`.
var slot_name: String = ""

## Human readable label for the slot (e.g. "Weapon").
var slot_label: String = ""

var _item_icon: TextureRect
var _empty_background: TextureRect
var _name_label: Label


func _ready() -> void:
	custom_minimum_size = SLOT_MIN_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _build_slot_stylebox())
	_build_children()
	refresh()


## Re-reads the equipped item from `EquipmentManager` (the single source of
## truth) and updates the icon, name and tooltip accordingly.
func refresh() -> void:
	item = EquipmentManager.get_equipped(slot_name)
	if item != null:
		_item_icon.texture = resolve_item_icon(item)
		_item_icon.visible = true
		_empty_background.visible = false
		_name_label.text = item.item_name
		tooltip_text = format_item_tooltip(item)
	else:
		_item_icon.texture = null
		_item_icon.visible = false
		_empty_background.visible = true
		_name_label.text = "Empty"
		tooltip_text = ""


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item == null:
		return null
	attach_drag_preview(item)
	return {"item": item, "source": "equipment", "slot": slot_name}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = data
	if payload.get("source", "") != "inventory":
		return false
	var dropped: ItemData = payload.get("item")
	if dropped == null:
		return false
	# Only items whose allowed slot matches this slot may be dropped here.
	return dropped.equipment_slot == ItemData.slot_from_name(slot_name)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	var dropped: ItemData = payload.get("item")
	if dropped == null:
		return
	EquipmentManager.equip_item(dropped, slot_name)


func _build_slot_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.109804, 0.109804, 0.14902, 0.901961)
	style.border_color = Color(0.301961, 0.278431, 0.352941, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = SLOT_CONTENT_MARGIN
	style.content_margin_top = SLOT_CONTENT_MARGIN
	style.content_margin_right = SLOT_CONTENT_MARGIN
	style.content_margin_bottom = SLOT_CONTENT_MARGIN
	return style


func _build_children() -> void:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hbox)

	# Icon area: an empty background texture behind the equipped item's icon.
	var icon_holder: Control = Control.new()
	icon_holder.custom_minimum_size = Vector2(SLOT_ICON_SIZE, SLOT_ICON_SIZE)
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_holder)

	_empty_background = TextureRect.new()
	_empty_background.texture = DEFAULT_ITEM_ICON
	_empty_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_empty_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_empty_background.modulate = EMPTY_BACKGROUND_MODULATE
	_empty_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_empty_background)

	_item_icon = TextureRect.new()
	_item_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_item_icon)

	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_box)

	var slot_label_node: Label = Label.new()
	slot_label_node.text = slot_label
	slot_label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(slot_label_node)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_name_label)
