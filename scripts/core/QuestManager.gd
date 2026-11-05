extends Node
## Autoload singleton that owns the *player-driven* quest loop.
##
## This replaces the previous `IdleQuestManager`, whose combat timer ran on its
## own and completed enemies even when the player did nothing. Here, nothing
## happens until the player explicitly starts a quest from the UI:
##
##   1. `start_quest()` begins a timer scaled by the bought quest-speed upgrade.
##   2. `_process()` advances it and broadcasts `quest_progress`.
##   3. On completion the quest becomes *ready* and waits — it is never claimed
##      automatically.
##   4. `claim_quest()` rolls the enemy's loot table through `LootRoller`, grants
##      the currency (scaled by the reward upgrade) and the real `ItemData`
##      drops, then emits `quest_claimed`/`quest_completed`.
##
## Zone selection also lives here because the zone is what defines the available
## quests; the two are always changed together.

const QUEST_SCRIPT_PATH: String = "res://scripts/resources/QuestData.gd"

## Gold multiplier applied per zone tier, mirroring the old reward curve.
const GOLD_TIER_MULTIPLIER: float = 1.5

## Characters level every `LEVELS_PER_ZONE` levels past the first zone, which is
## always available. Zone index 1 therefore unlocks at level 5, matching the
## original hand-authored thresholds but without a hardcoded table.
const LEVELS_PER_ZONE: int = 4

## The zone the player is currently adventuring in.
var current_active_zone: Resource = null

var _available_quests: Array[QuestData] = []
var _active_quest: QuestData = null
var _elapsed: float = 0.0
var _duration: float = 0.0
var _ready_to_claim: bool = false


func _ready() -> void:
	# Quests must freeze while the game is paused, unlike the UI overlays.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	SignalBus.level_up.connect(_on_level_up)
	SignalBus.upgrades_updated.connect(_on_upgrades_updated)
	_select_default_zone()


func _process(delta: float) -> void:
	if _active_quest == null or _ready_to_claim:
		return
	_elapsed += delta
	if _elapsed >= _duration:
		_elapsed = _duration
		_ready_to_claim = true
		SignalBus.quest_progress.emit(_active_quest, 1.0, 0.0)
		SignalBus.quest_ready.emit(_active_quest)
		return
	var ratio: float = clampf(_elapsed / maxf(_duration, 0.001), 0.0, 1.0)
	SignalBus.quest_progress.emit(_active_quest, ratio, _duration - _elapsed)


# --- Zones -----------------------------------------------------------------

## Every zone the game knows about, in database order.
func get_all_zones() -> Array[Resource]:
	return GameDatabase.get_all_zones()


func get_active_zone() -> Resource:
	return current_active_zone


## Returns the id of the active zone, or an empty name when none is active.
func get_active_zone_id() -> StringName:
	if current_active_zone == null:
		return &""
	return current_active_zone.zone_id


## Returns the character level required to enter the zone at `index`.
func get_zone_unlock_level(index: int) -> int:
	if index <= 0:
		return 1
	return 1 + index * LEVELS_PER_ZONE


## Returns `true` when the player's level is high enough to enter `zone`.
func is_zone_unlocked(zone: Resource) -> bool:
	if zone == null:
		return false
	var index: int = get_all_zones().find(zone)
	if index < 0:
		return false
	return ProgressionManager.get_level() >= get_zone_unlock_level(index)


## Activates `zone`. Returns `false` when it is invalid or still locked, leaving
## the current zone untouched so the player never loses their progress.
func set_active_zone(zone: Resource) -> bool:
	if zone == null:
		return false
	if zone.has_method("validate"):
		var validation_error: String = zone.validate()
		if not validation_error.is_empty():
			push_error("QuestManager: invalid zone '%s'. %s" % [zone.zone_name, validation_error])
			return false
	if not is_zone_unlocked(zone):
		push_warning("QuestManager: zone '%s' is still locked." % zone.zone_name)
		return false

	current_active_zone = zone
	# Switching zones abandons any quest in flight; it belongs to the old zone.
	_active_quest = null
	_ready_to_claim = false
	_elapsed = 0.0
	SignalBus.zone_changed.emit(zone)
	_rebuild_quests()
	return true


## Activates a zone by its registry id. Returns `false` when the id is unknown
## or the zone is still locked.
func set_active_zone_by_id(zone_id: StringName) -> bool:
	var zone: Resource = GameDatabase.get_zone(zone_id)
	if zone == null:
		return false
	return set_active_zone(zone)


func _select_default_zone() -> void:
	var default_zone: Resource = GameDatabase.get_default_zone()
	if default_zone == null and not get_all_zones().is_empty():
		default_zone = get_all_zones()[0]
	if default_zone == null:
		push_error("QuestManager: no zones are registered in GameDatabase.")
		return
	set_active_zone(default_zone)


# --- Quest list ------------------------------------------------------------

## The quests currently on offer for the active zone.
func get_quests() -> Array[QuestData]:
	return _available_quests.duplicate()


func get_active_quest() -> QuestData:
	return _active_quest


func is_quest_running() -> bool:
	return _active_quest != null


func is_quest_ready() -> bool:
	return _active_quest != null and _ready_to_claim


## Total duration (seconds) the running quest will take, upgrade applied.
func get_quest_duration() -> float:
	return _duration


func get_quest_elapsed() -> float:
	return _elapsed


func get_quest_progress_ratio() -> float:
	if _duration <= 0.0:
		return 0.0
	return clampf(_elapsed / _duration, 0.0, 1.0)


# --- Quest actions ---------------------------------------------------------

## Starts `quest`. Returns `false` when another quest is already running, when
## the quest is not part of the active zone, or when it is invalid.
func start_quest(quest: QuestData) -> bool:
	if quest == null or _active_quest != null:
		return false
	if not _available_quests.has(quest):
		return false
	if not quest.validate().is_empty():
		push_warning("QuestManager: refusing to start invalid quest '%s'." % quest.quest_id)
		return false

	_active_quest = quest
	_elapsed = 0.0
	_ready_to_claim = false
	_duration = maxf(1.0, quest.base_duration * _duration_multiplier())
	SignalBus.quest_started.emit(quest, _duration)
	SignalBus.quest_progress.emit(quest, 0.0, _duration)
	return true


## Cancels a running quest that has not finished yet. A ready quest must be
## claimed instead, so its rewards are never lost.
func abandon_quest() -> void:
	if _active_quest == null or _ready_to_claim:
		return
	_active_quest = null
	_elapsed = 0.0
	_duration = 0.0
	SignalBus.quests_refreshed.emit()


## Claims a finished quest, granting its currency and item drops. Returns the
## reward dictionary (empty when no quest is ready to claim).
func claim_quest() -> Dictionary:
	if _active_quest == null or not _ready_to_claim:
		return {}

	var quest: QuestData = _active_quest
	var rewards: Dictionary = _resolve_rewards(quest)

	if int(rewards.get("gold", 0)) > 0:
		# Routing through this signal keeps currency logic in CurrencyManager.
		SignalBus.enemy_defeated.emit(int(rewards["gold"]))

	var granted_items: Array[ItemData] = []
	for record: Variant in rewards.get("drops", []):
		if typeof(record) != TYPE_DICTIONARY:
			continue
		var drop: Dictionary = record
		var item: ItemData = drop.get("item")
		if item == null:
			continue
		var quantity: int = maxi(1, int(drop.get("quantity", 1)))
		if is_instance_valid(InventoryManager) and InventoryManager.add_item(item, quantity):
			granted_items.append(item)
			SignalBus.item_dropped.emit(item, Vector2.ZERO)
	rewards["items"] = granted_items

	SignalBus.quest_claimed.emit(rewards)
	# Progression listens to `quest_completed` for experience, so it is emitted
	# with the same payload the old loop used.
	SignalBus.quest_completed.emit({
		"gold": int(rewards.get("gold", 0)),
		"items": granted_items,
		"drops": rewards.get("drops", []),
		"enemy": quest.enemy,
		"quest": quest,
	})

	_active_quest = null
	_ready_to_claim = false
	_elapsed = 0.0
	_duration = 0.0
	return rewards


# --- Internals -------------------------------------------------------------

func _duration_multiplier() -> float:
	if not is_instance_valid(UpgradeManager):
		return 1.0
	return UpgradeManager.get_quest_duration_multiplier()


func _reward_multiplier() -> float:
	if not is_instance_valid(UpgradeManager):
		return 1.0
	return UpgradeManager.get_reward_multiplier()


func _loot_modifier() -> float:
	var modifier: float = 1.0
	if current_active_zone != null and current_active_zone.has_method("get_scaled_drop_rate_modifier"):
		modifier = current_active_zone.get_scaled_drop_rate_modifier(StatsManager.get_luck())
	if is_instance_valid(UpgradeManager):
		modifier += UpgradeManager.get_loot_fortune()
	return modifier


## Rolls the loot table and computes the currency reward for a finished quest.
func _resolve_rewards(quest: QuestData) -> Dictionary:
	var tier: int = 1
	if current_active_zone != null:
		tier = int(current_active_zone.tier_level)

	var gold: int = int(round(
		float(quest.base_gold) * pow(GOLD_TIER_MULTIPLIER, float(tier - 1)) * _reward_multiplier()
	))

	var drops: Array = []
	if quest.enemy != null:
		drops = LootRoller.merge_drops(
			LootRoller.roll_from_enemy(quest.enemy, _loot_modifier(), quest.loot_passes)
		)

	return {
		"gold": maxi(0, gold),
		"drops": drops,
		"enemy": quest.enemy,
		"quest": quest,
	}


func _rebuild_quests() -> void:
	_available_quests.clear()
	if current_active_zone == null:
		SignalBus.quests_refreshed.emit()
		return

	for enemy: Variant in current_active_zone.monster_pool:
		var monster: Resource = enemy
		if monster == null:
			continue
		_available_quests.append(_make_battle_quest(monster))
	_available_quests.append(_make_activity_quest(QuestData.QuestType.EXPLORE))
	_available_quests.append(_make_activity_quest(QuestData.QuestType.GATHER))

	SignalBus.quests_refreshed.emit()


func _make_battle_quest(enemy: Resource) -> QuestData:
	var quest: QuestData = load(QUEST_SCRIPT_PATH).new()
	quest.quest_id = StringName("battle_%s_%s" % [current_active_zone.zone_id, String(enemy.enemy_name).to_snake_case()])
	quest.quest_name = "Hunt: %s" % enemy.enemy_name
	quest.quest_type = QuestData.QuestType.BATTLE
	quest.zone_id = current_active_zone.zone_id
	quest.enemy = enemy
	quest.base_duration = clampf(8.0 + float(enemy.base_health) * 0.12, 6.0, 120.0)
	quest.base_gold = 15 + int(round(float(enemy.base_health) * 0.35))
	quest.loot_passes = 1 + int(current_active_zone.tier_level / 2)
	quest.flavor = "Track down and defeat a %s." % enemy.enemy_name
	return quest


func _make_activity_quest(quest_type: QuestData.QuestType) -> QuestData:
	var quest: QuestData = load(QUEST_SCRIPT_PATH).new()
	var type_key: String = "explore" if quest_type == QuestData.QuestType.EXPLORE else "gather"
	quest.quest_id = StringName("%s_%s" % [type_key, current_active_zone.zone_id])
	quest.quest_type = quest_type
	quest.zone_id = current_active_zone.zone_id
	quest.enemy = _first_monster()

	if quest_type == QuestData.QuestType.EXPLORE:
		quest.quest_name = "Explore %s" % current_active_zone.zone_name
		quest.base_duration = 14.0
		quest.base_gold = 30
		quest.loot_passes = 2
		quest.flavor = "Scout the area for hidden treasure."
	else:
		quest.quest_name = "Gather in %s" % current_active_zone.zone_name
		quest.base_duration = 10.0
		quest.base_gold = 18
		quest.loot_passes = 3
		quest.flavor = "Harvest materials from the land."

	return quest


func _first_monster() -> Resource:
	if current_active_zone == null or current_active_zone.monster_pool.is_empty():
		return null
	return current_active_zone.monster_pool[0]


func _on_level_up(_new_level: int) -> void:
	# A new level can unlock a zone, so refresh the offered quests and let the
	# zone UI re-evaluate its lock states.
	SignalBus.quests_refreshed.emit()


func _on_upgrades_updated() -> void:
	if _active_quest == null:
		return
	# A quest-speed purchase shortens the remaining time proportionally so a
	# running quest immediately benefits from the upgrade.
	var new_duration: float = maxf(1.0, _active_quest.base_duration * _duration_multiplier())
	if new_duration >= _duration:
		return
	var remaining_ratio: float = 0.0
	if _duration > 0.0:
		remaining_ratio = clampf((_duration - _elapsed) / _duration, 0.0, 1.0)
	_duration = maxf(new_duration, 0.001)
	_elapsed = _duration * (1.0 - remaining_ratio)
	if _elapsed >= _duration:
		_ready_to_claim = true
		SignalBus.quest_ready.emit(_active_quest)
