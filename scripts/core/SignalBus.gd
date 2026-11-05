extends Node
## Global signal hub used to decouple game logic from the UI layer.
##
## Registered as an Autoload singleton named `SignalBus`. Emitters and
## listeners never reference each other directly; they communicate purely
## through these signals.

## Emitted whenever the player's wallet changes, after tier auto-conversion.
## Values are always the fully normalized Copper / Silver / Gold amounts.
signal currency_updated(copper: int, silver: int, gold: int)

## Emitted when an enemy is defeated, carrying the Copper reward to be granted.
signal enemy_defeated(reward_copper: int)

## Emitted whenever the contents of the player's inventory change.
signal inventory_updated()

## Emitted when a specific inventory slot is updated.
signal slot_updated(index: int)

## Emitted when the inventory is full and an item cannot be added.
signal inventory_full()

## Emitted after the inventory has been sorted and reorganized.
signal inventory_reorganized()

## Emitted when a defeated enemy drops an item, with the drop position used
## for in-game feedback.
signal item_dropped(item_data: ItemData, drop_position: Vector2)

## Emitted whenever a piece of equipment changes. `slot_name` identifies the
## modified equipment slot and `item_data` is the newly equipped item, or `null`
## when the slot was cleared (unequipped).
signal equipment_updated(slot_name: String, item_data: ItemData)

## Emitted whenever player stats are recalculated.
## `stats` is a Dictionary containing: "attack_power", "defense", "critical_rate", "luck"
## Each entry is a Sub-Dictionary: {"base": float, "total": float, "bonus": float}
signal stats_updated(stats: Dictionary)

## Emitted when the active zone changes.
signal zone_changed(new_zone: Resource)

## Emitted when a new enemy is spawned.
signal enemy_spawned(enemy_data: Resource, current_health: int, max_health: int)

## Emitted when an enemy's health changes.
signal enemy_health_updated(current_health: int, max_health: int)

## Emitted when a quest (combat tick) is completed with rewards.
signal quest_completed(rewards: Dictionary)

## Emitted whenever a player setting changes and has been applied.
## `settings` is a snapshot dictionary (see `SettingsManager.get_snapshot()`).
signal settings_changed(settings: Dictionary)

## Emitted after the game state has been written to disk.
signal game_saved(path: String)

## Emitted after the game state has been restored from disk.
signal game_loaded(path: String)

## Emitted when the player gains experience points.
signal xp_gained(amount: int, current_xp: int, xp_to_next: int)

## Emitted when the player reaches a new character level.
signal level_up(new_level: int)

## Emitted when the pause state toggles. `paused` is the new state.
signal pause_toggled(paused: bool)

## Emitted when the credits sequence has finished playing.
signal credits_finished()
