extends PanelContainer
## Equipment panel: builds all thirteen equipment slots and keeps them in sync
## with the global equipment state purely through `SignalBus.equipment_updated`.
##
## The slots are laid out in a `GridContainer` whose column count adapts to the
## viewport: three columns when there is room, two on narrow (portrait) screens,
## so the full grid always fits without scrolling.

## Minimum logical viewport width that comfortably fits a three-column grid.
const THREE_COLUMN_MIN_WIDTH: float = 560.0

@onready var _grid: GridContainer = %EquipmentList

var _slots: Array[EquipmentSlotUI] = []


func _ready() -> void:
	SignalBus.equipment_updated.connect(_on_equipment_updated)
	_build_slots()

	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_columns):
		viewport.size_changed.connect(_update_columns)
	if not resized.is_connected(_update_columns):
		resized.connect(_update_columns)
	_update_columns()


## Builds one slot widget per `EquipmentManager` slot instance, so the UI and the
## gameplay state can never drift out of sync about how many slots exist.
func _build_slots() -> void:
	for i: int in EquipmentManager.SLOT_NAMES.size():
		var slot: EquipmentSlotUI = EquipmentSlotUI.new()
		slot.slot_name = EquipmentManager.SLOT_NAMES[i]
		slot.slot_label = EquipmentManager.SLOT_LABELS[i]
		_grid.add_child(slot)
		_slots.append(slot)


## Picks the column count that keeps the grid inside the current viewport.
func _update_columns() -> void:
	if _grid == null:
		return
	var viewport_width: float = get_viewport_rect().size.x
	_grid.columns = 3 if viewport_width >= THREE_COLUMN_MIN_WIDTH else 2


## Refreshes the slot that changed. Every slot reads its state from
## `EquipmentManager`, so only the affected slot needs to be updated.
func _on_equipment_updated(slot_name: String, _item_data: ItemData) -> void:
	for slot: EquipmentSlotUI in _slots:
		if slot.slot_name == slot_name:
			slot.refresh()
			return
