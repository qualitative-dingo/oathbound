extends GutTest
## Tests for ProgressionManager: tier gating, boss defeat, serialization.

var prog: ProgressionManager


func before_each() -> void:
	prog = ProgressionManager.new()
	add_child_autofree(prog)


# ── Tier system ──────────────────────────────────────────────────────────────

func test_initial_tier_is_one() -> void:
	assert_eq(prog.get_current_tier(), 1)


func test_defeat_boss_advances_tier() -> void:
	prog.defeat_boss(&"the_stag_king")
	assert_eq(prog.get_current_tier(), 2)


func test_defeating_same_boss_twice_noop() -> void:
	prog.defeat_boss(&"the_stag_king")
	prog.defeat_boss(&"the_stag_king")
	assert_eq(prog.get_current_tier(), 2)


func test_is_boss_defeated() -> void:
	assert_false(prog.is_boss_defeated(&"the_stag_king"))
	prog.defeat_boss(&"the_stag_king")
	assert_true(prog.is_boss_defeated(&"the_stag_king"))


func test_unknown_boss_defeat_stays_tier_one() -> void:
	prog.defeat_boss(&"random_boss")
	# Unknown boss is not in TIER_DATA, so highest matched tier stays 0 -> tier = 1
	assert_eq(prog.get_current_tier(), 1)


# ── Station unlocks ──────────────────────────────────────────────────────────

func test_ungated_station_always_unlocked() -> void:
	assert_true(prog.is_station_unlocked(&"workbench"))
	assert_true(prog.is_station_unlocked(&"forge"))


# ── Boss power ───────────────────────────────────────────────────────────────

func test_activate_power_requires_defeated_boss() -> void:
	prog.activate_boss_power(&"the_stag_king")
	assert_eq(prog.active_boss_power, &"", "Should not activate power for undefeated boss")


func test_activate_power_after_defeating_boss() -> void:
	prog.defeat_boss(&"the_stag_king")
	prog.activate_boss_power(&"the_stag_king")
	assert_eq(prog.active_boss_power, &"the_stag_king")
	assert_true(prog._power_active)


func test_power_cooldown_blocks_activation() -> void:
	prog.defeat_boss(&"the_stag_king")
	prog.boss_power_cooldown = 100.0
	prog.activate_boss_power(&"the_stag_king")
	assert_false(prog._power_active, "Should not activate during cooldown")


# ── Serialize / Deserialize ──────────────────────────────────────────────────

func test_serialize_roundtrip() -> void:
	prog.defeat_boss(&"the_stag_king")
	prog.activate_boss_power(&"the_stag_king")
	var data := prog.serialize()
	var new_prog := ProgressionManager.new()
	add_child_autofree(new_prog)
	new_prog.deserialize(data)
	assert_true(new_prog.is_boss_defeated(&"the_stag_king"))
	assert_eq(new_prog.active_boss_power, &"the_stag_king")
	assert_true(new_prog._power_active)


func test_deserialize_empty_data() -> void:
	prog.defeat_boss(&"the_stag_king")
	prog.deserialize({})
	assert_false(prog.is_boss_defeated(&"the_stag_king"), "Deserialize empty should clear state")
	assert_eq(prog.get_current_tier(), 1)


func test_serialize_preserves_cooldown() -> void:
	prog.boss_power_cooldown = 500.0
	var data := prog.serialize()
	var new_prog := ProgressionManager.new()
	add_child_autofree(new_prog)
	new_prog.deserialize(data)
	assert_almost_eq(new_prog.boss_power_cooldown, 500.0, 0.01)


func test_serialize_preserves_power_timer() -> void:
	prog.defeat_boss(&"the_stag_king")
	prog.activate_boss_power(&"the_stag_king")
	prog._power_timer = 120.0
	var data := prog.serialize()
	var new_prog := ProgressionManager.new()
	add_child_autofree(new_prog)
	new_prog.deserialize(data)
	assert_almost_eq(new_prog._power_timer, 120.0, 0.01)
	assert_true(new_prog._power_active)
