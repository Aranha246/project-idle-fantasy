extends Node

const MAIN_SCENE: String = "res://scenes/Main.tscn"
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1152, 648),
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
	Vector2i(1280, 800),
	Vector2i(844, 390),
	Vector2i(390, 844),
]
const EXPECTED_TABS: Array[String] = ["Overview", "Quests", "Upgrades", "Equipment", "Inventory"]

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	print("Starting no-scroll HUD layout tests...")
	call_deferred("_run")


func _run() -> void:
	var main_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_assert(main_scene != null, "Main scene loads")
	if main_scene == null:
		_finish()
		return

	var main: Node = main_scene.instantiate()
	get_tree().root.add_child(main)
	await _settle()

	var tabs: TabContainer = get_tree().root.get_node_or_null("Main/HUDRoot/HUDRootMargin/HUDRootBox/HUDTabs") as TabContainer
	_assert(tabs != null, "HUD tabs exist")
	if tabs == null:
		main.queue_free()
		await _settle()
		_finish()
		return

	_assert(_tab_titles(tabs) == EXPECTED_TABS, "HUD tabs use the expected screen order")
	_assert(_collect_scroll_containers(main).is_empty(), "No ScrollContainer nodes remain in the HUD")

	for resolution: Vector2i in RESOLUTIONS:
		get_window().size = resolution
		get_window().content_scale_size = resolution
		await _settle()
		var effective_size: Vector2 = get_viewport().get_visible_rect().size

		for tab_index: int in tabs.get_tab_count():
			tabs.current_tab = tab_index
			await _settle()

			var active_panels: Array[Control] = _visible_tracked_panels(main)
			_assert(not active_panels.is_empty(), "%s: tab %s shows content" % [resolution, tabs.get_tab_title(tab_index)])
			_assert(_panels_fit_viewport(active_panels, effective_size), "%s: tab %s fits inside the viewport" % [resolution, tabs.get_tab_title(tab_index)])
			_assert(_panels_do_not_overlap(active_panels), "%s: tab %s has no panel overlap" % [resolution, tabs.get_tab_title(tab_index)])

	main.queue_free()
	await _settle()
	_finish()


func _settle() -> void:
	for _i: int in 4:
		await get_tree().process_frame


func _tab_titles(tabs: TabContainer) -> Array[String]:
	var titles: Array[String] = []
	for tab_index: int in tabs.get_tab_count():
		titles.append(tabs.get_tab_title(tab_index))
	return titles


func _collect_scroll_containers(root_node: Node) -> Array[ScrollContainer]:
	var found: Array[ScrollContainer] = []
	for child: Node in root_node.get_children():
		if child is ScrollContainer:
			found.append(child as ScrollContainer)
		found.append_array(_collect_scroll_containers(child))
	return found


func _visible_tracked_panels(main: Node) -> Array[Control]:
	var panels: Array[Control] = []
	for panel_name: String in ["HUD", "ZoneSelectionUI", "StatsUI", "QuestUI", "UpgradeUI", "EquipmentUI", "InventoryUI"]:
		var panel: Control = main.find_child(panel_name, true, false) as Control
		if panel != null and panel.is_visible_in_tree():
			panels.append(panel)
	return panels


func _panels_fit_viewport(panels: Array[Control], viewport_size: Vector2) -> bool:
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, viewport_size)
	for panel: Control in panels:
		var panel_rect: Rect2 = panel.get_global_rect()
		if panel_rect.position.x < 0.0 or panel_rect.position.y < 0.0:
			push_warning("%s: %s starts outside viewport: rect=%s viewport=%s" % [viewport_size, panel.name, panel_rect, viewport_rect])
			return false
		if panel_rect.end.x > viewport_rect.end.x:
			push_warning("%s: %s exceeds viewport width: rect=%s viewport=%s" % [viewport_size, panel.name, panel_rect, viewport_rect])
			return false
		if panel_rect.end.y > viewport_rect.end.y:
			push_warning("%s: %s exceeds viewport height: rect=%s viewport=%s" % [viewport_size, panel.name, panel_rect, viewport_rect])
			return false
		if panel_rect.size.x + 0.5 < panel.get_combined_minimum_size().x:
			push_warning("%s: %s width below minimum: rect=%s minimum=%s" % [viewport_size, panel.name, panel_rect, panel.get_combined_minimum_size()])
			return false
		if panel_rect.size.y + 0.5 < panel.get_combined_minimum_size().y:
			push_warning("%s: %s height below minimum: rect=%s minimum=%s" % [viewport_size, panel.name, panel_rect, panel.get_combined_minimum_size()])
			return false
	return true


func _panels_do_not_overlap(panels: Array[Control]) -> bool:
	for i: int in panels.size():
		for j: int in range(i + 1, panels.size()):
			if panels[i].get_global_rect().intersects(panels[j].get_global_rect()):
				return false
	return true


func _assert(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: %s" % message)
	else:
		_failed += 1
		push_error("FAIL: %s" % message)


func _finish() -> void:
	print("")
	print("RESULT passed=%d failed=%d" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)
