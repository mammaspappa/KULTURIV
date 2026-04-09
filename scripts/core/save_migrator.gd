class_name SaveMigrator
extends RefCounted
## Save game migration framework.
##
## Save files carry an integer `save_version` (legacy files used a string `"1.0"`).
## When loading, SaveSystem calls SaveMigrator.migrate(data, current_version) which walks the
## registered migrators in order, transforming the dict in-place until it matches the current
## SAVE_VERSION. If no migrator path exists, migration fails loudly via Logger.error.
##
## Adding a migrator:
##   1. Bump SaveSystem.SAVE_VERSION from N to N+1.
##   2. Add a new static func migrate_N_to_N_plus_1(data: Dictionary) -> Dictionary
##   3. Register it in MIGRATIONS below.
##
## Each migrator MUST be deterministic and idempotent for a given input — never mutate
## external state. Return the migrated dict.

## Detect the version of a loaded save dict. Legacy saves used `version: "1.0"`; current
## saves use `save_version: <int>`. Missing → assume v1.
static func detect_version(data: Dictionary) -> int:
	if data.has("save_version"):
		var v = data["save_version"]
		if v is int:
			return v
		if v is float:
			return int(v)
		if v is String:
			return _parse_legacy_version_string(v)
	if data.has("version"):
		var v2 = data["version"]
		if v2 is String:
			return _parse_legacy_version_string(v2)
	return 1

static func _parse_legacy_version_string(s: String) -> int:
	# "1.0" → 1, "2.3" → 2, etc.
	var dot = s.find(".")
	var major = s if dot == -1 else s.substr(0, dot)
	if major.is_valid_int():
		return int(major)
	return 1

## Walk migrators until data matches `target_version`. Returns the migrated dict
## (which may be the same instance) or null on failure.
static func migrate(data: Dictionary, target_version: int) -> Variant:
	var current = detect_version(data)
	if current == target_version:
		return data
	if current > target_version:
		GameLog.error("save", "save is from a newer version (%d > %d); cannot downgrade" % [current, target_version])
		return null

	while current < target_version:
		var migrated = _apply_step(current, data)
		if migrated == null:
			return null
		data = migrated
		current += 1

	data["save_version"] = current
	return data

## Dispatch to a single migrator step. Returns null if no migrator is registered for `from`.
## Add new versions by extending the match below.
static func _apply_step(from_version: int, data: Dictionary) -> Variant:
	GameLog.info("save", "migrating save %d -> %d" % [from_version, from_version + 1])
	match from_version:
		1:
			return migrate_1_to_2(data)
		_:
			GameLog.error("save", "no migrator registered for step %d_to_%d" % [from_version, from_version + 1])
			return null

# ---- Registered migrators ----

## v1 → v2: this migration is currently a no-op (identity) for actual content, but it:
##   - Documents the v1 schema as the baseline
##   - Stamps `save_version: 2` into legacy saves so future migrations have a known starting point
##   - Strips the legacy `"version": "1.0"` string field
##   - Provides a tested code path the test suite can exercise
static func migrate_1_to_2(data: Dictionary) -> Dictionary:
	if data.has("version"):
		data.erase("version")
	data["save_version"] = 2
	return data
