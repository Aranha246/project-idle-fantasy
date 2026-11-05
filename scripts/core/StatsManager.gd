extends Node
## Autoload singleton that manages player attributes and gear-based modifications.

const RECALC_DELAY_MS: int = 100

# Base stats
var _base_attack_power: float = 10.0
var _base_defense: float = 5.0
var _base_critical_rate: float = 0.05 # 5%
var _base_luck: float = 0.0

# Current active stats (base + bonuses)
var _current_attack_power: float = 0.0
var _current_defense: float = 0.0
var _current_critical_rate: float = 0.0
var _current_luck: float = 0.0

var _recalc_timer: Timer


func _ready() -> void:
	_recalc_timer = Timer.new()
	_recalc_timer.wait_time = RECALC_DELAY_MS / 1000.0
	_recalc_timer.one_shot = true
	_recalc_timer.timeout.connect(_recalculate_stats)
	add_child(_recalc_timer)
	
	SignalBus.equipment_updated.connect(_on_equipment_changed)
	
	# Initial calculation
	_recalculate_stats()


func get_attack_power() -> float: return _current_attack_power
func get_defense() -> float: return _current_defense
func get_critical_rate() -> float: return _current_critical_rate
func get_luck() -> float: return _current_luck


func get_all_stats() -> Dictionary:
	return {
		"attack_power": {
			"base": _base_attack_power,
			"total": _current_attack_power,
			"bonus": _current_attack_power - _base_attack_power
		},
		"defense": {
			"base": _base_defense,
			"total": _current_defense,
			"bonus": _current_defense - _base_defense
		},
		"critical_rate": {
			"base": _base_critical_rate,
			"total": _current_critical_rate,
			"bonus": _current_critical_rate - _base_critical_rate
		},
		"luck": {
			"base": _base_luck,
			"total": _current_luck,
			"bonus": _current_luck - _base_luck
		}
	}


## Serializes only the base attributes; equipment bonuses are derived from the
## equipped items, which `SaveManager` persists separately.
func get_base_stats() -> Dictionary:
	return {
		"attack_power": _base_attack_power,
		"defense": _base_defense,
		"critical_rate": _base_critical_rate,
		"luck": _base_luck
	}


## Restores the base attributes from a save file and recalculates immediately.
func set_base_stats(data: Dictionary) -> void:
	_base_attack_power = maxf(0.0, float(data.get("attack_power", _base_attack_power)))
	_base_defense = maxf(0.0, float(data.get("defense", _base_defense)))
	_base_critical_rate = clampf(float(data.get("critical_rate", _base_critical_rate)), 0.0, 1.0)
	_base_luck = maxf(0.0, float(data.get("luck", _base_luck)))
	_recalculate_stats()


func _on_equipment_changed(_slot: String, _item: ItemData) -> void:
	# Debounce recalculation
	_recalc_timer.start()


func _recalculate_stats() -> void:
	var bonus_atk: float = 0.0
	var bonus_def: float = 0.0
	var bonus_crit: float = 0.0
	var bonus_luck: float = 0.0
	
	if is_instance_valid(EquipmentManager) and not EquipmentManager.get_slots().is_empty():
		for slot_name in EquipmentManager.SLOT_NAMES:
			var item: ItemData = EquipmentManager.get_equipped(slot_name)
			if item != null:
				bonus_atk += item.attack_power_mod
				bonus_def += item.defense_mod
				bonus_crit += item.critical_rate_mod
				bonus_luck += item.luck_mod
	
	_current_attack_power = _base_attack_power + bonus_atk
	_current_defense = _base_defense + bonus_def
	_current_critical_rate = clampf(_base_critical_rate + bonus_crit, 0.0, 1.0)
	_current_luck = _base_luck + bonus_luck
	
	SignalBus.stats_updated.emit(get_all_stats())
	print("[StatsManager] Stats recalculated: ATK=%.1f, DEF=%.1f, CRIT=%.1f%%, LUCK=%.1f" % [
		_current_attack_power, _current_defense, _current_critical_rate * 100.0, _current_luck
	])
