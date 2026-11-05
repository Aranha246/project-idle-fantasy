class_name LootRoller
extends RefCounted
## Stateless loot resolution shared by every drop source (enemies, quests,
## gathering activities).
##
## Keeping the roll here — instead of inside the quest loop — is what finally
## makes equipment drop: the old reward code hardcoded an empty drops array and
## never consulted the enemies' loot tables. The roller resolves each table entry
## against `GameDatabase` and returns the shared `ItemData` instances, so an item
## picked up from the ground is the exact same resource the equipment and save
## systems already know about.

## Rolls a loot table and returns a list of drop records.
##
## Each record is `{"item": ItemData, "quantity": int}`. `drop_rate_modifier`
## folds together the player's luck and the zone bonus and scales every entry's
## base chance (clamped to 100%). `passes` runs the whole table more than once so
## a "rich" quest (or a tougher enemy) can yield more loot from the same table.
static func roll_from_loot_table(
	loot_table: Array,
	drop_rate_modifier: float,
	passes: int = 1
) -> Array:
	var drops: Array = []
	if loot_table.is_empty():
		return drops

	var modifier: float = maxf(0.0, drop_rate_modifier)
	var pass_count: int = maxi(1, passes)

	for _pass: int in pass_count:
		for entry: Variant in loot_table:
			var loot: EnemyData.LootEntry = entry as EnemyData.LootEntry
			if loot == null or loot.item_id == &"":
				continue

			var chance: float = clampf(loot.drop_chance * modifier, 0.0, 1.0)
			if randf() >= chance:
				continue

			var item: ItemData = GameDatabase.get_item(loot.item_id)
			if item == null:
				push_warning("LootRoller: loot table references unknown item '%s'." % loot.item_id)
				continue

			drops.append({"item": item, "quantity": loot.roll_quantity()})

	return drops


## Convenience wrapper that rolls a single enemy's loot table.
static func roll_from_enemy(
	enemy: Resource,
	drop_rate_modifier: float,
	passes: int = 1
) -> Array:
	if enemy == null:
		return []
	return roll_from_loot_table(enemy.loot_table, drop_rate_modifier, passes)


## Merges duplicate entries in a drop list so the reward summary reports one row
## per item with a summed quantity (stackable materials rolled several times).
static func merge_drops(drops: Array) -> Array:
	var merged: Array = []
	var index_by_id: Dictionary = {}
	for record: Variant in drops:
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = record
		var item: ItemData = entry.get("item")
		if item == null:
			continue
		var quantity: int = maxi(1, int(entry.get("quantity", 1)))
		var key: String = String(item.item_id)
		if index_by_id.has(key):
			var existing: Dictionary = merged[index_by_id[key]]
			existing["quantity"] = int(existing["quantity"]) + quantity
		else:
			index_by_id[key] = merged.size()
			merged.append({"item": item, "quantity": quantity})
	return merged


## Total number of individual items in a drop list (sum of quantities).
static func total_quantity(drops: Array) -> int:
	var total: int = 0
	for record: Variant in drops:
		if typeof(record) == TYPE_DICTIONARY:
			total += maxi(1, int((record as Dictionary).get("quantity", 1)))
	return total
