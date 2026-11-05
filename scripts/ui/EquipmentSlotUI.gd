class_name EquipmentSlotUI
extends ItemSlotUI
## A single equipment slot widget.
##
## Shows the slot label plus the equipped item's icon and name, and supports
## drag & drop: the equipped item can be dragged back to the inventory and a
## compatible inventory item can be dropped here to equip it.

## Compact slot footprint so all thirteen slots fit a 3-column grid inside the
## shortest supported viewport (844x390) without any scrolling.
const SLOT_MIN_SIZE: Vector2 = Vector2(150.0, 48.0)
const SLOT_ICON_SIZE: float = 32.0
const SLOT_CONTENT_MARGIN: float = 6.0
## Horizontal gap between the icon box and the label column.
const SLOT_GAP: float = 8.0

## Canonical slot name (e.g. "WEAPON") understood by `EquipmentManager`.
var slot_name: String = ""

## Human readable label for the slot (e.g. "Weapon").
var slot_label: String = ""

var _item_icon: TextureRect
var _empty_background: Panel
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


## Right click or left double click unequips back into the inventory, mirroring
## the equipping gestures available on inventory slots.
func _gui_input(event: InputEvent) -> void:
	if item == null or not is_equip_gesture(event):
		return
	accept_event()
	_try_unequip()


## Unequips the displayed item, explaining through a toast when the inventory
## has no room for it.
func _try_unequip() -> void:
	var equipped: ItemData = item
	if equipped == null:
		return
	if EquipmentManager.unequip_item(slot_name) == null:
		SignalBus.notification_raised.emit(
			"No inventory space to unequip %s." % equipped.item_name, true
		)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var payload: Dictionary = data
	if payload.get("source", "") != "inventory":
		return false
	var dropped: ItemData = payload.get("item")
	if dropped == null:
		return false
	# Acceptance is decided by `EquipmentManager` so the two ring slots, which
	# share the single RING category, validate correctly.
	return EquipmentManager.can_equip_in(dropped, slot_name)


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


## Backdrop drawn behind the icon box while the slot is empty. It is a plain
## inset well (never the item fallback icon) so an empty slot stays clean
## instead of showing `res://icon.svg`.
func _build_empty_well_stylebox() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	style.border_color = Color(0.301961, 0.278431, 0.352941, 0.8)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	return style


func _build_children() -> void:
	# Use a MarginContainer to ensure content stays inside the panel borders.
	var margin_container: MarginContainer = MarginContainer.new()
	margin_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin_container.add_theme_constant_override("margin_left", int(SLOT_CONTENT_MARGIN))
	margin_container.add_theme_constant_override("margin_top", int(SLOT_CONTENT_MARGIN))
	margin_container.add_theme_constant_override("margin_right", int(SLOT_CONTENT_MARGIN))
	margin_container.add_theme_constant_override("margin_bottom", int(SLOT_CONTENT_MARGIN))
	margin_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin_container)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", int(SLOT_GAP))
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin_container.add_child(hbox)

	# Fixed-size icon box, vertically centred so it never stretches with the row.
	var icon_holder: Control = Control.new()
	icon_holder.custom_minimum_size = Vector2(SLOT_ICON_SIZE, SLOT_ICON_SIZE)
	icon_holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	icon_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(icon_holder)

	# Empty well: a neutral inset backdrop, deliberately NOT the item fallback
	# icon, so an empty slot shows nothing but a subtle frame.
	_empty_background = Panel.new()
	_empty_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_empty_background.add_theme_stylebox_override("panel", _build_empty_well_stylebox())
	_empty_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_empty_background)

	# Item icon: fixed 40x40 box, aspect-preserving, hidden while empty.
	_item_icon = TextureRect.new()
	_item_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_item_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_holder.add_child(_item_icon)

	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.add_theme_constant_override("separation", 2)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_box)

	var slot_label_node: Label = Label.new()
	slot_label_node.text = slot_label
	slot_label_node.modulate = Color(0.7, 0.7, 0.7, 1.0) # Dimmed slot label
	slot_label_node.add_theme_font_size_override("font_size", 11)
	slot_label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(slot_label_node)

	_name_label = Label.new()
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.add_theme_font_size_override("font_size", 13)
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text_box.add_child(_name_label)
