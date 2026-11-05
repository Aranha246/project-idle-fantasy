extends Node
## Central registry for authored game content (items and zones).
##
## Registered as an Autoload singleton named `GameDatabase`.
##
## Before this existed, zone definitions were duplicated between the quest
## manager and the zone UI, and items had no way to be resolved from a saved
## identifier. This database is the single source of truth for both, which lets
## `SaveManager` persist stable ids and rebuild live `Resource` instances on
## load, and lets the loot roller resolve an item id into a real `ItemData`.
##
## All authored content is built here as strongly typed `Resource` instances so
## every consumer (inventory, equipment, loot, save) shares one definition per
## item instead of comparing loose dictionaries.

const ZONE_SCRIPT_PATH: String = "res://scripts/resources/ZoneData.gd"
const ENEMY_SCRIPT_PATH: String = "res://scripts/resources/EnemyData.gd"
const ITEM_SCRIPT_PATH: String = "res://scripts/resources/ItemData.gd"

## Zone the game starts in and falls back to when a save has no valid zone.
const DEFAULT_ZONE_ID: StringName = &"whispering_woods"

var _items: Dictionary = {}
var _zones: Dictionary = {}
var _zone_order: Array[StringName] = []


func _ready() -> void:
	# Items are registered before zones so every loot entry has a target to
	# resolve against from the very first session.
	_register_default_items()
	_register_default_zones()


## Registers (or replaces) an item so it can later be resolved by id.
func register_item(item: ItemData) -> void:
	if item == null or item.item_id == &"":
		return
	_items[item.item_id] = item


## Returns the registered item for `item_id`, or `null` when unknown.
func get_item(item_id: StringName) -> ItemData:
	return _items.get(item_id, null)


func has_item(item_id: StringName) -> bool:
	return _items.has(item_id)


## Every registered item, in registration order.
func get_all_items() -> Array[ItemData]:
	var result: Array[ItemData] = []
	for item_id: StringName in _items.keys():
		result.append(_items[item_id])
	return result


## Registers (or replaces) a zone. Zones without an id are rejected, because a
## stable id is what makes save/load possible.
func register_zone(zone: Resource) -> void:
	if zone == null:
		return
	var zone_id: StringName = zone.zone_id
	if zone_id == &"":
		push_warning("GameDatabase: zone '%s' has no id and was not registered." % zone.zone_name)
		return
	if not _zones.has(zone_id):
		_zone_order.append(zone_id)
	_zones[zone_id] = zone


## Returns the zone registered under `zone_id`, or `null` when unknown.
func get_zone(zone_id: StringName) -> Resource:
	return _zones.get(zone_id, null)


## All registered zones, in registration order.
func get_all_zones() -> Array[Resource]:
	var result: Array[Resource] = []
	for zone_id: StringName in _zone_order:
		result.append(_zones[zone_id])
	return result


func get_default_zone() -> Resource:
	return get_zone(DEFAULT_ZONE_ID)


## Flattens an `ItemData` into JSON-safe primitives so it can be persisted
## alongside the save file. Textures are intentionally not serialized.
func serialize_item(item: ItemData) -> Dictionary:
	if item == null:
		return {}
	return {
		"item_name": item.item_name,
		"item_type": int(item.item_type),
		"rarity": int(item.rarity),
		"max_stack_size": item.max_stack_size,
		"sell_value_copper": item.sell_value_copper,
		"attack_power_mod": item.attack_power_mod,
		"defense_mod": item.defense_mod,
		"critical_rate_mod": item.critical_rate_mod,
		"luck_mod": item.luck_mod,
		"equipment_slot": int(item.equipment_slot),
		"required_level": item.required_level,
	}


## Rebuilds an `ItemData` from the primitive dictionary written by
## `serialize_item()`. Every field is explicitly converted because JSON has no
## notion of integers or enums.
func deserialize_item(item_id: StringName, data: Dictionary) -> ItemData:
	var item: ItemData = load(ITEM_SCRIPT_PATH).new()
	item.item_id = item_id
	item.item_name = str(data.get("item_name", ""))
	item.item_type = int(data.get("item_type", ItemData.ItemType.MATERIAL))
	item.rarity = int(data.get("rarity", ItemData.Rarity.COMMON))
	item.max_stack_size = maxi(1, int(data.get("max_stack_size", 1)))
	item.sell_value_copper = maxi(0, int(data.get("sell_value_copper", 0)))
	item.attack_power_mod = float(data.get("attack_power_mod", 0.0))
	item.defense_mod = float(data.get("defense_mod", 0.0))
	item.critical_rate_mod = float(data.get("critical_rate_mod", 0.0))
	item.luck_mod = float(data.get("luck_mod", 0.0))
	item.equipment_slot = int(data.get("equipment_slot", ItemData.EquipmentSlot.NONE))
	item.required_level = maxi(0, int(data.get("required_level", 0)))
	return item


# --- Item authoring --------------------------------------------------------

## Builds an item definition. Kept in code (rather than scattered `.tres`
## files) so the whole catalogue is reviewable in one place; the resulting
## objects are the `ItemData` Resources the rest of the game consumes.
func _make_item(
	item_id: StringName,
	item_name: String,
	item_type: ItemData.ItemType,
	rarity: ItemData.Rarity,
	equipment_slot: ItemData.EquipmentSlot,
	attack_power_mod: float,
	defense_mod: float,
	critical_rate_mod: float,
	luck_mod: float,
	max_stack_size: int,
	sell_value_copper: int,
	required_level: int = 0
) -> ItemData:
	var item: ItemData = load(ITEM_SCRIPT_PATH).new()
	item.item_id = item_id
	item.item_name = item_name
	item.item_type = item_type
	item.rarity = rarity
	item.equipment_slot = equipment_slot
	item.attack_power_mod = attack_power_mod
	item.defense_mod = defense_mod
	item.critical_rate_mod = critical_rate_mod
	item.luck_mod = luck_mod
	item.max_stack_size = maxi(1, max_stack_size)
	item.sell_value_copper = maxi(0, sell_value_copper)
	item.required_level = maxi(0, required_level)
	return item


func _register_default_items() -> void:
	# Consumables and materials (stackable, never equipped).
	register_item(_make_item(&"health_potion", "Health Potion", ItemData.ItemType.CONSUMABLE, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.NONE, 0.0, 0.0, 0.0, 0.0, 20, 12))
	register_item(_make_item(&"mana_potion", "Mana Potion", ItemData.ItemType.CONSUMABLE, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.NONE, 0.0, 0.0, 0.0, 0.0, 20, 18))
	register_item(_make_item(&"greater_elixir", "Greater Elixir", ItemData.ItemType.CONSUMABLE, ItemData.Rarity.RARE, ItemData.EquipmentSlot.NONE, 0.0, 0.0, 0.0, 0.0, 10, 60))
	register_item(_make_item(&"slime_gel", "Slime Gel", ItemData.ItemType.MATERIAL, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.NONE, 0.0, 0.0, 0.0, 0.0, 99, 3))
	register_item(_make_item(&"bat_wing", "Bat Wing", ItemData.ItemType.MATERIAL, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.NONE, 0.0, 0.0, 0.0, 0.0, 99, 4))
	register_item(_make_item(&"iron_ore", "Iron Ore", ItemData.ItemType.MATERIAL, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.NONE, 0.0, 0.0, 0.0, 0.0, 99, 8))
	register_item(_make_item(&"ancient_relic", "Ancient Relic", ItemData.ItemType.MATERIAL, ItemData.Rarity.RARE, ItemData.EquipmentSlot.NONE, 0.0, 0.0, 0.0, 0.0, 99, 25))

	# Helmet.
	register_item(_make_item(&"leather_cap", "Leather Cap", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.HELMET, 0.0, 2.0, 0.0, 0.0, 1, 20))
	register_item(_make_item(&"iron_helm", "Iron Helm", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.HELMET, 0.0, 5.0, 0.0, 0.0, 1, 60))
	register_item(_make_item(&"dragon_helm", "Dragon Helm", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.EPIC, ItemData.EquipmentSlot.HELMET, 0.0, 14.0, 0.01, 0.0, 1, 400))

	# Trinket.
	register_item(_make_item(&"lucky_charm", "Lucky Charm", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.TRINKET, 0.0, 0.0, 0.0, 2.0, 1, 25))
	register_item(_make_item(&"clover_pendant", "Clover Pendant", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.TRINKET, 0.0, 0.0, 0.0, 6.0, 1, 150))
	register_item(_make_item(&"fate_coin", "Fate Coin", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.LEGENDARY, ItemData.EquipmentSlot.TRINKET, 0.0, 0.0, 0.03, 15.0, 1, 1200))

	# Amulet.
	register_item(_make_item(&"copper_amulet", "Copper Amulet", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.AMULET, 2.0, 0.0, 0.0, 0.0, 1, 22))
	register_item(_make_item(&"sapphire_amulet", "Sapphire Amulet", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.AMULET, 7.0, 0.0, 0.02, 0.0, 1, 160))

	# Weapon.
	register_item(_make_item(&"rusty_dagger", "Rusty Dagger", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.WEAPON, 3.0, 0.0, 0.0, 0.0, 1, 15))
	register_item(_make_item(&"iron_sword", "Iron Sword", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.WEAPON, 8.0, 0.0, 0.0, 0.0, 1, 70))
	register_item(_make_item(&"steel_axe", "Steel Axe", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.WEAPON, 15.0, 0.0, 0.02, 0.0, 1, 180))
	register_item(_make_item(&"flame_blade", "Flame Blade", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.EPIC, ItemData.EquipmentSlot.WEAPON, 26.0, 0.0, 0.04, 0.0, 1, 520, 5))
	register_item(_make_item(&"dragonfang", "Dragonfang", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.LEGENDARY, ItemData.EquipmentSlot.WEAPON, 40.0, 0.0, 0.06, 0.0, 1, 1500, 8))

	# Off-hand.
	register_item(_make_item(&"wooden_shield", "Wooden Shield", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.OFF_HAND, 0.0, 3.0, 0.0, 0.0, 1, 18))
	register_item(_make_item(&"iron_buckler", "Iron Buckler", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.OFF_HAND, 0.0, 7.0, 0.0, 0.0, 1, 65))
	register_item(_make_item(&"aegis_shield", "Aegis Shield", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.EPIC, ItemData.EquipmentSlot.OFF_HAND, 0.0, 18.0, 0.0, 0.0, 1, 460, 5))

	# Body armor.
	register_item(_make_item(&"cloth_tunic", "Cloth Tunic", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.BODY_ARMOR, 0.0, 4.0, 0.0, 0.0, 1, 24))
	register_item(_make_item(&"chain_mail", "Chain Mail", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.BODY_ARMOR, 0.0, 9.0, 0.0, 0.0, 1, 85))
	register_item(_make_item(&"plate_armor", "Plate Armor", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.BODY_ARMOR, 0.0, 16.0, 0.0, 0.0, 1, 210))
	register_item(_make_item(&"dragonscale_mail", "Dragonscale Mail", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.LEGENDARY, ItemData.EquipmentSlot.BODY_ARMOR, 0.0, 30.0, 0.0, 0.0, 1, 1400, 8))

	# Ring (equippable in either ring slot).
	register_item(_make_item(&"copper_ring", "Copper Ring", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.RING, 1.0, 0.0, 0.0, 1.0, 1, 20))
	register_item(_make_item(&"silver_ring", "Silver Ring", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.RING, 3.0, 0.0, 0.0, 2.0, 1, 75))
	register_item(_make_item(&"ruby_ring", "Ruby Ring", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.RING, 6.0, 0.0, 0.02, 0.0, 1, 190))
	register_item(_make_item(&"signet_of_kings", "Signet of Kings", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.EPIC, ItemData.EquipmentSlot.RING, 10.0, 0.0, 0.0, 5.0, 1, 500, 6))

	# Necklace.
	register_item(_make_item(&"simple_necklace", "Simple Necklace", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.NECKLACE, 0.0, 0.0, 0.0, 1.0, 1, 20))
	register_item(_make_item(&"pearl_necklace", "Pearl Necklace", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.NECKLACE, 0.0, 0.0, 0.0, 3.0, 1, 70))
	register_item(_make_item(&"heart_of_forest", "Heart of the Forest", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.NECKLACE, 0.0, 6.0, 0.0, 4.0, 1, 175))

	# Belt.
	register_item(_make_item(&"leather_belt", "Leather Belt", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.BELT, 0.0, 2.0, 0.0, 0.0, 1, 18))
	register_item(_make_item(&"reinforced_belt", "Reinforced Belt", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.BELT, 0.0, 6.0, 0.0, 0.0, 1, 62))
	register_item(_make_item(&"titan_belt", "Titan Belt", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.EPIC, ItemData.EquipmentSlot.BELT, 6.0, 15.0, 0.0, 0.0, 1, 430))

	# Gloves.
	register_item(_make_item(&"cloth_gloves", "Cloth Gloves", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.GLOVES, 1.0, 0.0, 0.0, 0.0, 1, 16))
	register_item(_make_item(&"gauntlets", "Gauntlets", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.GLOVES, 4.0, 2.0, 0.0, 0.0, 1, 68))
	register_item(_make_item(&"assassin_grips", "Assassin Grips", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.GLOVES, 9.0, 0.0, 0.03, 0.0, 1, 195))

	# Boots.
	register_item(_make_item(&"worn_boots", "Worn Boots", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.COMMON, ItemData.EquipmentSlot.BOOTS, 0.0, 2.0, 0.0, 0.0, 1, 16))
	register_item(_make_item(&"swift_boots", "Swift Boots", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.UNCOMMON, ItemData.EquipmentSlot.BOOTS, 0.0, 4.0, 0.0, 2.0, 1, 72))
	register_item(_make_item(&"windsong_boots", "Windsong Boots", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.BOOTS, 0.0, 8.0, 0.0, 5.0, 1, 200))

	# Artifact.
	register_item(_make_item(&"cracked_orb", "Cracked Orb", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.RARE, ItemData.EquipmentSlot.ARTIFACT, 12.0, 0.0, 0.0, 6.0, 1, 260))
	register_item(_make_item(&"eternal_heart", "Eternal Heart", ItemData.ItemType.EQUIPMENT, ItemData.Rarity.LEGENDARY, ItemData.EquipmentSlot.ARTIFACT, 22.0, 12.0, 0.05, 10.0, 1, 2000, 10))


# --- Zone authoring --------------------------------------------------------

func _make_loot_entry(item_id: StringName, drop_chance: float, min_quantity: int, max_quantity: int) -> Resource:
	var entry: EnemyData.LootEntry = EnemyData.LootEntry.new()
	entry.item_id = item_id
	entry.drop_chance = clampf(drop_chance, 0.0, 1.0)
	entry.min_quantity = maxi(1, min_quantity)
	entry.max_quantity = maxi(min_quantity, max_quantity)
	return entry


func _register_default_zones() -> void:
	_make_zone(
		&"whispering_woods",
		"Whispering Woods",
		1,
		[_make_enemy("Green Slime", 50, 10.0, [
			_make_loot_entry(&"slime_gel", 0.9, 1, 3),
			_make_loot_entry(&"health_potion", 0.2, 1, 1),
			_make_loot_entry(&"iron_ore", 0.25, 1, 2),
			_make_loot_entry(&"rusty_dagger", 0.16, 1, 1),
			_make_loot_entry(&"leather_cap", 0.13, 1, 1),
			_make_loot_entry(&"cloth_tunic", 0.13, 1, 1),
			_make_loot_entry(&"cloth_gloves", 0.12, 1, 1),
			_make_loot_entry(&"worn_boots", 0.12, 1, 1),
			_make_loot_entry(&"wooden_shield", 0.1, 1, 1),
			_make_loot_entry(&"leather_belt", 0.1, 1, 1),
			_make_loot_entry(&"copper_ring", 0.09, 1, 1),
			_make_loot_entry(&"copper_amulet", 0.08, 1, 1),
			_make_loot_entry(&"simple_necklace", 0.08, 1, 1),
			_make_loot_entry(&"lucky_charm", 0.06, 1, 1),
		])],
		"A calm forest on the edge of the kingdom."
	)
	_make_zone(
		&"shadow_cave",
		"Shadow Cave",
		2,
		[_make_enemy("Shadow Bat", 120, 10.0, [
			_make_loot_entry(&"bat_wing", 0.9, 1, 3),
			_make_loot_entry(&"mana_potion", 0.25, 1, 1),
			_make_loot_entry(&"greater_elixir", 0.1, 1, 1),
			_make_loot_entry(&"ancient_relic", 0.08, 1, 1),
			_make_loot_entry(&"iron_sword", 0.18, 1, 1),
			_make_loot_entry(&"chain_mail", 0.15, 1, 1),
			_make_loot_entry(&"iron_helm", 0.15, 1, 1),
			_make_loot_entry(&"iron_buckler", 0.13, 1, 1),
			_make_loot_entry(&"reinforced_belt", 0.12, 1, 1),
			_make_loot_entry(&"gauntlets", 0.12, 1, 1),
			_make_loot_entry(&"swift_boots", 0.12, 1, 1),
			_make_loot_entry(&"silver_ring", 0.1, 1, 1),
			_make_loot_entry(&"pearl_necklace", 0.1, 1, 1),
			_make_loot_entry(&"sapphire_amulet", 0.08, 1, 1),
			_make_loot_entry(&"clover_pendant", 0.06, 1, 1),
		])],
		"A lightless cavern crawling with restless bats."
	)


func _make_enemy(enemy_name: String, health: int, weight: float, loot_table: Array) -> Resource:
	var enemy: Resource = load(ENEMY_SCRIPT_PATH).new()
	enemy.enemy_name = enemy_name
	enemy.base_health = health
	enemy.spawn_weight = weight
	enemy.loot_table = loot_table
	return enemy


func _make_zone(
	zone_id: StringName,
	zone_name: String,
	tier: int,
	monster_pool: Array,
	description: String
) -> void:
	var zone: Resource = load(ZONE_SCRIPT_PATH).new()
	zone.zone_id = zone_id
	zone.zone_name = zone_name
	zone.tier_level = tier
	zone.monster_pool = monster_pool
	zone.flavor_description = description
	register_zone(zone)
