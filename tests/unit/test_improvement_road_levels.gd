extends "res://addons/gut/test.gd"
## Phase 2 acceptance: road / railroad behavior comes from improvements.json `road_level` field
## rather than a hardcoded if-elif on improvement_id.

func test_road_has_road_level_one():
	var road = DataManager.get_improvement("road")
	assert_eq(int(road.get("road_level", 0)), 1)

func test_railroad_has_road_level_two():
	var railroad = DataManager.get_improvement("railroad")
	assert_eq(int(railroad.get("road_level", 0)), 2)

func test_normal_improvements_have_no_road_level():
	for iid in ["farm", "mine", "cottage", "lumbermill", "fort"]:
		var entry = DataManager.get_improvement(iid)
		assert_eq(int(entry.get("road_level", 0)), 0,
			"%s should not have a road_level" % iid)

func test_build_time_lookup_uses_json():
	# improvement_system.get_build_time should pull straight from improvements.json.
	assert_eq(ImprovementSystem.get_build_time("farm"), int(DataManager.get_improvement("farm").get("build_turns", -1)))
	assert_eq(ImprovementSystem.get_build_time("mine"), int(DataManager.get_improvement("mine").get("build_turns", -1)))
