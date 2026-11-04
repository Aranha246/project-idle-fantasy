class_name InventorySlot
extends RefCounted
## A single slot in the inventory, tracking the item and its current stack count.

var item: ItemData = null
var stack_count: int = 0

func _init(p_item: ItemData = null, p_count: int = 0) -> void:
	item = p_item
	stack_count = p_count

func is_empty() -> bool:
	return item == null

func can_stack_item(p_item: ItemData) -> bool:
	if is_empty(): return false
	return item.item_id == p_item.item_id and stack_count < item.max_stack_size

func get_remaining_capacity() -> int:
	if is_empty(): return 0
	return item.max_stack_size - stack_count
