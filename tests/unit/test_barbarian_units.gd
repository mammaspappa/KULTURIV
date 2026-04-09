extends "res://addons/gut/test.gd"
## Phase 2 acceptance: barbarian-eligible units are flagged in units.json with
## `barbarian_available: true` and `barbarian_tier: <int>`. The hardcoded availability map
## that used to live in barbarian_system.gd is gone.

func test_warrior_is_barbarian_tier_zero():
	var warrior = DataManager.get_unit("warrior")
	assert_true(bool(warrior.get("barbarian_available", false)))
	assert_eq(int(warrior.get("barbarian_tier", -1)), 0)

func test_naval_units_flagged():
	for uid in ["galley", "caravel", "frigate"]:
		var entry = DataManager.get_unit(uid)
		assert_true(bool(entry.get("barbarian_available", false)),
			"%s should be barbarian_available" % uid)
		assert_eq(String(entry.get("unit_class", "")), "naval",
			"%s should have unit_class=naval" % uid)

func test_modern_land_units_flagged():
	for uid in ["swordsman", "knight", "musketman", "rifleman"]:
		var entry = DataManager.get_unit(uid)
		assert_true(bool(entry.get("barbarian_available", false)),
			"%s should be barbarian_available" % uid)

func test_settler_not_barbarian_available():
	var settler = DataManager.get_unit("settler")
	assert_false(bool(settler.get("barbarian_available", false)))
