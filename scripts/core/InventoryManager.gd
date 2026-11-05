extends Node
## Autoload singleton that owns the player's inventory.
##
## Slots are modelled as a fixed-size, strongly-typed array; an empty slot is
## represented by `null`. Changes are broadcast through
## `SignalBus.inventory_updated` so the UI stays fully decoupled.

const MAX_CAPACITY: int = 20
const SORT_COOLDOWN_MS: int = 1000

var _slots: Array[InventorySlot] = []
var _last_sort_time: int = 0


func _ready() -> void:
	for i in MAX_CAPACITY:
		_slots.append(InventorySlot.new())


## Read-only view of the current slots.
func get_slots() -> Array[InventorySlot]:
	return _slots.duplicate()


## Adds `item` to the inventory, prioritizing stacking with existing items.
## Returns `false` if the item could not be fully added (inventory full).
func add_item(item: ItemData, quantity: int = 1) -> bool:
	if item == null or quantity <= 0:
		return false
	
	var remaining_to_add: int = quantity
	
	# 1. Try stacking in existing partial stacks
	if item.max_stack_size > 1:
		for i in _slots.size():
			var slot: InventorySlot = _slots[i]
			if slot.can_stack_item(item):
				var can_add: int = min(remaining_to_add, slot.get_remaining_capacity())
				slot.stack_count += can_add
				remaining_to_add -= can_add
				SignalBus.slot_updated.emit(i)
				
				if remaining_to_add <= 0:
					SignalBus.inventory_updated.emit()
					return true
	
	# 2. Allocate remaining to new empty slots
	while remaining_to_add > 0:
		var empty_index: int = -1
		for i in _slots.size():
			if _slots[i].is_empty():
				empty_index = i
				break
		
		if empty_index == -1:
			SignalBus.inventory_full.emit()
			# If we added some but not all, we still return false to indicate it wasn't FULLY added
			# but the partial addition remains.
			SignalBus.inventory_updated.emit()
			return false
			
		var can_add: int = min(remaining_to_add, item.max_stack_size)
		_slots[empty_index] = InventorySlot.new(item, can_add)
		remaining_to_add -= can_add
		SignalBus.slot_updated.emit(empty_index)
	
	SignalBus.inventory_updated.emit()
	return true


## Reorganizes the inventory: packs empty slots to the end, then sorts by
## item rarity (descending), item type, and item ID.
func sort_inventory(force_sort: bool = false) -> void:
	var current_time: int = Time.get_ticks_msec()
	if not force_sort and current_time - _last_sort_time < SORT_COOLDOWN_MS:
		return
	
	_last_sort_time = current_time
	
	# 1. Separate items from empty slots
	var items: Array[InventorySlot] = []
	for slot in _slots:
		if not slot.is_empty():
			items.append(slot)
	
	# 2. Sort the items
	items.sort_custom(func(a: InventorySlot, b: InventorySlot) -> bool:
		# Primary: Rarity (descending)
		if a.item.rarity != b.item.rarity:
			return a.item.rarity > b.item.rarity
			
		# Secondary: Item Type
		var a_prio: int = _get_type_priority(a.item.item_type)
		var b_prio: int = _get_type_priority(b.item.item_type)
		if a_prio != b_prio:
			return a_prio < b_prio
			
		# Tertiary: Item ID (grouping)
		return a.item.item_id < b.item.item_id
	)
	
	# 3. Rebuild the slots array
	for i in MAX_CAPACITY:
		if i < items.size():
			_slots[i] = items[i]
		else:
			_slots[i] = InventorySlot.new()
	
	SignalBus.inventory_reorganized.emit()
	SignalBus.inventory_updated.emit()


func _get_type_priority(type: ItemData.ItemType) -> int:
	match type:
		ItemData.ItemType.CONSUMABLE: return 0
		ItemData.ItemType.WEAPON, ItemData.ItemType.ARMOR: return 1
		ItemData.ItemType.MATERIAL: return 2
	return 99


## Returns whether any slot holds an item with the matching data.
func has_item(item: ItemData) -> bool:
	if item == null:
		return false
	for slot in _slots:
		if not slot.is_empty() and slot.item == item:
			return true
	return false


## Removes one or more of an item from the inventory.
func remove_item(item: ItemData, quantity: int = 1) -> bool:
	if item == null or quantity <= 0:
		return false
		
	var remaining_to_remove: int = quantity
	
	# Iterate backwards to remove from partial stacks first or just keep it simple?
	# Standard behavior is to remove from the end or just any matching slot.
	for i in range(_slots.size() - 1, -1, -1):
		var slot: InventorySlot = _slots[i]
		if not slot.is_empty() and slot.item.item_id == item.item_id:
			var can_remove: int = min(remaining_to_remove, slot.stack_count)
			slot.stack_count -= can_remove
			remaining_to_remove -= can_remove
			
			if slot.stack_count <= 0:
				_slots[i] = InventorySlot.new()
			
			SignalBus.slot_updated.emit(i)
			
			if remaining_to_remove <= 0:
				SignalBus.inventory_updated.emit()
				return true
				
	SignalBus.inventory_updated.emit()
	return remaining_to_remove == 0


## Serializes the occupied slots, preserving their grid positions so a restored
## inventory looks exactly as the player left it.
func get_state() -> Array:
	var entries: Array = []
	for i: int in _slots.size():
		var slot: InventorySlot = _slots[i]
		if slot.is_empty():
			continue
		entries.append({
			"index": i,
			"item_id": String(slot.item.item_id),
			"count": slot.stack_count,
		})
	return entries


## Restores the inventory from a save file. Unknown item ids are skipped with a
## warning instead of aborting the whole load.
func load_state(entries: Array) -> void:
	for i: int in _slots.size():
		_slots[i] = InventorySlot.new()

	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var data: Dictionary = entry
		var index: int = int(data.get("index", -1))
		if index < 0 or index >= _slots.size():
			continue

		var item_id: StringName = StringName(str(data.get("item_id", "")))
		var count: int = int(data.get("count", 0))
		if item_id == &"" or count <= 0:
			continue

		var item: ItemData = GameDatabase.get_item(item_id)
		if item == null:
			push_warning("InventoryManager: unknown item '%s' in save; skipped." % item_id)
			continue

		_slots[index] = InventorySlot.new(item, mini(count, item.max_stack_size))

	SignalBus.inventory_updated.emit()

