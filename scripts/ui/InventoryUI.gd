extends PanelContainer
## Inventory panel: builds a fixed grid of item slots and refreshes it whenever
## the global `SignalBus.inventory_updated` signal fires.

const SLOT_COUNT: int = 20

@onready var _grid: GridContainer = %InventoryGrid

var _slots: Array[InventorySlotUI] = []


func _ready() -> void:
	SignalBus.inventory_updated.connect(_on_inventory_updated)
	_build_slots()
	_refresh_slots()


func _build_slots() -> void:
	for i: int in SLOT_COUNT:
		var slot: InventorySlotUI = InventorySlotUI.new()
		_grid.add_child(slot)
		_slots.append(slot)


func _on_inventory_updated() -> void:
	_refresh_slots()


func _refresh_slots() -> void:
	var items: Array[ItemData] = InventoryManager.get_slots()
	for i: int in _slots.size():
		var item: ItemData = null
		if i < items.size():
			item = items[i]
		_slots[i].set_item(item)
