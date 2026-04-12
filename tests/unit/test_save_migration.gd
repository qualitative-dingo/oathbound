extends GutTest
## Tests for SaveManager migration helpers: item ID migration, affix replacement.

var save_mgr: Node


func before_each() -> void:
	save_mgr = load("res://scripts/autoloads/save_manager.gd").new()
	add_child_autofree(save_mgr)


# ── _strip_position_from_player ──────────────────────────────────────────────

func test_strip_position_removes_pos_and_rot() -> void:
	var data := {
		"position": {"x": 10, "y": 20, "z": 30},
		"rotation_y": 1.5,
		"health": 80.0,
		"stamina": 50.0,
	}
	var result: Dictionary = save_mgr._strip_position_from_player(data)
	assert_false(result.has("position"))
	assert_false(result.has("rotation_y"))
	assert_true(result.has("health"))
	assert_true(result.has("stamina"))


func test_strip_position_preserves_other_fields() -> void:
	var data := {
		"position": {"x": 1, "y": 2, "z": 3},
		"rotation_y": 0.0,
		"health": 100.0,
		"equipped_weapon": "stone_sword",
		"base_strength": 5,
	}
	var result: Dictionary = save_mgr._strip_position_from_player(data)
	assert_eq(result["health"], 100.0)
	assert_eq(result["equipped_weapon"], "stone_sword")
	assert_eq(result["base_strength"], 5)


func test_strip_position_does_not_modify_original() -> void:
	var data := {"position": {"x": 1, "y": 2, "z": 3}, "rotation_y": 0.0}
	save_mgr._strip_position_from_player(data)
	assert_true(data.has("position"), "Original dict should be unchanged")


# ── _migrate_item_id ─────────────────────────────────────────────────────────

func test_migrate_low_star_returns_unchanged() -> void:
	var result: StringName = save_mgr._migrate_item_id(&"stone_sword:2")
	assert_eq(result, &"stone_sword:2")


func test_migrate_material_returns_unchanged() -> void:
	var result: StringName = save_mgr._migrate_item_id(&"wood")
	assert_eq(result, &"wood")


func test_migrate_high_star_no_affixes_adds_affixes() -> void:
	# 3-star weapon with no affixes should get affixes added
	var result: StringName = save_mgr._migrate_item_id(&"stone_sword:3")
	var parsed := ItemDatabase.parse_star_id(result)
	assert_eq(parsed["base_id"], &"stone_sword")
	assert_eq(parsed["stars"], 3)
	assert_true((parsed["affixes"] as Array).size() > 0, "Should have gained affixes")


func test_migrate_already_has_affixes_returns_unchanged() -> void:
	var affixes: Array[StringName] = [&"lifesteal"]
	var rolls := {&"lifesteal": 50}
	var id := ItemDatabase.make_star_id(&"iron_sword", 3, affixes, rolls)
	var result: StringName = save_mgr._migrate_item_id(id)
	assert_eq(result, id, "Item with existing affixes should not be re-rolled")


# ── _migrate_replaced_affixes ────────────────────────────────────────────────

func test_migrate_replaced_affix_piercing_to_bouncing_shot() -> void:
	var affixes: Array[StringName] = [&"piercing"]
	var rolls := {&"piercing": 75}
	var id := ItemDatabase.make_star_id(&"crude_bow", 3, affixes, rolls)
	var result: StringName = save_mgr._migrate_replaced_affixes(id)
	var parsed := ItemDatabase.parse_star_id(result)
	var parsed_affixes: Array = parsed["affixes"]
	assert_false(parsed_affixes.has(&"piercing"), "Old affix should be replaced")
	assert_true(parsed_affixes.has(&"bouncing_shot"), "Should have replacement affix")


func test_migrate_no_replaced_affix_returns_unchanged() -> void:
	var affixes: Array[StringName] = [&"lifesteal"]
	var rolls := {&"lifesteal": 50}
	var id := ItemDatabase.make_star_id(&"iron_sword", 3, affixes, rolls)
	var result: StringName = save_mgr._migrate_replaced_affixes(id)
	assert_eq(result, id)


func test_migrate_no_affixes_returns_unchanged() -> void:
	var result: StringName = save_mgr._migrate_replaced_affixes(&"wood")
	assert_eq(result, &"wood")


# ── _deserialize_inventory ───────────────────────────────────────────────────

func test_deserialize_inventory_basic() -> void:
	var data := {
		"items": {"wood": 50, "stone": 30},
		"order": ["wood", "stone"],
		"equipped": {"weapon": "starting_axe"},
	}
	save_mgr._deserialize_inventory(data)
	assert_eq(Inventory.get_amount(&"wood"), 50)
	assert_eq(Inventory.get_amount(&"stone"), 30)
	assert_eq(Inventory.get_equipped("weapon"), &"starting_axe")


func test_deserialize_inventory_empty_noop() -> void:
	Inventory.add_item(&"wood", 10)
	save_mgr._deserialize_inventory({})
	assert_eq(Inventory.get_amount(&"wood"), 10, "Empty dict should be a no-op")


func test_deserialize_inventory_legacy_format() -> void:
	# Old format: flat dict without "items" wrapper
	var data := {"wood": 25, "stone": 10}
	save_mgr._deserialize_inventory(data)
	assert_eq(Inventory.get_amount(&"wood"), 25)
	assert_eq(Inventory.get_amount(&"stone"), 10)


func test_deserialize_inventory_restores_order() -> void:
	var data := {
		"items": {"stone": 5, "wood": 10},
		"order": ["stone", "wood"],
	}
	save_mgr._deserialize_inventory(data)
	var order := Inventory.get_order()
	assert_eq(order[0], &"stone")
	assert_eq(order[1], &"wood")


func test_deserialize_inventory_missing_order_entry_still_added() -> void:
	var data := {
		"items": {"wood": 5, "stone": 3},
		"order": ["wood"],
	}
	save_mgr._deserialize_inventory(data)
	assert_eq(Inventory.get_amount(&"stone"), 3, "Stone should still be in inventory")
	assert_true(Inventory.get_order().has(&"stone"), "Stone should appear in order")
