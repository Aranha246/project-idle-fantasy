extends Node2D
## Root scene controller.
##
## Every UI panel is mounted inside a single screen-fixed `CanvasLayer` and laid
## out by one shared container hierarchy:
##
##     CanvasLayer
##       └─ MarginContainer        (16px screen margin)
##            └─ ScrollContainer   (prevents any overlap / off-screen bleeding)
##                 └─ HBoxContainer (16px gap between panels)
##                      ├─ HUD / currency panel  (fixed width, left aligned)
##                      ├─ Zone selection panel  (flexible)
##                      ├─ Character stats panel (fixed width)
##                      ├─ Equipment panel       (fixed width)
##                      └─ Inventory panel       (flexible, rightmost)
##
## Because every panel is a child of the same `HBoxContainer`, panels can never
## overlap regardless of the viewport size: their spacing is enforced by the
## container separation and content that does not fit scrolls horizontally
## instead of bleeding past the screen edge.
##
## Scenes are loaded defensively: a missing or broken file logs an error and is
## skipped instead of crashing the game.

## Panels to mount, in strict left-to-right order.
const UI_SCENES: Array[String] = [
	"res://scenes/ui/HUD.tscn",
	"res://scenes/ui/ZoneSelectionUI.tscn",
	"res://scenes/ui/StatsUI.tscn",
	"res://scenes/ui/EquipmentUI.tscn",
	"res://scenes/ui/InventoryUI.tscn",
]

## CanvasLayer level used to host the HUD.
const UI_LAYER: int = 1

## Screen edge margin (in pixels) applied on all four sides.
const SCREEN_MARGIN: int = 16

## Gap (in pixels) enforced between adjacent panels.
const PANEL_GAP: int = 16

## Fallback width used when a panel declares no minimum width of its own.
const MIN_PANEL_WIDTH: float = 160.0

var _scroll: ScrollContainer = null
var _panel_row: HBoxContainer = null
var _root_margin: MarginContainer = null


func _ready() -> void:
	_build_hud_root()
	for scene_path: String in UI_SCENES:
		_mount_ui_panel(scene_path)

	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


## Builds the single CanvasLayer > Margin > Scroll > HBox hierarchy that owns
## every HUD panel.
func _build_hud_root() -> void:
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.name = "HUDRoot"
	ui_layer.layer = UI_LAYER
	add_child(ui_layer)

	_root_margin = MarginContainer.new()
	_root_margin.name = "HUDRootMargin"
	_root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_margin.add_theme_constant_override("margin_left", SCREEN_MARGIN)
	_root_margin.add_theme_constant_override("margin_top", SCREEN_MARGIN)
	_root_margin.add_theme_constant_override("margin_right", SCREEN_MARGIN)
	_root_margin.add_theme_constant_override("margin_bottom", SCREEN_MARGIN)
	_root_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(_root_margin)

	_scroll = ScrollContainer.new()
	_scroll.name = "HUDPanelScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_root_margin.add_child(_scroll)

	_panel_row = HBoxContainer.new()
	_panel_row.name = "HUDPanelRow"
	_panel_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_panel_row.add_theme_constant_override("separation", PANEL_GAP)
	_panel_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_panel_row)


## Instantiates `scene_path` and adds it to the panel row so the container
## enforces ordering and spacing.
func _mount_ui_panel(scene_path: String) -> void:
	var panel: Control = _instantiate_panel(scene_path)
	if panel == null:
		return
	_panel_row.add_child(panel)


## Validates and instantiates `scene_path`, returning null (with an error
## logged) when the resource is missing or cannot be turned into a Control.
func _instantiate_panel(scene_path: String) -> Control:
	if not ResourceLoader.exists(scene_path):
		push_error("Main: UI scene not found at '%s'." % scene_path)
		return null
	var packed_scene: PackedScene = load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Main: '%s' is not a valid PackedScene." % scene_path)
		return null
	var instance: Node = packed_scene.instantiate()
	if instance == null:
		push_error("Main: failed to instantiate '%s'." % scene_path)
		return null
	if not instance is Control:
		push_error("Main: '%s' root is not a Control and cannot be laid out." % scene_path)
		instance.queue_free()
		return null
	return instance as Control


## Runtime guardrail: keeps the panel row inside the viewport at every
## resolution by enabling scrolling only on the axis that actually overflows.
func _on_viewport_resized() -> void:
	if _scroll == null or _panel_row == null:
		return

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var viewport_size: Vector2 = viewport.get_visible_rect().size
	var available_width: float = maxf(0.0, viewport_size.x - float(SCREEN_MARGIN) * 2.0)
	var available_height: float = maxf(0.0, viewport_size.y - float(SCREEN_MARGIN) * 2.0)

	if _required_row_width() > available_width:
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	else:
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	if _required_row_height() > available_height:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	else:
		_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


## Total width the panel row needs at its current minimum sizes. Uses
## `get_combined_minimum_size()` so panel content (not just the declared
## `custom_minimum_size`) is taken into account.
func _required_row_width() -> float:
	var total: float = 0.0
	var count: int = 0
	for child: Node in _panel_row.get_children():
		if child is Control:
			var panel: Control = child as Control
			total += maxf(panel.get_combined_minimum_size().x, MIN_PANEL_WIDTH)
			count += 1
	if count > 1:
		total += float(PANEL_GAP) * float(count - 1)
	return total


## Tallest panel in the row, used to decide whether vertical scrolling is needed.
func _required_row_height() -> float:
	var tallest: float = 0.0
	for child: Node in _panel_row.get_children():
		if child is Control:
			tallest = maxf(tallest, (child as Control).get_combined_minimum_size().y)
	return tallest
