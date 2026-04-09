extends "res://addons/gut/test.gd"
## Tests for the save_migrator framework.

const SaveMigratorClass = preload("res://scripts/core/save_migrator.gd")

func test_detect_version_from_int():
	assert_eq(SaveMigratorClass.detect_version({"save_version": 2}), 2)
	assert_eq(SaveMigratorClass.detect_version({"save_version": 7}), 7)

func test_detect_version_from_legacy_string():
	assert_eq(SaveMigratorClass.detect_version({"version": "1.0"}), 1)
	assert_eq(SaveMigratorClass.detect_version({"version": "2.5"}), 2)

func test_detect_version_defaults_to_v1():
	assert_eq(SaveMigratorClass.detect_version({}), 1)

func test_migrate_v1_to_v2_strips_legacy_field():
	var legacy = {
		"version": "1.0",
		"turn": 42,
		"settings": {"map_width": 80}
	}
	var result = SaveMigratorClass.migrate(legacy, 2)
	assert_true(result is Dictionary)
	assert_eq(int(result["save_version"]), 2)
	assert_false(result.has("version"))
	assert_eq(int(result["turn"]), 42)
	assert_eq(int(result["settings"]["map_width"]), 80)

func test_migrate_no_op_when_already_at_target():
	var current = {"save_version": 2, "turn": 1}
	var result = SaveMigratorClass.migrate(current, 2)
	assert_eq(int(result["save_version"]), 2)

func test_migrate_rejects_downgrade():
	var future = {"save_version": 99}
	var result = SaveMigratorClass.migrate(future, 2)
	assert_eq(result, null, "should refuse to downgrade")
