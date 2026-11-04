extends Node
## Drives the idle combat loop by simulating one combat tick per second.
##
## Each tick represents a defeated enemy: it awards Copper through
## `SignalBus.enemy_defeated` and may additionally roll for loot. A successful
## roll builds an `ItemData`, hands it to the inventory and announces it
## through `SignalBus.item_dropped`.
##
## This is a script-only Autoload, so it deliberately uses plain typed member
## variables (never `@export`) and is configured entirely from code.

const TICK_INTERVAL: float = 1.0
const MIN_REWARD_COPPER: int = 15
const MAX_REWARD_COPPER: int = 45

## Chance (0.0 - 1.0) that a defeated enemy drops a loot item. Configurable
## from code; intentionally not an `@export` so the autoload does not depend on
## inspector-authored values.
var loot_drop_chance: float = 0.25

## Item dropped when a roll succeeds. When left `null`, a built-in default loot
## item is generated instead (see `_create_loot_item`).
var loot_item: ItemData = null

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


## Rolls for a loot drop and, on success, hands the item to the inventory.
## Emitting `item_dropped` is left to `_grant_to_inventory` so the notification
## is only broadcast once the item truly exists in a slot.
func _try_drop_loot() -> void:
	var roll: float = randf()
	if roll >= loot_drop_chance:
		return
	print("[IdleQuestManager] Loot roll succeeded (roll=%.4f < chance=%.2f)." % [roll, loot_drop_chance])

	var item: ItemData = _create_loot_item()
	if item == null:
		push_error("IdleQuestManager: loot roll succeeded but no valid ItemData was produced.")
		return

	_grant_to_inventory(item)


## Returns the configured loot item, falling back to a freshly built default
## `ItemData` so a null `loot_item` never interrupts loot spawning.
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


## Adds `item` to the inventory and, only once the addition is confirmed,
## broadcasts `item_dropped`. Reports (but never crashes on) a missing singleton
## or a full inventory.
func _grant_to_inventory(item: ItemData) -> void:
	if not is_instance_valid(InventoryManager):
		push_error("IdleQuestManager: InventoryManager is unavailable; dropped '%s' was discarded." % item.item_name)
		return

	var added: bool = InventoryManager.add_item(item)
	if not added:
		push_warning("IdleQuestManager: inventory is full; dropped '%s' was discarded." % item.item_name)
		return

	print("[IdleQuestManager] Item '%s' (id=%s) added to inventory." % [item.item_name, item.item_id])
	SignalBus.item_dropped.emit(item, Vector2.ZERO)
