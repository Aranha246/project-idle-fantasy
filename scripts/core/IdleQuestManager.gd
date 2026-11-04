extends Node
## Drives the idle combat loop by simulating combat ticks modified by player stats.

const TICK_INTERVAL: float = 1.0
const MIN_REWARD_COPPER: int = 15
const MAX_REWARD_COPPER: int = 45

# Base quest failure rate
var base_failure_chance: float = 0.10 # 10%
var base_loot_drop_chance: float = 0.25

## Scaling factors for stat-driven progression
var attack_power_scaling: float = 0.005 # 0.5% speed increase per point
var luck_drop_scaling: float = 0.01 # 1% drop chance increase per point
var defense_fail_reduction: float = 0.005 # 0.5% failure reduction per point

## Current player stats snapshot
var _player_stats: Dictionary = {}

var _combat_timer: Timer
var loot_item: ItemData = null


func _ready() -> void:
	SignalBus.stats_updated.connect(_on_stats_updated)
	
	_combat_timer = Timer.new()
	_combat_timer.wait_time = TICK_INTERVAL
	_combat_timer.one_shot = false
	_combat_timer.autostart = true
	_combat_timer.timeout.connect(_on_combat_tick)
	add_child(_combat_timer)


func _on_stats_updated(stats: Dictionary) -> void:
	_player_stats = stats
	
	# Update combat speed based on Attack Power
	var atk: float = stats.attack_power.total
	var speed_mod: float = 1.0 / (1.0 + (atk * attack_power_scaling))
	_combat_timer.wait_time = TICK_INTERVAL * speed_mod
	
	print("[IdleQuestManager] Stats updated. New Tick Interval: %.3fs" % _combat_timer.wait_time)


func _on_combat_tick() -> void:
	if _check_quest_failure():
		print("[IdleQuestManager] Quest tick failed!")
		return
		
	var reward_copper: int = randi_range(MIN_REWARD_COPPER, MAX_REWARD_COPPER)
	SignalBus.enemy_defeated.emit(reward_copper)
	_try_drop_loot()


func _check_quest_failure() -> bool:
	var def: float = _player_stats.get("defense", {"total": 0.0}).total
	var atk: float = _player_stats.get("attack_power", {"total": 0.0}).total
	
	# Combined defense and attack power reduce failure chance
	var reduction: float = (def * defense_fail_reduction) + (atk * 0.001)
	var current_fail_chance: float = max(0.01, base_failure_chance - reduction)
	
	return randf() < current_fail_chance


func _try_drop_loot() -> void:
	var luck: float = _player_stats.get("luck", {"total": 0.0}).total
	var current_drop_chance: float = base_loot_drop_chance + (luck * luck_drop_scaling)
	
	var roll: float = randf()
	if roll >= current_drop_chance:
		return
		
	var item: ItemData = _create_loot_item()
	if item != null:
		_grant_to_inventory(item)


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
	default_item.equipment_slot = ItemData.EquipmentSlot.WEAPON
	# Default stats for the rusty dagger
	default_item.attack_power_mod = 2.0
	default_item.luck_mod = 1.0
	
	return default_item


func _grant_to_inventory(item: ItemData) -> void:
	if not is_instance_valid(InventoryManager):
		return
		
	if InventoryManager.add_item(item):
		SignalBus.item_dropped.emit(item, Vector2.ZERO)
