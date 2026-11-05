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
	_test_upgrades()
	_test_quest_is_player_driven()
	await _test_quest_claim_grants_rewards()
	await _test_quest_claim_drops_equipment()
	_test_progression_pacing()
	_test_save_persistence()
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


# --- UI wiring (player agency end to end) -----------------------------------

func _test_main_ui_wiring() -> void:
	var main_scene: PackedScene = load(MAIN_SCENE) as PackedScene
	_assert(main_scene != null, "the main scene loads for the UI suite")
	if main_scene == null:
		return

	var main: Node = main_scene.instantiate()
	get_tree().root.add_child(main)
	await _settle()

	_assert(_collect_scroll_containers(main).is_empty(), "the redesigned HUD has no scrolling containers")

	var tabs: TabContainer = _find_tab_container(main)
	_assert(tabs != null, "the HUD is built from a tab container")
	if tabs == null:
		main.queue_free()
		return
	_assert(tabs.get_tab_count() == 5, "the HUD exposes five tabs")

	var has_quests: bool = false
	var has_upgrades: bool = false
	for i: int in tabs.get_tab_count():
		var title: String = tabs.get_tab_title(i)
		if title == "Quests":
			has_quests = true
		elif title == "Upgrades":
			has_upgrades = true
	_assert(has_quests, "the quest board has its own tab")
	_assert(has_upgrades, "the upgrade shop has its own tab")

	var hero: HeroArt = _find_first(main, "HeroArt") as HeroArt
	_assert(hero != null, "the animated hero artwork is mounted in the quest board")
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
	_assert(not QuestManager.is_quest_running(), "loading the HUD never starts a quest on its own")

	var quest_button: Button = _first_quest_button(main)
	_assert(quest_button != null, "the quest board lists startable quests")
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

	# The upgrade shop spends currency from the UI.
	CurrencyManager.load_state({"copper": 0, "silver": 0, "gold": 0})
	CurrencyManager.add_copper(100_000)
	await _settle()
	var buy_button: Button = _first_buy_button(main)
	_assert(buy_button != null, "the upgrade shop lists buyable upgrades")
	if buy_button != null:
		var levels_before: int = _total_upgrade_levels()
		buy_button.pressed.emit()
		await _settle()
		_assert(_total_upgrade_levels() == levels_before + 1, "pressing a buy button purchases an upgrade")

	main.queue_free()
	await _settle()


func _cleanup() -> void:
	get_tree().paused = false
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
