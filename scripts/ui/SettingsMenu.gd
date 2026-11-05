class_name SettingsMenu
extends CanvasLayer
## Settings screen covering graphics, audio and accessibility.
##
## Every control writes straight through to `SettingsManager`, which applies the
## change immediately and persists it. Groups live in a `TabContainer` so the
## panel stays short enough to fit small viewports without any scrolling.
##
## Contains no `ScrollContainer` so the project-wide no-scroll guarantee holds.

signal closed

const PANEL_MIN_WIDTH: float = 340.0
const PANEL_MIN_HEIGHT: float = 250.0
const BUTTON_MIN_HEIGHT: float = 44.0
const HEADER_FONT_SIZE: int = 22
const VALUE_LABEL_WIDTH: float = 52.0
const SLIDER_MIN_WIDTH: float = 140.0

const WINDOW_MODE_LABELS: Array[String] = ["Windowed", "Fullscreen", "Borderless"]

## Guards the programmatic value sync in `_ready()` from being written back.
var _syncing: bool = false

var _root: Control = null


func _init() -> void:
	name = "SettingsMenu"
	layer = 101
	visible = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Controls are initialised from the current settings, so suppress the
	# change handlers until the construction pass is finished.
	_syncing = true
	_build()
	_syncing = false


## Applies the shared UI theme to the overlay's control tree.
func set_ui_theme(ui_theme: Theme) -> void:
	if _root != null:
		_root.theme = ui_theme


func set_shown(shown: bool) -> void:
	visible = shown


func _build() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var backdrop: ColorRect = ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.0, 0.0, 0.0, 0.75)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(backdrop)

	var center: CenterContainer = CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.name = "SettingsPanel"
	panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, PANEL_MIN_HEIGHT)
	center.add_child(panel)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)

	var header: Label = Label.new()
	header.text = "Settings"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", HEADER_FONT_SIZE)
	column.add_child(header)

	var tabs: TabContainer = TabContainer.new()
	tabs.name = "SettingsTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)

	tabs.add_child(_build_tab("Graphics", _build_graphics_tab))
	tabs.add_child(_build_tab("Audio", _build_audio_tab))
	tabs.add_child(_build_tab("Accessibility", _build_accessibility_tab))

	column.add_child(_build_footer())


func _build_tab(tab_name: String, builder: Callable) -> MarginContainer:
	var margin: MarginContainer = MarginContainer.new()
	margin.name = tab_name
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)

	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Rows"
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	builder.call(column)
	return margin


func _build_graphics_tab(column: VBoxContainer) -> void:
	_add_option_row(
		column,
		"Window Mode",
		WINDOW_MODE_LABELS,
		SettingsManager.window_mode,
		_on_window_mode_selected
	)
	_add_check_row(column, "V-Sync", SettingsManager.vsync_enabled, _on_vsync_toggled)
	_add_slider_row(
		column,
		"UI Scale",
		SettingsManager.ui_scale,
		SettingsManager.UI_SCALE_MIN,
		SettingsManager.UI_SCALE_MAX,
		SettingsManager.UI_SCALE_STEP,
		_on_ui_scale_changed
	)


func _build_audio_tab(column: VBoxContainer) -> void:
	for bus_name: String in SettingsManager.AUDIO_BUSES:
		_add_slider_row(
			column,
			"%s Volume" % bus_name,
			_volume_for(bus_name),
			0.0,
			1.0,
			0.05,
			func(value: float) -> void: _on_volume_changed(bus_name, value)
		)


func _build_accessibility_tab(column: VBoxContainer) -> void:
	_add_check_row(column, "Reduce Motion", SettingsManager.reduce_motion, _on_reduce_motion_toggled)
	_add_check_row(column, "High Contrast", SettingsManager.high_contrast, _on_high_contrast_toggled)
	_add_check_row(column, "Show FPS Counter", SettingsManager.show_fps, _on_show_fps_toggled)


func _build_footer() -> HBoxContainer:
	var footer: HBoxContainer = HBoxContainer.new()
	footer.name = "Footer"
	footer.add_theme_constant_override("separation", 10)

	footer.add_child(_make_button("Reset Defaults", _on_reset_pressed))

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	footer.add_child(_make_button("Back", _on_back_pressed))

	return footer


func _make_button(button_label: String, on_pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.text = button_label
	button.custom_minimum_size = Vector2(0.0, BUTTON_MIN_HEIGHT)
	button.pressed.connect(on_pressed)
	return button


# --- Row builders ----------------------------------------------------------

func _add_check_row(parent: VBoxContainer, row_label: String, value: bool, on_toggled: Callable) -> void:
	var row: HBoxContainer = _make_row(row_label)
	var toggle: CheckButton = CheckButton.new()
	toggle.button_pressed = value
	toggle.toggled.connect(func(pressed: bool) -> void:
		if not _syncing:
			on_toggled.call(pressed)
	)
	row.add_child(toggle)
	parent.add_child(row)


func _add_option_row(
	parent: VBoxContainer,
	row_label: String,
	options: Array[String],
	selected: int,
	on_selected: Callable
) -> void:
	var row: HBoxContainer = _make_row(row_label)
	var option: OptionButton = OptionButton.new()
	for entry: String in options:
		option.add_item(entry)
	option.selected = clampi(selected, 0, options.size() - 1)
	option.item_selected.connect(func(index: int) -> void:
		if not _syncing:
			on_selected.call(index)
	)
	row.add_child(option)
	parent.add_child(row)


func _add_slider_row(
	parent: VBoxContainer,
	row_label: String,
	value: float,
	minimum: float,
	maximum: float,
	step: float,
	on_changed: Callable
) -> void:
	var row: HBoxContainer = _make_row(row_label)

	var slider: HSlider = HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = clampf(value, minimum, maximum)
	slider.custom_minimum_size = Vector2(SLIDER_MIN_WIDTH, 0.0)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)

	var value_label: Label = Label.new()
	value_label.custom_minimum_size = Vector2(VALUE_LABEL_WIDTH, 0.0)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.text = _format_value(slider.value)
	row.add_child(value_label)

	slider.value_changed.connect(func(new_value: float) -> void:
		value_label.text = _format_value(new_value)
		if not _syncing:
			on_changed.call(new_value)
	)
	parent.add_child(row)


func _make_row(row_label: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var label: Label = Label.new()
	label.text = row_label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)

	return row


func _format_value(value: float) -> String:
	return "%.2f" % value


func _volume_for(bus_name: String) -> float:
	match bus_name:
		"Master":
			return SettingsManager.master_volume
		"Music":
			return SettingsManager.music_volume
		"SFX":
			return SettingsManager.sfx_volume
	return 1.0


# --- Handlers --------------------------------------------------------------

func _on_window_mode_selected(index: int) -> void:
	SettingsManager.set_window_mode(index)


func _on_vsync_toggled(pressed: bool) -> void:
	SettingsManager.set_vsync(pressed)


func _on_ui_scale_changed(value: float) -> void:
	SettingsManager.set_ui_scale(value)


func _on_volume_changed(bus_name: String, value: float) -> void:
	SettingsManager.set_volume(bus_name, value)


func _on_reduce_motion_toggled(pressed: bool) -> void:
	SettingsManager.set_reduce_motion(pressed)


func _on_high_contrast_toggled(pressed: bool) -> void:
	SettingsManager.set_high_contrast(pressed)


func _on_show_fps_toggled(pressed: bool) -> void:
	SettingsManager.set_show_fps(pressed)


func _on_reset_pressed() -> void:
	SettingsManager.reset_to_defaults()


func _on_back_pressed() -> void:
	set_shown(false)
	closed.emit()
