extends GutTest
## Tests for DamageSystem: damage resolution, armor, resistances, stagger.

var ds: DamageSystem


func before_each() -> void:
	ds = DamageSystem.new()
	ds.max_health = 100.0
	ds.base_armor = 0.0
	ds.stagger_threshold_fraction = 0.3
	ds.stagger_duration = 1.5
	ds.stagger_reset_time = 3.0
	ds._ready()
	add_child_autofree(ds)


# ── Basic damage ─────────────────────────────────────────────────────────────

func test_basic_damage_no_armor() -> void:
	var result := ds.take_hit(25.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 25.0, 0.01)
	assert_almost_eq(ds.current_health, 75.0, 0.01)


func test_damage_reduces_health() -> void:
	ds.take_hit(10.0, &"slash", 1.0, 0.0, null)
	ds.take_hit(15.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(ds.current_health, 75.0, 0.01)


# ── Armor ────────────────────────────────────────────────────────────────────

func test_armor_reduces_damage() -> void:
	ds.base_armor = 10.0
	var result := ds.take_hit(25.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 15.0, 0.01)


func test_armor_minimum_one_damage() -> void:
	ds.base_armor = 1000.0
	var result := ds.take_hit(5.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 1.0, 0.01)


func test_armor_does_not_apply_when_immune() -> void:
	ds.base_armor = 5.0
	ds.resistances[&"fire"] = DamageSystem.Resistance.IMMUNE
	var result := ds.take_hit(50.0, &"fire", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 0.0, 0.01)


# ── Resistances ──────────────────────────────────────────────────────────────

func test_resistance_immune() -> void:
	ds.resistances[&"fire"] = DamageSystem.Resistance.IMMUNE
	var result := ds.take_hit(50.0, &"fire", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 0.0, 0.01)
	assert_almost_eq(ds.current_health, 100.0, 0.01)


func test_resistance_very_resistant() -> void:
	ds.resistances[&"frost"] = DamageSystem.Resistance.VERY_RESISTANT
	var result := ds.take_hit(40.0, &"frost", 1.0, 0.0, null)
	# 40 * 0.25 = 10, no armor, so 10
	assert_almost_eq(float(result["dealt"]), 10.0, 0.01)


func test_resistance_resistant() -> void:
	ds.resistances[&"poison"] = DamageSystem.Resistance.RESISTANT
	var result := ds.take_hit(40.0, &"poison", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 20.0, 0.01)


func test_resistance_weak() -> void:
	ds.resistances[&"lightning"] = DamageSystem.Resistance.WEAK
	var result := ds.take_hit(20.0, &"lightning", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 30.0, 0.01)


func test_resistance_very_weak() -> void:
	ds.resistances[&"spirit"] = DamageSystem.Resistance.VERY_WEAK
	var result := ds.take_hit(20.0, &"spirit", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 40.0, 0.01)


func test_resistance_normal_default() -> void:
	var result := ds.take_hit(30.0, &"unknown_type", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 30.0, 0.01)


func test_resistance_multiplier_constants() -> void:
	assert_eq(DamageSystem.RESISTANCE_MULTIPLIERS[DamageSystem.Resistance.IMMUNE], 0.0)
	assert_eq(DamageSystem.RESISTANCE_MULTIPLIERS[DamageSystem.Resistance.VERY_RESISTANT], 0.25)
	assert_eq(DamageSystem.RESISTANCE_MULTIPLIERS[DamageSystem.Resistance.RESISTANT], 0.5)
	assert_eq(DamageSystem.RESISTANCE_MULTIPLIERS[DamageSystem.Resistance.NORMAL], 1.0)
	assert_eq(DamageSystem.RESISTANCE_MULTIPLIERS[DamageSystem.Resistance.WEAK], 1.5)
	assert_eq(DamageSystem.RESISTANCE_MULTIPLIERS[DamageSystem.Resistance.VERY_WEAK], 2.0)


# ── Armor + Resistance combined ──────────────────────────────────────────────

func test_armor_plus_resistance() -> void:
	ds.base_armor = 5.0
	ds.resistances[&"slash"] = DamageSystem.Resistance.RESISTANT
	# 20 * 0.5 = 10, minus 5 armor = 5
	var result := ds.take_hit(20.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 5.0, 0.01)


func test_armor_plus_resistance_floor_at_one() -> void:
	ds.base_armor = 50.0
	ds.resistances[&"slash"] = DamageSystem.Resistance.RESISTANT
	# 20 * 0.5 = 10, minus 50 armor -> min 1
	var result := ds.take_hit(20.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 1.0, 0.01)


# ── Invulnerability (dodge) ──────────────────────────────────────────────────

func test_dodge_iframes_block_all_damage() -> void:
	ds.is_invulnerable = true
	var result := ds.take_hit(50.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 0.0, 0.01)
	assert_true(result.get("dodged", false))
	assert_almost_eq(ds.current_health, 100.0, 0.01)


# ── Parry ────────────────────────────────────────────────────────────────────

func test_parry_blocks_all_damage() -> void:
	ds.is_parry_window_active = true
	var result := ds.take_hit(80.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 0.0, 0.01)
	assert_true(result.get("parried", false))
	assert_almost_eq(ds.current_health, 100.0, 0.01)


# ── Stagger ──────────────────────────────────────────────────────────────────

func test_stagger_triggers_at_threshold() -> void:
	# threshold = 100 * 0.3 = 30. Hit for 30 with stagger_mult=1.0 -> accumulator=30
	ds.take_hit(30.0, &"blunt", 1.0, 0.0, null)
	assert_true(ds.is_staggered)


func test_stagger_does_not_trigger_below_threshold() -> void:
	ds.take_hit(29.0, &"blunt", 1.0, 0.0, null)
	assert_false(ds.is_staggered)


func test_stagger_doubles_damage() -> void:
	ds.is_staggered = true
	var result := ds.take_hit(20.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 40.0, 0.01)


func test_stagger_multiplier_scales_accumulation() -> void:
	# threshold = 30, hit for 20 with stagger_mult=2.0 -> accumulator=40 -> triggers
	ds.take_hit(20.0, &"blunt", 2.0, 0.0, null)
	assert_true(ds.is_staggered)


# ── Death ────────────────────────────────────────────────────────────────────

func test_death_at_zero_health() -> void:
	ds.take_hit(100.0, &"slash", 1.0, 0.0, null)
	assert_true(ds.is_dead)
	assert_almost_eq(ds.current_health, 0.0, 0.01)


func test_overkill_clamps_to_zero() -> void:
	ds.take_hit(500.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(ds.current_health, 0.0, 0.01)
	assert_true(ds.is_dead)


func test_dead_entity_takes_no_damage() -> void:
	ds.take_hit(100.0, &"slash", 1.0, 0.0, null)
	var result := ds.take_hit(50.0, &"slash", 1.0, 0.0, null)
	assert_almost_eq(float(result["dealt"]), 0.0, 0.01)
	assert_true(result.get("blocked", false))


# ── Healing ──────────────────────────────────────────────────────────────────

func test_heal_restores_health() -> void:
	ds.take_hit(40.0, &"slash", 1.0, 0.0, null)
	ds.heal(20.0)
	assert_almost_eq(ds.current_health, 80.0, 0.01)


func test_heal_does_not_exceed_max() -> void:
	ds.take_hit(10.0, &"slash", 1.0, 0.0, null)
	ds.heal(999.0)
	assert_almost_eq(ds.current_health, 100.0, 0.01)


func test_heal_does_nothing_when_dead() -> void:
	ds.take_hit(100.0, &"slash", 1.0, 0.0, null)
	ds.heal(50.0)
	assert_almost_eq(ds.current_health, 0.0, 0.01)


# ── Priority: invulnerable > parry > resistance ─────────────────────────────

func test_invulnerable_takes_priority_over_parry() -> void:
	ds.is_invulnerable = true
	ds.is_parry_window_active = true
	var result := ds.take_hit(50.0, &"slash", 1.0, 0.0, null)
	assert_true(result.get("dodged", false))
	assert_false(result.get("parried", false))
