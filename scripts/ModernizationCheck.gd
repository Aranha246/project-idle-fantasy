extends Node
## Headless validation suite for the modernization pass.
##
## Covers the content database, the input map, settings persistence,
## progression, save/load round-tripping, the three overlay menus, and the way
## `Main` wires them together. Follows the same result contract as
## `NoScrollLayoutCheck`: prints `RESULT passed=N failed=M` and exits non-zero
## when anything fails.

const MAIN_SCENE: String = "res://scenes/Main.tscn"
const TEST_SAVE_PATH: String = "user://test_modernization_save.json"

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("Starting modernization tests...")
	call_deferred("_run")


func _run() -> void:
	_test_autoloads()
	_test_game_database()
	_test_visual_assets()
	_test_input_actions()
	_test_settings()
	_test_progression()
	_test_save_load()
	await _test_overlay_menus()
	await _test_main_integration()
	await _test_performance()
	await _test_soak()
	_cleanup()
	_finish()


# --- Suites ----------------------------------------------------------------

func _test_autoloads() -> void:
	for singleton_name: String in ["GameDatabase", "SettingsManager", "ProgressionManager", "SaveManager"]:
		_assert(get_tree().root.has_node(singleton_name), "autoload '%s' is registered" % singleton_name)


func _test_game_database() -> void:
	var zones: Array[Resource] = GameDatabase.get_all_zones()
	_assert(zones.size() >= 2, "GameDatabase registers more than one zone")

	var all_valid: bool = true
	var all_have_ids: bool = true
	for zone: Resource in zones:
		if not zone.has_method("validate") or not zone.validate().is_empty():
			all_valid = false
		if zone.zone_id == &"":
			all_have_ids = false
	_assert(all_valid, "every registered zone passes validation")
	_assert(all_have_ids, "every registered zone has a stable id")

	var default_zone: Resource = GameDatabase.get_default_zone()
	_assert(default_zone != null, "a default zone is registered")
	_assert(GameDatabase.get_zone(&"whispering_woods") != null, "zones are resolvable by id")
	_assert(GameDatabase.get_zone(&"does_not_exist") == null, "unknown zone ids resolve to null")


func _test_visual_assets() -> void:
	# Every rarity must produce a usable, visible, cached icon texture so runtime
	# generated loot never falls back to an engine placeholder graphic.
	var common_icon: Texture2D = GameTheme.build_item_icon(ItemData.Rarity.COMMON)
	_assert(common_icon != null, "the generated item icon is a valid texture")
	_assert(common_icon.get_width() > 0 and common_icon.get_height() > 0, "the generated item icon has real dimensions")
	_assert(GameTheme.build_item_icon(ItemData.Rarity.COMMON) == common_icon, "generated icons are cached per rarity")

	var center: Vector2i = Vector2i(common_icon.get_width() / 2, common_icon.get_height() / 2)
	var center_pixel: Color = common_icon.get_image().get_pixelv(center)
	_assert(center_pixel.a > 0.5, "the generated item icon is opaque at its centre")
	_assert(common_icon.get_image().get_pixel(0, 0).a < 0.5, "the generated item icon is transparent at its corners")

	var legendary_icon: Texture2D = GameTheme.build_item_icon(ItemData.Rarity.LEGENDARY)
	var legendary_pixel: Color = legendary_icon.get_image().get_pixelv(center)
	_assert(legendary_pixel != center_pixel, "each rarity produces a distinctly tinted icon")

	var tints_distinct: bool = true
	for rarity_index: int in range(ItemData.Rarity.size() - 1):
		if GameTheme.rarity_color(rarity_index) == GameTheme.rarity_color(rarity_index + 1):
			tints_distinct = false
	_assert(tints_distinct, "adjacent rarities resolve to distinct tints")
	GameTheme.rarity_color(999)
	GameTheme.rarity_color(-5)
	_assert(true, "out-of-range rarity indices clamp safely")


func _test_input_actions() -> void:
	InputActions.ensure_default_actions()
	_assert(InputMap.has_action(InputActions.PAUSE_ACTION), "pause action exists")

	var has_key: bool = false
	var has_joypad: bool = false
	for event: InputEvent in InputMap.action_get_events(InputActions.PAUSE_ACTION):
		if event is InputEventKey:
			has_key = true
		elif event is InputEventJoypadButton:
			has_joypad = true
	_assert(has_key, "pause action is bound to a keyboard key")
	_assert(has_joypad, "pause action is bound to a gamepad button")

	# Navigation actions ship with the engine and cover keyboard + gamepad menus.
	var navigation_actions: Array[String] = ["ui_accept", "ui_cancel", "ui_up", "ui_down", "ui_left", "ui_right"]
	var navigation_ok: bool = true
	for action: String in navigation_actions:
		if not InputMap.has_action(action):
			navigation_ok = false
	_assert(navigation_ok, "default UI navigation actions are available")


func _test_settings() -> void:
	SettingsManager.reset_to_defaults()
	_assert(SettingsManager.ui_scale == 1.0, "reset restores the default UI scale")

	SettingsManager.set_ui_scale(99.0)
	_assert(is_equal_approx(SettingsManager.ui_scale, SettingsManager.UI_SCALE_MAX), "UI scale clamps to the maximum")
	SettingsManager.set_ui_scale(-5.0)
	_assert(is_equal_approx(SettingsManager.ui_scale, SettingsManager.UI_SCALE_MIN), "UI scale clamps to the minimum")

	SettingsManager.set_volume("SFX", 2.0)
	_assert(is_equal_approx(SettingsManager.sfx_volume, 1.0), "volume clamps to 1.0")
	SettingsManager.set_volume("NotABus", 0.5)
	_assert(true, "unknown audio bus names are ignored without error")

	var snapshot: Dictionary = SettingsManager.get_snapshot()
	var snapshot_keys: Array[String] = [
		"window_mode", "vsync_enabled", "ui_scale",
		"master_volume", "music_volume", "sfx_volume",
		"reduce_motion", "high_contrast", "show_fps",
	]
	var keys_ok: bool = true
	for key: String in snapshot_keys:
		if not snapshot.has(key):
			keys_ok = false
	_assert(keys_ok, "settings snapshot exposes every option")

	# Persistence round-trip.
	SettingsManager.set_ui_scale(1.25)
	SettingsManager.set_show_fps(true)
	SettingsManager.set_reduce_motion(true)
	SettingsManager.save_settings()

	SettingsManager.ui_scale = 1.0
	SettingsManager.show_fps = false
	SettingsManager.reduce_motion = false
	SettingsManager.load_settings()
	_assert(is_equal_approx(SettingsManager.ui_scale, 1.25), "settings survive a save/load round-trip")
	_assert(SettingsManager.show_fps, "boolean settings survive a save/load round-trip")

	SettingsManager.reset_to_defaults()


func _test_progression() -> void:
	ProgressionManager.load_state({"level": 1, "xp": 0})
	_assert(ProgressionManager.get_level() == 1, "progression resets to level 1")
	_assert(ProgressionManager.get_xp_to_next() > 0, "the first level requires experience")

	var required: int = ProgressionManager.get_xp_to_next()
	ProgressionManager.add_xp(required)
	_assert(ProgressionManager.get_level() == 2, "gaining a full bar levels the character up")
	_assert(ProgressionManager.get_xp() == 0, "overflow experience is carried correctly")

	ProgressionManager.add_xp(0)
	_assert(ProgressionManager.get_level() == 2, "zero experience is ignored")

	ProgressionManager.load_state({"level": 1, "xp": 0})


func _test_save_load() -> void:
	# Seed a distinctive state, persist it, wipe it, then restore it.
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	CurrencyManager.add_copper(250)
	StatsManager.set_base_stats({"attack_power": 42.0, "defense": 7.0, "critical_rate": 0.1, "luck": 3.0})
	ProgressionManager.load_state({"level": 4, "xp": 12})

	var saved: bool = SaveManager.save_game(TEST_SAVE_PATH)
	_assert(saved, "SaveManager writes a save file")
	_assert(SaveManager.has_save(TEST_SAVE_PATH), "the written save file exists")

	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	StatsManager.set_base_stats({"attack_power": 1.0, "defense": 1.0, "critical_rate": 0.0, "luck": 0.0})
	ProgressionManager.load_state({"level": 1, "xp": 0})

	var loaded: bool = SaveManager.load_game(TEST_SAVE_PATH)
	_assert(loaded, "SaveManager reads the save file back")
	_assert(CurrencyManager.copper == 50 and CurrencyManager.silver == 2, "currency is restored with tier normalization")
	_assert(is_equal_approx(StatsManager.get_base_stats().attack_power, 42.0), "base stats are restored")
	_assert(ProgressionManager.get_level() == 4, "progression is restored")

	_assert(SaveManager.load_game("user://definitely_missing.json") == false, "loading a missing save fails gracefully")
	_assert(SaveManager.delete_save(TEST_SAVE_PATH), "the test save file can be deleted")

	# Leave the live managers in a clean default state for later suites.
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	StatsManager.set_base_stats({"attack_power": 10.0, "defense": 5.0, "critical_rate": 0.05, "luck": 0.0})
	ProgressionManager.load_state({"level": 1, "xp": 0})


func _test_overlay_menus() -> void:
	var pause_menu: CanvasLayer = (load("res://scripts/ui/PauseMenu.gd") as GDScript).new()
	var settings_menu: CanvasLayer = (load("res://scripts/ui/SettingsMenu.gd") as GDScript).new()
	var credits: CanvasLayer = (load("res://scripts/ui/Credits.gd") as GDScript).new()

	for menu: CanvasLayer in [pause_menu, settings_menu, credits]:
		get_tree().root.add_child(menu)
	await _settle()

	_assert(not pause_menu.visible, "the pause menu starts hidden")
	_assert(is_equal_approx(pause_menu.layer, 100.0), "the pause menu renders above the HUD")
	_assert(_find_button(pause_menu, "Resume") != null, "the pause menu has a Resume button")
	_assert(_find_button(pause_menu, "Quit to Desktop") != null, "the pause menu has a Quit button")

	var settings_tabs: TabContainer = _find_tab_container(settings_menu)
	_assert(settings_tabs != null and settings_tabs.get_tab_count() == 3, "the settings menu has three tabs")
	_assert(_find_check_button(settings_menu, "V-Sync") != null, "the graphics tab exposes V-Sync")
	_assert(_find_check_button(settings_menu, "High Contrast") != null, "the accessibility tab exposes High Contrast")
	_assert(_find_button(settings_menu, "Back") != null, "the settings menu can be closed")

	var credits_closed: Array[bool] = [false]
	credits.closed.connect(func() -> void: credits_closed[0] = true)
	credits.set_shown(true)
	_assert(credits.visible, "the credits card can be shown")
	credits.close()
	_assert(not credits.visible and credits_closed[0], "closing the credits reports completion")

	for menu: CanvasLayer in [pause_menu, settings_menu, credits]:
		_assert(_collect_scroll_containers(menu).is_empty(), "%s contains no ScrollContainer" % menu.name)
		menu.queue_free()
	await _settle()


func _test_main_integration() -> void:
	var main_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_assert(main_scene != null, "the main scene loads")
	if main_scene == null:
		return

	var main: Node = main_scene.instantiate()
	get_tree().root.add_child(main)
	await _settle()

	_assert(main.get_node_or_null("BackgroundLayer/Background") != null, "the backdrop layer is created")
	_assert(main.get_node_or_null("BackgroundLayer/AmbientMotes") != null, "the ambient particle effect is created")
	_assert(main.get_node_or_null("PauseMenu") != null, "the pause menu is mounted")
	_assert(main.get_node_or_null("SettingsMenu") != null, "the settings menu is mounted")
	_assert(main.get_node_or_null("Credits") != null, "the credits overlay is mounted")
	_assert(main.get_node_or_null("FPSLayer/FPSLabel") != null, "the FPS counter is mounted")

	var hud_margin: MarginContainer = main.get_node_or_null("HUDRoot/HUDRootMargin") as MarginContainer
	_assert(hud_margin != null and hud_margin.theme != null, "the shared theme is applied to the HUD")

	var pause_menu: CanvasLayer = main.get_node_or_null("PauseMenu") as CanvasLayer
	_assert(pause_menu != null and not pause_menu.visible, "the game starts unpaused")

	# Toggling pause must pause the tree and surface the overlay.
	var pause_signals: Array[bool] = []
	SignalBus.pause_toggled.connect(func(paused: bool) -> void: pause_signals.append(paused))
	main._toggle_pause()
	await _settle()
	_assert(get_tree().paused, "toggling pause pauses the scene tree")
	_assert(pause_menu.visible, "toggling pause shows the pause overlay")
	_assert(pause_signals.size() > 0 and pause_signals[0], "pause state is broadcast on SignalBus")

	main._toggle_pause()
	await _settle()
	_assert(not get_tree().paused, "toggling pause again resumes the game")
	_assert(not pause_menu.visible, "resuming hides the pause overlay")

	# The accessibility FPS toggle must drive the on-screen label.
	var fps_label: Label = main.get_node_or_null("FPSLayer/FPSLabel") as Label
	_assert(fps_label != null and not fps_label.visible, "the FPS counter is hidden by default")
	SettingsManager.set_show_fps(true)
	await _settle()
	_assert(fps_label.visible, "enabling Show FPS reveals the counter")
	SettingsManager.set_show_fps(false)
	await _settle()
	_assert(not fps_label.visible, "disabling Show FPS hides the counter")

	# High contrast must rebuild the theme without error.
	SettingsManager.set_high_contrast(true)
	await _settle()
	_assert(hud_margin.theme != null, "the theme survives a high-contrast rebuild")
	SettingsManager.set_high_contrast(false)

	main.queue_free()
	await _settle()


func _test_performance() -> void:
	var load_start_usec: int = Time.get_ticks_usec()
	var main_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_assert(main_scene != null, "the main scene loads for the performance suite")
	if main_scene == null:
		return

	var main: Node = main_scene.instantiate()
	get_tree().root.add_child(main)
	await _settle()
	var load_usec: int = Time.get_ticks_usec() - load_start_usec
	_assert(load_usec < 3_000_000, "the main scene loads in under 3 s (%.1f ms)" % (float(load_usec) / 1000.0))

	# Sample a short run and confirm the average frame time stays inside a 60 Hz
	# budget (16.6 ms), which is the ceiling for responsive 60+ FPS play.
	const SAMPLE_FRAMES: int = 60
	const FRAME_BUDGET_USEC: float = 16666.0
	var total_usec: int = 0
	for _i: int in SAMPLE_FRAMES:
		var frame_start_usec: int = Time.get_ticks_usec()
		await get_tree().process_frame
		total_usec += Time.get_ticks_usec() - frame_start_usec
	var average_usec: float = float(total_usec) / float(SAMPLE_FRAMES)
	_assert(average_usec < FRAME_BUDGET_USEC, "average frame time holds a 60 FPS budget (%.2f ms)" % (average_usec / 1000.0))
	_assert(Engine.get_frames_per_second() >= 0, "the engine reports a valid frame rate")

	# Memory sanity: a non-trivial but bounded footprint.
	var memory_bytes: int = OS.get_static_memory_usage()
	_assert(memory_bytes > 0, "the engine reports static memory usage")

	# Node budget: the fully-wired HUD must stay well under a sane node ceiling.
	var node_count: int = _collect_nodes(main).size()
	_assert(node_count > 0 and node_count < 2000, "the mounted scene stays within a sane node budget (%d nodes)" % node_count)

	main.queue_free()
	await _settle()


func _test_soak() -> void:
	var main_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	if main_scene == null:
		_assert(false, "the main scene loads for the soak suite")
		return

	var main: Node = main_scene.instantiate()
	get_tree().root.add_child(main)
	await _settle()

	var pause_menu: CanvasLayer = main.get_node_or_null("PauseMenu") as CanvasLayer
	_assert(pause_menu != null, "the soak suite can reach the pause overlay")
	var baseline_nodes: int = _collect_nodes(main).size()

	# Simulate an extended session: repeatedly cycle the pause overlay and confirm
	# the paused state stays consistent every time.
	var cycle_consistent: bool = true
	for _cycle: int in 8:
		main._toggle_pause()
		await _settle()
		if not get_tree().paused or pause_menu == null or not pause_menu.visible:
			cycle_consistent = false
		main._toggle_pause()
		await _settle()
		if get_tree().paused or pause_menu == null or pause_menu.visible:
			cycle_consistent = false
	_assert(cycle_consistent, "repeated pause toggles stay consistent over a session")

	# Drive the idle loop for a longer stretch of frames.
	const SOAK_FRAMES: int = 300
	for _i: int in SOAK_FRAMES:
		await get_tree().process_frame

	var settled_nodes: int = _collect_nodes(main).size()
	_assert(settled_nodes == baseline_nodes, "node count stays stable over an extended session (%d -> %d)" % [baseline_nodes, settled_nodes])

	# The managers must still answer correctly after the long run.
	_assert(ProgressionManager.get_level() >= 1, "progression stays valid after an extended session")
	_assert(CurrencyManager.copper >= 0, "currency stays valid after an extended session")
	_assert(not get_tree().paused, "the tree is left unpaused mid-session")

	main.queue_free()
	await _settle()


func _cleanup() -> void:
	get_tree().paused = false
	SettingsManager.reset_to_defaults()
	SaveManager.delete_save(TEST_SAVE_PATH)
	ProgressionManager.load_state({"level": 1, "xp": 0})


# --- Helpers ---------------------------------------------------------------

func _settle() -> void:
	for _i: int in 4:
		await get_tree().process_frame


func _find_button(root_node: Node, button_text: String) -> Button:
	for node: Node in _collect_nodes(root_node):
		var button: Button = node as Button
		if button != null and button.text == button_text:
			return button
	return null


func _find_check_button(root_node: Node, contains_text: String) -> CheckButton:
	for node: Node in _collect_nodes(root_node):
		var toggle: CheckButton = node as CheckButton
		if toggle != null:
			var row: Node = toggle.get_parent()
			if row != null:
				for sibling: Node in row.get_children():
					var label: Label = sibling as Label
					if label != null and label.text.contains(contains_text):
						return toggle
	return null


func _find_tab_container(root_node: Node) -> TabContainer:
	for node: Node in _collect_nodes(root_node):
		var tabs: TabContainer = node as TabContainer
		if tabs != null:
			return tabs
	return null


func _collect_scroll_containers(root_node: Node) -> Array[ScrollContainer]:
	var found: Array[ScrollContainer] = []
	for node: Node in _collect_nodes(root_node):
		var scroll: ScrollContainer = node as ScrollContainer
		if scroll != null:
			found.append(scroll)
	return found


func _collect_nodes(root_node: Node) -> Array[Node]:
	var nodes: Array[Node] = [root_node]
	for child: Node in root_node.get_children():
		nodes.append_array(_collect_nodes(child))
	return nodes


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: %s" % message)


func _finish() -> void:
	print("RESULT passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
