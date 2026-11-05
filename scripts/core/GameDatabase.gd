extends Node
## Central registry for authored game content (items and zones).
##
## Registered as an Autoload singleton named `GameDatabase`.
##
## Before this existed, zone definitions were duplicated between
## `IdleQuestManager` and `ZoneSelectionUI`, and items had no way to be resolved
## from a saved identifier. This database is the single source of truth for both,
## which lets `SaveManager` persist stable ids and rebuild live `Resource`
## instances on load.

const ZONE_SCRIPT_PATH: String = "res://scripts/resources/ZoneData.gd"
const ENEMY_SCRIPT_PATH: String = "res://scripts/resources/EnemyData.gd"
const ITEM_SCRIPT_PATH: String = "res://scripts/resources/ItemData.gd"

## Zone the game starts in and falls back to when a save has no valid zone.
const DEFAULT_ZONE_ID: StringName = &"whispering_woods"

var _items: Dictionary = {}
var _zones: Dictionary = {}
var _zone_order: Array[StringName] = []


func _ready() -> void:
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
	return item


func _register_default_zones() -> void:
	_make_zone(
		&"whispering_woods",
		"Whispering Woods",
		1,
		[_make_enemy("Green Slime", 50, 10.0)],
		"A calm forest on the edge of the kingdom."
	)
	_make_zone(
		&"shadow_cave",
		"Shadow Cave",
		2,
		[_make_enemy("Shadow Bat", 120, 10.0)],
		"A lightless cavern crawling with restless bats."
	)


func _make_enemy(enemy_name: String, health: int, weight: float) -> Resource:
	var enemy: Resource = load(ENEMY_SCRIPT_PATH).new()
	enemy.enemy_name = enemy_name
	enemy.base_health = health
	enemy.spawn_weight = weight
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
