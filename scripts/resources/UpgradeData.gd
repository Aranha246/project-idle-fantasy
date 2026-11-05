class_name UpgradeData
extends Resource
## Data definition for a single purchasable upgrade track.
##
## Follows the project's Resource-first rule: upgrade mechanics are authored as
## strongly typed resources instead of loose dictionaries, so `UpgradeManager`
## and the upgrade UI read the same fields and never re-implement the cost curve.

## What a level of the upgrade actually does.
enum EffectKind {
	## Adds `effect_per_level` to a base character stat (see `stat_key`).
	FLAT_STAT,
	## Reduces quest duration by a multiplicative factor per level.
	QUEST_SPEED,
	## Increases the currency earned from quest rewards.
	REWARD_MULTIPLIER,
	## Adds to the loot drop-rate modifier.
	LOOT_FORTUNE,
}

## Stable identifier used for persistence and signal payloads.
@export var upgrade_id: StringName = &""
@export var display_name: String = "Upgrade"
@export var description: String = ""
@export var effect_kind: EffectKind = EffectKind.FLAT_STAT

## Target stat for `FLAT_STAT` upgrades (e.g. "attack_power", "luck").
@export var stat_key: String = ""

## Magnitude applied per purchased level. Its meaning depends on `effect_kind`.
@export var effect_per_level: float = 1.0

## Copper cost of the first level.
@export var base_cost_copper: int = 100

## Multiplier applied to the cost for each subsequent level.
@export var cost_growth: float = 1.6

@export var max_level: int = 25


func _init() -> void:
	base_cost_copper = maxi(1, base_cost_copper)
	cost_growth = maxf(1.0, cost_growth)
	max_level = maxi(1, max_level)


## Copper cost to buy `level` going from `level - 1` to `level` (1-based).
func cost_for_level(level: int) -> int:
	if level < 1 or level > max_level:
		return -1
	return maxi(1, int(round(float(base_cost_copper) * pow(cost_growth, float(level - 1)))))


## How long the upgrade's effect is described in the UI, given a level.
func effect_summary(level: int) -> String:
	match effect_kind:
		EffectKind.QUEST_SPEED:
			return "-%.0f%% quest time" % ((1.0 - pow(1.0 - effect_per_level, float(level))) * 100.0)
		EffectKind.REWARD_MULTIPLIER:
			return "+%.0f%% quest rewards" % (effect_per_level * float(level) * 100.0)
		EffectKind.LOOT_FORTUNE:
			return "+%.0f%% drop rate" % (effect_per_level * float(level) * 100.0)
		_:
			return "+%.1f %s" % [effect_per_level * float(level), stat_key.replace("_", " ")]


func validate() -> String:
	if upgrade_id == &"":
		return "Upgrade id cannot be empty."
	if display_name.is_empty():
		return "Upgrade name cannot be empty."
	if effect_kind == EffectKind.FLAT_STAT and stat_key.is_empty():
		return "Flat stat upgrades require a stat key."
	return ""
