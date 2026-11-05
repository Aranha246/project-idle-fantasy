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


func _ready() -> void:
	_ensure_audio_buses()
	load_settings()
	apply_all()


## Restores persisted values, falling back to the defaults on a fresh install
## or a corrupt file.
func load_settings() -> void:
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
	apply_all()
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


func _after_change() -> void:
	save_settings()
	SignalBus.settings_changed.emit(get_snapshot())


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
