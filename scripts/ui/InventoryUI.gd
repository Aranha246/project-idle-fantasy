extends PanelContainer
## Inventory panel: builds a fixed grid of item slots and refreshes it whenever
## the global `SignalBus.inventory_updated` signal fires.

const SLOT_COUNT: int = 20
const SLOT_SIZE: float = 48.0
const SLOT_ICON_MARGIN: float = 4.0

## Placeholder shown whenever an item has no `item_icon` assigned (for example
## items generated at runtime such as the default 'Rusty Dagger' loot).
## `icon.svg` imports as a `CompressedTexture2D`, which is a `Texture2D`, so it
## is safe to assign directly to any slot's `TextureRect.texture`.
const DEFAULT_ITEM_ICON: Texture2D = preload("res://icon.svg")

@onready var _grid: GridContainer = %InventoryGrid

var _slot_icons: Array[TextureRect] = []
var _slot_panels: Array[Panel] = []


func _ready() -> void:
	SignalBus.inventory_updated.connect(_on_inventory_updated)
	_build_slots()
	_refresh_slots()


func _build_slots() -> void:
	for i: int in SLOT_COUNT:
		var slot: Panel = Panel.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)

		var icon: TextureRect = TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = SLOT_ICON_MARGIN
		icon.offset_top = SLOT_ICON_MARGIN
		icon.offset_right = -SLOT_ICON_MARGIN
		icon.offset_bottom = -SLOT_ICON_MARGIN
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

		slot.add_child(icon)
		_grid.add_child(slot)
		_slot_panels.append(slot)
		_slot_icons.append(icon)


func _on_inventory_updated() -> void:
	_refresh_slots()


func _refresh_slots() -> void:
	var items: Array[ItemData] = InventoryManager.get_slots()
	for i: int in _slot_icons.size():
		var icon: TextureRect = _slot_icons[i]
		var slot: Panel = _slot_panels[i]
		var item: ItemData = null
		if i < items.size():
			item = items[i]
		if item != null:
			icon.texture = _resolve_icon(item)
			slot.tooltip_text = _format_tooltip(item)
		else:
			icon.texture = null
			slot.tooltip_text = ""


## Builds the multi-line metadata tooltip shown when hovering an occupied slot.
## Enum names are read from the `ItemData` enum dictionaries and title-cased so
## the display stays in sync automatically if new types or rarities are added.
func _format_tooltip(item: ItemData) -> String:
	var type_name: String = ItemData.ItemType.keys()[item.item_type].capitalize()
	var rarity_name: String = ItemData.Rarity.keys()[item.rarity].capitalize()
	return "Name: %s\nType: %s\nRarity: %s\nSell Value: %d CP" % [
		item.item_name,
		type_name,
		rarity_name,
		item.sell_value_copper,
	]


## Returns the item's own icon, or the shared placeholder when none is assigned.
## Runtime-generated loot (e.g. the default 'Rusty Dagger') has a null
## `item_icon`, so this guarantees every occupied slot renders a texture instead
## of a blank cell and without logging missing-resource errors.
func _resolve_icon(item: ItemData) -> Texture2D:
	if item.item_icon != null:
		return item.item_icon
	return DEFAULT_ITEM_ICON
