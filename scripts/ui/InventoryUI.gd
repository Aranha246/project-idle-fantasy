extends PanelContainer
## Inventory panel: builds a fixed grid of item slots and refreshes it whenever
## the global `SignalBus.inventory_updated` signal fires.

## Preferred maximum number of columns; more than this starts to look like a
## spreadsheet rather than an inventory. Kept high enough that the 48-slot grid
## stays short (fewer rows) and therefore fits 844x390 without scrolling.
const MAX_COLUMNS: int = 10
## Never go below this many columns so the grid stays usable on tiny screens.
const MIN_COLUMNS: int = 4
const GRID_SEPARATION: int = 6

@onready var _grid: GridContainer = %InventoryGrid
@onready var _sort_button: Button = %SortButton

var _slots: Array[InventorySlotUI] = []


func _ready() -> void:
	SignalBus.inventory_updated.connect(_on_inventory_updated)
	SignalBus.slot_updated.connect(_on_slot_updated)
	SignalBus.inventory_reorganized.connect(_on_inventory_reorganized)
	
	_sort_button.pressed.connect(_on_sort_pressed)
	
	_build_slots()

	var viewport: Viewport = get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_update_columns):
		viewport.size_changed.connect(_update_columns)
	if not resized.is_connected(_update_columns):
		resized.connect(_update_columns)
	_update_columns()

	_refresh_slots()


## Chooses the column count so the whole grid fits the current viewport. Uses the
## widest layout that still fits the available width, which also minimises the
## number of rows (and therefore the height).
func _update_columns() -> void:
	if _grid == null:
		return
	var viewport_width: float = get_viewport_rect().size.x
	var slot_size: float = InventorySlotUI.SLOT_SIZE
	# Reserve room for the 16 px screen margins on both sides plus panel padding.
	var available_width: float = viewport_width - 64.0
	var fitting_columns: int = int(floor((available_width + float(GRID_SEPARATION)) / (slot_size + float(GRID_SEPARATION))))
	_grid.columns = clampi(fitting_columns, MIN_COLUMNS, MAX_COLUMNS)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_S:
			_on_sort_pressed()


## Builds one widget per inventory capacity slot, read from `InventoryManager`
## so the UI always matches the real storage size (expanded to 48).
func _build_slots() -> void:
	for _i: int in InventoryManager.MAX_CAPACITY:
		var slot: InventorySlotUI = InventorySlotUI.new()
		_grid.add_child(slot)
		_slots.append(slot)


func _on_inventory_updated() -> void:
	_refresh_slots()


func _on_slot_updated(index: int) -> void:
	if index >= 0 and index < _slots.size():
		var slots: Array[InventorySlot] = InventoryManager.get_slots()
		if index < slots.size():
			_slots[index].set_item_slot(slots[index])


func _on_inventory_reorganized() -> void:
	_refresh_slots()


func _on_sort_pressed() -> void:
	if is_instance_valid(InventoryManager):
		InventoryManager.sort_inventory(true)


func _refresh_slots() -> void:
	var slots: Array[InventorySlot] = InventoryManager.get_slots()
	for i: int in _slots.size():
		var slot_data: InventorySlot = null
		if i < slots.size():
			slot_data = slots[i]
		_slots[i].set_item_slot(slot_data)
