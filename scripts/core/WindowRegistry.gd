class_name WindowRegistry
extends RefCounted
## Authored catalogue of the game's floating windows.
##
## This is the single source of truth for which windows exist, what they are
## called, the default key that toggles each one and where it first appears.
## `SettingsManager` (persistence + input map), the settings screen and the UI
## window system all read from here, so an id, title or default key can never
## drift between them.

## Stable window ids. Referenced instead of raw strings so a typo fails to
## compile rather than silently addressing a non-existent window.
const CHARACTER_ID: StringName = &"character"
const QUESTS_ID: StringName = &"quests"
const UPGRADES_ID: StringName = &"upgrades"
const MAP_ID: StringName = &"map"
const STATS_ID: StringName = &"stats"
const SETTINGS_ID: StringName = &"settings"

## Key reserved for the pause overlay; never assignable to a window.
const RESERVED_KEY: Key = KEY_ESCAPE

## Reported by `SettingsManager.set_keybinding` when the requested key belongs to
## a non-window action (Escape pauses) and therefore cannot be reassigned.
const RESERVED_BINDING: StringName = &"__reserved__"


## Every authored window, in menu-bar order.
static func get_definitions() -> Array[WindowData]:
	var definitions: Array[WindowData] = []
	definitions.append(_make(CHARACTER_ID, "Character", KEY_C, Vector2(48.0, 96.0), true))
	definitions.append(_make(QUESTS_ID, "Quests", KEY_J, Vector2(320.0, 96.0)))
	definitions.append(_make(UPGRADES_ID, "Upgrades", KEY_U, Vector2(560.0, 96.0)))
	definitions.append(_make(MAP_ID, "Map", KEY_M, Vector2(760.0, 96.0)))
	definitions.append(_make(STATS_ID, "Stats", KEY_P, Vector2(980.0, 96.0)))
	definitions.append(_make(SETTINGS_ID, "Settings", KEY_O, Vector2(600.0, 220.0)))
	return definitions


## Every authored window id, in menu-bar order.
static func get_window_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for definition: WindowData in get_definitions():
		ids.append(definition.window_id)
	return ids


## Returns the definition for `window_id`, or `null` when unknown.
static func get_definition(window_id: StringName) -> WindowData:
	for definition: WindowData in get_definitions():
		if definition.window_id == window_id:
			return definition
	return null


static func has_window(window_id: StringName) -> bool:
	return get_definition(window_id) != null


## The default key for each window, as a `window id -> keycode` dictionary.
static func get_default_bindings() -> Dictionary:
	var bindings: Dictionary = {}
	for definition: WindowData in get_definitions():
		bindings[definition.window_id] = int(definition.default_key)
	return bindings


## Returns the id of the window bound to `keycode`, or an empty `StringName`
## when no window owns that key. Used for keybinding conflict detection.
static func window_for_key(bindings: Dictionary, keycode: int) -> StringName:
	for window_id: Variant in bindings.keys():
		if int(bindings[window_id]) == keycode:
			return StringName(window_id)
	return &""


## Human readable title for `window_id`, or the raw id when unknown.
static func get_title(window_id: StringName) -> String:
	var definition: WindowData = get_definition(window_id)
	return definition.title if definition != null else String(window_id)


static func _make(
	window_id: StringName,
	title: String,
	default_key: Key,
	default_position: Vector2,
	open_by_default: bool = false
) -> WindowData:
	var data: WindowData = WindowData.new()
	data.window_id = window_id
	data.title = title
	data.default_key = default_key
	data.default_position = default_position
	data.open_by_default = open_by_default
	return data
