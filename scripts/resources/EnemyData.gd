class_name EnemyData
extends Resource
## Data definition for an enemy with health, attack type, and loot tables.

@export var enemy_name: String = "Monster"
@export var base_health: int = 100
@export_enum("melee", "ranged", "magic") var attack_type: String = "melee"
@export var loot_table: Array = []
@export var spawn_weight: float = 1.0
@export var enemy_sprite: Texture2D


## Nested resource class to track item drop data.
class LootEntry extends Resource:
	@export var item_id: StringName = &""
	@export var drop_chance: float = 0.1 # 10%
	@export var min_quantity: int = 1
	@export var max_quantity: int = 1
	
	func roll_drop() -> int:
		if randf() < drop_chance:
			return randi_range(min_quantity, max_quantity)
		return 0
