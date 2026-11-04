extends Node
## Autoload singleton that owns the player's equipped items.
##
## Equipment is stored in a fixed, strongly-typed array of exactly three slots
## (Weapon, Armor, Accessory); an empty slot is represented by `null`. This is a
## deliberate choice over a generic Dictionary so every access is statically
## typed. Changes are broadcast exclusively through `SignalBus.equipment_updated`,
## keeping the UI and every other system decoupled from this manager.

## Canonical slot names, ordered so the array index matches the numeric value of
## `ItemData.EquipmentSlot`: 0 -> WEAPON, 1 -> ARMOR, 2 -> ACCESSORY.
const SLOT_NAMES: Array[String] = ["WEAPON", "ARMOR", "ACCESSORY"]

var _equipped: Array[ItemData] = []


func _ready() -> void:
	# All three slots start empty (`null`).
	_equipped.resize(SLOT_NAMES.size())


## Returns the item equipped in `slot`, or `null` when the slot is empty or the
## slot name is invalid.
func get_equipped(slot: String) -> ItemData:
	var slot_index: int = _slot_index(slot)
	if slot_index == -1:
		return null
	return _equipped[slot_index]


## Equips `item` into `slot`, returning `true` only on success.
##
## Fails (returning `false`) when the slot name is invalid, the item is `null`
## or not equippable, the item is not allowed in the requested slot, or the item
## is not present in the player's inventory. Any item already occupying the slot
## is unequipped and returned to the inventory first.
func equip_item(item: ItemData, slot: String) -> bool:
	var slot_index: int = _slot_index(slot)
	if slot_index == -1:
		push_warning("EquipmentManager: '%s' is not a valid equipment slot." % slot)
		return false
	if item == null:
		push_warning("EquipmentManager: cannot equip a null item.")
		return false
	if not ItemData.is_valid_equipment_slot(item.equipment_slot):
		push_warning("EquipmentManager: item '%s' is not equippable." % item.item_name)
		return false
	if int(item.equipment_slot) != slot_index:
		push_warning(
			"EquipmentManager: item '%s' cannot be equipped in the '%s' slot."
			% [item.item_name, slot]
		)
		return false
	if not is_instance_valid(InventoryManager) or not InventoryManager.has_item(item):
		push_warning("EquipmentManager: item '%s' is not in the inventory." % item.item_name)
		return false

	# Remove the incoming item first so that a freed slot is guaranteed to exist
	# for any item displaced from the target slot, even when the inventory is
	# otherwise full.
	if not InventoryManager.remove_item(item):
		push_warning(
			"EquipmentManager: failed to remove item '%s' from the inventory." % item.item_name
		)
		return false

	if _equipped[slot_index] != null:
		var displaced: ItemData = unequip_item(slot)
		if displaced == null:
			# Roll back so the inventory keeps the item it started with.
			InventoryManager.add_item(item)
			push_error("EquipmentManager: could not displace the item in slot '%s'." % slot)
			return false

	_equipped[slot_index] = item
	SignalBus.equipment_updated.emit(slot, item)
	return true


## Unequips the item in `slot`, returns it to the inventory and hands the removed
## `ItemData` back to the caller. Returns `null` when the slot is invalid or
## empty. If the item cannot be returned to the inventory it is kept equipped
## (returning `null`) so it is never silently destroyed.
func unequip_item(slot: String) -> ItemData:
	var slot_index: int = _slot_index(slot)
	if slot_index == -1:
		push_warning("EquipmentManager: '%s' is not a valid equipment slot." % slot)
		return null
	var item: ItemData = _equipped[slot_index]
	if item == null:
		return null
	if not is_instance_valid(InventoryManager) or not InventoryManager.add_item(item):
		push_error("EquipmentManager: no inventory space to unequip '%s'." % item.item_name)
		return null
	_equipped[slot_index] = null
	SignalBus.equipment_updated.emit(slot, null)
	return item


## Returns the index of `slot` within `SLOT_NAMES`, or `-1` when the name is not
## a valid equipment slot.
func _slot_index(slot: String) -> int:
	return SLOT_NAMES.find(slot)
