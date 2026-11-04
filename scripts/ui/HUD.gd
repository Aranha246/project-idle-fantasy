extends CanvasLayer
## Heads-up display for the player's tiered currency.
##
## The root node is a CanvasLayer, so the HUD renders above the game world
## and stays fixed on screen regardless of the active Camera2D. It listens to
## the global `SignalBus.currency_updated` signal to refresh the labels.

@onready var copper_label: Label = %CopperLabel
@onready var silver_label: Label = %SilverLabel
@onready var gold_label: Label = %GoldLabel


func _ready() -> void:
	SignalBus.currency_updated.connect(_on_currency_updated)
	# Sync the display with the wallet's current state on spawn.
	_refresh_currency_labels(CurrencyManager.copper, CurrencyManager.silver, CurrencyManager.gold)


func _on_currency_updated(copper: int, silver: int, gold: int) -> void:
	_refresh_currency_labels(copper, silver, gold)


func _refresh_currency_labels(copper: int, silver: int, gold: int) -> void:
	copper_label.text = "%d CP" % copper
	silver_label.text = "%d SP" % silver
	gold_label.text = "%d GP" % gold
