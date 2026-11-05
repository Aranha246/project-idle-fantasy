class_name GameTheme
extends RefCounted
## Central UI theme builder.
##
## Produces a single, cohesive `Theme` for every control in the game so panels,
## buttons and tabs share one visual language instead of each scene inventing its
## own colours. A high-contrast variant (larger fonts, maximum-contrast borders
## and colours) is generated for the accessibility option.
##
## Geometry is deliberately conservative: the tab and button padding stays close
## to the engine defaults so the no-scroll layout guarantees are preserved.

## Full-screen backdrop painted behind every panel.
const BACKGROUND_COLOR: Color = Color(0.054902, 0.050980, 0.086275, 1.0)

## Colour of the ambient motes drifting in the background.
const AMBIENT_COLOR: Color = Color(0.623529, 0.482353, 0.921569, 0.35)

const BG_PANEL: Color = Color(0.090196, 0.090196, 0.121569, 0.92)
const BORDER: Color = Color(0.301961, 0.278431, 0.352941, 1.0)
const ACCENT: Color = Color(0.623529, 0.482353, 0.921569, 1.0)
const TEXT: Color = Color(0.921569, 0.929412, 0.960784, 1.0)

const BG_PANEL_HC: Color = Color(0.0, 0.0, 0.0, 0.98)
const BORDER_HC: Color = Color(1.0, 1.0, 1.0, 1.0)
const ACCENT_HC: Color = Color(1.0, 0.843137, 0.2, 1.0)
const TEXT_HC: Color = Color(1.0, 1.0, 1.0, 1.0)

## Rarity tints, used wherever the UI colour-codes a rarity (slot borders,
## tooltips). The order mirrors `ItemData.Rarity`
## (COMMON, UNCOMMON, RARE, EPIC, LEGENDARY).
const RARITY_COLORS: Array[Color] = [
	Color(0.741176, 0.760784, 0.803922, 1.0),
	Color(0.435294, 0.803922, 0.462745, 1.0),
	Color(0.352941, 0.658824, 0.921569, 1.0),
	Color(0.729412, 0.435294, 0.921569, 1.0),
	Color(1.0, 0.647059, 0.176471, 1.0),
]

## Directory holding the authored item icon sprites.
const ITEM_ICON_DIR: String = "res://assets/sprites/items/"

## Icon file stem per equipment category, indexed by `ItemData.EquipmentSlot`.
## Non-equippable items resolve to the consumable or material sprite instead.
const SLOT_ICON_FILES: Array[String] = [
	"helmet",
	"trinket",
	"amulet",
	"weapon",
	"off_hand",
	"body_armor",
	"ring",
	"necklace",
	"belt",
	"gloves",
	"boots",
	"artifact",
]
const CONSUMABLE_ICON_FILE: String = "consumable"
const MATERIAL_ICON_FILE: String = "material"

const BASE_FONT_SIZE: int = 16
const HIGH_CONTRAST_FONT_SIZE: int = 18

## Cache keyed by icon file stem so each sprite is only loaded once per session.
static var _item_icon_cache: Dictionary = {}

const CORNER_RADIUS: int = 6
const PANEL_MARGIN: float = 10.0
const BUTTON_PADDING_H: float = 14.0
const BUTTON_PADDING_V: float = 8.0
const TAB_PADDING_H: float = 14.0
const TAB_PADDING_V: float = 5.0


## Builds the theme. Pass `true` for the accessibility high-contrast variant.
static func build(high_contrast: bool = false) -> Theme:
	var text_color: Color = TEXT_HC if high_contrast else TEXT
	var border_color: Color = BORDER_HC if high_contrast else BORDER
	var panel_color: Color = BG_PANEL_HC if high_contrast else BG_PANEL
	var accent_color: Color = ACCENT_HC if high_contrast else ACCENT
	var font_size: int = HIGH_CONTRAST_FONT_SIZE if high_contrast else BASE_FONT_SIZE

	var theme: Theme = Theme.new()
	theme.default_font_size = font_size

	theme.set_color("font_color", "Label", text_color)
	theme.set_color("font_color", "Button", text_color)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_pressed_color", "Button", Color.WHITE)
	theme.set_color("font_focus_color", "Button", Color.WHITE)
	theme.set_color("font_color", "CheckBox", text_color)
	theme.set_color("font_color", "CheckButton", text_color)
	theme.set_color("font_color", "OptionButton", text_color)

	theme.set_stylebox("panel", "PanelContainer", _panel_style(panel_color, border_color))
	theme.set_stylebox("panel", "Panel", _panel_style(panel_color, border_color))

	theme.set_stylebox("normal", "Button", _button_style(panel_color, border_color))
	theme.set_stylebox("hover", "Button", _button_style(panel_color.lightened(0.12), accent_color))
	theme.set_stylebox("pressed", "Button", _button_style(panel_color.darkened(0.2), accent_color))
	theme.set_stylebox("disabled", "Button", _button_style(panel_color.darkened(0.3), border_color.darkened(0.5)))
	theme.set_stylebox("focus", "Button", _focus_style(accent_color))

	theme.set_stylebox("normal", "OptionButton", _button_style(panel_color, border_color))
	theme.set_stylebox("hover", "OptionButton", _button_style(panel_color.lightened(0.12), accent_color))
	theme.set_stylebox("pressed", "OptionButton", _button_style(panel_color.darkened(0.2), accent_color))
	theme.set_stylebox("focus", "OptionButton", _focus_style(accent_color))

	# Tabs intentionally keep tight vertical padding so the HUD panel row keeps
	# fitting short viewports without scrolling.
	theme.set_stylebox("tab_selected", "TabContainer", _tab_style(panel_color, accent_color, true))
	theme.set_stylebox("tab_unselected", "TabContainer", _tab_style(panel_color, border_color, false))
	theme.set_stylebox("tab_hovered", "TabContainer", _tab_style(panel_color.lightened(0.1), accent_color, false))
	theme.set_color("font_selected_color", "TabContainer", Color.WHITE)
	theme.set_color("font_unselected_color", "TabContainer", text_color)
	theme.set_color("font_hovered_color", "TabContainer", Color.WHITE)

	theme.set_stylebox("background", "ProgressBar", _flat_style(panel_color.darkened(0.3), border_color))
	theme.set_stylebox("fill", "ProgressBar", _flat_style(accent_color, accent_color))

	theme.set_stylebox("slider", "HSlider", _flat_style(panel_color.darkened(0.3), border_color))
	theme.set_stylebox("grabber_area", "HSlider", _flat_style(accent_color, accent_color))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _flat_style(accent_color.lightened(0.2), accent_color))

	return theme


static func _panel_style(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = _flat_style(background, border)
	style.content_margin_left = PANEL_MARGIN
	style.content_margin_top = PANEL_MARGIN
	style.content_margin_right = PANEL_MARGIN
	style.content_margin_bottom = PANEL_MARGIN
	return style


static func _button_style(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = _flat_style(background, border)
	style.content_margin_left = BUTTON_PADDING_H
	style.content_margin_top = BUTTON_PADDING_V
	style.content_margin_right = BUTTON_PADDING_H
	style.content_margin_bottom = BUTTON_PADDING_V
	return style


static func _focus_style(accent: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = _flat_style(Color(0.0, 0.0, 0.0, 0.0), accent)
	return style


static func _tab_style(background: Color, border: Color, selected: bool) -> StyleBoxFlat:
	var style: StyleBoxFlat = _flat_style(background, border)
	style.content_margin_left = TAB_PADDING_H
	style.content_margin_top = TAB_PADDING_V
	style.content_margin_right = TAB_PADDING_H
	style.content_margin_bottom = TAB_PADDING_V
	if selected:
		style.set_border_width_all(2)
	return style


static func _flat_style(background: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.set_border_width_all(2)
	style.border_color = border
	style.set_corner_radius_all(CORNER_RADIUS)
	return style


## Returns the tint for a rarity index, clamped so an out-of-range value still
## yields a valid colour.
static func rarity_color(rarity_index: int) -> Color:
	return RARITY_COLORS[clampi(rarity_index, 0, RARITY_COLORS.size() - 1)]


## Resolves the authored icon file stem an item uses: equippable items map
## through `SLOT_ICON_FILES` by category, everything else falls back to the
## consumable or material sprite.
static func icon_file_stem(item: ItemData) -> String:
	if item != null and ItemData.is_valid_equipment_slot(item.equipment_slot):
		return SLOT_ICON_FILES[int(item.equipment_slot)]
	if item != null and item.item_type == ItemData.ItemType.CONSUMABLE:
		return CONSUMABLE_ICON_FILE
	return MATERIAL_ICON_FILE


## Loads (and caches) the authored icon sprite for an item, keyed by its icon
## file stem so each PNG is read from disk at most once per session. Used as the
## fallback art for items that ship no `item_icon`, so runtime generated loot
## reads as authored art instead of the engine placeholder. Returns `null` when
## the sprite is missing so callers degrade gracefully instead of crashing.
static func build_item_icon(item: ItemData) -> Texture2D:
	var stem: String = icon_file_stem(item)
	if _item_icon_cache.has(stem):
		return _item_icon_cache[stem] as Texture2D
	var path: String = ITEM_ICON_DIR + stem + ".png"
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	else:
		push_warning("GameTheme: missing item icon sprite '%s'" % path)
	_item_icon_cache[stem] = texture
	return texture
