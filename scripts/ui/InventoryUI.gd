extends PanelContainer
## Inventory panel: builds a fixed grid of item slots and refreshes it whenever
## the global `SignalBus.inventory_updated` signal fires.

const SLOT_COUNT: int = 20

@onready var _grid: GridContainer = %InventoryGrid
@onready var _sort_button: Button = %SortButton

var _slots: Array[InventorySlotUI] = []


func _ready() -> void:
	SignalBus.inventory_updated.connect(_on_inventory_updated)
	SignalBus.slot_updated.connect(_on_slot_updated)
	SignalBus.inventory_reorganized.connect(_on_inventory_reorganized)
	
	_sort_button.pressed.connect(_on_sort_pressed)
	
	_build_slots()
	_refresh_slots()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_S:
			_on_sort_pressed()


func _build_slots() -> void:
	for i: int in SLOT_COUNT:
		var slot: InventorySlotUI = InventorySlotUI.new()
		_grid.add_child(slot)
		_slots.append(slot)


func _on_inventory_updated() -> void:
	_refresh_slots()


func _on_slot_updated(index: int) -> void:
	if index >= 0 and index < _slots.size():
		var slots: Array[InventorySlot] = InventoryManager.get_slots()
		if index < slots.size():
			_slots[index].set_item_slot(slots[index])


func _on_inventory_reorganized() -> void:
	_refresh_slots()


func _on_sort_pressed() -> void:
	if is_instance_valid(InventoryManager):
		InventoryManager.sort_inventory(true)


func _refresh_slots() -> void:
	var slots: Array[InventorySlot] = InventoryManager.get_slots()
	for i: int in _slots.size():
		var slot_data: InventorySlot = null
		if i < slots.size():
			slot_data = slots[i]
		_slots[i].set_item_slot(slot_data)
