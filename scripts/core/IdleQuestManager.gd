extends Node
## Manages multiple gameplay zones, monster spawning, and stat-scaled combat.

const TICK_INTERVAL: float = 1.0

# Progression thresholds (simplified for now)
var zone_unlock_levels: Dictionary = {
	0: 1,  # Zone 0 unlocks at level 1
	1: 5,  # Zone 1 unlocks at level 5
}

## Scaling factors
@export var attack_power_speed_scaling: float = 0.005 # 0.5% speed per AP
@export var gold_tier_multiplier: float = 1.5 # 50% more gold per tier
@export var health_tier_multiplier: float = 2.0 # 100% more health per tier

## Current state
var current_active_zone: Resource = null
var current_enemy: Resource = null
var current_enemy_max_health: int = 0
var current_enemy_health: int = 0
var _player_stats: Dictionary = {}
var _combat_timer: Timer

# Pending rewards tracking
var _pending_gold: int = 0
var _pending_items: Array[ItemData] = []


func _ready() -> void:
	SignalBus.stats_updated.connect(_on_stats_updated)
	
	_combat_timer = Timer.new()
	_combat_timer.wait_time = TICK_INTERVAL
	_combat_timer.one_shot = false
	_combat_timer.timeout.connect(_on_combat_tick)
	add_child(_combat_timer)
	
	# Initial setup - we would normally load this from a database or resource collection
	_initialize_default_zone()


func set_active_zone(zone: Resource) -> void:
	if zone == null: return
	
	if zone.has_method("validate"):
		var validation_error: String = zone.validate()
		if not validation_error.is_empty():
			push_error("IdleQuestManager: invalid zone '%s'. %s" % [zone.zone_name, validation_error])
			return
		
	current_active_zone = zone
	SignalBus.zone_changed.emit(zone)
	_spawn_enemy()
	
	if not _combat_timer.is_inside_tree():
		await _combat_timer.ready
	_combat_timer.start()


func _initialize_default_zone() -> void:
	var starter_zone: Resource = GameDatabase.get_default_zone()
	if starter_zone == null:
		push_error("IdleQuestManager: no default zone is registered in GameDatabase.")
		return
	set_active_zone(starter_zone)


## Returns the id of the active zone, or an empty name when none is active.
func get_active_zone_id() -> StringName:
	if current_active_zone == null:
		return &""
	return current_active_zone.zone_id


## Activates a zone by its registry id. Returns `false` when the id is unknown,
## so callers can fall back to the current zone instead of clearing it.
func set_active_zone_by_id(zone_id: StringName) -> bool:
	var zone: Resource = GameDatabase.get_zone(zone_id)
	if zone == null:
		return false
	set_active_zone(zone)
	return true


func _on_stats_updated(stats: Dictionary) -> void:
	_player_stats = stats
	
	# Update combat speed based on Attack Power
	var atk: float = stats.attack_power.total
	var speed_mod: float = 1.0 / (1.0 + (atk * attack_power_speed_scaling))
	_combat_timer.wait_time = TICK_INTERVAL * speed_mod


func _on_combat_tick() -> void:
	if current_enemy == null:
		_spawn_enemy()
		return
		
	# Combat logic: each tick deals damage to the enemy
	var damage: int = int(_player_stats.get("attack_power", {"total": 10.0}).total)
	current_enemy_health -= damage
	
	if current_enemy_health <= 0:
		_complete_enemy()
	else:
		SignalBus.enemy_health_updated.emit(current_enemy_health, current_enemy_max_health)


func _spawn_enemy() -> void:
	if current_active_zone == null or current_active_zone.monster_pool.is_empty():
		return
		
	# Weighted selection
	var total_weight: float = 0.0
	for monster in current_active_zone.monster_pool:
		total_weight += monster.spawn_weight
		
	var roll: float = randf() * total_weight
	var current_weight: float = 0.0
	
	for monster in current_active_zone.monster_pool:
		current_weight += monster.spawn_weight
		if roll <= current_weight:
			current_enemy = monster
			break
			
	# Scale health to zone tier
	var tier: int = current_active_zone.tier_level
	current_enemy_max_health = int(current_enemy.base_health * pow(health_tier_multiplier, tier - 1))
	current_enemy_health = current_enemy_max_health
	
	SignalBus.enemy_spawned.emit(current_enemy, current_enemy_health, current_enemy_max_health)


func _complete_enemy() -> void:
	var rewards := _calculate_quest_rewards()
	
	# Grant rewards
	if rewards.gold > 0:
		SignalBus.enemy_defeated.emit(rewards.gold)
		
	for item in rewards.items:
		_grant_to_inventory(item)
		
	SignalBus.quest_completed.emit({
		"gold": rewards.gold,
		"items": rewards.items,
		"enemy": current_enemy
	})
	
	_spawn_enemy()


func _calculate_quest_rewards() -> Dictionary:
	var tier: int = current_active_zone.tier_level
	var luck: float = _player_stats.get("luck", {"total": 0.0}).total
	
	# Gold scaling
	var base_gold: int = randi_range(15, 45)
	var scaled_gold: int = int(base_gold * pow(gold_tier_multiplier, tier - 1))
	
	# Item drops
	var dropped_items: Array[ItemData] = []
	# For now, we use a simple chance based on luck and zone
	var drop_mod: float = current_active_zone.get_scaled_drop_rate_modifier(luck)
	
	# We would normally iterate through enemy loot tables here
	# For this implementation, let's just keep the default loot roll if applicable
	
	return {
		"gold": scaled_gold,
		"items": dropped_items
	}


func _grant_to_inventory(item: ItemData) -> void:
	if is_instance_valid(InventoryManager) and InventoryManager.add_item(item):
		SignalBus.item_dropped.emit(item, Vector2.ZERO)
