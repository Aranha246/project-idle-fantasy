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

const KEY_ROW_BUTTON_MIN_WIDTH: float = 116.0
const KEY_ROW_BUTTON_MIN_HEIGHT: float = 26.0
const FEEDBACK_FONT_SIZE: int = 12
const FEEDBACK_COLOR: Color = Color(0.831373, 0.847059, 0.921569)
const FEEDBACK_ERROR_COLOR: Color = Color(0.921569, 0.325490, 0.325490)

const CAPTURE_HINT: String = "Press a key..."

## Guards the programmatic value sync in `_ready()` from being written back.
var _syncing: bool = false

var _root: Control = null

## Window id whose binding is currently being captured, or an empty `StringName`
## when no capture is running.
var _capture_window_id: StringName = &""

## Window id -> its rebind button, so a successful change or a reset can refresh
## every label without rebuilding the tab.
var _key_buttons: Dictionary = {}

var _keybind_feedback: Label = null


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
	# Leaving the screen mid-capture must not leave a keypress waiting to be
	# swallowed by a panel the player can no longer see.
	if not shown and _capture_window_id != &"":
		_cancel_capture("")
	visible = shown


## Captures the next key press while a rebind is in progress.
##
## Runs in `_input`, ahead of `WindowManager._unhandled_input`, so the captured
## key is consumed here and can never also toggle a window.
func _input(event: InputEvent) -> void:
	if _capture_window_id == &"":
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	get_viewport().set_input_as_handled()

	var keycode: int = int(key_event.physical_keycode)
	if keycode == int(KEY_NONE):
		keycode = int(key_event.keycode)
	if keycode == int(KEY_ESCAPE):
		_cancel_capture("Binding cancelled.")
		return

	var window_id: StringName = _capture_window_id
	var conflict: StringName = SettingsManager.set_keybinding(window_id, keycode)
	if conflict == WindowRegistry.RESERVED_BINDING:
		_set_feedback("That key is reserved for the pause menu.", true)
		return
	if conflict != &"":
		_set_feedback(
			"%s is already used by the %s window."
			% [OS.get_keycode_string(keycode), WindowRegistry.get_title(conflict)],
			true
		)
		return

	_capture_window_id = &""
	_refresh_key_buttons()
	_set_feedback(
		"%s is now bound to %s."
		% [WindowRegistry.get_title(window_id), OS.get_keycode_string(keycode)]
	)


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
	tabs.add_child(_build_tab("Keybindings", _build_keybindings_tab))

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


## One row per authored window. Rebinding writes straight through to
## `SettingsManager`, which applies the new binding to the `InputMap` at once, so
## a change takes effect the moment it is made rather than on the next launch.
func _build_keybindings_tab(column: VBoxContainer) -> void:
	for definition: WindowData in WindowRegistry.get_definitions():
		if definition.is_valid():
			_add_keybind_row(column, definition)

	column.add_child(_build_keybind_footer())

	_keybind_feedback = Label.new()
	_keybind_feedback.name = "KeybindFeedback"
	_keybind_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keybind_feedback.add_theme_font_size_override("font_size", FEEDBACK_FONT_SIZE)
	_keybind_feedback.add_theme_color_override("font_color", FEEDBACK_COLOR)
	column.add_child(_keybind_feedback)


func _add_keybind_row(parent: VBoxContainer, definition: WindowData) -> void:
	var row: HBoxContainer = _make_row(definition.title)

	var button: Button = Button.new()
	button.name = "Bind_" + String(definition.window_id)
	button.custom_minimum_size = Vector2(KEY_ROW_BUTTON_MIN_WIDTH, KEY_ROW_BUTTON_MIN_HEIGHT)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.text = _binding_label(definition.window_id)
	button.tooltip_text = "Click, then press the key to open the %s window." % definition.title
	button.pressed.connect(_on_bind_pressed.bind(definition.window_id))

	_key_buttons[definition.window_id] = button
	row.add_child(button)
	parent.add_child(row)


func _build_keybind_footer() -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.name = "KeybindFooter"
	row.add_theme_constant_override("separation", 10)
	row.add_child(_make_compact_button("Reset Keybindings", _on_reset_keybindings_pressed))
	return row


func _make_compact_button(button_label: String, on_pressed: Callable) -> Button:
	var button: Button = Button.new()
	button.text = button_label
	button.custom_minimum_size = Vector2(0.0, KEY_ROW_BUTTON_MIN_HEIGHT)
	button.pressed.connect(on_pressed)
	return button


## Human readable label for a window's current binding.
func _binding_label(window_id: StringName) -> String:
	var keycode: int = int(SettingsManager.keybindings.get(window_id, int(KEY_NONE)))
	if keycode == int(KEY_NONE):
		return "Unbound"
	return OS.get_keycode_string(keycode)


func _refresh_key_buttons() -> void:
	for window_id: Variant in _key_buttons.keys():
		var button: Button = _key_buttons[window_id] as Button
		if button == null:
			continue
		var id: StringName = StringName(window_id)
		button.text = CAPTURE_HINT if id == _capture_window_id else _binding_label(id)


func _set_feedback(message: String, is_error: bool = false) -> void:
	if _keybind_feedback == null:
		return
	_keybind_feedback.text = message
	_keybind_feedback.add_theme_color_override(
		"font_color", FEEDBACK_ERROR_COLOR if is_error else FEEDBACK_COLOR
	)


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
	# `reset_to_defaults` also restores the authored window shortcuts, so the
	# keybinding rows have to be refreshed to stay truthful.
	_capture_window_id = &""
	_refresh_key_buttons()
	_set_feedback("All settings restored to their defaults.")


func _on_bind_pressed(window_id: StringName) -> void:
	_capture_window_id = window_id
	_refresh_key_buttons()
	_set_feedback(
		"Press a key for the %s window, or Escape to cancel."
		% WindowRegistry.get_title(window_id)
	)


func _on_reset_keybindings_pressed() -> void:
	_capture_window_id = &""
	SettingsManager.reset_keybindings()
	_refresh_key_buttons()
	_set_feedback("Keybindings restored to their defaults.")


func _cancel_capture(message: String) -> void:
	_capture_window_id = &""
	_refresh_key_buttons()
	_set_feedback(message)


func _on_back_pressed() -> void:
	set_shown(false)
	closed.emit()
