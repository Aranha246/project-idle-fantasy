extends Node
## Drives the idle combat loop by simulating one combat tick per second.
##
## Each tick represents a defeated enemy and forwards the rolled Copper
## reward through `SignalBus.enemy_defeated`, keeping this manager fully
## unaware of the currency layer.

const TICK_INTERVAL: float = 1.0
const MIN_REWARD_COPPER: int = 15
const MAX_REWARD_COPPER: int = 45

var _combat_timer: Timer


func _ready() -> void:
	_combat_timer = Timer.new()
	_combat_timer.wait_time = TICK_INTERVAL
	_combat_timer.one_shot = false
	_combat_timer.autostart = true
	_combat_timer.timeout.connect(_on_combat_tick)
	add_child(_combat_timer)


func _on_combat_tick() -> void:
	var reward_copper: int = randi_range(MIN_REWARD_COPPER, MAX_REWARD_COPPER)
	SignalBus.enemy_defeated.emit(reward_copper)
