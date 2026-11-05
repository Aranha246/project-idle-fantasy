extends Node
## Autoload singleton that owns character level and experience.
##
## Experience is granted for every completed quest (combat tick) and scales the
## character level, which in turn drives zone unlocking. Progress is broadcast
## through `SignalBus.xp_gained` and `SignalBus.level_up` so the UI never needs
## to poll this manager.

## Experience required to advance from level 1 to level 2.
const BASE_XP: int = 50

## Multiplier applied to the requirement for each subsequent level.
const XP_GROWTH: float = 1.35

## Experience granted per completed quest, before tier scaling.
const XP_PER_QUEST: int = 10

## Guards against a runaway level-up loop if a save is hand-edited.
const MAX_LEVEL: int = 9999

var _level: int = 1
var _xp: int = 0


func _ready() -> void:
	SignalBus.quest_completed.connect(_on_quest_completed)


func get_level() -> int:
	return _level


func get_xp() -> int:
	return _xp


## Experience still needed to reach the next level.
func get_xp_to_next() -> int:
	return _xp_required_for(_level)


## Adds experience and processes any resulting level-ups.
func add_xp(amount: int) -> void:
	if amount <= 0 or _level >= MAX_LEVEL:
		return
	_xp += amount
	SignalBus.xp_gained.emit(amount, _xp, get_xp_to_next())

	while _level < MAX_LEVEL and _xp >= _xp_required_for(_level):
		_xp -= _xp_required_for(_level)
		_level += 1
		SignalBus.level_up.emit(_level)


## Serializes progression for `SaveManager`.
func get_state() -> Dictionary:
	return {"level": _level, "xp": _xp}


## Restores progression from a save file.
func load_state(data: Dictionary) -> void:
	_level = clampi(int(data.get("level", 1)), 1, MAX_LEVEL)
	_xp = maxi(0, int(data.get("xp", 0)))


func _on_quest_completed(rewards: Dictionary) -> void:
	# Rewards carry the defeated enemy; its health doubles as a difficulty proxy
	# so tougher zones award more experience.
	var enemy: Resource = rewards.get("enemy", null)
	var bonus: int = 0
	if enemy != null:
		bonus = maxi(0, int(enemy.base_health) / 25)
	add_xp(XP_PER_QUEST + bonus)


## Total experience needed to advance from `level` to `level + 1`.
func _xp_required_for(level: int) -> int:
	return maxi(1, int(round(float(BASE_XP) * pow(XP_GROWTH, float(level - 1)))))
