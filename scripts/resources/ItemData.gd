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
	## Generic equippable item. New authored equipment uses this type and carries
	## its real category in `equipment_slot`; the legacy `WEAPON`/`ARMOR` values
	## are kept only so already-persisted saves keep their meaning.
	EQUIPMENT,
}

enum Rarity {
	COMMON,
	UNCOMMON,
	RARE,
	EPIC,
	LEGENDARY,
}

## Equipment category an item belongs to.
##
## `NONE` marks an item as not equippable; every other value is a valid category
## and is validated by `is_valid_equipment_slot()` before any equipment
## operation. Note that a category is not the same as a slot instance: `RING`
## maps to two distinct player slots (the first and second ring).
enum EquipmentSlot {
	NONE = -1,
	HELMET = 0,
	TRINKET = 1,
	AMULET = 2,
	WEAPON = 3,
	OFF_HAND = 4,
	BODY_ARMOR = 5,
	RING = 6,
	NECKLACE = 7,
	BELT = 8,
	GLOVES = 9,
	BOOTS = 10,
	ARTIFACT = 11,
}

## Canonical name of each equipment category, indexed by its enum value. Used for
## tooltips, logs and any UI that needs to describe an item's category.
const SLOT_NAMES: Array[String] = [
	"HELMET",
	"TRINKET",
	"AMULET",
	"WEAPON",
	"OFF_HAND",
	"BODY_ARMOR",
	"RING",
	"NECKLACE",
	"BELT",
	"GLOVES",
	"BOOTS",
	"ARTIFACT",
]

## Human readable label for each equipment category, indexed by enum value.
const SLOT_LABELS: Array[String] = [
	"Helmet",
	"Trinket",
	"Amulet",
	"Weapon",
	"Off-Hand",
	"Body Armor",
	"Ring",
	"Necklace",
	"Belt",
	"Gloves",
	"Boots",
	"Artifact",
]

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


## Returns `true` only for valid equipment categories, guarding every equipment
## operation against invalid slot assignments.
static func is_valid_equipment_slot(slot: EquipmentSlot) -> bool:
	var index: int = int(slot)
	return index >= 0 and index < SLOT_NAMES.size()


## Converts a canonical slot name (as used by `EquipmentManager`) into its enum
## value, or `EquipmentSlot.NONE` when the name is not a valid equipment slot.
static func slot_from_name(slot_name: String) -> EquipmentSlot:
	var index: int = SLOT_NAMES.find(slot_name)
	if index < 0:
		return EquipmentSlot.NONE
	return index as EquipmentSlot


## Converts an equipment slot enum value into its canonical name, or an empty
## string when the value is not a valid equipment slot.
static func slot_to_name(slot: EquipmentSlot) -> String:
	if not is_valid_equipment_slot(slot):
		return ""
	return SLOT_NAMES[int(slot)]


## Returns the human readable label for an equipment category, or an empty
## string when the value is not a valid equipment Slot.
static func slot_label(slot: EquipmentSlot) -> String:
	if not is_valid_equipment_slot(slot):
		return ""
	return SLOT_LABELS[int(slot)]
