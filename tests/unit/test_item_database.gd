extends GutTest
## Tests for ItemDatabase static helpers: star IDs, affix rolling, crafting probabilities.


# ── make_star_id / parse_star_id round-trip ──────────────────────────────────

func test_base_id_no_stars_returns_base() -> void:
	var id := ItemDatabase.make_star_id(&"wood", 0)
	assert_eq(id, &"wood", "0-star with no affixes should return base id")


func test_make_star_id_with_stars() -> void:
	var id := ItemDatabase.make_star_id(&"stone_sword", 3)
	assert_eq(id, &"stone_sword:3", "Should produce base:stars format")


func test_roundtrip_base_only() -> void:
	var parsed := ItemDatabase.parse_star_id(&"wood")
	assert_eq(parsed["base_id"], &"wood")
	assert_eq(parsed["stars"], 0)
	assert_true((parsed["affixes"] as Array).is_empty())


func test_roundtrip_with_stars() -> void:
	var id := ItemDatabase.make_star_id(&"bronze_sword", 4)
	var parsed := ItemDatabase.parse_star_id(id)
	assert_eq(parsed["base_id"], &"bronze_sword")
	assert_eq(parsed["stars"], 4)


func test_roundtrip_with_affixes() -> void:
	var affixes: Array[StringName] = [&"lifesteal", &"windfury"]
	var rolls := {&"lifesteal": 75, &"windfury": 50}
	var id := ItemDatabase.make_star_id(&"iron_sword", 3, affixes, rolls)
	var parsed := ItemDatabase.parse_star_id(id)
	assert_eq(parsed["base_id"], &"iron_sword")
	assert_eq(parsed["stars"], 3)
	var parsed_affixes: Array = parsed["affixes"]
	assert_eq(parsed_affixes.size(), 2)
	assert_has(parsed_affixes, &"lifesteal")
	assert_has(parsed_affixes, &"windfury")


func test_parse_strips_instance_suffix() -> void:
	var id := ItemDatabase.make_star_id(&"stone_sword", 2)
	var instanced := StringName(str(id) + "#3")
	var parsed := ItemDatabase.parse_star_id(instanced)
	assert_eq(parsed["base_id"], &"stone_sword")
	assert_eq(parsed["stars"], 2)


func test_strip_instance_suffix_no_hash() -> void:
	assert_eq(ItemDatabase.strip_instance_suffix(&"wood"), &"wood")


func test_strip_instance_suffix_with_hash() -> void:
	assert_eq(ItemDatabase.strip_instance_suffix(&"stone_sword:3#2"), &"stone_sword:3")


# ── Affix rolling ────────────────────────────────────────────────────────────

func test_roll_affixes_zero_stars_returns_empty() -> void:
	var result := ItemDatabase.roll_affixes(0, "sword")
	assert_eq(result.size(), 0)


func test_roll_affixes_one_star_returns_empty() -> void:
	var result := ItemDatabase.roll_affixes(1, "sword")
	assert_eq(result.size(), 0)


func test_roll_affixes_two_stars_returns_one() -> void:
	var result := ItemDatabase.roll_affixes(2, "sword")
	assert_eq(result.size(), 1)


func test_roll_affixes_three_stars_returns_two() -> void:
	var result := ItemDatabase.roll_affixes(3, "sword")
	assert_eq(result.size(), 2)


func test_roll_affixes_four_stars_returns_three() -> void:
	var result := ItemDatabase.roll_affixes(4, "sword")
	assert_eq(result.size(), 3)


func test_roll_affixes_five_stars_returns_five() -> void:
	var result := ItemDatabase.roll_affixes(5, "sword")
	assert_eq(result.size(), 5)


func test_roll_affixes_unknown_slot_returns_empty() -> void:
	var result := ItemDatabase.roll_affixes(5, "nonexistent_slot")
	assert_eq(result.size(), 0)


func test_roll_affixes_no_duplicates() -> void:
	for _i in 20:
		var result := ItemDatabase.roll_affixes(5, "sword")
		var unique := {}
		for a in result:
			assert_false(unique.has(a), "Rolled duplicate affix: %s" % a)
			unique[a] = true


func test_rolled_affixes_match_slot() -> void:
	var result := ItemDatabase.roll_affixes(3, "axe")
	for affix_id in result:
		var data: Dictionary = ItemDatabase.AFFIXES[affix_id]
		assert_eq(data["slot"], "axe", "Affix %s should be an axe affix" % affix_id)


# ── Affix values ─────────────────────────────────────────────────────────────

func test_get_affix_value_min_roll() -> void:
	var val := ItemDatabase.get_affix_value(&"lifesteal", 0.0)
	assert_almost_eq(val, 0.06, 0.001)


func test_get_affix_value_max_roll() -> void:
	var val := ItemDatabase.get_affix_value(&"lifesteal", 1.0)
	assert_almost_eq(val, 0.10, 0.001)


func test_get_affix_value_mid_roll() -> void:
	var val := ItemDatabase.get_affix_value(&"lifesteal", 0.5)
	assert_almost_eq(val, 0.08, 0.001)


func test_get_affix_value_no_min_max_returns_fallback() -> void:
	var val := ItemDatabase.get_affix_value(&"cleaving", 0.5)
	assert_eq(val, -1.0)


func test_roll_affix_magnitudes_returns_all_keys() -> void:
	var affixes: Array[StringName] = [&"lifesteal", &"windfury", &"firebrand"]
	var rolls := ItemDatabase.roll_affix_magnitudes(affixes)
	assert_eq(rolls.size(), 3)
	assert_true(rolls.has(&"lifesteal"))
	assert_true(rolls.has(&"windfury"))
	assert_true(rolls.has(&"firebrand"))


func test_roll_affix_magnitudes_values_in_range() -> void:
	var affixes: Array[StringName] = [&"lifesteal"]
	for _i in 50:
		var rolls := ItemDatabase.roll_affix_magnitudes(affixes)
		var val: int = int(rolls[&"lifesteal"])
		assert_true(val >= 0 and val <= 100, "Roll should be 0-100, got %d" % val)


# ── Star rarity ──────────────────────────────────────────────────────────────

func test_star_weights_sum_to_one() -> void:
	var total := 0.0
	for w in ItemDatabase.STAR_WEIGHTS:
		total += w
	assert_almost_eq(total, 1.0, 0.001)


func test_roll_star_level_returns_valid_range() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for _i in 100:
		var star := ItemDatabase.roll_star_level(rng)
		assert_true(star >= 0 and star <= 5, "Star should be 0-5, got %d" % star)


func test_roll_star_level_zero_is_most_common() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var counts := [0, 0, 0, 0, 0, 0]
	for _i in 10000:
		counts[ItemDatabase.roll_star_level(rng)] += 1
	assert_true(counts[0] > counts[1], "0-star should be more common than 1-star")
	assert_true(counts[1] > counts[2], "1-star should be more common than 2-star")


# ── Rarity helpers ───────────────────────────────────────────────────────────

func test_get_rarity_color_valid() -> void:
	assert_eq(ItemDatabase.get_rarity_color(0), ItemDatabase.RARITY_COLORS[0])
	assert_eq(ItemDatabase.get_rarity_color(5), ItemDatabase.RARITY_COLORS[5])


func test_get_rarity_color_out_of_range() -> void:
	assert_eq(ItemDatabase.get_rarity_color(-1), ItemDatabase.RARITY_COLORS[0])
	assert_eq(ItemDatabase.get_rarity_color(99), ItemDatabase.RARITY_COLORS[0])


func test_get_rarity_name_valid() -> void:
	assert_eq(ItemDatabase.get_rarity_name(0), "Common")
	assert_eq(ItemDatabase.get_rarity_name(3), "Epic")
	assert_eq(ItemDatabase.get_rarity_name(5), "Mythical")


func test_get_rarity_name_out_of_range() -> void:
	assert_eq(ItemDatabase.get_rarity_name(-1), "Common")


# ── Crafting probabilities ───────────────────────────────────────────────────

func test_crafting_probabilities_sum_to_one() -> void:
	for avg in [0.0, 1.0, 2.5, 3.0, 4.5, 5.0]:
		var probs := ItemDatabase.get_crafting_probabilities(avg)
		var total := 0.0
		for p in probs:
			total += p
		assert_almost_eq(total, 1.0, 0.001, "Probs should sum to 1.0 for avg=%.1f" % avg)


func test_crafting_probabilities_length_is_six() -> void:
	var probs := ItemDatabase.get_crafting_probabilities(2.0)
	assert_eq(probs.size(), 6)


func test_crafting_probabilities_peak_near_avg() -> void:
	var probs := ItemDatabase.get_crafting_probabilities(2.0)
	assert_true(probs[2] > probs[0], "Star 2 should be more probable than star 0 at avg=2.0")
	assert_true(probs[2] > probs[4], "Star 2 should be more probable than star 4 at avg=2.0")


func test_crafting_probabilities_all_non_negative() -> void:
	for avg in [0.0, 0.5, 1.0, 2.0, 3.0, 4.0, 5.0]:
		var probs := ItemDatabase.get_crafting_probabilities(avg)
		for p in probs:
			assert_true(p >= 0.0, "Probability should be non-negative at avg=%.1f" % avg)


func test_roll_crafting_star_in_range() -> void:
	for _i in 100:
		var star := ItemDatabase.roll_crafting_star(2.5)
		assert_true(star >= 0 and star <= 5, "Crafted star should be 0-5, got %d" % star)


# ── format_affix_description ─────────────────────────────────────────────────

func test_format_affix_with_fmt() -> void:
	var desc := ItemDatabase.format_affix_description(&"lifesteal", 0.5)
	assert_true(desc.length() > 0, "Description should not be empty")
	assert_true("8" in desc, "Mid-roll lifesteal should show ~8%%")


func test_format_affix_without_fmt_returns_static_description() -> void:
	var desc := ItemDatabase.format_affix_description(&"cleaving", 0.5)
	assert_eq(desc, "Melee attacks hit in a wider arc")


# ── get_affix_pool ───────────────────────────────────────────────────────────

func test_affix_pool_only_returns_matching_slot() -> void:
	var pool := ItemDatabase._get_affix_pool("chest")
	assert_true(pool.size() > 0, "Chest pool should not be empty")
	for affix_id in pool:
		assert_eq(ItemDatabase.AFFIXES[affix_id]["slot"], "chest")
