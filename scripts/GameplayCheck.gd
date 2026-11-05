extends Node
## Headless functional / gameplay suite for the quest, loot and upgrade overhaul.
##
## Unlike `ModernizationCheck` (which proves the game *builds* and stays within
## its technical budgets) this suite proves the game *plays*: it drives the real
## managers through a full player session and asserts the observable outcomes.
## Its most important job is as a regression guard for the "no equipment ever
## drops" bug — it forces a guaranteed drop and follows the item from the enemy
## loot table, through `LootRoller`, into the inventory and onto the character.
##
## Follows the same result contract as the other checks: prints
## `RESULT passed=N failed=M` and exits non-zero when anything fails.

const MAIN_SCENE: String = "res://scenes/Main.tscn"
const TEST_SAVE_PATH: String = "user://test_gameplay_save.json"

const ZONE_SCRIPT_PATH: String = "res://scripts/resources/ZoneData.gd"
const ENEMY_SCRIPT_PATH: String = "res://scripts/resources/EnemyData.gd"
const ITEM_SCRIPT_PATH: String = "res://scripts/resources/ItemData.gd"

## The thirteen slot instances, in the order they must be presented.
const EXPECTED_SLOT_NAMES: Array[String] = [
	"HELMET",
	"TRINKET",
	"AMULET",
	"WEAPON",
	"OFF_HAND",
	"BODY_ARMOR",
	"RING_1",
	"RING_2",
	"NECKLACE",
	"BELT",
	"GLOVES",
	"BOOTS",
	"ARTIFACT",
]

## Enough Copper to buy any track to its maximum, so the cost-curve test never
## trips over affordability.
const FUNDING_COPPER: int = 500_000_000

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("Starting gameplay tests...")
	call_deferred("_run")


func _run() -> void:
	_test_loot_roller()
	_test_inventory_capacity()
	_test_equipment_slots()
	_test_equip_gestures()
	_test_upgrades()
	_test_quest_is_player_driven()
	await _test_quest_claim_grants_rewards()
	await _test_quest_claim_drops_equipment()
	_test_progression_pacing()
	_test_save_persistence()
	_test_window_system()
	await _test_main_ui_wiring()
	_cleanup()
	_finish()


# --- Loot -------------------------------------------------------------------

func _test_loot_roller() -> void:
	var zone: Resource = GameDatabase.get_zone(&"whispering_woods")
	_assert(zone != null, "the starting zone is registered")
	if zone == null:
		return
	var slime: Resource = zone.monster_pool[0]
	_assert(slime != null and not slime.loot_table.is_empty(), "the starting enemy has a loot table")
	if slime == null:
		return

	# Regression guard for the drop bug: the table must carry real equipment,
	# not just materials.
	var equipment_entries: int = 0
	for entry: Variant in slime.loot_table:
		var loot: EnemyData.LootEntry = entry as EnemyData.LootEntry
		if loot == null:
			continue
		var item: ItemData = GameDatabase.get_item(loot.item_id)
		if item != null and ItemData.is_valid_equipment_slot(item.equipment_slot):
			equipment_entries += 1
	_assert(equipment_entries >= 3, "the starting enemy's table offers several pieces of equipment")

	# A fully boosted roll must drop every entry, and that set must include gear.
	var guaranteed: Array = LootRoller.roll_from_loot_table(slime.loot_table, 999.0, 1)
	_assert(guaranteed.size() == slime.loot_table.size(), "a fully boosted roll drops every loot-table entry")

	var dropped_equipment: int = 0
	for record: Variant in guaranteed:
		var drop: Dictionary = record
		var item: ItemData = drop.get("item")
		if item != null and ItemData.is_valid_equipment_slot(item.equipment_slot):
			dropped_equipment += 1
	_assert(dropped_equipment > 0, "a boosted roll actually drops equipment")

	_assert(LootRoller.roll_from_loot_table([], 1.0, 1).is_empty(), "an empty loot table drops nothing")
	_assert(LootRoller.roll_from_enemy(null, 1.0, 1).is_empty(), "a null enemy drops nothing")

	# Extra passes re-roll the whole table, which is how richer quests pay out.
	var tripled: Array = LootRoller.roll_from_loot_table(slime.loot_table, 999.0, 3)
	_assert(tripled.size() == slime.loot_table.size() * 3, "extra loot passes re-roll the whole table")

	# Duplicate material rolls collapse into one summed stack.
	var merged: Array = LootRoller.merge_drops(tripled)
	_assert(merged.size() < tripled.size(), "merge_drops combines duplicate drops")
	_assert(LootRoller.total_quantity(tripled) >= tripled.size(), "total_quantity counts every individual item")
	_assert(LootRoller.merge_drops([]).is_empty(), "merging an empty drop list is a no-op")


# --- Inventory --------------------------------------------------------------

func _test_inventory_capacity() -> void:
	InventoryManager.load_state([])
	_assert(InventoryManager.MAX_CAPACITY >= 48, "inventory storage was expanded to at least 48 slots")

	var slots: Array[InventorySlot] = InventoryManager.get_slots()
	_assert(slots.size() == InventoryManager.MAX_CAPACITY, "the inventory allocates its full storage size")

	var gel: ItemData = GameDatabase.get_item(&"slime_gel")
	_assert(gel != null, "a stackable material resolves from the database")
	if gel == null:
		return

	_assert(InventoryManager.add_item(gel, 5), "a stackable material can be stored")
	_assert(InventoryManager.has_item(gel), "the stored material is present")
	_assert(InventoryManager.add_item(gel, 4), "a second stack of the same material merges")
	_assert(InventoryManager.remove_item(gel, 9), "the merged material stack can be removed")
	_assert(not InventoryManager.has_item(gel), "removing the stack empties the slot")

	_assert(not InventoryManager.add_item(null, 1), "adding a null item is rejected")
	_assert(not InventoryManager.add_item(gel, 0), "adding zero items is rejected")

	InventoryManager.load_state([])


# --- Equipment --------------------------------------------------------------

func _test_equipment_slots() -> void:
	_assert(EquipmentManager.SLOT_NAMES.size() == 13, "there are thirteen equipment slot instances")
	_assert(EquipmentManager.SLOT_CATEGORIES.size() == EquipmentManager.SLOT_NAMES.size(), "every slot maps to exactly one category")

	var names_match: bool = true
	for i: int in EXPECTED_SLOT_NAMES.size():
		if EquipmentManager.SLOT_NAMES[i] != EXPECTED_SLOT_NAMES[i]:
			names_match = false
	_assert(names_match, "slots cover helmet, trinket, amulet, weapon, off-hand, armor, two rings, necklace, belt, gloves, boots and artifact")

	# Thirteen instances across twelve categories; the ring category is reused.
	var categories: Dictionary = {}
	for category: int in EquipmentManager.SLOT_CATEGORIES:
		categories[category] = true
	_assert(categories.size() == 12, "the thirteen slots cover twelve equipment categories")
	_assert(EquipmentManager.get_slot_category("RING_1") == ItemData.EquipmentSlot.RING, "the first ring slot accepts rings")
	_assert(EquipmentManager.get_slot_category("RING_2") == ItemData.EquipmentSlot.RING, "the second ring slot accepts rings")

	var sword: ItemData = GameDatabase.get_item(&"iron_sword")
	var shield: ItemData = GameDatabase.get_item(&"wooden_shield")
	var ring: ItemData = GameDatabase.get_item(&"copper_ring")
	_assert(sword != null and shield != null and ring != null, "the catalogue ships a weapon, a shield and a ring")
	if sword == null or shield == null or ring == null:
		return

	# Equip eligibility also requires the item to be held, so put the samples in
	# the bag before asking which slot each one fits.
	EquipmentManager.load_state({})
	InventoryManager.load_state([])
	InventoryManager.add_item(sword, 1)
	InventoryManager.add_item(shield, 1)
	InventoryManager.add_item(ring, 1)

	_assert(EquipmentManager.can_equip_in(sword, "WEAPON"), "a weapon fits the weapon slot")
	_assert(not EquipmentManager.can_equip_in(sword, "OFF_HAND"), "a weapon does not fit the off-hand slot")
	_assert(EquipmentManager.can_equip_in(shield, "OFF_HAND"), "a shield fits the off-hand slot")
	_assert(EquipmentManager.can_equip_in(ring, "RING_1") and EquipmentManager.can_equip_in(ring, "RING_2"), "a ring fits either ring slot")
	_assert(not EquipmentManager.can_equip_in(null, "WEAPON"), "a null item cannot be equipped")
	_assert(not EquipmentManager.can_equip_in(sword, "NOT_A_SLOT"), "an unknown slot rejects every item")

	# Equip / unequip round-trip through the inventory.
	EquipmentManager.load_state({})
	InventoryManager.load_state([])
	_assert(InventoryManager.add_item(sword, 1), "a weapon can be picked up before equipping")
	_assert(EquipmentManager.auto_equip(sword) == "WEAPON", "auto-equip places a weapon in the weapon slot")
	_assert(EquipmentManager.get_equipped("WEAPON") == sword, "the weapon slot now holds the weapon")
	_assert(not InventoryManager.has_item(sword), "equipping removes the item from the bag")
	_assert(EquipmentManager.unequip_item("WEAPON") == sword, "unequipping returns the weapon")
	_assert(EquipmentManager.get_equipped("WEAPON") == null, "the weapon slot is empty again")
	_assert(InventoryManager.has_item(sword), "the unequipped weapon is back in the bag")

	# Two copies of the same ring must land in the two distinct ring slots.
	EquipmentManager.load_state({})
	InventoryManager.load_state([])
	InventoryManager.add_item(ring, 2)
	_assert(EquipmentManager.auto_equip(ring) == "RING_1", "the first ring fills the first ring slot")
	_assert(EquipmentManager.auto_equip(ring) == "RING_2", "the second ring fills the second ring slot")

	# A fresh profile starts with all thirteen slots empty.
	EquipmentManager.load_state({})
	var empty_slots: int = 0
	for equipped: ItemData in EquipmentManager.get_slots():
		if equipped == null:
			empty_slots += 1
	_assert(empty_slots == 13, "a fresh profile starts with thirteen empty equipment slots")

	EquipmentManager.load_state({})
	InventoryManager.load_state([])


# --- Equipping gestures -----------------------------------------------------

## Covers the two equipping gestures from the request: right click and left
## double click equip from the bag, the same gestures unequip from the character
## window, and a rejected equip explains itself through a toast.
func _test_equip_gestures() -> void:
	# Gesture recognition is shared by both slot types.
	_assert(ItemSlotUI.is_equip_gesture(_mouse_event(MOUSE_BUTTON_RIGHT)), "a right click is an equip gesture")
	_assert(
		not ItemSlotUI.is_equip_gesture(_mouse_event(MOUSE_BUTTON_RIGHT, false)),
		"releasing the right button is not an equip gesture"
	)
	_assert(
		ItemSlotUI.is_equip_gesture(_mouse_event(MOUSE_BUTTON_LEFT, true, true)),
		"a left double click is an equip gesture"
	)
	_assert(
		not ItemSlotUI.is_equip_gesture(_mouse_event(MOUSE_BUTTON_LEFT)),
		"a single left click is not an equip gesture, so drag & drop keeps working"
	)

	var toasts: Array = []
	SignalBus.notification_raised.connect(func(message: String, is_error: bool) -> void:
		toasts.append([message, is_error])
	)

	# Right-clicking a bag item equips it straight into its slot.
	EquipmentManager.load_state({})
	InventoryManager.load_state([])
	var sword: ItemData = GameDatabase.get_item(&"iron_sword")
	InventoryManager.add_item(sword, 1)
	var bag_slot: InventorySlotUI = InventorySlotUI.new()
	get_tree().root.add_child(bag_slot)
	bag_slot.item = sword
	bag_slot._gui_input(_mouse_event(MOUSE_BUTTON_RIGHT))
	_assert(EquipmentManager.get_equipped("WEAPON") == sword, "right-clicking a bag item equips it into its slot")
	_assert(not InventoryManager.has_item(sword), "equipping moves the item out of the bag")
	_assert(toasts.is_empty(), "a successful equip raises no error toast")

	# A left double click has exactly the same effect.
	EquipmentManager.load_state({})
	InventoryManager.load_state([])
	InventoryManager.add_item(sword, 1)
	bag_slot.item = sword
	bag_slot._gui_input(_mouse_event(MOUSE_BUTTON_LEFT, true, true))
	_assert(EquipmentManager.get_equipped("WEAPON") == sword, "double-clicking a bag item also equips it")

	# The same gestures unequip from the character window.
	var equipment_slot: EquipmentSlotUI = EquipmentSlotUI.new()
	equipment_slot.slot_name = "WEAPON"
	equipment_slot.slot_label = "Weapon"
	get_tree().root.add_child(equipment_slot)
	equipment_slot.refresh()
	var toasts_before: int = toasts.size()
	equipment_slot._gui_input(_mouse_event(MOUSE_BUTTON_RIGHT))
	_assert(EquipmentManager.get_equipped("WEAPON") == null, "right-clicking an equipped item unequips it")
	_assert(InventoryManager.has_item(sword), "the unequipped item returns to the bag")
	_assert(toasts.size() == toasts_before, "a successful unequip raises no error toast")

	# A rejected equip explains itself instead of failing silently.
	EquipmentManager.load_state({})
	InventoryManager.load_state([])
	var potion: ItemData = GameDatabase.get_item(&"health_potion")
	InventoryManager.add_item(potion, 1)
	bag_slot.item = potion
	bag_slot._gui_input(_mouse_event(MOUSE_BUTTON_LEFT, true, true))
	_assert(EquipmentManager.get_equipped("WEAPON") == null, "a consumable is never equipped")
	_assert(
		toasts.size() == toasts_before + 1 and bool(toasts[toasts.size() - 1][1]),
		"a rejected equip raises an error toast"
	)

	bag_slot.queue_free()
	equipment_slot.queue_free()
	EquipmentManager.load_state({})
	InventoryManager.load_state([])


# --- Upgrades ---------------------------------------------------------------

func _test_upgrades() -> void:
	UpgradeManager.load_state({})
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	StatsManager.set_base_stats({"attack_power": 10.0, "defense": 5.0, "critical_rate": 0.05, "luck": 0.0})

	var tracks: Array[UpgradeData] = UpgradeManager.get_all_upgrades()
	_assert(tracks.size() >= 6, "the upgrade shop offers several tracks")

	var quest_speed: UpgradeData = UpgradeManager.get_upgrade(&"quest_speed")
	_assert(quest_speed != null and quest_speed.validate().is_empty(), "the quest-speed track is valid")
	_assert(is_equal_approx(UpgradeManager.get_quest_duration_multiplier(), 1.0), "quests are not accelerated before any purchase")
	_assert(is_equal_approx(UpgradeManager.get_reward_multiplier(), 1.0), "rewards are not boosted before any purchase")
	_assert(is_equal_approx(UpgradeManager.get_loot_fortune(), 0.0), "loot is not boosted before any purchase")

	var first_cost: int = UpgradeManager.get_next_cost(&"quest_speed")
	_assert(first_cost == quest_speed.base_cost_copper, "the first level costs the base price")
	_assert(not UpgradeManager.can_afford(&"quest_speed"), "an empty wallet cannot afford an upgrade")
	_assert(not UpgradeManager.purchase(&"quest_speed"), "purchasing without funds fails and changes nothing")
	_assert(UpgradeManager.get_level(&"quest_speed") == 0, "a failed purchase leaves the level untouched")

	CurrencyManager.add_copper(FUNDING_COPPER)
	_assert(UpgradeManager.can_afford(&"quest_speed"), "a funded wallet can afford an upgrade")
	var before: int = CurrencyManager.get_total_copper()
	_assert(UpgradeManager.purchase(&"quest_speed"), "a funded purchase succeeds")
	_assert(UpgradeManager.get_level(&"quest_speed") == 1, "the purchase raises the track level")
	_assert(CurrencyManager.get_total_copper() == before - first_cost, "the purchase spends exactly the listed cost")
	_assert(UpgradeManager.get_quest_duration_multiplier() < 1.0, "buying quest speed shortens quest duration")
	_assert(UpgradeManager.get_next_cost(&"quest_speed") > first_cost, "each level costs more than the last")

	_assert(UpgradeManager.purchase(&"reward_multiplier"), "the reward track can be bought")
	_assert(UpgradeManager.get_reward_multiplier() > 1.0, "buying rewards raises the reward multiplier")
	_assert(UpgradeManager.purchase(&"loot_fortune"), "the loot track can be bought")
	_assert(UpgradeManager.get_loot_fortune() > 0.0, "buying loot fortune raises the drop-rate bonus")
	_assert(UpgradeManager.purchase(&"attack_power"), "a flat-stat track can be bought")
	_assert(UpgradeManager.get_stat_bonus("attack_power") > 0.0, "a flat-stat upgrade grants its stat bonus")

	# Maxing a track stops further purchases and clamps its effect.
	var guard: int = 0
	while not UpgradeManager.is_maxed(&"quest_speed") and guard < 200:
		guard += 1
		if not UpgradeManager.purchase(&"quest_speed"):
			break
	_assert(UpgradeManager.is_maxed(&"quest_speed"), "the quest-speed track can be maxed out")
	_assert(UpgradeManager.get_next_cost(&"quest_speed") == -1, "a maxed track reports no next cost")
	_assert(not UpgradeManager.purchase(&"quest_speed"), "a maxed track cannot be purchased again")
	_assert(UpgradeManager.get_quest_duration_multiplier() < 1.0, "a maxed quest-speed track keeps quests faster")
	_assert(UpgradeManager.get_quest_duration_multiplier() >= UpgradeManager.MIN_DURATION_MULTIPLIER, "quest speed never shortens past its safety floor")

	_assert(UpgradeManager.get_upgrade(&"does_not_exist") == null, "an unknown upgrade id resolves to null")
	_assert(UpgradeManager.get_next_cost(&"does_not_exist") == -1, "an unknown upgrade has no cost")

	UpgradeManager.load_state({})
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	StatsManager.set_base_stats({"attack_power": 10.0, "defense": 5.0, "critical_rate": 0.05, "luck": 0.0})


# --- Player-driven quest loop ----------------------------------------------

func _test_quest_is_player_driven() -> void:
	ProgressionManager.load_state({"level": 1, "xp": 0})
	QuestManager.abandon_quest()
	_assert(QuestManager.set_active_zone_by_id(&"whispering_woods"), "a zone can be made active")

	var offers: Array[QuestData] = QuestManager.get_quests()
	_assert(offers.size() >= 3, "the active zone offers battle, explore and gather quests")

	# The core fix: selecting a zone plays nothing. The player must opt in.
	_assert(not QuestManager.is_quest_running(), "no quest runs immediately after selecting a zone")
	_assert(not QuestManager.is_quest_ready(), "no quest is ready to claim before one is started")
	_assert(QuestManager.claim_quest().is_empty(), "claiming with no running quest grants nothing")

	var battle: QuestData = _first_battle_quest()
	_assert(battle != null and battle.enemy != null, "a battle quest is bound to an enemy")
	if battle == null or offers.size() < 2:
		return

	# Arrays are reference values, so the lambda can mutate this captured list.
	var started_events: Array = []
	SignalBus.quest_started.connect(func(_quest: Resource, _duration: float) -> void:
		started_events.append(_duration)
	)

	_assert(QuestManager.start_quest(battle), "the player can explicitly start a quest")
	_assert(QuestManager.is_quest_running(), "the started quest is running")
	_assert(not QuestManager.is_quest_ready(), "a freshly started quest is not instantly complete")
	_assert(QuestManager.get_quest_duration() > 0.0, "a running quest has a positive duration")
	_assert(started_events.size() == 1, "starting a quest is broadcast on SignalBus")

	_assert(not QuestManager.start_quest(offers[offers.size() - 1]), "a second quest cannot start while one is running")

	QuestManager.abandon_quest()
	_assert(not QuestManager.is_quest_running(), "abandoning a quest stops the loop")


func _test_quest_claim_grants_rewards() -> void:
	ProgressionManager.load_state({"level": 1, "xp": 0})
	QuestManager.set_active_zone_by_id(&"whispering_woods")

	var quest: QuestData = _first_battle_quest()
	_assert(quest != null, "a battle quest is available to claim")
	if quest == null:
		return

	var copper_before: int = CurrencyManager.get_total_copper()
	var claim_events: Array = []
	SignalBus.quest_claimed.connect(func(_rewards: Dictionary) -> void:
		claim_events.append(_rewards)
	)

	_assert(QuestManager.start_quest(quest), "the quest starts for the claim test")
	# Fast-forward the *real* timer rather than faking completion.
	QuestManager._elapsed = QuestManager.get_quest_duration()
	await _settle()
	_assert(QuestManager.is_quest_ready(), "the quest becomes ready once its timer elapses")

	var rewards: Dictionary = QuestManager.claim_quest()
	_assert(not rewards.is_empty(), "claiming a ready quest returns its rewards")
	_assert(int(rewards.get("gold", 0)) > 0, "claiming grants a positive currency reward")
	_assert(CurrencyManager.get_total_copper() > copper_before, "the currency reward reaches the wallet")
	_assert(rewards.has("items") and rewards.has("drops"), "the reward summary reports items and loot rolls")
	_assert(claim_events.size() == 1, "claiming is broadcast on SignalBus")
	_assert(not QuestManager.is_quest_running(), "the loop stops after a quest is claimed")
	_assert(QuestManager.claim_quest().is_empty(), "a claimed quest cannot be claimed twice")


## Deterministic proof that equipment now drops: a purpose-built zone whose only
## enemy has a 100%-chance loot entry removes the randomness, so the test asserts
## the *mechanism* (table -> roller -> inventory -> equipment) rather than a
## lucky roll.
func _test_quest_claim_drops_equipment() -> void:
	var test_item: ItemData = load(ITEM_SCRIPT_PATH).new()
	test_item.item_id = &"check_guaranteed_relic"
	test_item.item_name = "Check Relic"
	test_item.item_type = ItemData.ItemType.EQUIPMENT
	test_item.rarity = ItemData.Rarity.RARE
	test_item.equipment_slot = ItemData.EquipmentSlot.ARTIFACT
	test_item.max_stack_size = 1
	GameDatabase.register_item(test_item)

	var entry: EnemyData.LootEntry = EnemyData.LootEntry.new()
	entry.item_id = &"check_guaranteed_relic"
	entry.drop_chance = 1.0
	entry.min_quantity = 1
	entry.max_quantity = 1

	var enemy: Resource = load(ENEMY_SCRIPT_PATH).new()
	enemy.enemy_name = "Check Dummy"
	enemy.base_health = 10
	enemy.spawn_weight = 1.0
	enemy.loot_table = [entry]

	var arena: Resource = load(ZONE_SCRIPT_PATH).new()
	arena.zone_id = &"check_arena"
	arena.zone_name = "Check Arena"
	arena.tier_level = 1
	arena.monster_pool = [enemy]
	GameDatabase.register_zone(arena)

	ProgressionManager.load_state({"level": 60, "xp": 0})
	_assert(QuestManager.set_active_zone(arena), "the deterministic test zone can be activated")

	InventoryManager.load_state([])
	EquipmentManager.load_state({})

	var quest: QuestData = _first_battle_quest()
	_assert(quest != null and quest.enemy == enemy, "the test zone offers a quest for its enemy")
	if quest == null:
		return

	_assert(QuestManager.start_quest(quest), "the drop-test quest starts")
	QuestManager._elapsed = QuestManager.get_quest_duration()
	await _settle()
	_assert(QuestManager.is_quest_ready(), "the drop-test quest becomes ready")

	var rewards: Dictionary = QuestManager.claim_quest()
	var granted: Array = rewards.get("items", [])
	_assert(granted.size() == 1, "the guaranteed equipment drop is granted (regression: equipment now drops)")
	_assert(InventoryManager.has_item(test_item), "the dropped equipment reaches the inventory")

	var equipped_slot: String = EquipmentManager.auto_equip(test_item)
	_assert(equipped_slot == "ARTIFACT", "the dropped equipment can be equipped into its slot")
	_assert(EquipmentManager.get_equipped("ARTIFACT") == test_item, "the equipped relic occupies the artifact slot")

	# Restore a clean world for the remaining suites.
	EquipmentManager.load_state({})
	InventoryManager.load_state([])
	ProgressionManager.load_state({"level": 1, "xp": 0})
	QuestManager.set_active_zone_by_id(&"whispering_woods")


# --- Progression & pacing (gameplay feel) ----------------------------------

## Validates the *feel* of progression rather than a single mechanic: zones are
## gated behind clear level goals, reaching a goal feels like a reward, and
## bought speed upgrades produce a noticeable change in quest pacing.
func _test_progression_pacing() -> void:
	_assert(QuestManager.get_zone_unlock_level(0) == 1, "the starting zone is open from level 1")
	var second_zone: Resource = GameDatabase.get_zone(&"shadow_cave")
	_assert(second_zone != null, "a second zone is authored")
	if second_zone == null:
		return

	var second_unlock: int = QuestManager.get_zone_unlock_level(1)
	_assert(second_unlock > 1, "the second zone requires character levels, giving early goals")

	QuestManager.set_active_zone_by_id(&"whispering_woods")
	ProgressionManager.load_state({"level": second_unlock - 1, "xp": 0})
	_assert(not QuestManager.is_zone_unlocked(second_zone), "the second zone stays locked below its level")
	_assert(not QuestManager.set_active_zone_by_id(&"shadow_cave"), "a locked zone cannot be entered")

	ProgressionManager.load_state({"level": second_unlock, "xp": 0})
	_assert(QuestManager.is_zone_unlocked(second_zone), "levelling up unlocks the next zone")
	_assert(QuestManager.set_active_zone_by_id(&"shadow_cave"), "the unlocked zone can now be entered")

	var quest: QuestData = _first_battle_quest()
	_assert(quest != null, "the unlocked zone offers a quest")
	if quest == null:
		return

	# Buying quest speed must produce a measurable pacing improvement.
	UpgradeManager.load_state({})
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	var base_duration: float = maxf(1.0, quest.base_duration * UpgradeManager.get_quest_duration_multiplier())
	CurrencyManager.add_copper(100_000)
	_assert(UpgradeManager.purchase(&"quest_speed"), "quest speed can be bought for the pacing check")
	var upgraded_duration: float = maxf(1.0, quest.base_duration * UpgradeManager.get_quest_duration_multiplier())
	_assert(upgraded_duration < base_duration, "buying quest speed measurably shortens a quest")

	UpgradeManager.load_state({})
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	ProgressionManager.load_state({"level": 1, "xp": 0})
	QuestManager.set_active_zone_by_id(&"whispering_woods")


# --- Persistence ------------------------------------------------------------

func _test_save_persistence() -> void:
	_assert(SaveManager.SAVE_VERSION >= 2, "the save format version tracks the upgrade payload")

	ProgressionManager.load_state({"level": 3, "xp": 0})
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	CurrencyManager.add_copper(5000)
	UpgradeManager.load_state({"quest_speed": 3, "reward_multiplier": 2})
	InventoryManager.load_state([])
	EquipmentManager.load_state({})

	var sword: ItemData = GameDatabase.get_item(&"iron_sword")
	InventoryManager.add_item(sword, 1)
	_assert(EquipmentManager.auto_equip(sword) == "WEAPON", "an item can be equipped before saving")

	_assert(SaveManager.save_game(TEST_SAVE_PATH), "the game state can be saved")
	_assert(SaveManager.has_save(TEST_SAVE_PATH), "the written save file exists")

	UpgradeManager.load_state({})
	InventoryManager.load_state([])
	EquipmentManager.load_state({})
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})

	_assert(SaveManager.load_game(TEST_SAVE_PATH), "the saved game state can be restored")
	_assert(UpgradeManager.get_level(&"quest_speed") == 3, "purchased upgrade levels survive a save/load round-trip")
	_assert(UpgradeManager.get_level(&"reward_multiplier") == 2, "every upgrade track is persisted")
	_assert(EquipmentManager.get_equipped("WEAPON") != null, "equipped gear survives a save/load round-trip")
	_assert(CurrencyManager.get_total_copper() > 0, "the wallet survives a save/load round-trip")
	var equipment_state: Dictionary = EquipmentManager.get_state()
	_assert(str(equipment_state.get("WEAPON", "")) != "", "the restored state records the equipped weapon")

	_assert(SaveManager.load_game("user://definitely_missing.json") == false, "loading a missing save fails gracefully")
	_assert(SaveManager.delete_save(TEST_SAVE_PATH), "the test save can be deleted")

	UpgradeManager.load_state({})
	InventoryManager.load_state([])
	EquipmentManager.load_state({})
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})


# --- Window system & keybindings --------------------------------------------

## Covers the Path of Exile-style window system: every window ships a default
## shortcut, rebinding applies instantly, conflicts and reserved keys are
## rejected, and the layout survives a simulated client restart.
func _test_window_system() -> void:
	var window_ids: Array[StringName] = WindowRegistry.get_window_ids()
	_assert(window_ids.size() >= 5, "the registry authors several floating windows")

	var defaults: Dictionary = WindowRegistry.get_default_bindings()
	_assert(defaults.size() == window_ids.size(), "every window ships a default keybinding")
	_assert(int(defaults[WindowRegistry.CHARACTER_ID]) == int(KEY_C), "the character window defaults to C")
	_assert(SettingsManager.keybindings.size() == window_ids.size(), "the live bindings cover every window")

	# --- rebinding applies immediately, with no restart ---------------------
	var conflict: StringName = SettingsManager.set_keybinding(WindowRegistry.STATS_ID, int(KEY_K))
	_assert(conflict == &"", "a free key rebinds without a conflict")
	_assert(int(SettingsManager.keybindings[WindowRegistry.STATS_ID]) == int(KEY_K), "the rebind is stored")
	_assert(
		_action_uses_key(InputActions.window_action(WindowRegistry.STATS_ID), KEY_K),
		"the rebind reaches the input map without a restart"
	)

	# --- conflict detection -------------------------------------------------
	conflict = SettingsManager.set_keybinding(WindowRegistry.STATS_ID, int(KEY_J))
	_assert(conflict == WindowRegistry.QUESTS_ID, "a key owned by another window is rejected and names the owner")
	_assert(int(SettingsManager.keybindings[WindowRegistry.STATS_ID]) == int(KEY_K), "a rejected rebind changes nothing")

	# --- the pause key stays reserved --------------------------------------
	conflict = SettingsManager.set_keybinding(WindowRegistry.STATS_ID, int(KEY_ESCAPE))
	_assert(conflict == WindowRegistry.RESERVED_BINDING, "the pause key cannot be assigned to a window")

	# --- reset to defaults --------------------------------------------------
	SettingsManager.reset_keybindings()
	_assert(int(SettingsManager.keybindings[WindowRegistry.STATS_ID]) == int(KEY_P), "resetting restores the default binding")
	_assert(
		_action_uses_key(InputActions.window_action(WindowRegistry.STATS_ID), KEY_P),
		"the reset reaches the input map without a restart"
	)

	# --- window visibility is broadcast on SignalBus ------------------------
	WindowManager.reset_to_defaults()
	var visibility_events: Array = []
	SignalBus.window_visibility_changed.connect(
		func(window_id: StringName, is_open: bool) -> void:
			visibility_events.append([window_id, is_open])
	)
	_assert(WindowManager.is_open(WindowRegistry.CHARACTER_ID), "the character window opens by default")
	WindowManager.toggle_window(WindowRegistry.CHARACTER_ID)
	_assert(not WindowManager.is_open(WindowRegistry.CHARACTER_ID), "toggling closes an open window")
	_assert(
		visibility_events.size() == 1 and visibility_events[0][0] == WindowRegistry.CHARACTER_ID,
		"a window toggle is broadcast on SignalBus"
	)
	WindowManager.toggle_window(WindowRegistry.CHARACTER_ID)
	_assert(WindowManager.is_open(WindowRegistry.CHARACTER_ID), "toggling again reopens the window")

	# --- persistence survives a simulated restart ---------------------------
	WindowManager.set_open(WindowRegistry.QUESTS_ID, true)
	WindowManager.set_open(WindowRegistry.STATS_ID, false)
	SettingsManager.set_window_position(WindowRegistry.QUESTS_ID, Vector2(210.0, 130.0))
	SettingsManager.set_window_minimized(WindowRegistry.QUESTS_ID, true)
	SettingsManager.set_window_maximized(WindowRegistry.UPGRADES_ID, true)

	# Corrupt the runtime state, then reload the file and resync exactly as a
	# fresh client boot would, proving the file is the source of truth.
	WindowManager._open[WindowRegistry.QUESTS_ID] = false
	WindowManager._open[WindowRegistry.STATS_ID] = true
	WindowManager._open[WindowRegistry.UPGRADES_ID] = false
	SettingsManager.load_settings()
	WindowManager.sync_from_settings()

	_assert(WindowManager.is_open(WindowRegistry.QUESTS_ID), "a window open at exit reopens on the next launch")
	_assert(not WindowManager.is_open(WindowRegistry.STATS_ID), "a window closed at exit stays closed on the next launch")
	var restored: Dictionary = SettingsManager.get_window_layout(WindowRegistry.QUESTS_ID)
	_assert(restored.get("position", Vector2.ZERO) == Vector2(210.0, 130.0), "the window position survives a restart")
	_assert(bool(restored.get("minimized", false)), "the minimized state survives a restart")
	_assert(
		bool(SettingsManager.get_window_layout(WindowRegistry.UPGRADES_ID).get("maximized", false)),
		"the maximized state survives a restart"
	)
	_assert(FileAccess.file_exists(SettingsManager.SETTINGS_PATH), "the window layout is written to the settings file")

	# --- a layout that hides every window is repaired -----------------------
	# Every window can be closed by hand, and closing the Character window is
	# enough to reach that state because it is the only one open out of the box.
	# Restoring it verbatim would boot the game onto an empty work area that
	# looks exactly like the interface failing to render, so the boot path has
	# to refuse it.
	for window_id: StringName in WindowRegistry.get_window_ids():
		WindowManager.set_open(window_id, false)
	_assert(WindowManager.get_open_window_ids().is_empty(), "every window can be closed by hand")
	SettingsManager.load_settings()
	WindowManager.sync_from_settings()
	_assert(
		WindowManager.is_open(WindowRegistry.CHARACTER_ID),
		"booting from an all-closed layout reopens the authored default window"
	)
	_assert(
		SettingsManager.get_window_layout(WindowRegistry.QUESTS_ID).get("position", Vector2.ZERO) == Vector2(210.0, 130.0),
		"repairing an all-closed layout leaves the other windows untouched"
	)

	# Leave the authored defaults in place for the remaining suites.
	WindowManager.reset_to_defaults()
	SettingsManager.reset_to_defaults()


# --- UI wiring (player agency end to end) -----------------------------------

func _test_main_ui_wiring() -> void:
	var main_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_assert(main_scene != null, "the main scene loads for the UI suite")
	if main_scene == null:
		return

	var main: Node = main_scene.instantiate()
	get_tree().root.add_child(main)
	await _settle()

	var menu_bar: MenuBarUI = main.get_node_or_null("HUDRoot/HUDRootMargin/HUDRootBox/MenuBar") as MenuBarUI
	var window_host: WindowHostUI = main.get_node_or_null("HUDRoot/HUDRootMargin/HUDRootBox/WindowHost") as WindowHostUI
	_assert(menu_bar != null, "the persistent menu bar is mounted")
	_assert(window_host != null, "the floating window host is mounted")
	if menu_bar == null or window_host == null:
		main.queue_free()
		await _settle()
		return

	# The persistent chrome must never scroll; only window bodies may.
	_assert(_collect_scroll_containers(menu_bar).is_empty(), "the menu bar has no scrolling containers")
	var status_bar: Control = main.get_node_or_null("HUDRoot/HUDRootMargin/HUDRootBox/StatusBar") as Control
	_assert(
		status_bar != null and _collect_scroll_containers(status_bar).is_empty(),
		"the status bar has no scrolling containers"
	)

	# Every authored floating window is mounted and listed in the menu bar. The
	# settings entry is the exception: it opens the existing modal overlay.
	var floating_ids: Array[StringName] = []
	for window_id: StringName in WindowRegistry.get_window_ids():
		if window_id != WindowRegistry.SETTINGS_ID:
			floating_ids.append(window_id)
	var mounted: int = 0
	var listed: int = 0
	for window_id: StringName in floating_ids:
		if window_host.get_game_window(window_id) != null:
			mounted += 1
		if menu_bar.get_toggle(window_id) != null:
			listed += 1
	_assert(mounted == floating_ids.size(), "the window host mounts every floating window")
	_assert(listed == floating_ids.size(), "the menu bar lists every floating window")
	_assert(menu_bar.get_toggle(WindowRegistry.SETTINGS_ID) != null, "the menu bar also lists the settings window")

	# The unified Character window carries the equipment slots and the bag.
	var character: GameWindow = window_host.get_game_window(WindowRegistry.CHARACTER_ID)
	_assert(character != null, "the unified character window is mounted")
	if character != null:
		_assert(_find_first(character, "EquipmentList") != null, "the character window shows the equipment slots")
		_assert(_find_first(character, "InventoryGrid") != null, "the character window shows the inventory grid")

	# Quests live in their own window; open it so the board lays out.
	WindowManager.set_open(WindowRegistry.QUESTS_ID, true)
	await _settle()
	_assert(WindowManager.is_open(WindowRegistry.QUESTS_ID), "the quest window can be opened")

	var hero: HeroArt = _find_first(main, "HeroArt") as HeroArt
	_assert(hero != null, "the animated hero artwork is mounted in the quest window")
	_assert(hero != null and hero.get_frame_count() > 0, "the hero sprite frames load from the shipped art")

	# Every authored hero frame must ship, because the hero art no longer has a
	# procedural fallback to draw when a frame is missing.
	var missing_hero_frames: Array[String] = []
	for pose_index: int in HeroArt.POSE_FILES.size():
		for frame_index: int in HeroArt.POSE_FRAME_COUNTS[pose_index]:
			var frame_path: String = "%s%s_%d.png" % [HeroArt.SPRITE_DIR, HeroArt.POSE_FILES[pose_index], frame_index]
			if not ResourceLoader.exists(frame_path):
				missing_hero_frames.append(frame_path)
	_assert(missing_hero_frames.is_empty(), "every hero sprite frame ships with the project (missing: %s)" % ", ".join(missing_hero_frames))

	# Player agency: only a click on the quest board starts a quest.
	ProgressionManager.load_state({"level": 1, "xp": 0})
	UpgradeManager.load_state({})
	QuestManager.abandon_quest()
	QuestManager.set_active_zone_by_id(&"whispering_woods")
	await _settle()
	_assert(not QuestManager.is_quest_running(), "loading the windows never starts a quest on its own")

	var quest_button: Button = _first_quest_button(main)
	_assert(quest_button != null, "the quest window lists startable quests")
	if quest_button != null:
		quest_button.pressed.emit()
		await _settle()
		_assert(QuestManager.is_quest_running(), "pressing a quest button starts that quest")
		_assert(hero != null and hero.get_pose() != HeroArt.Pose.IDLE, "the hero animates into the quest's pose")

		var action_button: Button = _find_first(main, "QuestActionButton") as Button
		_assert(action_button != null, "the quest board has a claim/cancel action button")
		if action_button != null:
			action_button.pressed.emit()
			await _settle()
			_assert(not QuestManager.is_quest_running(), "the action button can cancel a running quest")

	# The upgrade shop spends currency from its own window.
	WindowManager.set_open(WindowRegistry.UPGRADES_ID, true)
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	CurrencyManager.add_copper(100_000)
	await _settle()
	var buy_button: Button = _first_buy_button(main)
	_assert(buy_button != null, "the upgrade window lists buyable upgrades")
	if buy_button != null:
		var levels_before: int = _total_upgrade_levels()
		buy_button.pressed.emit()
		await _settle()
		_assert(_total_upgrade_levels() == levels_before + 1, "pressing a buy button purchases an upgrade")

	main.queue_free()
	await _settle()
	WindowManager.reset_to_defaults()


func _cleanup() -> void:
	get_tree().paused = false
	WindowManager.reset_to_defaults()
	SettingsManager.reset_to_defaults()
	QuestManager.abandon_quest()
	QuestManager.set_active_zone_by_id(&"whispering_woods")
	UpgradeManager.load_state({})
	InventoryManager.load_state([])
	EquipmentManager.load_state({})
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	ProgressionManager.load_state({"level": 1, "xp": 0})
	SaveManager.delete_save(TEST_SAVE_PATH)


# --- Helpers ----------------------------------------------------------------

func _first_battle_quest() -> QuestData:
	for quest: QuestData in QuestManager.get_quests():
		if quest.quest_type == QuestData.QuestType.BATTLE:
			return quest
	return null


func _total_upgrade_levels() -> int:
	var total: int = 0
	for upgrade: UpgradeData in UpgradeManager.get_all_upgrades():
		total += UpgradeManager.get_level(upgrade.upgrade_id)
	return total


func _settle() -> void:
	for _i: int in 4:
		await get_tree().process_frame


func _first_quest_button(root_node: Node) -> Button:
	var list: Node = _find_first(root_node, "QuestList")
	if list == null:
		return null
	for child: Node in list.get_children():
		var button: Button = child as Button
		if button != null:
			return button
	return null


func _first_buy_button(root_node: Node) -> Button:
	for node: Node in _collect_nodes(root_node):
		var button: Button = node as Button
		if button != null and button.text.begins_with("Buy"):
			return button
	return null


func _find_first(root_node: Node, node_name: String) -> Node:
	for node: Node in _collect_nodes(root_node):
		if node.name == node_name:
			return node
	return null


## Builds a synthetic mouse-button event for the equipping-gesture checks.
func _mouse_event(button: MouseButton, pressed: bool = true, double_click: bool = false) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.double_click = double_click
	return event


## Whether the `InputMap` action currently carries a keyboard binding for `keycode`.
func _action_uses_key(action: StringName, keycode: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event: InputEvent in InputMap.action_get_events(action):
		var key_event: InputEventKey = event as InputEventKey
		if key_event != null and key_event.physical_keycode == keycode:
			return true
	return false


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
