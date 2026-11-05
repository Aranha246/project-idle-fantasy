extends PanelContainer
## The player's quest board: the single place where gameplay is *started*.
##
## Nothing in this game progresses on its own any more. This panel lists the
## quests offered by the active zone as buttons; pressing one calls
## `QuestManager.start_quest()`, and once the timer finishes the action button
## becomes the "Claim Reward" prompt. The panel itself contains no timers and
## holds no game state — it only reflects `SignalBus` and asks `QuestManager` to
## act, keeping the UI fully decoupled from the rules.

@onready var _quest_list: VBoxContainer = %QuestList
@onready var _active_label: Label = %ActiveQuestLabel
@onready var _progress_bar: ProgressBar = %QuestProgressBar
@onready var _action_button: Button = %QuestActionButton


func _ready() -> void:
	SignalBus.quests_refreshed.connect(_rebuild_quest_list)
	SignalBus.zone_changed.connect(_on_zone_changed)
	SignalBus.quest_started.connect(_on_quest_started)
	SignalBus.quest_progress.connect(_on_quest_progress)
	SignalBus.quest_ready.connect(_on_quest_ready)
	SignalBus.quest_claimed.connect(_on_quest_claimed)

	_action_button.pressed.connect(_on_action_pressed)
	_rebuild_quest_list()
	_refresh_active_display()


## Rebuilds the offered quests from `QuestManager`. Called whenever the zone
## changes, the player levels up (possibly unlocking a zone) or a quest ends.
func _rebuild_quest_list() -> void:
	for child: Node in _quest_list.get_children():
		child.queue_free()

	for quest: QuestData in QuestManager.get_quests():
		var button: Button = Button.new()
		button.text = "%s  (%s)" % [quest.quest_name, quest.type_label()]
		button.tooltip_text = "%s\n%s\nDuration: %.0fs  •  Reward: %d CP" % [
			quest.quest_name,
			quest.flavor,
			quest.base_duration,
			quest.base_gold,
		]
		button.clip_text = true
		button.pressed.connect(_on_quest_selected.bind(quest))
		_quest_list.add_child(button)

	_refresh_quest_buttons()


func _refresh_quest_buttons() -> void:
	# A quest can only be started when none is currently running.
	var running: bool = QuestManager.is_quest_running()
	for child: Node in _quest_list.get_children():
		var button: Button = child as Button
		if button != null:
			button.disabled = running


func _on_quest_selected(quest: QuestData) -> void:
	QuestManager.start_quest(quest)


func _on_action_pressed() -> void:
	if QuestManager.is_quest_ready():
		QuestManager.claim_quest()
	elif QuestManager.is_quest_running():
		QuestManager.abandon_quest()


func _on_zone_changed(_zone: Resource) -> void:
	_refresh_active_display()


func _on_quest_started(quest: Resource, duration: float) -> void:
	var quest_data: QuestData = quest as QuestData
	if quest_data != null:
		_active_label.text = "%s — in progress" % quest_data.quest_name
	_progress_bar.max_value = maxf(1.0, duration)
	_progress_bar.value = 0.0
	_action_button.text = "Cancel Quest"
	_action_button.disabled = false
	_refresh_quest_buttons()


func _on_quest_progress(_quest: Resource, ratio: float, remaining: float) -> void:
	if _progress_bar.max_value <= 1.0:
		_progress_bar.max_value = maxf(1.0, QuestManager.get_quest_duration())
	_progress_bar.value = clampf(ratio, 0.0, 1.0) * _progress_bar.max_value
	if QuestManager.is_quest_running() and not QuestManager.is_quest_ready():
		_active_label.text = "%s — %.0fs left" % [QuestManager.get_active_quest().quest_name, maxf(0.0, remaining)]


func _on_quest_ready(quest: Resource) -> void:
	var quest_data: QuestData = quest as QuestData
	if quest_data != null:
		_active_label.text = "%s — complete!" % quest_data.quest_name
	_progress_bar.value = _progress_bar.max_value
	_action_button.text = "Claim Reward"
	_action_button.disabled = false


func _on_quest_claimed(rewards: Dictionary) -> void:
	var gold: int = int(rewards.get("gold", 0))
	var drops: Array = rewards.get("drops", [])
	_active_label.text = "Reward: %d CP and %d item stack(s)." % [gold, drops.size()]
	_progress_bar.value = 0.0
	_action_button.text = "Claim Reward"
	_action_button.disabled = true
	_refresh_quest_buttons()


## Syncs the panel with `QuestManager`'s current state (used on first show and
## after a zone change).
func _refresh_active_display() -> void:
	if QuestManager.is_quest_ready():
		_on_quest_ready(QuestManager.get_active_quest())
		return
	if QuestManager.is_quest_running():
		var quest: QuestData = QuestManager.get_active_quest()
		_progress_bar.max_value = maxf(1.0, QuestManager.get_quest_duration())
		_progress_bar.value = QuestManager.get_quest_progress_ratio() * _progress_bar.max_value
		if quest != null:
			_active_label.text = "%s — in progress" % quest.quest_name
		_action_button.text = "Cancel Quest"
		_action_button.disabled = false
	else:
		_active_label.text = "Select a quest to begin."
		_progress_bar.value = 0.0
		_action_button.text = "Claim Reward"
		_action_button.disabled = true
	_refresh_quest_buttons()
