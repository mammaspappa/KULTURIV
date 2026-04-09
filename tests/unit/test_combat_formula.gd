extends "res://addons/gut/test.gd"
## Pin the BTS combat damage formula. Any change here will be visible in the diff so balance
## tweaks are intentional, not accidental.

func _expected_damage(diff: float) -> float:
	var base: float = float(DataManager.get_tunable("combat.damage.base", 20.0))
	var mult: float = float(DataManager.get_tunable("combat.damage.strength_multiplier", 3.0))
	var lo: float = float(DataManager.get_tunable("combat.damage.min", 12.0))
	var hi: float = float(DataManager.get_tunable("combat.damage.max", 40.0))
	return clamp(base + diff * mult, lo, hi)

func test_damage_at_equal_strength_is_base():
	assert_almost_eq(_expected_damage(0.0), 20.0, 0.001)

func test_damage_clamps_to_min():
	# A huge negative differential should clamp to the minimum.
	assert_almost_eq(_expected_damage(-100.0), 12.0, 0.001)

func test_damage_clamps_to_max():
	# A huge positive differential should clamp to the maximum.
	assert_almost_eq(_expected_damage(100.0), 40.0, 0.001)

func test_damage_scales_linearly_in_range():
	# +1 strength differential = +3 damage in the linear region.
	var d0 = _expected_damage(0.0)
	var d1 = _expected_damage(1.0)
	assert_almost_eq(d1 - d0, 3.0, 0.001)

func test_combat_system_uses_same_formula():
	# CombatSystem._damage_from_diff is the production code path. It must agree with our
	# expectation derived from the same tunables.
	var prod = CombatSystem._damage_from_diff(2.0)
	var expected = _expected_damage(2.0)
	assert_almost_eq(prod, expected, 0.001)

func test_damage_formula_is_symmetric_when_unclamped():
	# Within the linear region, +diff and -diff should be reflections about `base`.
	# Use diff=2: 20 + 2*3 = 26, 20 - 2*3 = 14. Both inside [12, 40] so no clamping.
	var att_dmg = CombatSystem._damage_from_diff(2.0)
	var def_dmg = CombatSystem._damage_from_diff(-2.0)
	assert_almost_eq(att_dmg + def_dmg, 40.0, 0.001)  # = 2 * base
	assert_almost_eq(att_dmg, 26.0, 0.001)
	assert_almost_eq(def_dmg, 14.0, 0.001)

func test_damage_formula_clamps_asymmetrically_at_extremes():
	# Big differential exits the linear region; the underdog clamps before the favorite.
	# diff=5: 20+15=35 (in range), 20-15=5 → clamped to 12.
	var att = CombatSystem._damage_from_diff(5.0)
	var def = CombatSystem._damage_from_diff(-5.0)
	assert_almost_eq(att, 35.0, 0.001)
	assert_almost_eq(def, 12.0, 0.001)
