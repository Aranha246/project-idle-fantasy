extends PanelContainer
## Heads-up display for the player's level, experience and tiered currency.
##
## The root node is a `PanelContainer` so the panel is laid out by the HUD's
## shared container row in `Main.gd` (which owns the screen-fixed CanvasLayer),
## guaranteeing it never overlaps the neighbouring panels. It listens to the
## global `SignalBus.currency_updated` and progression signals to refresh the
## labels without ever polling a manager.

@onready var level_label: Label = %LevelLabel
@onready var xp_bar: ProgressBar = %XPBar
@onready var copper_label: Label = %CopperLabel
@onready var silver_label: Label = %SilverLabel
@onready var gold_label: Label = %GoldLabel


func _ready() -> void:
	SignalBus.currency_updated.connect(_on_currency_updated)
	SignalBus.xp_gained.connect(_on_xp_gained)
	SignalBus.level_up.connect(_on_level_up)
	# A loaded save rewrites progression without emitting xp/level signals, so
	# refresh explicitly when a session is restored.
	SignalBus.game_loaded.connect(_on_game_loaded)

	# Sync the display with the current state on spawn.
	_refresh_currency_labels(CurrencyManager.copper, CurrencyManager.silver, CurrencyManager.gold)
	_refresh_progression(ProgressionManager.get_level(), ProgressionManager.get_xp(), ProgressionManager.get_xp_to_next())


func _on_game_loaded(_path: String) -> void:
	_refresh_currency_labels(CurrencyManager.copper, CurrencyManager.silver, CurrencyManager.gold)
	_refresh_progression(ProgressionManager.get_level(), ProgressionManager.get_xp(), ProgressionManager.get_xp_to_next())


func _on_currency_updated(copper: int, silver: int, gold: int) -> void:
	_refresh_currency_labels(copper, silver, gold)


func _on_xp_gained(_amount: int, current_xp: int, xp_to_next: int) -> void:
	_refresh_progression(ProgressionManager.get_level(), current_xp, xp_to_next)


func _on_level_up(new_level: int) -> void:
	_refresh_progression(new_level, ProgressionManager.get_xp(), ProgressionManager.get_xp_to_next())


func _refresh_progression(level: int, current_xp: int, xp_to_next: int) -> void:
	level_label.text = "Level %d  -  %d/%d XP" % [level, current_xp, xp_to_next]
	xp_bar.max_value = float(maxi(1, xp_to_next))
	xp_bar.value = float(clampi(current_xp, 0, xp_to_next))


func _refresh_currency_labels(copper: int, silver: int, gold: int) -> void:
	copper_label.text = "%d CP" % copper
	silver_label.text = "%d SP" % silver
	gold_label.text = "%d GP" % gold
