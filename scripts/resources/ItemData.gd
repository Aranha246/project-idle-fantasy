class_name ItemData
extends Resource
## Data definition for a single item (weapon, armor, consumable or material).
##
## Custom Resource so item databases can be authored in the editor and shared
## between systems without hardcoded dictionaries, per project standards.

enum ItemType {
	WEAPON,
	ARMOR,
	CONSUMABLE,
	MATERIAL,
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

## Equipment slots an item may be assigned to.
## `NONE` marks an item as not equippable; only `WEAPON`, `ARMOR` and
## `ACCESSORY` are valid equipment slots and are validated by
## `is_valid_equipment_slot()` before any equipment operation.
enum EquipmentSlot {
	NONE = -1,
	WEAPON = 0,
	ARMOR = 1,
	ACCESSORY = 2,
}

@export var item_id: StringName = &""
@export var item_name: String = ""
@export var item_icon: Texture2D
@export var item_type: ItemType = ItemType.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
@export var max_stack_size: int = 1
@export var sell_value_copper: int = 0

## Stat modifiers granted when this item is equipped.
@export var attack_power_mod: float = 0.0
@export var defense_mod: float = 0.0
@export var critical_rate_mod: float = 0.0 # Additive (e.g., 0.05 for 5%)
@export var luck_mod: float = 0.0 # Additive drop rate modifier

## The equipment slot this item may be equipped in. Keep it `EquipmentSlot.NONE`
## (the default) for anything that is not equippable.
@export var equipment_slot: EquipmentSlot = EquipmentSlot.NONE


## Returns `true` only for the three valid equipment slots, guarding every
## equipment operation against invalid slot assignments.
static func is_valid_equipment_slot(slot: EquipmentSlot) -> bool:
	return (
		slot == EquipmentSlot.WEAPON
		or slot == EquipmentSlot.ARMOR
		or slot == EquipmentSlot.ACCESSORY
	)


## Converts a canonical slot name (as used by `EquipmentManager`) into its enum
## value, or `EquipmentSlot.NONE` when the name is not a valid equipment slot.
static func slot_from_name(slot_name: String) -> EquipmentSlot:
	match slot_name:
		"WEAPON":
			return EquipmentSlot.WEAPON
		"ARMOR":
			return EquipmentSlot.ARMOR
		"ACCESSORY":
			return EquipmentSlot.ACCESSORY
	return EquipmentSlot.NONE


## Converts an equipment slot enum value into its canonical name, or an empty
## string when the value is not a valid equipment slot.
static func slot_to_name(slot: EquipmentSlot) -> String:
	match slot:
		EquipmentSlot.WEAPON:
			return "WEAPON"
		EquipmentSlot.ARMOR:
			return "ARMOR"
		EquipmentSlot.ACCESSORY:
			return "ACCESSORY"
	return ""
