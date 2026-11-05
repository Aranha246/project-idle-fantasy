extends Node
## Autoload singleton that owns the player's purchased upgrades.
##
## Upgrades are the currency sink that turns earned Copper into character and
## quest progression: faster quests, richer rewards, better drop rates and flat
## stat gains. Every track is an authored `UpgradeData` resource, and all state
## is a level per track so it saves as a tiny id -> level map.
##
## The manager only ever *reports* its multipliers; `QuestManager`, `LootRoller`
## and `StatsManager` read them, keeping the effect direction one-way and the
## systems decoupled.

const UPGRADE_SCRIPT_PATH: String = "res://scripts/resources/UpgradeData.gd"

## Never let quest-speed upgrades shorten a quest below this fraction of its
## base duration, so quests always take a meaningful amount of time.
const MIN_DURATION_MULTIPLIER: float = 0.25

var _upgrades: Dictionary = {}
var _order: Array[StringName] = []
var _levels: Dictionary = {}


func _ready() -> void:
	_register_default_upgrades()
	for upgrade_id: StringName in _order:
		_levels[upgrade_id] = 0
	SignalBus.game_loaded.connect(_on_game_loaded)


func _on_game_loaded(_path: String) -> void:
	SignalBus.upgrades_updated.emit()


## Every upgrade track, in display order.
func get_all_upgrades() -> Array[UpgradeData]:
	var result: Array[UpgradeData] = []
	for upgrade_id: StringName in _order:
		result.append(_upgrades[upgrade_id])
	return result


func get_upgrade(upgrade_id: StringName) -> UpgradeData:
	return _upgrades.get(upgrade_id, null)


func get_level(upgrade_id: StringName) -> int:
	return int(_levels.get(upgrade_id, 0))


## Copper cost of the next level, or `-1` when the track is maxed or unknown.
func get_next_cost(upgrade_id: StringName) -> int:
	var upgrade: UpgradeData = get_upgrade(upgrade_id)
	if upgrade == null:
		return -1
	var next_level: int = get_level(upgrade_id) + 1
	return upgrade.cost_for_level(next_level)


func is_maxed(upgrade_id: StringName) -> bool:
	var upgrade: UpgradeData = get_upgrade(upgrade_id)
	if upgrade == null:
		return true
	return get_level(upgrade_id) >= upgrade.max_level


## Returns `true` when the player can currently afford the next level.
func can_afford(upgrade_id: StringName) -> bool:
	if is_maxed(upgrade_id):
		return false
	var cost: int = get_next_cost(upgrade_id)
	if cost < 0:
		return false
	return is_instance_valid(CurrencyManager) and CurrencyManager.get_total_copper() >= cost


## Buys one level of `upgrade_id`, spending the currency. Returns `true` on
## success; `false` when the track is unknown, maxed, or unaffordable.
func purchase(upgrade_id: StringName) -> bool:
	if not _upgrades.has(upgrade_id) or is_maxed(upgrade_id):
		return false
	var cost: int = get_next_cost(upgrade_id)
	if cost < 0:
		return false
	if not is_instance_valid(CurrencyManager) or not CurrencyManager.spend_copper(cost):
		return false

	var new_level: int = get_level(upgrade_id) + 1
	_levels[upgrade_id] = new_level
	SignalBus.upgrade_purchased.emit(upgrade_id, new_level)
	SignalBus.upgrades_updated.emit()
	return true


# --- Derived effects -------------------------------------------------------

## Flat bonus a stat receives from all flat-stat upgrades.
func get_stat_bonus(stat_key: String) -> float:
	var total: float = 0.0
	for upgrade_id: StringName in _order:
		var upgrade: UpgradeData = _upgrades[upgrade_id]
		if upgrade.effect_kind != UpgradeData.EffectKind.FLAT_STAT:
			continue
		if upgrade.stat_key != stat_key:
			continue
		total += upgrade.effect_per_level * float(get_level(upgrade_id))
	return total


## Multiplier applied to a quest's base duration (< 1.0 means faster).
func get_quest_duration_multiplier() -> float:
	var multiplier: float = 1.0
	for upgrade_id: StringName in _order:
		var upgrade: UpgradeData = _upgrades[upgrade_id]
		if upgrade.effect_kind != UpgradeData.EffectKind.QUEST_SPEED:
			continue
		multiplier *= pow(1.0 - upgrade.effect_per_level, float(get_level(upgrade_id)))
	return clampf(multiplier, MIN_DURATION_MULTIPLIER, 1.0)


## Multiplier applied to quest currency rewards (>= 1.0 means richer).
func get_reward_multiplier() -> float:
	var multiplier: float = 1.0
	for upgrade_id: StringName in _order:
		var upgrade: UpgradeData = _upgrades[upgrade_id]
		if upgrade.effect_kind != UpgradeData.EffectKind.REWARD_MULTIPLIER:
			continue
		multiplier += upgrade.effect_per_level * float(get_level(upgrade_id))
	return maxf(1.0, multiplier)


## Additive bonus folded into the loot drop-rate modifier.
func get_loot_fortune() -> float:
	var bonus: float = 0.0
	for upgrade_id: StringName in _order:
		var upgrade: UpgradeData = _upgrades[upgrade_id]
		if upgrade.effect_kind != UpgradeData.EffectKind.LOOT_FORTUNE:
			continue
		bonus += upgrade.effect_per_level * float(get_level(upgrade_id))
	return maxf(0.0, bonus)


# --- Persistence -----------------------------------------------------------

func get_state() -> Dictionary:
	var state: Dictionary = {}
	for upgrade_id: StringName in _order:
		state[String(upgrade_id)] = get_level(upgrade_id)
	return state


func load_state(data: Dictionary) -> void:
	for upgrade_id: StringName in _order:
		var upgrade: UpgradeData = _upgrades[upgrade_id]
		var level: int = clampi(int(data.get(String(upgrade_id), 0)), 0, upgrade.max_level)
		_levels[upgrade_id] = level
	SignalBus.upgrades_updated.emit()


# --- Authoring -------------------------------------------------------------

func _register_default_upgrades() -> void:
	_add_upgrade(&"quest_speed", "Pathfinder's Map", "Chart faster routes so quests finish sooner.", UpgradeData.EffectKind.QUEST_SPEED, "", 0.04, 120, 1.6, 25)
	_add_upgrade(&"reward_multiplier", "Merchant's Ledger", "Negotiate richer payouts from every quest.", UpgradeData.EffectKind.REWARD_MULTIPLIER, "", 0.08, 150, 1.65, 25)
	_add_upgrade(&"loot_fortune", "Fortune Charm", "Improve the chance that enemies drop loot.", UpgradeData.EffectKind.LOOT_FORTUNE, "", 0.03, 200, 1.7, 20)
	_add_upgrade(&"attack_power", "Weapon Training", "Permanently raises Attack Power.", UpgradeData.EffectKind.FLAT_STAT, "attack_power", 2.0, 100, 1.55, 30)
	_add_upgrade(&"defense", "Armor Training", "Permanently raises Defense.", UpgradeData.EffectKind.FLAT_STAT, "defense", 2.0, 100, 1.55, 30)
	_add_upgrade(&"luck", "Lucky Star", "Permanently raises Luck.", UpgradeData.EffectKind.FLAT_STAT, "luck", 1.0, 140, 1.6, 25)


func _add_upgrade(
	upgrade_id: StringName,
	display_name: String,
	description: String,
	effect_kind: UpgradeData.EffectKind,
	stat_key: String,
	effect_per_level: float,
	base_cost: int,
	cost_growth: float,
	max_level: int
) -> void:
	var upgrade: UpgradeData = load(UPGRADE_SCRIPT_PATH).new()
	upgrade.upgrade_id = upgrade_id
	upgrade.display_name = display_name
	upgrade.description = description
	upgrade.effect_kind = effect_kind
	upgrade.stat_key = stat_key
	upgrade.effect_per_level = effect_per_level
	upgrade.base_cost_copper = base_cost
	upgrade.cost_growth = cost_growth
	upgrade.max_level = max_level
	_upgrades[upgrade_id] = upgrade
	_order.append(upgrade_id)
