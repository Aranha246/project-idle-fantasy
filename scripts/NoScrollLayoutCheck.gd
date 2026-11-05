extends Node
## Headless layout guard for the windowed interface.
##
## Proves three things, at every supported resolution:
##
## - the persistent chrome (menu bar and status bar) never scrolls,
## - every floating window stays fully on screen,
## - and no window shows a scrollbar at 1280x720 or larger, the point past
##   which content is expected to fit. Scrolling is allowed only below that, and
##   only inside a window body, so small screens stay usable without the
##   interface ever growing scrollbars of its own.

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

## At and above this size no scrollbar may be visible anywhere.
const SCROLL_FREE_MIN_SIZE: Vector2i = Vector2i(1280, 720)

const CHROME_PATH: String = "HUDRoot/HUDRootMargin/HUDRootBox"
const RECT_TOLERANCE: float = 1.0

var _failed: int = 0
var _passed: int = 0


func _ready() -> void:
	print("Starting no-scroll layout tests...")
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

	var menu_bar: MenuBarUI = main.get_node_or_null(CHROME_PATH + "/MenuBar") as MenuBarUI
	var window_host: WindowHostUI = main.get_node_or_null(CHROME_PATH + "/WindowHost") as WindowHostUI
	var status_bar: Control = main.get_node_or_null(CHROME_PATH + "/StatusBar") as Control

	_assert(menu_bar != null, "the persistent menu bar exists")
	_assert(window_host != null, "the floating window host exists")
	_assert(status_bar != null, "the persistent status bar exists")
	if menu_bar == null or window_host == null or status_bar == null:
		main.queue_free()
		await _settle()
		_finish()
		return

	# --- chrome never scrolls ------------------------------------------------
	_assert(_collect_scroll_containers(menu_bar).is_empty(), "the menu bar has no scroll container")
	_assert(_collect_scroll_containers(status_bar).is_empty(), "the status bar has no scroll container")

	# --- every authored window is listed and mounted -------------------------
	var floating_ids: Array[StringName] = _floating_window_ids()
	_assert(not floating_ids.is_empty(), "the registry authors at least one floating window")

	var missing_toggles: int = 0
	var missing_windows: int = 0
	for window_id: StringName in floating_ids:
		if menu_bar.get_toggle(window_id) == null:
			missing_toggles += 1
		if window_host.get_game_window(window_id) == null:
			missing_windows += 1
	_assert(missing_toggles == 0, "the menu bar lists every floating window")
	_assert(missing_windows == 0, "the window host mounts every floating window")
	_assert(menu_bar.get_toggle(WindowRegistry.SETTINGS_ID) != null, "the menu bar also lists the settings window")

	_assert(
		_collect_scroll_containers(main).size() == _collect_scroll_containers(window_host).size(),
		"scrolling only ever happens inside a window body"
	)

	# Open everything so the layout is exercised at its densest.
	for window_id: StringName in floating_ids:
		WindowManager.set_open(window_id, true)
	await _settle()

	var open_count: int = 0
	for window_id: StringName in floating_ids:
		var window: GameWindow = window_host.get_game_window(window_id)
		if window != null and window.visible:
			open_count += 1
	_assert(open_count == floating_ids.size(), "every floating window can be open at the same time")

	for resolution: Vector2i in RESOLUTIONS:
		get_window().size = resolution
		get_window().content_scale_size = resolution
		await _settle()

		var label: String = "%dx%d" % [resolution.x, resolution.y]
		var viewport_size: Vector2 = get_viewport().get_visible_rect().size

		_assert(_fits_viewport(menu_bar, viewport_size), "%s: the menu bar fits the viewport" % label)
		_assert(_fits_viewport(status_bar, viewport_size), "%s: the status bar fits the viewport" % label)
		_assert(_fits_viewport(window_host, viewport_size), "%s: the window host fits the viewport" % label)

		var outside: String = ""
		for window_id: StringName in floating_ids:
			var window: GameWindow = window_host.get_game_window(window_id)
			if window == null or not window.visible:
				continue
			if not _fits_viewport(window, viewport_size):
				outside = String(window_id)
				break
		_assert(outside.is_empty(), "%s: every open window stays on screen (%s escaped)" % [label, outside])

		if resolution.x >= SCROLL_FREE_MIN_SIZE.x and resolution.y >= SCROLL_FREE_MIN_SIZE.y:
			var scrollbars: Array[ScrollContainer] = _visible_scrollbars(window_host)
			_assert(
				scrollbars.is_empty(),
				"%s: no window shows a scrollbar (%d visible)" % [label, scrollbars.size()]
			)

	# Leave the real settings file exactly as the authored defaults describe it.
	WindowManager.reset_to_defaults()
	main.queue_free()
	await _settle()
	_finish()


# --- Helpers ---------------------------------------------------------------

func _settle() -> void:
	for _i: int in 4:
		await get_tree().process_frame


## Every authored window that is a floating panel, i.e. all of them except the
## settings entry, which opens the existing modal overlay instead.
func _floating_window_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for window_id: StringName in WindowRegistry.get_window_ids():
		if window_id != WindowRegistry.SETTINGS_ID:
			ids.append(window_id)
	return ids


func _fits_viewport(control: Control, viewport_size: Vector2) -> bool:
	if control == null:
		return false
	var rect: Rect2 = control.get_global_rect()
	return (
		rect.position.x >= -RECT_TOLERANCE
		and rect.position.y >= -RECT_TOLERANCE
		and rect.end.x <= viewport_size.x + RECT_TOLERANCE
		and rect.end.y <= viewport_size.y + RECT_TOLERANCE
	)


func _collect_scroll_containers(root_node: Node) -> Array[ScrollContainer]:
	var found: Array[ScrollContainer] = []
	for child: Node in root_node.get_children():
		if child is ScrollContainer:
			found.append(child as ScrollContainer)
		found.append_array(_collect_scroll_containers(child))
	return found


## Scroll containers whose vertical or horizontal bar is actually drawn.
func _visible_scrollbars(root_node: Node) -> Array[ScrollContainer]:
	var found: Array[ScrollContainer] = []
	for node: Node in _collect_scroll_containers(root_node):
		# Looked up dynamically: the script-level `ScrollContainer` type does not
		# expose its scrollbar children, so a direct property access would fail.
		var vertical_bar: VScrollBar = node.get("scroll_vertical_bar") as VScrollBar
		var horizontal_bar: HScrollBar = node.get("scroll_horizontal_bar") as HScrollBar
		var shows_vertical: bool = vertical_bar != null and vertical_bar.visible
		var shows_horizontal: bool = horizontal_bar != null and horizontal_bar.visible
		if shows_vertical or shows_horizontal:
			found.append(node as ScrollContainer)
	return found


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
