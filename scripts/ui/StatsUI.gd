extends PanelContainer
## Displays real-time player attributes with gear bonuses highlighted.

const STAT_LABELS := {
	"attack_power": "Attack Power",
	"defense": "Defense",
	"critical_rate": "Crit Rate",
	"luck": "Luck"
}

const TOOLTIPS := {
	"attack_power": "Increases quest completion speed.",
	"defense": "Reduces quest failure chance.",
	"critical_rate": "Chance to deal double damage (future feature).",
	"luck": "Increases loot drop chance."
}

var _label_nodes: Dictionary = {}


func _ready() -> void:
	SignalBus.stats_updated.connect(_on_stats_updated)
	_build_ui()
	
	# Initial refresh if StatsManager is already active
	if is_instance_valid(StatsManager):
		_on_stats_updated(StatsManager.get_all_stats())


func _build_ui() -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)
	
	var header := Label.new()
	header.text = "Character Stats"
	header.add_theme_font_size_override("font_size", 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)
	
	for stat_key in STAT_LABELS.keys():
		var hbox := HBoxContainer.new()
		hbox.tooltip_text = TOOLTIPS[stat_key]
		vbox.add_child(hbox)
		
		var name_label := Label.new()
		name_label.text = STAT_LABELS[stat_key]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_font_size_override("font_size", 14)
		hbox.add_child(name_label)
		
		var value_label := Label.new()
		value_label.add_theme_font_size_override("font_size", 14)
		hbox.add_child(value_label)
		_label_nodes[stat_key] = value_label


func _on_stats_updated(stats: Dictionary) -> void:
	for stat_key in STAT_LABELS.keys():
		if not stats.has(stat_key) or not _label_nodes.has(stat_key):
			continue
			
		var data: Dictionary = stats[stat_key]
		var label: Label = _label_nodes[stat_key]
		
		var value_text: String = ""
		if stat_key == "critical_rate":
			value_text = "%.1f%%" % (data.total * 100.0)
		else:
			value_text = "%.1f" % data.total
			
		label.text = value_text
		
		# Color-code bonuses
		if data.bonus > 0:
			label.modulate = Color(0.4, 1.0, 0.4) # Green
		elif data.bonus < 0:
			label.modulate = Color(1.0, 0.4, 0.4) # Red
		else:
			label.modulate = Color.WHITE
