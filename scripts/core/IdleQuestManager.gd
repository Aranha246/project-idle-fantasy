extends Node
## Drives the idle combat loop by simulating one combat tick per second.
##
## Each tick represents a defeated enemy: it awards Copper through
## `SignalBus.enemy_defeated` and may additionally roll for loot. A successful
## roll builds an `ItemData`, hands it to the inventory and announces it
## through `SignalBus.item_dropped`.

const TICK_INTERVAL: float = 1.0
const MIN_REWARD_COPPER: int = 15
const MAX_REWARD_COPPER: int = 45

## Chance (0.0 - 1.0) that a defeated enemy drops a loot item.
@export_range(0.0, 1.0, 0.01) var loot_drop_chance: float = 0.25

## Item dropped when a roll succeeds. When left empty, a built-in default
## loot item is generated instead (see `_create_loot_item`).
@export var loot_item: ItemData

var _combat_timer: Timer


func _ready() -> void:
	_combat_timer = Timer.new()
	_combat_timer.wait_time = TICK_INTERVAL
	_combat_timer.one_shot = false
	_combat_timer.autostart = true
	_combat_timer.timeout.connect(_on_combat_tick)
	add_child(_combat_timer)


func _on_combat_tick() -> void:
	var reward_copper: int = randi_range(MIN_REWARD_COPPER, MAX_REWARD_COPPER)
	SignalBus.enemy_defeated.emit(reward_copper)
	_try_drop_loot()


## Rolls for a loot drop and, on success, grants it to the inventory before
## broadcasting the `item_dropped` notification.
func _try_drop_loot() -> void:
	if randf() >= loot_drop_chance:
		return

	var item: ItemData = _create_loot_item()
	if item == null:
		push_error("IdleQuestManager: loot roll succeeded but no valid ItemData was produced.")
		return

	if not _grant_to_inventory(item):
		return

	SignalBus.item_dropped.emit(item, Vector2.ZERO)


## Returns the configured loot item, falling back to a built-in default.
func _create_loot_item() -> ItemData:
	if loot_item != null:
		return loot_item

	var default_item: ItemData = ItemData.new()
	default_item.item_id = &"rusty_dagger"
	default_item.item_name = "Rusty Dagger"
	default_item.item_type = ItemData.ItemType.WEAPON
	default_item.rarity = ItemData.Rarity.COMMON
	default_item.max_stack_size = 1
	default_item.sell_value_copper = 10
	return default_item


## Places `item` into the inventory, reporting (but never crashing on) the
## cases where the singleton is missing or the inventory has no free slot.
func _grant_to_inventory(item: ItemData) -> bool:
	if not is_instance_valid(InventoryManager):
		push_error("IdleQuestManager: InventoryManager is unavailable; dropped '%s' was discarded." % item.item_name)
		return false
	if not InventoryManager.add_item(item):
		push_warning("IdleQuestManager: inventory is full; dropped '%s' was discarded." % item.item_name)
		return false
	return true
