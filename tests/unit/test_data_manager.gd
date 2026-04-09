extends "res://addons/gut/test.gd"
## Smoke tests for DataManager: every JSON file loads, every cross-reference resolves,
## and the schema validator passes on the shipped data.

func test_all_data_dictionaries_populated():
	assert_gt(DataManager.units.size(), 0, "units.json loaded")
	assert_gt(DataManager.buildings.size(), 0, "buildings.json loaded")
	assert_gt(DataManager.techs.size(), 0, "techs.json loaded")
	assert_gt(DataManager.civs.size(), 0, "civs.json loaded")
	assert_gt(DataManager.terrains.size(), 0, "terrains.json loaded")
	assert_gt(DataManager.improvements.size(), 0, "improvements.json loaded")
	assert_gt(DataManager.civics.size(), 0, "civics.json loaded")
	assert_gt(DataManager.religions.size(), 0, "religions.json loaded")
	assert_gt(DataManager.promotions.size(), 0, "promotions.json loaded")
	assert_gt(DataManager.leaders.size(), 0, "leaders.json loaded")

func test_unit_required_techs_resolve():
	# Every required_tech on every unit must be a real tech (or empty).
	for unit_id in DataManager.units.keys():
		var entry = DataManager.units[unit_id]
		if not (entry is Dictionary):
			continue
		var req = String(entry.get("required_tech", ""))
		if req != "":
			assert_true(DataManager.techs.has(req),
				"unit '%s' required_tech '%s' must exist" % [unit_id, req])

func test_building_required_techs_resolve():
	for bid in DataManager.buildings.keys():
		var entry = DataManager.buildings[bid]
		if not (entry is Dictionary):
			continue
		var req = String(entry.get("required_tech", ""))
		if req != "":
			assert_true(DataManager.techs.has(req),
				"building '%s' required_tech '%s' must exist" % [bid, req])

func test_tech_prerequisites_resolve():
	for tid in DataManager.techs.keys():
		var entry = DataManager.techs[tid]
		if not (entry is Dictionary):
			continue
		for prereq in entry.get("prerequisites", []):
			assert_true(DataManager.techs.has(prereq),
				"tech '%s' prerequisite '%s' must exist" % [tid, prereq])
		for prereq in entry.get("or_prerequisites", []):
			assert_true(DataManager.techs.has(prereq),
				"tech '%s' or_prerequisite '%s' must exist" % [tid, prereq])

func test_civ_starting_techs_resolve():
	for cid in DataManager.civs.keys():
		var entry = DataManager.civs[cid]
		if not (entry is Dictionary):
			continue
		for tech in entry.get("starting_techs", []):
			assert_true(DataManager.techs.has(tech),
				"civ '%s' starting_tech '%s' must exist" % [cid, tech])

func test_improvement_required_techs_resolve():
	for iid in DataManager.improvements.keys():
		var entry = DataManager.improvements[iid]
		if not (entry is Dictionary):
			continue
		var req = String(entry.get("required_tech", ""))
		if req != "":
			assert_true(DataManager.techs.has(req),
				"improvement '%s' required_tech '%s' must exist" % [iid, req])

func test_get_tunable_returns_default_for_missing_path():
	var v = DataManager.get_tunable("nonexistent.deeply.nested.key", 42)
	assert_eq(int(v), 42)

func test_get_tunable_resolves_existing_path():
	# These are stable values shipped with the project — they were originally hardcoded
	# constants and should never silently change.
	assert_eq(int(DataManager.get_tunable("victory.max_turns", -1)), 500)
	assert_eq(int(DataManager.get_tunable("combat.max_combat_rounds", -1)), 100)
	assert_almost_eq(float(DataManager.get_tunable("combat.barbarian_bonus", -1.0)), 1.25, 0.001)
	assert_almost_eq(float(DataManager.get_tunable("religion.base_spread_chance", -1.0)), 0.05, 0.001)
