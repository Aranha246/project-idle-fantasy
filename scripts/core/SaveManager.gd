extends Node
## Autoload singleton that persists and restores the whole game state.
##
## The save file is a single JSON document at `user://savegame.json` holding the
## currency wallet, base stats, character progression, active zone, inventory and
## equipment. Item definitions are embedded alongside their ids so a save stays
## loadable even though the project has no authored item catalogue yet.
##
## Saves happen automatically on a timer and when the window is closed, and can
## be triggered manually from the pause menu.

const SAVE_PATH: String = "user://savegame.json"

## Bumped to 2 when purchased upgrade levels joined the save payload.
const SAVE_VERSION: int = 2

## How often the game state is written to disk while playing.
const AUTOSAVE_INTERVAL_SECONDS: float = 60.0

var _autosave_timer: Timer


func _ready() -> void:
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL_SECONDS
	_autosave_timer.autostart = true
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)


func _notification(what: int) -> void:
	# Never lose progress when the player closes the window.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func has_save(path: String = SAVE_PATH) -> bool:
	return FileAccess.file_exists(path)


## Writes the current game state to `path`. Returns `true` on success.
func save_game(path: String = SAVE_PATH) -> bool:
	var state: Dictionary = _gather_state()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error(
			"SaveManager: could not open '%s' for writing (%s)."
			% [path, error_string(FileAccess.get_open_error())]
		)
		return false

	file.store_string(JSON.stringify(state, "\t"))
	file.close()
	SignalBus.game_saved.emit(path)
	return true


## Restores the game state from `path`. Returns `true` on success, and `false`
## (without touching live state) when the file is missing or corrupt.
func load_game(path: String = SAVE_PATH) -> bool:
	if not has_save(path):
		return false

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error(
			"SaveManager: could not open '%s' for reading (%s)."
			% [path, error_string(FileAccess.get_open_error())]
		)
		return false

	var text: String = file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("SaveManager: save file '%s' is not valid JSON." % path)
		return false

	_apply_state(parsed)
	SignalBus.game_loaded.emit(path)
	return true


## Deletes the save file. Returns `true` when a file was removed.
func delete_save(path: String = SAVE_PATH) -> bool:
	if not has_save(path):
		return false
	var error: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		# Fall back to the user:// virtual path when globalizing is not possible.
		var dir: DirAccess = DirAccess.open("user://")
		if dir == null:
			return false
		error = dir.remove(path.get_file())
	if error != OK:
		push_error("SaveManager: could not delete '%s' (%s)." % [path, error_string(error)])
		return false
	return true


func _on_autosave_timeout() -> void:
	save_game()


func _gather_state() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"currency": CurrencyManager.get_state(),
		"base_stats": StatsManager.get_base_stats(),
		"progression": ProgressionManager.get_state(),
		"upgrades": UpgradeManager.get_state(),
		"zone_id": String(QuestManager.get_active_zone_id()),
		"inventory": InventoryManager.get_state(),
		"equipment": EquipmentManager.get_state(),
		"items": _collect_item_snapshots(),
	}


func _apply_state(data: Dictionary) -> void:
	# Items must exist in the database before the inventory and equipment can
	# resolve their ids back into live resources.
	_restore_item_definitions(data.get("items", {}))

	InventoryManager.load_state(data.get("inventory", []))
	EquipmentManager.load_state(data.get("equipment", {}))
	CurrencyManager.load_state(data.get("currency", {}))
	StatsManager.set_base_stats(data.get("base_stats", {}))
	ProgressionManager.load_state(data.get("progression", {}))
	# Upgrades feed quest pacing and stats, so restore them before the zone is
	# re-selected (a shorter quest duration is derived on selection).
	UpgradeManager.load_state(data.get("upgrades", {}))

	var zone_id: StringName = StringName(str(data.get("zone_id", "")))
	if zone_id != &"" and not QuestManager.set_active_zone_by_id(zone_id):
		push_warning("SaveManager: saved zone '%s' is unknown or locked; keeping the current zone." % zone_id)


## Collects a definition for every item currently held or equipped, keyed by id.
func _collect_item_snapshots() -> Dictionary:
	var catalog: Dictionary = {}
	for slot: InventorySlot in InventoryManager.get_slots():
		_register_item_snapshot(catalog, slot.item)
	for slot_name: String in EquipmentManager.SLOT_NAMES:
		_register_item_snapshot(catalog, EquipmentManager.get_equipped(slot_name))
	return catalog


func _register_item_snapshot(catalog: Dictionary, item: ItemData) -> void:
	if item == null or item.item_id == &"":
		return
	var key: String = String(item.item_id)
	if not catalog.has(key):
		catalog[key] = GameDatabase.serialize_item(item)


func _restore_item_definitions(items: Variant) -> void:
	if typeof(items) != TYPE_DICTIONARY:
		return
	var definitions: Dictionary = items
	for item_id: Variant in definitions.keys():
		var fields: Variant = definitions[item_id]
		if typeof(fields) != TYPE_DICTIONARY:
			continue
		GameDatabase.register_item(
			GameDatabase.deserialize_item(StringName(str(item_id)), fields)
		)
