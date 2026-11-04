extends Node
## Autoload singleton that owns the player's inventory.
##
## Slots are modelled as a fixed-size, strongly-typed array; an empty slot is
## represented by `null`. Changes are broadcast through
## `SignalBus.inventory_updated` so the UI stays fully decoupled.

const MAX_CAPACITY: int = 20

var _slots: Array[ItemData] = []


func _ready() -> void:
	_slots.resize(MAX_CAPACITY)


## Places `item` in the first empty slot and returns whether it succeeded.
## Returns `false` for a null item or when the inventory is full.
func add_item(item: ItemData) -> bool:
	if item == null:
		return false
	var empty_index: int = _slots.find(null)
	if empty_index == -1:
		return false
	_slots[empty_index] = item
	SignalBus.inventory_updated.emit()
	return true
