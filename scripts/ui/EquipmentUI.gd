extends PanelContainer
## Equipment panel: builds the three equipment slots and keeps them in sync with
## the global equipment state purely through `SignalBus.equipment_updated`.

## Canonical slot names understood by `EquipmentManager`, in display order.
const SLOT_NAMES: Array[String] = ["WEAPON", "ARMOR", "ACCESSORY"]

## Human readable labels shown next to each slot.
const SLOT_LABELS: Array[String] = ["Weapon", "Armor", "Accessory"]

@onready var _list: VBoxContainer = %EquipmentList

var _slots: Array[EquipmentSlotUI] = []


func _ready() -> void:
	SignalBus.equipment_updated.connect(_on_equipment_updated)
	_build_slots()


func _build_slots() -> void:
	for i: int in SLOT_NAMES.size():
		var slot: EquipmentSlotUI = EquipmentSlotUI.new()
		slot.slot_name = SLOT_NAMES[i]
		slot.slot_label = SLOT_LABELS[i]
		_list.add_child(slot)
		_slots.append(slot)


## Refreshes the slot that changed. Every slot reads its state from
## `EquipmentManager`, so only the affected slot needs to be updated.
func _on_equipment_updated(slot_name: String, _item_data: ItemData) -> void:
	for slot: EquipmentSlotUI in _slots:
		if slot.slot_name == slot_name:
			slot.refresh()
			return
