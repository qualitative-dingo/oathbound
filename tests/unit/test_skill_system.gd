extends GutTest
## Tests for SkillSystem: XP curves, leveling, death penalty, serialization.

var skills: SkillSystem


func before_each() -> void:
	skills = SkillSystem.new()
	skills._ready()
	add_child_autofree(skills)


# ── Initial state ────────────────────────────────────────────────────────────

func test_all_skills_start_at_zero() -> void:
	for skill_id: StringName in SkillSystem.SKILL_DEFS.keys():
		assert_eq(skills.get_skill_level(skill_id), 0.0, "%s should start at 0" % skill_id)


func test_nonexistent_skill_returns_zero() -> void:
	assert_eq(skills.get_skill_level(&"nonexistent"), 0.0)


# ── Skill factor ─────────────────────────────────────────────────────────────

func test_skill_factor_at_zero() -> void:
	assert_almost_eq(skills.get_skill_factor(&"swords"), 1.0, 0.001)


func test_skill_factor_at_max() -> void:
	skills.skills[&"swords"]["level"] = 100.0
	assert_almost_eq(skills.get_skill_factor(&"swords"), 2.0, 0.001)


func test_skill_factor_at_fifty() -> void:
	skills.skills[&"swords"]["level"] = 50.0
	assert_almost_eq(skills.get_skill_factor(&"swords"), 1.5, 0.001)


# ── XP curve ─────────────────────────────────────────────────────────────────

func test_xp_for_level_zero() -> void:
	var xp := skills._xp_for_next_level(0.0)
	assert_almost_eq(xp, 10.0, 0.001, "Level 0 should need 10 XP")


func test_xp_for_level_ten() -> void:
	var xp := skills._xp_for_next_level(10.0)
	assert_almost_eq(xp, 60.0, 0.001, "Level 10 should need 10 + 10*5 = 60 XP")


func test_xp_increases_with_level() -> void:
	var xp_0 := skills._xp_for_next_level(0.0)
	var xp_50 := skills._xp_for_next_level(50.0)
	var xp_99 := skills._xp_for_next_level(99.0)
	assert_true(xp_50 > xp_0, "Higher levels should need more XP")
	assert_true(xp_99 > xp_50, "Higher levels should need more XP")


# ── Add XP / Level up ───────────────────────────────────────────────────────

func test_add_xp_accumulates() -> void:
	skills.add_xp(&"swords", 1.0)
	assert_true(skills.skills[&"swords"]["xp"] > 0.0)


func test_add_xp_to_nonexistent_skill_noop() -> void:
	skills.add_xp(&"cooking")
	assert_false(skills.skills.has(&"cooking"))


func test_level_up_from_xp() -> void:
	# Level 0 needs 10 XP; base_xp=1.0, level_factor at 0 = 1.0
	# So each add_xp(&"swords") adds 1.0 XP. Need 10 calls to level up.
	for _i in 10:
		skills.add_xp(&"swords", 1.0)
	assert_eq(skills.get_skill_level(&"swords"), 1.0)


func test_level_does_not_exceed_max() -> void:
	skills.skills[&"swords"]["level"] = 99.0
	skills.skills[&"swords"]["xp"] = 0.0
	# XP for level 99 -> 100 = 10 + 99*5 = 505. Soft cap factor: 1.0 - (99/100)*0.5 = 0.505
	# Effective xp per call: 1.0 * 1.0 * 0.505 = 0.505. Need ~1000 calls.
	for _i in 1200:
		skills.add_xp(&"swords", 1.0)
	assert_true(skills.get_skill_level(&"swords") <= SkillSystem.MAX_SKILL_LEVEL)


func test_soft_cap_reduces_xp_gain_at_high_levels() -> void:
	var xp_gained_low: float
	var xp_gained_high: float

	skills.skills[&"swords"]["level"] = 0.0
	skills.skills[&"swords"]["xp"] = 0.0
	skills.add_xp(&"swords", 1.0)
	xp_gained_low = skills.skills[&"swords"]["xp"]

	skills.skills[&"swords"]["level"] = 80.0
	skills.skills[&"swords"]["xp"] = 0.0
	skills.add_xp(&"swords", 1.0)
	xp_gained_high = skills.skills[&"swords"]["xp"]

	assert_true(xp_gained_high < xp_gained_low, "XP gain should be lower at high levels")


# ── Death penalty ────────────────────────────────────────────────────────────

func test_death_penalty_reduces_levels() -> void:
	skills.skills[&"swords"]["level"] = 50.0
	skills.skills[&"axes"]["level"] = 30.0
	var total_before := 80.0
	skills.apply_death_penalty()
	var total_after := skills.get_skill_level(&"swords") + skills.get_skill_level(&"axes")
	var expected_loss := total_before * SkillSystem.DEATH_PENALTY_FRACTION
	assert_almost_eq(total_after, total_before - expected_loss, 0.01)


func test_death_penalty_proportional_distribution() -> void:
	skills.skills[&"swords"]["level"] = 80.0
	skills.skills[&"axes"]["level"] = 20.0
	skills.apply_death_penalty()
	# Swords should lose 4x more than axes (80/100 * 5 = 4, 20/100 * 5 = 1)
	var swords_loss := 80.0 - skills.get_skill_level(&"swords")
	var axes_loss := 20.0 - skills.get_skill_level(&"axes")
	assert_almost_eq(swords_loss / axes_loss, 4.0, 0.1)


func test_death_penalty_does_not_go_below_zero() -> void:
	skills.skills[&"swords"]["level"] = 0.5
	skills.apply_death_penalty()
	assert_true(skills.get_skill_level(&"swords") >= 0.0)


func test_death_penalty_resets_xp() -> void:
	skills.skills[&"swords"]["level"] = 50.0
	skills.skills[&"swords"]["xp"] = 8.0
	skills.apply_death_penalty()
	assert_almost_eq(skills.skills[&"swords"]["xp"], 0.0, 0.001)


func test_death_penalty_all_zero_noop() -> void:
	skills.apply_death_penalty()
	for skill_id: StringName in skills.skills.keys():
		assert_eq(skills.get_skill_level(skill_id), 0.0)


func test_no_skill_drain_immunity() -> void:
	skills.skills[&"swords"]["level"] = 50.0
	skills.grant_no_skill_drain()
	skills.apply_death_penalty()
	assert_almost_eq(skills.get_skill_level(&"swords"), 50.0, 0.001)


func test_no_skill_drain_timer() -> void:
	skills.grant_no_skill_drain()
	assert_almost_eq(skills.no_skill_drain_timer, SkillSystem.SKILL_DRAIN_IMMUNITY_DURATION, 0.01)


# ── Serialize / Deserialize ──────────────────────────────────────────────────

func test_serialize_roundtrip() -> void:
	skills.skills[&"swords"]["level"] = 42.0
	skills.skills[&"swords"]["xp"] = 7.5
	skills.skills[&"bows"]["level"] = 15.0
	var data := skills.serialize()
	var new_skills := SkillSystem.new()
	new_skills._ready()
	add_child_autofree(new_skills)
	new_skills.deserialize(data)
	assert_almost_eq(new_skills.get_skill_level(&"swords"), 42.0, 0.001)
	assert_almost_eq(new_skills.skills[&"swords"]["xp"], 7.5, 0.001)
	assert_almost_eq(new_skills.get_skill_level(&"bows"), 15.0, 0.001)


func test_deserialize_ignores_unknown_skills() -> void:
	var data := {&"flight": {"level": 99.0, "xp": 0.0}}
	skills.deserialize(data)
	assert_false(skills.skills.has(&"flight"))
