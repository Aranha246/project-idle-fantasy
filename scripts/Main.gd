extends Node2D
## Root scene controller.
##
## The HUD no longer uses any scrolling containers. Instead, the interface is
## split into five responsive tabs:
##
## - Overview: currency, zone selection, and character stats
## - Quests: the player-driven quest board (with the animated hero)
## - Upgrades: the currency upgrade shop
## - Equipment: equipment management
## - Inventory: inventory management
##
## This keeps every panel fully visible on supported resolutions without
## horizontal or vertical scrollbars. The overview screen swaps between a
## side-by-side layout on wider viewports and a stacked layout on narrower ones.
##
## Responsibilities beyond layout:
##
## - applying the shared `GameTheme` and rebuilding it when accessibility
##   options change,
## - mounting the pause, settings and credits overlays and routing their
##   signals,
## - toggling the pause state (and `get_tree().paused`) on the `pause` action,
## - autosave/restore through `SaveManager`,
## - and an optional on-screen FPS counter.

const SCREEN_MARGIN: int = 16
const PANEL_GAP: int = 12
const UI_LAYER: int = 1
const BACKGROUND_LAYER: int = -1
const FPS_LAYER: int = 50
const WIDE_LAYOUT_MIN_WIDTH: float = 720.0
const WIDE_LAYOUT_MIN_HEIGHT: float = 340.0

const FPS_LABEL_INSET: float = 10.0
const FPS_LABEL_FONT_SIZE: int = 13

const HUD_SCENE: String = "res://scenes/ui/HUD.tscn"
const ZONE_SCENE: String = "res://scenes/ui/ZoneSelectionUI.tscn"
const STATS_SCENE: String = "res://scenes/ui/StatsUI.tscn"
const QUEST_SCENE: String = "res://scenes/ui/QuestUI.tscn"
const UPGRADE_SCENE: String = "res://scenes/ui/UpgradeUI.tscn"
const EQUIPMENT_SCENE: String = "res://scenes/ui/EquipmentUI.tscn"
const INVENTORY_SCENE: String = "res://scenes/ui/InventoryUI.tscn"

var _tabs: TabContainer = null
var _overview_wide_row: HBoxContainer = null
var _overview_wide_zone_host: VBoxContainer = null
var _overview_wide_sidebar: VBoxContainer = null
var _overview_narrow_column: VBoxContainer = null
var _quests_host: MarginContainer = null
var _upgrades_host: MarginContainer = null
var _equipment_host: CenterContainer = null
var _inventory_host: CenterContainer = null

var _hud_panel: Control = null
var _zone_panel: Control = null
var _stats_panel: Control = null
var _quest_panel: Control = null
var _upgrade_panel: Control = null
var _equipment_panel: Control = null
var _inventory_panel: Control = null

var _hud_theme_root: Control = null
var _fps_label: Label = null
var _ambient_particles: CPUParticles2D = null

var _pause_menu: PauseMenu = null
var _settings_menu: SettingsMenu = null
var _credits: Credits = null

var _ui_theme: Theme = null


func _ready() -> void:
	# Register the action map before anything can listen for input.
	InputActions.ensure_default_actions()

	# Keep processing while the tree is paused so the pause key can resume.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_ui_theme = GameTheme.build(SettingsManager.high_contrast)

	_build_background()
	_build_hud_root()
	_instantiate_panels()
	_assign_static_panels()
	_refresh_overview_layout()
	_build_overlays()
	_build_fps_overlay()

	# Restore a previous session before the first frame so the HUD starts with
	# the correct wallet, stats and zone instead of flashing the defaults.
	if SaveManager.has_save():
		SaveManager.load_game()

	SignalBus.settings_changed.connect(_on_settings_changed)

	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_on_viewport_resized):
		viewport.size_changed.connect(_on_viewport_resized)


func _process(_delta: float) -> void:
	if _fps_label != null and _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(InputActions.PAUSE_ACTION):
		return
	# In a menu context the pause key backs out of the open overlay first.
	if _credits != null and _credits.visible:
		_credits.close()
		get_viewport().set_input_as_handled()
		return
	if _settings_menu != null and _settings_menu.visible:
		_settings_menu.set_shown(false)
		get_viewport().set_input_as_handled()
		return
	_toggle_pause()
	get_viewport().set_input_as_handled()


func _build_background() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "BackgroundLayer"
	layer.layer = BACKGROUND_LAYER
	add_child(layer)

	var background: ColorRect = ColorRect.new()
	background.name = "Background"
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = GameTheme.BACKGROUND_COLOR
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)

	_ambient_particles = _build_ambient_particles()
	layer.add_child(_ambient_particles)
	_update_ambient_bounds()


## Slowly drifting motes add depth to the flat backdrop. Implemented as
## `CPUParticles2D` (not GPU) so it also renders in headless/software builds, and
## kept at a low particle count so it costs nothing measurable on minimum spec.
func _build_ambient_particles() -> CPUParticles2D:
	var particles: CPUParticles2D = CPUParticles2D.new()
	particles.name = "AmbientMotes"
	particles.amount = 24
	particles.lifetime = 7.0
	particles.preprocess = 3.0
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.direction = Vector2(0.0, -1.0)
	particles.spread = 18.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 6.0
	particles.initial_velocity_max = 18.0
	particles.scale_amount_min = 0.4
	particles.scale_amount_max = 1.1
	particles.color = GameTheme.AMBIENT_COLOR
	particles.texture = _build_mote_texture()
	return particles


## A soft radial dot used by the ambient motes, generated in code so the project
## does not need a sprite asset for it.
func _build_mote_texture() -> GradientTexture2D:
	var gradient: Gradient = Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))

	var texture: GradientTexture2D = GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 16
	texture.height = 16
	return texture


## Re-anchors the emitter to the bottom edge of the current logical viewport.
func _update_ambient_bounds() -> void:
	if _ambient_particles == null:
		return
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	var size: Vector2 = viewport.get_visible_rect().size
	# Keep emitting even during the transient zero-size frame at startup.
	var half_width: float = maxf(size.x * 0.5, 640.0)
	_ambient_particles.position = Vector2(size.x * 0.5, size.y + 24.0)
	_ambient_particles.emission_rect_extents = Vector2(half_width, 8.0)
	_ambient_particles.emitting = not SettingsManager.reduce_motion


func _build_overlays() -> void:
	_pause_menu = PauseMenu.new()
	add_child(_pause_menu)
	_pause_menu.set_ui_theme(_ui_theme)
	_pause_menu.resume_requested.connect(func() -> void: _set_paused(false))
	_pause_menu.save_requested.connect(_on_save_requested)
	_pause_menu.settings_requested.connect(_on_settings_requested)
	_pause_menu.credits_requested.connect(_on_credits_requested)
	_pause_menu.quit_requested.connect(_on_quit_requested)

	_settings_menu = SettingsMenu.new()
	add_child(_settings_menu)
	_settings_menu.set_ui_theme(_ui_theme)
	_settings_menu.closed.connect(_on_settings_closed)

	_credits = Credits.new()
	add_child(_credits)
	_credits.set_ui_theme(_ui_theme)
	_credits.closed.connect(_on_credits_closed)


func _build_fps_overlay() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "FPSLayer"
	layer.layer = FPS_LAYER
	add_child(layer)

	_fps_label = Label.new()
	_fps_label.name = "FPSLabel"
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_fps_label.offset_left = -(FPS_LABEL_INSET + 120.0)
	_fps_label.offset_top = -(FPS_LABEL_INSET + 30.0)
	_fps_label.offset_right = -FPS_LABEL_INSET
	_fps_label.offset_bottom = -FPS_LABEL_INSET
	_fps_label.add_theme_font_size_override("font_size", FPS_LABEL_FONT_SIZE)
	_fps_label.modulate = Color(0.7, 1.0, 0.7, 0.9)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fps_label)

	_apply_show_fps(SettingsManager.show_fps)


func _apply_show_fps(show_fps: bool) -> void:
	if _fps_label != null:
		_fps_label.visible = show_fps
		if show_fps:
			_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


func _on_settings_changed(settings: Dictionary) -> void:
	# Regenerate the theme so the high-contrast option takes effect immediately.
	var high_contrast: bool = bool(settings.get("high_contrast", false))
	_ui_theme = GameTheme.build(high_contrast)
	if _hud_theme_root != null:
		_hud_theme_root.theme = _ui_theme
	_update_ambient_bounds()
	if _pause_menu != null:
		_pause_menu.set_ui_theme(_ui_theme)
	if _settings_menu != null:
		_settings_menu.set_ui_theme(_ui_theme)
	if _credits != null:
		_credits.set_ui_theme(_ui_theme)
	_apply_show_fps(bool(settings.get("show_fps", false)))


func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if _pause_menu != null:
		_pause_menu.set_paused(paused)
	SignalBus.pause_toggled.emit(paused)


func _on_save_requested() -> void:
	var saved: bool = SaveManager.save_game()
	if _pause_menu != null:
		_pause_menu.set_status("Saved." if saved else "Save failed.")


func _on_settings_requested() -> void:
	if _pause_menu != null:
		_pause_menu.set_status("")
	if _settings_menu != null:
		_settings_menu.set_shown(true)


func _on_settings_closed() -> void:
	# Returning from settings inside gameplay should surface the pause menu again.
	if get_tree().paused and _pause_menu != null:
		_pause_menu.set_paused(true)


func _on_credits_requested() -> void:
	if _pause_menu != null:
		_pause_menu.set_status("")
	if _credits != null:
		_credits.set_shown(true)


func _on_credits_closed() -> void:
	if get_tree().paused and _pause_menu != null:
		_pause_menu.set_paused(true)


func _on_quit_requested() -> void:
	SaveManager.save_game()
	get_tree().quit()


func _build_hud_root() -> void:
	var ui_layer: CanvasLayer = CanvasLayer.new()
	ui_layer.name = "HUDRoot"
	ui_layer.layer = UI_LAYER
	add_child(ui_layer)

	var root_margin: MarginContainer = MarginContainer.new()
	root_margin.name = "HUDRootMargin"
	root_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_margin.add_theme_constant_override("margin_left", SCREEN_MARGIN)
	root_margin.add_theme_constant_override("margin_top", SCREEN_MARGIN)
	root_margin.add_theme_constant_override("margin_right", SCREEN_MARGIN)
	root_margin.add_theme_constant_override("margin_bottom", SCREEN_MARGIN)
	root_margin.theme = _ui_theme
	ui_layer.add_child(root_margin)
	_hud_theme_root = root_margin

	var root_box: VBoxContainer = VBoxContainer.new()
	root_box.name = "HUDRootBox"
	root_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_theme_constant_override("separation", PANEL_GAP)
	root_margin.add_child(root_box)

	_tabs = TabContainer.new()
	_tabs.name = "HUDTabs"
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.clip_contents = true
	root_box.add_child(_tabs)

	_build_overview_tab()
	_build_quests_tab()
	_build_upgrades_tab()
	_build_equipment_tab()
	_build_inventory_tab()


func _build_overview_tab() -> void:
	var overview_screen: Control = Control.new()
	overview_screen.name = "Overview"
	overview_screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	overview_screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(overview_screen)

	_overview_wide_row = HBoxContainer.new()
	_overview_wide_row.name = "WideLayout"
	_overview_wide_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overview_wide_row.add_theme_constant_override("separation", PANEL_GAP)
	overview_screen.add_child(_overview_wide_row)

	_overview_wide_zone_host = VBoxContainer.new()
	_overview_wide_zone_host.name = "ZoneHost"
	_overview_wide_zone_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overview_wide_zone_host.add_theme_constant_override("separation", PANEL_GAP)
	_overview_wide_row.add_child(_overview_wide_zone_host)

	_overview_wide_sidebar = VBoxContainer.new()
	_overview_wide_sidebar.name = "Sidebar"
	_overview_wide_sidebar.add_theme_constant_override("separation", PANEL_GAP)
	_overview_wide_row.add_child(_overview_wide_sidebar)

	_overview_narrow_column = VBoxContainer.new()
	_overview_narrow_column.name = "NarrowLayout"
	_overview_narrow_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overview_narrow_column.add_theme_constant_override("separation", PANEL_GAP)
	overview_screen.add_child(_overview_narrow_column)


func _build_quests_tab() -> void:
	# A MarginContainer tab keeps the tab's title ("Quests") independent of the
	# mounted panel's own node name while still stretching the panel to fill.
	_quests_host = MarginContainer.new()
	_quests_host.name = "Quests"
	_tabs.add_child(_quests_host)


func _build_upgrades_tab() -> void:
	_upgrades_host = MarginContainer.new()
	_upgrades_host.name = "Upgrades"
	_tabs.add_child(_upgrades_host)


func _build_equipment_tab() -> void:
	_equipment_host = CenterContainer.new()
	_equipment_host.name = "Equipment"
	_equipment_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equipment_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_equipment_host)


func _build_inventory_tab() -> void:
	_inventory_host = CenterContainer.new()
	_inventory_host.name = "Inventory"
	_inventory_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inventory_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_child(_inventory_host)


func _instantiate_panels() -> void:
	_hud_panel = _instantiate_panel(HUD_SCENE)
	_zone_panel = _instantiate_panel(ZONE_SCENE)
	_stats_panel = _instantiate_panel(STATS_SCENE)
	_quest_panel = _instantiate_panel(QUEST_SCENE)
	_upgrade_panel = _instantiate_panel(UPGRADE_SCENE)
	_equipment_panel = _instantiate_panel(EQUIPMENT_SCENE)
	_inventory_panel = _instantiate_panel(INVENTORY_SCENE)


func _assign_static_panels() -> void:
	_place_panel(_quest_panel, _quests_host)
	_place_panel(_upgrade_panel, _upgrades_host)
	_place_panel(_equipment_panel, _equipment_host)
	_place_panel(_inventory_panel, _inventory_host)


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
		push_error("Main: '%s' root is not a Control and cannot be mounted in the HUD." % scene_path)
		instance.queue_free()
		return null

	return instance as Control


func _on_viewport_resized() -> void:
	_refresh_overview_layout()
	_update_ambient_bounds()


func _refresh_overview_layout() -> void:
	if _tabs == null:
		return

	var viewport: Viewport = get_viewport()
	if viewport == null:
		return

	var available_size: Vector2 = viewport.get_visible_rect().size - Vector2(float(SCREEN_MARGIN * 2), float(SCREEN_MARGIN * 2))
	var use_wide_layout: bool = (
		available_size.x >= WIDE_LAYOUT_MIN_WIDTH
		and available_size.y >= WIDE_LAYOUT_MIN_HEIGHT
		and available_size.x > available_size.y
	)

	_overview_wide_row.visible = use_wide_layout
	_overview_narrow_column.visible = not use_wide_layout

	if use_wide_layout:
		_place_panel(_zone_panel, _overview_wide_zone_host)
		_place_panel(_hud_panel, _overview_wide_sidebar)
		_place_panel(_stats_panel, _overview_wide_sidebar)
	else:
		_place_panel(_hud_panel, _overview_narrow_column)
		_place_panel(_stats_panel, _overview_narrow_column)
		_place_panel(_zone_panel, _overview_narrow_column)


func _place_panel(panel: Control, target: Node) -> void:
	if panel == null or target == null:
		return
	if panel.get_parent() == target:
		return

	var current_parent: Node = panel.get_parent()
	if current_parent != null:
		current_parent.remove_child(panel)
	target.add_child(panel)
