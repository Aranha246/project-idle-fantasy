extends PanelContainer
## UI for zone selection and monitoring current combat progress.

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
	SignalBus.enemy_spawned.connect(_on_enemy_spawned)
	SignalBus.enemy_health_updated.connect(_on_enemy_health_updated)
	SignalBus.quest_completed.connect(_on_quest_completed)
	
	# We would normally populate this from a central database
	_load_zones()
	_build_zone_list()


func _load_zones() -> void:
	# The zone catalogue lives in GameDatabase so this UI, the idle quest
	# manager and the save system all agree on the same set of zones.
	_available_zones = GameDatabase.get_all_zones()


func _build_zone_list() -> void:
	for zone in _available_zones:
		var btn := Button.new()
		btn.text = "%s (Tier %d)" % [zone.zone_name, zone.tier_level]
		btn.pressed.connect(func(): _switch_zone(zone))
		_zone_list.add_child(btn)


func _switch_zone(zone: Resource) -> void:
	if is_instance_valid(IdleQuestManager):
		IdleQuestManager.set_active_zone(zone)


func _on_zone_changed(zone: Resource) -> void:
	_zone_name_label.text = zone.zone_name
	if zone.background_texture:
		_background_rect.texture = zone.background_texture
	_accumulated_gold = 0
	_update_rewards_display()


func _on_enemy_spawned(enemy: Resource, current_health: int, max_health: int) -> void:
	_enemy_name_label.text = enemy.enemy_name
	_enemy_health_bar.max_value = max_health
	_enemy_health_bar.value = current_health


func _on_enemy_health_updated(current_health: int, max_health: int) -> void:
	_enemy_health_bar.value = current_health


func _on_quest_completed(rewards: Dictionary) -> void:
	_accumulated_gold += rewards.get("gold", 0)
	_update_rewards_display()


func _update_rewards_display() -> void:
	_pending_rewards_label.text = "Session Gold: %d" % _accumulated_gold
