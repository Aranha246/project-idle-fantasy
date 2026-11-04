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

@export var item_id: StringName = &""
@export var item_name: String = ""
@export var item_icon: Texture2D
@export var item_type: ItemType = ItemType.MATERIAL
@export var rarity: Rarity = Rarity.COMMON
@export var max_stack_size: int = 1
@export var sell_value_copper: int = 0
