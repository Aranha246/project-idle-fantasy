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
