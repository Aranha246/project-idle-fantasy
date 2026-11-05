extends Node
## Autoload singleton that owns every player-facing option.
##
## Options are grouped into display, audio and accessibility settings, persisted
## to `user://settings.cfg`, and applied immediately when changed. Any change
## broadcasts `SignalBus.settings_changed` so the UI can react without the
## settings screen knowing which systems care.

const SETTINGS_PATH: String = "user://settings.cfg"
const CONFIG_VERSION: int = 1

const UI_SCALE_MIN: float = 0.75
const UI_SCALE_MAX: float = 1.5
const UI_SCALE_STEP: float = 0.05

## DisplayServer window modes exposed to the player.
enum WindowMode {
	WINDOWED,
	FULLSCREEN,
	BORDERLESS,
}

## Audio buses the settings screen can control. `Master` always exists; the
## others are created on demand so the project does not depend on a hand-edited
## bus layout.
const AUDIO_BUSES: Array[String] = ["Master", "Music", "SFX"]

# --- Display ---------------------------------------------------------------
var window_mode: int = WindowMode.WINDOWED
var vsync_enabled: bool = true
var ui_scale: float = 1.0

# --- Audio -----------------------------------------------------------------
var master_volume: float = 1.0
var music_volume: float = 0.8
var sfx_volume: float = 0.8

# --- Accessibility ---------------------------------------------------------
var reduce_motion: bool = false
var high_contrast: bool = false
var show_fps: bool = false

# --- Keybindings -----------------------------------------------------------
## Window id -> keycode. Owned here so rebindings persist and apply instantly.
var keybindings: Dictionary = {}

# --- Window layout ---------------------------------------------------------
## Window id -> { "open": bool, "minimized": bool, "maximized": bool,
## "position": Vector2 }. Kept out of the save game on purpose so window
## placement survives even when there is no save to load.
var window_layout: Dictionary = {}

## Set once the initial load has finished. Mutators triggered by another
## autoload before this point are applied in memory but not yet persisted, so an
## early change can never overwrite the file with half-initialised values.
var _config_ready: bool = false


func _ready() -> void:
	_ensure_audio_buses()
	load_settings()
	apply_all()
	_apply_keybindings()
	_config_ready = true


## Restores persisted values, falling back to the defaults on a fresh install
## or a corrupt file.
func load_settings() -> void:
	keybindings = WindowRegistry.get_default_bindings()
	window_layout = _default_window_layout()

	var config: ConfigFile = ConfigFile.new()
	var error: Error = config.load(SETTINGS_PATH)
	if error != OK:
		# A missing file is the normal first-run case, not an error worth logging.
		if error != ERR_FILE_NOT_FOUND:
			push_warning("SettingsManager: could not read '%s' (%s)." % [SETTINGS_PATH, error_string(error)])
		return

	window_mode = int(config.get_value("display", "window_mode", window_mode))
	vsync_enabled = bool(config.get_value("display", "vsync_enabled", vsync_enabled))
	ui_scale = float(config.get_value("display", "ui_scale", ui_scale))

	master_volume = float(config.get_value("audio", "master_volume", master_volume))
	music_volume = float(config.get_value("audio", "music_volume", music_volume))
	sfx_volume = float(config.get_value("audio", "sfx_volume", sfx_volume))

	reduce_motion = bool(config.get_value("accessibility", "reduce_motion", reduce_motion))
	high_contrast = bool(config.get_value("accessibility", "high_contrast", high_contrast))
	show_fps = bool(config.get_value("accessibility", "show_fps", show_fps))

	for window_id: StringName in keybindings.keys():
		keybindings[window_id] = int(
			config.get_value("input", String(window_id), int(keybindings[window_id]))
		)

	for window_id: StringName in window_layout.keys():
		var entry: Dictionary = window_layout[window_id]
		var prefix: String = String(window_id)
		entry["open"] = bool(config.get_value("windows", prefix + "_open", entry["open"]))
		entry["minimized"] = bool(config.get_value("windows", prefix + "_minimized", entry["minimized"]))
		entry["maximized"] = bool(config.get_value("windows", prefix + "_maximized", entry["maximized"]))
		entry["position"] = config.get_value("windows", prefix + "_position", entry["position"])
		window_layout[window_id] = entry

	_sanitize()


func save_settings() -> void:
	var config: ConfigFile = ConfigFile.new()
	config.set_value("meta", "version", CONFIG_VERSION)

	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "vsync_enabled", vsync_enabled)
	config.set_value("display", "ui_scale", ui_scale)

	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)

	config.set_value("accessibility", "reduce_motion", reduce_motion)
	config.set_value("accessibility", "high_contrast", high_contrast)
	config.set_value("accessibility", "show_fps", show_fps)

	for window_id: Variant in keybindings.keys():
		config.set_value("input", String(window_id), int(keybindings[window_id]))

	for window_id: Variant in window_layout.keys():
		var entry: Dictionary = window_layout[window_id]
		var prefix: String = String(window_id)
		config.set_value("windows", prefix + "_open", bool(entry.get("open", false)))
		config.set_value("windows", prefix + "_minimized", bool(entry.get("minimized", false)))
		config.set_value("windows", prefix + "_maximized", bool(entry.get("maximized", false)))
		config.set_value("windows", prefix + "_position", entry.get("position", Vector2.ZERO))

	var error: Error = config.save(SETTINGS_PATH)
	if error != OK:
		push_error("SettingsManager: could not write '%s' (%s)." % [SETTINGS_PATH, error_string(error)])


## Pushes every value into the engine. Safe to call at any time.
func apply_all() -> void:
	_apply_display()
	_apply_audio()
	_apply_ui_scale()


# --- Mutators --------------------------------------------------------------

func set_window_mode(mode: int) -> void:
	window_mode = clampi(mode, WindowMode.WINDOWED, WindowMode.BORDERLESS)
	_apply_display()
	_after_change()


func set_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	_apply_display()
	_after_change()


func set_ui_scale(scale: float) -> void:
	ui_scale = clampf(snappedf(scale, UI_SCALE_STEP), UI_SCALE_MIN, UI_SCALE_MAX)
	_apply_ui_scale()
	_after_change()


## Sets the linear volume (0..1) of one of `AUDIO_BUSES`. Unknown bus names are
## ignored instead of raising, so the UI can bind generically.
func set_volume(bus_name: String, value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	match bus_name:
		"Master":
			master_volume = clamped
		"Music":
			music_volume = clamped
		"SFX":
			sfx_volume = clamped
		_:
			push_warning("SettingsManager: unknown audio bus '%s'." % bus_name)
			return
	_apply_audio()
	_after_change()


func set_reduce_motion(enabled: bool) -> void:
	reduce_motion = enabled
	_after_change()


func set_high_contrast(enabled: bool) -> void:
	high_contrast = enabled
	_after_change()


func set_show_fps(enabled: bool) -> void:
	show_fps = enabled
	_after_change()


## Rebinds the window `window_id` to `keycode`.
##
## Returns the id of the window that already owns `keycode` when the binding was
## rejected, or an empty `StringName` when it was applied. A key reserved by a
## non-window action reports `WindowRegistry.RESERVED_BINDING`. Conflict
## detection lives here rather than in the UI so every caller shares one rule.
func set_keybinding(window_id: StringName, keycode: int) -> StringName:
	if not keybindings.has(window_id):
		return &""

	if keycode == WindowRegistry.RESERVED_KEY:
		return WindowRegistry.RESERVED_BINDING

	if keycode != KEY_NONE:
		var conflict: StringName = WindowRegistry.window_for_key(keybindings, keycode)
		if conflict != &"" and conflict != window_id:
			return conflict

	keybindings[window_id] = keycode
	_apply_keybindings()
	_persist_only()
	return &""


## Restores every window shortcut to its authored default and applies it
## immediately, without requiring a restart.
func reset_keybindings() -> void:
	keybindings = WindowRegistry.get_default_bindings()
	_apply_keybindings()
	_persist_only()


## Persists whether `window_id` is currently open.
func set_window_open(window_id: StringName, is_open: bool) -> void:
	_update_window_entry(window_id, "open", is_open)


## Persists the on-screen position of `window_id`.
func set_window_position(window_id: StringName, position: Vector2) -> void:
	_update_window_entry(window_id, "position", position)


## Persists whether `window_id` is collapsed to its title bar.
func set_window_minimized(window_id: StringName, minimized: bool) -> void:
	_update_window_entry(window_id, "minimized", minimized)


## Persists whether `window_id` fills the work area.
func set_window_maximized(window_id: StringName, maximized: bool) -> void:
	_update_window_entry(window_id, "maximized", maximized)


## Returns a copy of the persisted layout for `window_id`, or an empty
## dictionary when the id is not a known window.
func get_window_layout(window_id: StringName) -> Dictionary:
	if not window_layout.has(window_id):
		return {}
	return (window_layout[window_id] as Dictionary).duplicate()


## Restores every option to its default and applies it immediately.
func reset_to_defaults() -> void:
	window_mode = WindowMode.WINDOWED
	vsync_enabled = true
	ui_scale = 1.0
	master_volume = 1.0
	music_volume = 0.8
	sfx_volume = 0.8
	reduce_motion = false
	high_contrast = false
	show_fps = false
	keybindings = WindowRegistry.get_default_bindings()
	window_layout = _default_window_layout()
	apply_all()
	_apply_keybindings()
	_after_change()


## Returns a JSON-safe snapshot of the current options, used by the UI and by
## `SignalBus.settings_changed` listeners.
func get_snapshot() -> Dictionary:
	return {
		"window_mode": window_mode,
		"vsync_enabled": vsync_enabled,
		"ui_scale": ui_scale,
		"master_volume": master_volume,
		"music_volume": music_volume,
		"sfx_volume": sfx_volume,
		"reduce_motion": reduce_motion,
		"high_contrast": high_contrast,
		"show_fps": show_fps,
	}


# --- Internals -------------------------------------------------------------

## Keeps loaded values inside their legal ranges so a hand-edited config file
## cannot push the game into an unusable state.
func _sanitize() -> void:
	window_mode = clampi(window_mode, WindowMode.WINDOWED, WindowMode.BORDERLESS)
	ui_scale = clampf(ui_scale, UI_SCALE_MIN, UI_SCALE_MAX)
	master_volume = clampf(master_volume, 0.0, 1.0)
	music_volume = clampf(music_volume, 0.0, 1.0)
	sfx_volume = clampf(sfx_volume, 0.0, 1.0)
	_sanitize_keybindings()
	_sanitize_window_layout()


## Repairs a loaded binding set so every known window has a key and no two
## windows share one, which a hand-edited file could otherwise cause.
func _sanitize_keybindings() -> void:
	var defaults: Dictionary = WindowRegistry.get_default_bindings()
	var claimed: Dictionary = {}
	for window_id: StringName in defaults.keys():
		var keycode: int = int(keybindings.get(window_id, int(defaults[window_id])))
		if keycode == KEY_NONE or keycode == WindowRegistry.RESERVED_KEY or claimed.has(keycode):
			var fallback: int = int(defaults[window_id])
			keycode = fallback if not claimed.has(fallback) else KEY_NONE
		keybindings[window_id] = keycode
		if keycode != KEY_NONE:
			claimed[keycode] = window_id


## Repairs a loaded layout so every known window has a well-formed entry.
func _sanitize_window_layout() -> void:
	var defaults: Dictionary = _default_window_layout()
	for window_id: StringName in defaults.keys():
		var fallback: Dictionary = defaults[window_id]
		if not window_layout.has(window_id):
			window_layout[window_id] = fallback
			continue
		var entry: Dictionary = window_layout[window_id]
		entry["open"] = bool(entry.get("open", fallback["open"]))
		entry["minimized"] = bool(entry.get("minimized", false))
		entry["maximized"] = bool(entry.get("maximized", false))
		var position: Variant = entry.get("position", fallback["position"])
		entry["position"] = position if position is Vector2 else fallback["position"]
		window_layout[window_id] = entry


## The first-run layout: every window at its authored position, closed unless it
## opted into opening by default.
func _default_window_layout() -> Dictionary:
	var layout: Dictionary = {}
	for definition: WindowData in WindowRegistry.get_definitions():
		layout[definition.window_id] = {
			"open": definition.open_by_default,
			"minimized": false,
			"maximized": false,
			"position": definition.default_position,
		}
	return layout


## Writes one field of a window's layout entry and persists the result.
func _update_window_entry(window_id: StringName, key: String, value: Variant) -> void:
	if not window_layout.has(window_id):
		return
	var entry: Dictionary = (window_layout[window_id] as Dictionary).duplicate()
	entry[key] = value
	window_layout[window_id] = entry
	_after_change()


## Pushes the current bindings into the `InputMap` so a rebind takes effect
## immediately, with no restart.
func _apply_keybindings() -> void:
	InputActions.apply_window_bindings(keybindings)


func _after_change() -> void:
	if not _config_ready:
		return
	save_settings()
	SignalBus.settings_changed.emit(get_snapshot())


## Persists without broadcasting `settings_changed`.
##
## Used by changes that only affect input routing (keybindings): they must be
## written to disk immediately but must not force the UI to rebuild its theme,
## which would be a needless repaint for something no widget displays.
func _persist_only() -> void:
	if not _config_ready:
		return
	save_settings()


func _ensure_audio_buses() -> void:
	for bus_name: String in AUDIO_BUSES:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		var index: int = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus_name)
		AudioServer.set_bus_send(index, "Master")


func _apply_display() -> void:
	# The headless DisplayServer ignores these calls, which keeps automated
	# tests working without a window.
	match window_mode:
		WindowMode.FULLSCREEN:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	var vsync_mode: int = DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)


func _apply_audio() -> void:
	_apply_bus_volume("Master", master_volume)
	_apply_bus_volume("Music", music_volume)
	_apply_bus_volume("SFX", sfx_volume)


func _apply_bus_volume(bus_name: String, value: float) -> void:
	var index: int = AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	if value <= 0.0:
		AudioServer.set_bus_mute(index, true)
		return
	AudioServer.set_bus_mute(index, false)
	AudioServer.set_bus_volume_db(index, linear_to_db(value))


func _apply_ui_scale() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	viewport.content_scale_factor = ui_scale
