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

## Emitted when a defeated enemy drops an item, with the drop position used
## for in-game feedback.
signal item_dropped(item_data: ItemData, drop_position: Vector2)

## Emitted whenever a piece of equipment changes. `slot_name` identifies the
## modified equipment slot and `item_data` is the newly equipped item, or `null`
## when the slot was cleared (unequipped).
signal equipment_updated(slot_name: String, item_data: ItemData)
