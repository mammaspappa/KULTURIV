extends "res://addons/gut/test.gd"
## Verifies every tunables file loaded by DataManager has the keys the codebase relies on.
## Add an assertion here whenever a new tunable is referenced from code so a missing JSON entry
## fails the build instead of silently falling back to a hardcoded default.

func test_combat_tunables():
	for path in ["combat.damage.base", "combat.damage.strength_multiplier",
			"combat.damage.min", "combat.damage.max",
			"combat.max_combat_rounds", "combat.withdraw_threshold",
			"combat.barbarian_bonus",
			"combat.air.bomb_damage_variance_min", "combat.air.bomb_damage_variance_max",
			"combat.nuke.sdi_intercept_chance", "combat.nuke.fallout_duration_turns",
			"combat.bombard.defense_reduction_per_point"]:
		assert_true(DataManager.get_tunable(path, null) != null, path + " must be set")

func test_cities_tunables():
	for path in ["cities.culture_thresholds",
			"cities.draft.anger_turns", "cities.draft.pop_cost", "cities.draft.max_per_turn",
			"cities.draft.required_tech", "cities.draft.required_civic_legal",
			"cities.whip.production_per_pop", "cities.whip.anger_turns",
			"cities.fallback_unit"]:
		assert_true(DataManager.get_tunable(path, null) != null, path + " must be set")

func test_religion_tunables():
	for path in ["religion.base_spread_chance",
			"religion.happiness.holy_city", "religion.happiness.with_building",
			"religion.founding_techs"]:
		assert_true(DataManager.get_tunable(path, null) != null, path + " must be set")

func test_barbarians_tunables():
	for path in ["barbarians.camp.spawn_interval", "barbarians.camp.min_distance",
			"barbarians.camp.city_distance", "barbarians.camp.max_camps",
			"barbarians.camp.unit_spawn_interval",
			"barbarians.city_founding.base_min_turn", "barbarians.city_founding.base_chance",
			"barbarians.fallback_unit"]:
		assert_true(DataManager.get_tunable(path, null) != null, path + " must be set")

func test_victory_tunables():
	assert_eq(int(DataManager.get_tunable("victory.max_turns", -1)), 500)
	assert_almost_eq(float(DataManager.get_tunable("victory.domination_land_percent", -1.0)), 0.55, 0.001)
	assert_almost_eq(float(DataManager.get_tunable("victory.domination_pop_percent", -1.0)), 0.55, 0.001)
	assert_eq(int(DataManager.get_tunable("victory.cultural_threshold", -1)), 50000)
	assert_eq(int(DataManager.get_tunable("victory.cultural_cities_needed", -1)), 3)

func test_civics_tunables():
	var costs = DataManager.get_tunable("civics.upkeep_costs", null)
	assert_true(costs is Dictionary)
	assert_eq(int(costs.get("none", -1)), 0)
	assert_eq(int(costs.get("low", -1)), 1)
	assert_eq(int(costs.get("medium", -1)), 2)
	assert_eq(int(costs.get("high", -1)), 3)
	assert_true(DataManager.get_tunable("civics.default_civics", null) != null)

func test_great_people_tunables():
	assert_eq(int(DataManager.get_tunable("great_people.base_threshold", -1)), 100)
	assert_eq(int(DataManager.get_tunable("great_people.threshold_increase_per_birth", -1)), 50)
	var bgm = DataManager.get_tunable("great_people.building_gp_map", null)
	assert_true(bgm is Dictionary)
	assert_eq(String(bgm.get("library", "")), "scientist")
	assert_eq(String(bgm.get("market", "")), "merchant")

func test_units_tunables():
	assert_eq(int(DataManager.get_tunable("units.position_history_length", -1)), 6)
	assert_almost_eq(float(DataManager.get_tunable("units.great_general.combat_bonus", -1.0)), 0.20, 0.001)
	assert_almost_eq(float(DataManager.get_tunable("units.great_general.xp_bonus", -1.0)), 0.50, 0.001)

func test_year_progression_tunables():
	var prog = DataManager.get_tunable("year_progression.progression", null)
	assert_true(prog is Array)
	assert_gt(prog.size(), 0)
	for stage in prog:
		assert_true(stage is Dictionary)
		assert_true(stage.has("until_turn"))
		assert_true(stage.has("years_per_turn"))

func test_mapgen_tunables():
	assert_almost_eq(float(DataManager.get_tunable("mapgen.thresholds.sea_level", -1.0)), 0.4, 0.001)
	assert_almost_eq(float(DataManager.get_tunable("mapgen.thresholds.mountain", -1.0)), 0.82, 0.001)
	assert_almost_eq(float(DataManager.get_tunable("mapgen.thresholds.hill", -1.0)), 0.68, 0.001)
	# Plate presets must exist for every supported map type the UI exposes.
	for map_type in ["pangaea", "continents", "archipelago", "fractal"]:
		var preset = DataManager.get_tunable("mapgen.plates." + map_type, null)
		assert_true(preset is Dictionary, "mapgen.plates.%s must be a dict" % map_type)
		assert_true(preset.has("continental_count_min"), "mapgen.plates.%s.continental_count_min" % map_type)
