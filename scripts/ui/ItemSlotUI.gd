class_name ItemSlotUI
extends Panel
## Shared base class for the inventory and equipment slot widgets.
##
## Centralises the common item presentation helpers (icon fallback, tooltip
## formatting and drag preview) so both slot types render items consistently and
## duplicate no logic.

const SLOT_ICON_MARGIN: float = 4.0

## Item currently displayed by this slot (`null` when the slot is empty).
var item: ItemData = null


## Returns the item's own icon, or the authored category sprite when none is
## assigned (for example items generated at runtime such as the default
## 'Rusty Dagger' loot). The resolved icon is a plain `Texture2D`, so it is
## safe to assign directly to any slot's `TextureRect.texture`.
func resolve_item_icon(source_item: ItemData) -> Texture2D:
	if source_item.item_icon != null:
		return source_item.item_icon
	return GameTheme.build_item_icon(source_item)


## Builds the multi-line metadata tooltip shown when hovering an occupied slot.
## Enum names are read from the `ItemData` enum dictionaries and title-cased so
## the display stays in sync automatically if new types or rarities are added.
func format_item_tooltip(source_item: ItemData) -> String:
	var type_name: String = ItemData.ItemType.keys()[source_item.item_type].capitalize()
	var rarity_name: String = ItemData.Rarity.keys()[source_item.rarity].capitalize()
	return "Name: %s\nType: %s\nRarity: %s\nSell Value: %d CP" % [
		source_item.item_name,
		type_name,
		rarity_name,
		source_item.sell_value_copper,
	]


## Builds the small preview control shown while an item is being dragged.
func build_drag_preview(source_item: ItemData) -> Control:
	var preview: TextureRect = TextureRect.new()
	preview.texture = resolve_item_icon(source_item)
	preview.custom_minimum_size = Vector2(48.0, 48.0)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return preview


## Attaches the drag preview. Godot's `Viewport` only accepts a preview while a
## drag is actually running (it enforces the very same `gui_is_dragging()` check
## internally), so guarding on it keeps real drags working unchanged while
## direct calls to the drag handlers stay silent instead of logging an error.
func attach_drag_preview(source_item: ItemData) -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.gui_is_dragging():
		set_drag_preview(build_drag_preview(source_item))


## Player-facing explanation for a rejected equip request, naming the item and,
## where it helps, the requirement that was not met.
func equip_failure_message(result: int, source_item: ItemData) -> String:
	if source_item == null:
		return "Nothing to equip."
	if result == EquipmentManager.EquipResult.LEVEL_TOO_LOW:
		return "%s requires level %d." % [source_item.item_name, source_item.required_level]
	if result == EquipmentManager.EquipResult.WRONG_SLOT:
		return "%s does not fit any of your slots." % source_item.item_name
	if result == EquipmentManager.EquipResult.NOT_EQUIPPABLE:
		return "%s cannot be equipped." % source_item.item_name
	if result == EquipmentManager.EquipResult.NOT_IN_INVENTORY:
		return "%s is not in your inventory." % source_item.item_name
	return "Cannot equip %s." % source_item.item_name


## Returns `true` when `event` is one of the two equipping gestures: a right
## click, or a left double click. Shared so inventory and equipment slots react
## to exactly the same gestures.
static func is_equip_gesture(event: InputEvent) -> bool:
	var mouse_button: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button == null or not mouse_button.pressed:
		return false
	if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		return true
	return mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.double_click
