extends PanelContainer
## Inventory panel: builds a fixed grid of item slots and refreshes it whenever
## the global `SignalBus.inventory_updated` signal fires.

const SLOT_COUNT: int = 20
const SLOT_SIZE: float = 48.0
const SLOT_ICON_MARGIN: float = 4.0

@onready var _grid: GridContainer = %InventoryGrid

var _slot_icons: Array[TextureRect] = []


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
		_slot_icons.append(icon)


func _on_inventory_updated() -> void:
	_refresh_slots()


func _refresh_slots() -> void:
	var items: Array[ItemData] = InventoryManager.get_slots()
	for i: int in _slot_icons.size():
		var icon: TextureRect = _slot_icons[i]
		var item: ItemData = null
		if i < items.size():
			item = items[i]
		if item != null:
			icon.texture = item.item_icon
			icon.tooltip_text = item.item_name
		else:
			icon.texture = null
			icon.tooltip_text = ""
