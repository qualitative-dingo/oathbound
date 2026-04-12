extends GutTest
## Tests for PlayerInventory: stacking, equipment, slot operations.

var inv: PlayerInventory


func before_each() -> void:
	inv = PlayerInventory.new()


# ── Add / Remove basics ─────────────────────────────────────────────────────

func test_add_material_stacks() -> void:
	inv.add_item(&"wood", 10)
	assert_eq(inv.get_amount(&"wood"), 10)
	inv.add_item(&"wood", 5)
	assert_eq(inv.get_amount(&"wood"), 15)


func test_remove_item_success() -> void:
	inv.add_item(&"stone", 20)
	var ok := inv.remove_item(&"stone", 5)
	assert_true(ok)
	assert_eq(inv.get_amount(&"stone"), 15)


func test_remove_item_insufficient() -> void:
	inv.add_item(&"stone", 3)
	var ok := inv.remove_item(&"stone", 10)
	assert_false(ok)
	assert_eq(inv.get_amount(&"stone"), 3)


func test_remove_all_erases_slot() -> void:
	inv.add_item(&"wood", 5)
	inv.remove_item(&"wood", 5)
	assert_false(inv.has_item(&"wood"))
	assert_eq(inv.get_amount(&"wood"), 0)


func test_remove_nonexistent_item() -> void:
	assert_false(inv.remove_item(&"nonexistent", 1))


func test_has_item() -> void:
	inv.add_item(&"wood", 5)
	assert_true(inv.has_item(&"wood", 1))
	assert_true(inv.has_item(&"wood", 5))
	assert_false(inv.has_item(&"wood", 6))


# ── Gear gets unique IDs ────────────────────────────────────────────────────

func test_gear_gets_unique_ids() -> void:
	inv.add_item(&"stone_sword", 1)
	inv.add_item(&"stone_sword", 1)
	var items := inv.get_all_items()
	assert_true(items.has(&"stone_sword"), "First gear should keep base id")
	assert_true(items.has(&"stone_sword#2"), "Second gear should get #2 suffix")


func test_gear_each_has_quantity_one() -> void:
	inv.add_item(&"stone_sword", 3)
	var items := inv.get_all_items()
	for key: StringName in items.keys():
		if str(key).begins_with("stone_sword"):
			assert_eq(int(items[key]), 1)


# ── Order ────────────────────────────────────────────────────────────────────

func test_order_tracks_addition() -> void:
	inv.add_item(&"wood", 5)
	inv.add_item(&"stone", 3)
	var order := inv.get_order()
	assert_eq(order[0], &"wood")
	assert_eq(order[1], &"stone")


func test_swap_slots() -> void:
	inv.add_item(&"wood", 5)
	inv.add_item(&"stone", 3)
	inv.swap_slots(0, 1)
	var order := inv.get_order()
	assert_eq(order[0], &"stone")
	assert_eq(order[1], &"wood")


func test_swap_to_empty_slot() -> void:
	inv.add_item(&"wood", 5)
	inv.swap_slots(0, 5)
	var order := inv.get_order()
	assert_eq(order[5], &"wood")


func test_swap_same_index_noop() -> void:
	inv.add_item(&"wood", 5)
	inv.swap_slots(0, 0)
	assert_eq(inv.get_order()[0], &"wood")


func test_swap_invalid_from_index() -> void:
	inv.add_item(&"wood", 5)
	inv.swap_slots(-1, 0)
	assert_eq(inv.get_order()[0], &"wood")


# ── Equipment ────────────────────────────────────────────────────────────────

func test_equip_armor() -> void:
	inv.add_item(&"leather_vest", 1)
	inv.equip_armor(&"leather_vest")
	assert_eq(inv.get_equipped("chest"), &"leather_vest")
	assert_false(inv.has_item(&"leather_vest"))


func test_unequip_armor() -> void:
	inv.add_item(&"leather_vest", 1)
	inv.equip_armor(&"leather_vest")
	inv.unequip_armor("chest")
	assert_eq(inv.get_equipped("chest"), &"")
	assert_true(inv.has_item(&"leather_vest"))


func test_equip_replaces_previous() -> void:
	inv.add_item(&"leather_vest", 1)
	inv.add_item(&"chain_chest", 1)
	inv.equip_armor(&"leather_vest")
	inv.equip_armor(&"chain_chest")
	assert_eq(inv.get_equipped("chest"), &"chain_chest")
	assert_true(inv.has_item(&"leather_vest"), "Old armor should return to inventory")
	assert_false(inv.has_item(&"chain_chest"), "New armor should be removed from inventory")


func test_is_equipped() -> void:
	inv.add_item(&"leather_vest", 1)
	inv.equip_armor(&"leather_vest")
	assert_true(inv.is_equipped(&"leather_vest"))
	assert_false(inv.is_equipped(&"stone_sword"))


func test_unequip_empty_slot_noop() -> void:
	inv.unequip_armor("chest")
	assert_eq(inv.get_equipped("chest"), &"")


# ── Star-aware queries ───────────────────────────────────────────────────────

func test_get_amount_any_star() -> void:
	inv.add_item(&"wood", 10)
	inv.add_item(&"wood:2", 5)
	inv.add_item(&"wood:4", 3)
	assert_eq(inv.get_amount_any_star(&"wood"), 18)


func test_has_item_any_star() -> void:
	inv.add_item(&"wood:3", 5)
	assert_true(inv.has_item_any_star(&"wood", 5))
	assert_false(inv.has_item_any_star(&"wood", 6))


func test_get_amount_capped_star() -> void:
	inv.add_item(&"wood", 10)
	inv.add_item(&"wood:1", 5)
	inv.add_item(&"wood:3", 3)
	assert_eq(inv.get_amount_capped_star(&"wood", 2, 0), 15)


func test_remove_item_any_star() -> void:
	inv.add_item(&"wood", 10)
	inv.add_item(&"wood:2", 5)
	var ok := inv.remove_item_any_star(&"wood", 12)
	assert_true(ok)
	assert_eq(inv.get_amount_any_star(&"wood"), 3)


func test_remove_item_any_star_insufficient() -> void:
	inv.add_item(&"wood", 5)
	assert_false(inv.remove_item_any_star(&"wood", 10))
	assert_eq(inv.get_amount(&"wood"), 5)


# ── Capped star consume with preference ──────────────────────────────────────

func test_preview_consume_capped_star_prefer_high() -> void:
	inv.add_item(&"wood", 10)
	inv.add_item(&"wood:3", 5)
	var preview := inv.preview_consume_capped_star(&"wood", 7, 5, 0, false)
	assert_true(preview.has(3), "Should take from star 3 first when prefer_low=false")


func test_preview_consume_capped_star_prefer_low() -> void:
	inv.add_item(&"wood", 10)
	inv.add_item(&"wood:3", 5)
	var preview := inv.preview_consume_capped_star(&"wood", 7, 5, 0, true)
	assert_true(preview.has(0), "Should take from star 0 first when prefer_low=true")


# ── Total armor ──────────────────────────────────────────────────────────────

func test_get_total_armor_empty() -> void:
	assert_almost_eq(inv.get_total_armor(), 0.0, 0.01)


func test_get_total_armor_with_equipment() -> void:
	inv.add_item(&"leather_vest", 1)
	inv.equip_armor(&"leather_vest")
	var armor := inv.get_total_armor()
	assert_true(armor > 0.0, "Equipped leather vest should give armor > 0")


# ── Grouped item list ────────────────────────────────────────────────────────

func test_grouped_item_list_materials_merge() -> void:
	inv.add_item(&"wood", 10)
	inv.add_item(&"wood:2", 5)
	var groups := inv.get_grouped_item_list()
	var wood_group: Dictionary = {}
	for g in groups:
		if g["base_id"] == &"wood":
			wood_group = g
			break
	assert_false(wood_group.is_empty(), "Should find a wood group")
	assert_eq(wood_group["total"], 15)
	assert_true(wood_group["is_grouped"])


func test_grouped_item_list_gear_stays_separate() -> void:
	inv.add_item(&"stone_sword", 1)
	inv.add_item(&"stone_sword", 1)
	var groups := inv.get_grouped_item_list()
	var sword_groups := 0
	for g in groups:
		if g["base_id"] == &"stone_sword":
			sword_groups += 1
	assert_eq(sword_groups, 2, "Each gear piece should be its own group entry")


# ── Clear ────────────────────────────────────────────────────────────────────

func test_clear_empties_everything() -> void:
	inv.add_item(&"wood", 50)
	inv.add_item(&"stone_sword", 1)
	inv.equip_armor(&"stone_sword")
	inv.clear()
	assert_eq(inv.get_all_items().size(), 0)
	assert_eq(inv.get_order().size(), 0)
	assert_eq(inv.get_all_equipped().size(), 0)


# ── Give starting gear ───────────────────────────────────────────────────────

func test_give_starting_gear() -> void:
	inv.give_starting_gear()
	assert_eq(inv.get_equipped("weapon"), &"starting_axe")
	assert_eq(inv.get_equipped("sword"), &"starting_sword")
	assert_eq(inv.get_equipped("bow"), &"starting_bow")
	assert_eq(inv.get_equipped("chest"), &"starting_chest")
