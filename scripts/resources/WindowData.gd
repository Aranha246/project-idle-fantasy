class_name WindowData
extends Resource
## Data definition for one of the game's floating UI windows.
##
## A custom Resource (per project standards) describing a window's stable id, its
## display title, the default key that toggles it and where it first appears.
## `WindowRegistry` authors one of these per window so ids, titles and default
## keybindings live in a single strongly typed place instead of loose
## dictionaries scattered between the UI and the settings manager.

## Stable identifier used for persistence, keybindings and signal payloads.
@export var window_id: StringName = &""

## Human readable title shown in the window's title bar and the menu bar.
@export var title: String = ""

## Key that toggles this window out of the box. Players can rebind it.
@export var default_key: Key = KEY_NONE

## Where the window is placed the first time the game runs.
@export var default_position: Vector2 = Vector2.ZERO

## Whether the window is open the first time the game runs.
@export var open_by_default: bool = false


## Returns `true` when the definition carries enough information to be usable.
func is_valid() -> bool:
	return window_id != &"" and not title.is_empty()
