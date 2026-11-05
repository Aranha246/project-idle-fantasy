class_name QuestData
extends Resource
## Data definition for a single, player-initiated quest.
##
## Every quest the player can undertake is one of these resources. A quest is
## never started automatically — `QuestManager` only runs a quest after the player
## presses its Start button — which is what replaces the old self-playing loop.

enum QuestType {
	## Fight a specific monster from the zone.
	BATTLE,
	## Scout the zone for knowledge and treasure.
	EXPLORE,
	## Harvest materials from the zone.
	GATHER,
}

@export var quest_id: StringName = &""
@export var quest_name: String = ""
@export var quest_type: QuestType = QuestType.BATTLE

## Zone this quest belongs to; only offered while that zone is active.
@export var zone_id: StringName = &""

## Monster whose loot table is rolled when the quest is claimed.
@export var enemy: Resource = null

## Seconds the quest takes before upgrade bonuses are applied.
@export_range(1.0, 600.0) var base_duration: float = 18.0

## Copper awarded on completion, before tier and reward-multiplier scaling.
@export var base_gold: int = 25

## How many times the loot table is rolled on claim.
@export_range(1, 5) var loot_passes: int = 1

@export var flavor: String = ""


func type_label() -> String:
	match quest_type:
		QuestType.EXPLORE:
			return "Explore"
		QuestType.GATHER:
			return "Gather"
		_:
			return "Battle"


func validate() -> String:
	if quest_id == &"":
		return "Quest id cannot be empty."
	if quest_name.is_empty():
		return "Quest name cannot be empty."
	if zone_id == &"":
		return "Quest must belong to a zone."
	if base_duration <= 0.0:
		return "Quest duration must be positive."
	if base_gold < 0:
		return "Quest gold reward cannot be negative."
	return ""
