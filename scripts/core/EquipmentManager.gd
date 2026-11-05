extends Node
## Autoload singleton that owns the player's equipped items.
##
## Equipment is stored in a fixed, strongly-typed array of thirteen slot
## *instances* covering every authored equipment category; an empty slot is
## represented by `null`. Two of those instances share the `RING` category, so a
## slot is defined by its instance name (`RING_1`, `RING_2`) while what it
## accepts is defined by `SLOT_CATEGORIES`. This is a deliberate choice over a
## generic Dictionary so every access is statically typed.
##
## Changes are broadcast exclusively through `SignalBus.equipment_updated`,
## keeping the UI and every other system decoupled from this manager.

## Canonical slot instance names, in display order (matching the on-screen grid).
const SLOT_NAMES: Array[String] = [
	"HELMET",
	"TRINKET",
	"AMULET",
	"WEAPON",
	"OFF_HAND",
	"BODY_ARMOR",
	"RING_1",
	"RING_2",
	"NECKLACE",
	"BELT",
	"GLOVES",
	"BOOTS",
	"ARTIFACT",
]

## Human readable label for each slot instance, aligned with `SLOT_NAMES`.
const SLOT_LABELS: Array[String] = [
	"Helmet",
	"Trinket",
	"Amulet",
	"Weapon",
	"Off-Hand",
	"Body Armor",
	"Ring I",
	"Ring II",
	"Necklace",
	"Belt",
	"Gloves",
	"Boots",
	"Artifact",
]

## `ItemData.EquipmentSlot` category each slot instance accepts, aligned with
## `SLOT_NAMES`. Both ring instances accept the single `RING` category, which is
## exactly why a slot name can no longer be compared to a category directly.
const SLOT_CATEGORIES: Array[int] = [
	ItemData.EquipmentSlot.HELMET,
	ItemData.EquipmentSlot.TRINKET,
	ItemData.EquipmentSlot.AMULET,
	ItemData.EquipmentSlot.WEAPON,
	ItemData.EquipmentSlot.OFF_HAND,
	ItemData.EquipmentSlot.BODY_ARMOR,
	ItemData.EquipmentSlot.RING,
	ItemData.EquipmentSlot.RING,
	ItemData.EquipmentSlot.NECKLACE,
	ItemData.EquipmentSlot.BELT,
	ItemData.EquipmentSlot.GLOVES,
	ItemData.EquipmentSlot.BOOTS,
	ItemData.EquipmentSlot.ARTIFACT,
]

var _equipped: Array[ItemData] = []


func _ready() -> void:
	# Every slot starts empty (`null`).
	_equipped.resize(SLOT_NAMES.size())
	for i: int in SLOT_NAMES.size():
		_equipped[i] = null


## Returns the item equipped in `slot`, or `null` when the slot is empty or the
## slot name is invalid.
func get_equipped(slot: String) -> ItemData:
	var slot_index: int = _slot_index(slot)
	if slot_index == -1:
		return null
	return _equipped[slot_index]


## Returns the category a slot instance accepts, or `ItemData.EquipmentSlot.NONE`
## when the name is invalid.
func get_slot_category(slot: String) -> ItemData.EquipmentSlot:
	var slot_index: int = _slot_index(slot)
	if slot_index == -1:
		return ItemData.EquipmentSlot.NONE
	return SLOT_CATEGORIES[slot_index] as ItemData.EquipmentSlot


func get_slot_label(slot: String) -> String:
	var slot_index: int = _slot_index(slot)
	if slot_index == -1:
		return ""
	return SLOT_LABELS[slot_index]


## Returns `true` when `item` may be equipped in `slot` (correct category and
## actually equippable). Used both for equipping and for UI drop validation.
func can_equip_in(item: ItemData, slot: String) -> bool:
	if item == null:
		return false
	if not ItemData.is_valid_equipment_slot(item.equipment_slot):
		return false
	var slot_index: int = _slot_index(slot)
	if slot_index == -1:
		return false
	return int(item.equipment_slot) == SLOT_CATEGORIES[slot_index]


## Finds the first slot instance that can accept `item`, preferring an empty one
## so auto-equip never displaces an already equipped item. Returns an empty
## string when no slot accepts the item.
func find_slot_for_item(item: ItemData) -> String:
	if item == null or not ItemData.is_valid_equipment_slot(item.equipment_slot):
		return ""
	var fallback: String = ""
	for i: int in SLOT_NAMES.size():
		if int(item.equipment_slot) != SLOT_CATEGORIES[i]:
			continue
		if _equipped[i] == null:
			return SLOT_NAMES[i]
		if fallback.is_empty():
			fallback = SLOT_NAMES[i]
	return fallback


## Equips `item` into the first slot that accepts it. Returns the slot name used,
## or an empty string when the item is not equippable or not in the inventory.
func auto_equip(item: ItemData) -> String:
	var slot: String = find_slot_for_item(item)
	if slot.is_empty():
		return ""
	return slot if equip_item(item, slot) else ""


## Equips `item` into `slot`, returning `true` only on success.
##
## Fails (returning `false`) when the slot name is invalid, the item is `null`
## or not equippable, the item's category does not match the slot, or the item is
## not present in the player's inventory. Any item already occupying the slot is
## unequipped and returned to the inventory first.
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
	if int(item.equipment_slot) != SLOT_CATEGORIES[slot_index]:
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


## Read-only view of the current slots.
func get_slots() -> Array[ItemData]:
	return _equipped.duplicate()


## Serializes the equipped items as a slot name -> item id map. Empty slots map
## to an empty string.
func get_state() -> Dictionary:
	var state: Dictionary = {}
	for i: int in SLOT_NAMES.size():
		var item: ItemData = _equipped[i]
		state[SLOT_NAMES[i]] = String(item.item_id) if item != null else ""
	return state


## Restores equipment directly from a save file.
##
## Unlike `equip_item()`, this deliberately bypasses the inventory checks: a
## loaded item is already equipped, so it is not expected to be in the bag.
func load_state(data: Dictionary) -> void:
	for i: int in SLOT_NAMES.size():
		var slot_name: String = SLOT_NAMES[i]
		var item_id: StringName = StringName(str(data.get(slot_name, "")))

		var item: ItemData = null
		if item_id != &"":
			item = GameDatabase.get_item(item_id)
			if item == null:
				push_warning(
					"EquipmentManager: unknown item '%s' in save; clearing slot '%s'."
					% [item_id, slot_name]
				)

		_equipped[i] = item
		SignalBus.equipment_updated.emit(slot_name, item)


## Returns the index of `slot` within `SLOT_NAMES`, or `-1` when the name is not
## a valid equipment slot.
func _slot_index(slot: String) -> int:
	return SLOT_NAMES.find(slot)
