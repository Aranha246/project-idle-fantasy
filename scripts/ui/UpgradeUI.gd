extends PanelContainer
## The currency upgrade shop.
##
## Lists every track authored by `UpgradeManager` and lets the player exchange
## Copper for permanent bonuses — faster quests, richer rewards, better drop
## rates and flat stat gains. The panel owns no rules: it reads costs/levels from
## the manager and asks it to `purchase()`, then re-renders on the
## `upgrades_updated` / `currency_updated` signals, keeping it decoupled from the
## economy logic.

const ROW_GAP: int = 8
const BUY_BUTTON_MIN_WIDTH: float = 118.0
const EFFECT_FONT_SIZE: int = 11

## Switching to two columns halves the number of rows, which is what keeps the
## shop inside short landscape viewports (844x390) without scrolling.
const TWO_COLUMN_MIN_WIDTH: float = 640.0

@onready var _currency_label: Label = %CurrencyLabel
@onready var _track_list: GridContainer = %TrackList

## Maps an upgrade id to the label/button nodes that render it.
var _row_by_id: Dictionary = {}


func _ready() -> void:
	SignalBus.upgrades_updated.connect(_refresh)
	SignalBus.currency_updated.connect(_on_currency_updated)
	SignalBus.game_loaded.connect(_on_game_loaded)

	_build_rows()

	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_columns):
		viewport.size_changed.connect(_update_columns)
	_update_columns()

	_refresh()


## Chooses one or two columns based on the viewport width so the track list
## always fits the available height.
func _update_columns() -> void:
	if _track_list == null:
		return
	var viewport_width: float = get_viewport_rect().size.x
	_track_list.columns = 2 if viewport_width >= TWO_COLUMN_MIN_WIDTH else 1


## Builds one row per upgrade track. Rows are created once; only their text and
## disabled state change afterwards.
func _build_rows() -> void:
	for child: Node in _track_list.get_children():
		child.queue_free()
	_row_by_id.clear()

	for upgrade: UpgradeData in UpgradeManager.get_all_upgrades():
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", ROW_GAP)

		var info: VBoxContainer = VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)

		var name_label: Label = Label.new()
		name_label.clip_text = true
		name_label.tooltip_text = "%s\n%s" % [upgrade.display_name, upgrade.description]
		info.add_child(name_label)

		var effect_label: Label = Label.new()
		effect_label.add_theme_font_size_override("font_size", EFFECT_FONT_SIZE)
		effect_label.modulate = Color(0.62, 0.82, 1.0)
		effect_label.clip_text = true
		info.add_child(effect_label)
		row.add_child(info)

		var buy_button: Button = Button.new()
		buy_button.custom_minimum_size = Vector2(BUY_BUTTON_MIN_WIDTH, 0.0)
		buy_button.clip_text = true
		buy_button.pressed.connect(_on_buy_pressed.bind(upgrade.upgrade_id))
		row.add_child(buy_button)

		_track_list.add_child(row)
		_row_by_id[upgrade.upgrade_id] = {
			"name": name_label,
			"effect": effect_label,
			"button": buy_button,
		}


func _refresh() -> void:
	if _currency_label != null and is_instance_valid(CurrencyManager):
		_currency_label.text = "Copper: %d CP" % CurrencyManager.get_total_copper()

	for upgrade: UpgradeData in UpgradeManager.get_all_upgrades():
		var row: Dictionary = _row_by_id.get(upgrade.upgrade_id, {})
		if row.is_empty():
			continue

		var upgrade_id: StringName = upgrade.upgrade_id
		var level: int = UpgradeManager.get_level(upgrade_id)
		var name_label: Label = row["name"]
		var effect_label: Label = row["effect"]
		var buy_button: Button = row["button"]

		name_label.text = "%s  (Lv %d/%d)" % [upgrade.display_name, level, upgrade.max_level]
		effect_label.text = upgrade.effect_summary(level)

		if UpgradeManager.is_maxed(upgrade_id):
			buy_button.text = "Maxed"
			buy_button.disabled = true
		else:
			buy_button.text = "Buy  %d CP" % UpgradeManager.get_next_cost(upgrade_id)
			buy_button.disabled = not UpgradeManager.can_afford(upgrade_id)


func _on_buy_pressed(upgrade_id: StringName) -> void:
	UpgradeManager.purchase(upgrade_id)


func _on_currency_updated(_copper: int, _silver: int, _gold: int) -> void:
	_refresh()


func _on_game_loaded(_path: String) -> void:
	_refresh()
