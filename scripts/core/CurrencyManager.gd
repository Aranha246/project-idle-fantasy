extends Node
## Autoload singleton that owns the player's tiered currency.
##
## Holds the wallet as three normalized tiers and auto-converts overflow
## upwards: 100 Copper = 1 Silver, 100 Silver = 1 Gold.
## Any change is broadcast through `SignalBus.currency_updated`.

const COPPER_PER_SILVER: int = 100
const SILVER_PER_GOLD: int = 100

var copper: int = 0
var silver: int = 0
var gold: int = 0


func _ready() -> void:
	SignalBus.enemy_defeated.connect(_on_enemy_defeated)


## Total wallet value expressed in Copper, so affordability can be compared
## against a single number regardless of how the tiers are broken up.
func get_total_copper() -> int:
	return copper + silver * COPPER_PER_SILVER + gold * COPPER_PER_SILVER * SILVER_PER_GOLD


## Adds raw Copper to the wallet, then normalizes and broadcasts the result.
func add_copper(amount: int) -> void:
	if amount <= 0:
		return
	copper += amount
	_normalize_tiers()
	SignalBus.currency_updated.emit(copper, silver, gold)


## Spends `amount` Copper when the wallet can afford it. Returns `true` on
## success and `false` (leaving the wallet untouched) when the player is short,
## which is the guard the upgrade system relies on.
func spend_copper(amount: int) -> bool:
	if amount <= 0:
		return false
	var total: int = get_total_copper()
	if total < amount:
		return false

	var remainder: int = total - amount
	gold = remainder / (COPPER_PER_SILVER * SILVER_PER_GOLD)
	remainder %= COPPER_PER_SILVER * SILVER_PER_GOLD
	silver = remainder / COPPER_PER_SILVER
	copper = remainder % COPPER_PER_SILVER
	_normalize_tiers()
	SignalBus.currency_updated.emit(copper, silver, gold)
	return true


@warning_ignore("integer_division")
func _normalize_tiers() -> void:
	silver += copper / COPPER_PER_SILVER
	copper %= COPPER_PER_SILVER
	gold += silver / SILVER_PER_GOLD
	silver %= SILVER_PER_GOLD


func _on_enemy_defeated(reward_copper: int) -> void:
	add_copper(reward_copper)


## Serializes the wallet for `SaveManager`.
func get_state() -> Dictionary:
	return {"copper": copper, "silver": silver, "gold": gold}


## Restores the wallet from a save file, normalizing tiers and broadcasting.
func load_state(data: Dictionary) -> void:
	copper = maxi(0, int(data.get("copper", 0)))
	silver = maxi(0, int(data.get("silver", 0)))
	gold = maxi(0, int(data.get("gold", 0)))
	_normalize_tiers()
	SignalBus.currency_updated.emit(copper, silver, gold)
