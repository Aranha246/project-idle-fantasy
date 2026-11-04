class_name ZoneData
extends Resource
## Data definition for a gameplay zone with specific tiers and monster pools.

@export var zone_name: String = "New Zone"
@export var tier_level: int = 1:
	set(value):
		tier_level = clampi(value, 1, 10)
@export var monster_pool: Array = []
@export var background_texture: Texture2D
@export var flavor_description: String = ""
@export var base_drop_rate_modifier: float = 1.0:
	set(value):
		base_drop_rate_modifier = maxf(0.0, value)
@export var rare_drop_rate_bonus: float = 0.0:
	set(value):
		rare_drop_rate_bonus = maxf(0.0, value)


func _init() -> void:
	# Enforce validation on instantiation if properties are set.
	# Note: Exported variables are set after _init in Godot, 
	# so we also use setters for runtime validation.
	tier_level = clampi(tier_level, 1, 10)
	base_drop_rate_modifier = maxf(0.0, base_drop_rate_modifier)
	rare_drop_rate_bonus = maxf(0.0, rare_drop_rate_bonus)


## Calculates the final drop rate by combining zone base modifier with player luck.
func get_scaled_drop_rate_modifier(player_luck: float) -> float:
	# Logic: base zone modifier + additive luck bonus (1% per luck point)
	return base_drop_rate_modifier + (player_luck * 0.01)


## Validates the zone configuration. Returns an empty string if valid, or an error message.
func validate() -> String:
	if zone_name.is_empty():
		return "Zone name cannot be empty."
	if monster_pool.is_empty():
		return "Monster pool cannot be empty."
	for monster in monster_pool:
		if monster == null:
			return "Monster pool contains null entries."
	return ""
