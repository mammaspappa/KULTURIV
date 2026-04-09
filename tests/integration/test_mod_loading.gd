extends "res://addons/gut/test.gd"
## Integration test: confirms the mod loading mechanism is wired up.
## Doesn't actually mount a mod (the test runner can't write to user:// reliably across CI),
## but verifies the methods exist and the loaded_mods array is in a consistent shape.

func test_loaded_mods_array_exists():
	assert_true(DataManager.loaded_mods is Array, "loaded_mods should be an Array")

func test_data_manager_has_deep_merge():
	# Internal helper, but it's load-bearing for mod overrides — assert it's reachable.
	assert_true(DataManager.has_method("_deep_merge"))

func test_deep_merge_overlays_nested_dicts():
	var base = {"a": {"b": 1, "c": 2}, "d": 3}
	var overlay = {"a": {"b": 99}, "e": 4}
	var result = DataManager._deep_merge(base, overlay)
	assert_eq(int(result["a"]["b"]), 99, "overlay value wins")
	assert_eq(int(result["a"]["c"]), 2, "untouched nested key preserved")
	assert_eq(int(result["d"]), 3, "untouched top-level key preserved")
	assert_eq(int(result["e"]), 4, "new key added")

func test_deep_merge_replaces_arrays_wholesale():
	# Arrays don't merge element-by-element — they're replaced. This matches the documented
	# behavior in DataManager._deep_merge: redefining a list means redefining a list.
	var base = {"a": [1, 2, 3]}
	var overlay = {"a": [9]}
	var result = DataManager._deep_merge(base, overlay)
	assert_eq(result["a"].size(), 1)
	assert_eq(int(result["a"][0]), 9)
