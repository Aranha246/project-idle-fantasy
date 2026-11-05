extends PanelContainer
## Zone panel: picks the active zone and mirrors the player's running quest.
##
## Now that quests are player-driven, the old "enemy health" readout is
## repurposed to show the *progress of the quest the player chose to start*.
## The panel never drives gameplay itself — it only reads `SignalBus` state and
## calls into `QuestManager` when the player presses a zone button.

@onready var _zone_list: VBoxContainer = %ZoneList
@onready var _zone_name_label: Label = %ZoneNameLabel
@onready var _enemy_name_label: Label = %EnemyNameLabel
@onready var _enemy_health_bar: ProgressBar = %EnemyHealthBar
@onready var _pending_rewards_label: Label = %PendingRewardsLabel
@onready var _background_rect: TextureRect = %BackgroundRect

var _available_zones: Array[Resource] = []
var _accumulated_gold: int = 0


func _ready() -> void:
	SignalBus.zone_changed.connect(_on_zone_changed)
	SignalBus.quests_refreshed.connect(_on_quests_refreshed)
	SignalBus.quest_started.connect(_on_quest_started)
	SignalBus.quest_progress.connect(_on_quest_progress)
	SignalBus.quest_claimed.connect(_on_quest_claimed)
	SignalBus.level_up.connect(_on_level_up)

	_available_zones = QuestManager.get_all_zones()
	_build_zone_list()
	_refresh_active_zone_header()


func _build_zone_list() -> void:
	for child: Node in _zone_list.get_children():
		child.queue_free()

	for index: int in _available_zones.size():
		var zone: Resource = _available_zones[index]
		var unlock_level: int = QuestManager.get_zone_unlock_level(index)
		var unlocked: bool = QuestManager.is_zone_unlocked(zone)

		var button: Button = Button.new()
		button.text = "%s (Tier %d)" % [zone.zone_name, zone.tier_level]
		button.disabled = not unlocked
		button.tooltip_text = (
			"Enter %s" % zone.zone_name if unlocked
			else "Locked — reach level %d" % unlock_level
		)
		button.pressed.connect(_switch_zone.bind(zone))
		_zone_list.add_child(button)


func _switch_zone(zone: Resource) -> void:
	QuestManager.set_active_zone(zone)


func _refresh_active_zone_header() -> void:
	var zone: Resource = QuestManager.get_active_zone()
	if zone == null:
		_zone_name_label.text = "No Zone"
		return
	_zone_name_label.text = "%s — Tier %d" % [zone.zone_name, zone.tier_level]
	if zone.background_texture != null:
		_background_rect.texture = zone.background_texture
	if not zone.flavor_description.is_empty():
		_zone_name_label.tooltip_text = zone.flavor_description
	_reset_quest_display()


func _reset_quest_display() -> void:
	_enemy_name_label.text = "No quest in progress"
	_enemy_health_bar.max_value = 1.0
	_enemy_health_bar.value = 0.0


func _on_zone_changed(_zone: Resource) -> void:
	_accumulated_gold = 0
	_refresh_active_zone_header()
	_update_rewards_display()


func _on_quests_refreshed() -> void:
	# A level-up can unlock a zone, so the lock states are rebuilt from scratch.
	_available_zones = QuestManager.get_all_zones()
	_build_zone_list()


func _on_quest_started(quest: Resource, duration: float) -> void:
	var quest_data: QuestData = quest as QuestData
	if quest_data == null:
		return
	_enemy_name_label.text = quest_data.quest_name
	_enemy_health_bar.max_value = maxf(1.0, duration)
	_enemy_health_bar.value = 0.0


func _on_quest_progress(quest: Resource, ratio: float, _remaining: float) -> void:
	var quest_data: QuestData = quest as QuestData
	if quest_data == null:
		return
	if _enemy_health_bar.max_value <= 1.0:
		_enemy_health_bar.max_value = maxf(1.0, QuestManager.get_quest_duration())
	_enemy_health_bar.value = clampf(ratio, 0.0, 1.0) * _enemy_health_bar.max_value


func _on_quest_claimed(rewards: Dictionary) -> void:
	_accumulated_gold += int(rewards.get("gold", 0))
	_reset_quest_display()
	_update_rewards_display()


func _on_level_up(_new_level: int) -> void:
	_on_quests_refreshed()


func _update_rewards_display() -> void:
	_pending_rewards_label.text = "Session Gold: %d" % _accumulated_gold
