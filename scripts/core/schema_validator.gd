class_name SchemaValidator
extends RefCounted
## Lightweight schema validation for JSON data files.
##
## A schema is a Dictionary with optional keys:
##   required: Array[String]   - field names that must exist on every entry
##   types:    Dictionary      - field name -> type (TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_DICTIONARY, TYPE_ARRAY, TYPE_BOOL)
##   refs:     Dictionary      - field name -> "data_set_name" (e.g. "techs"); validator will check the value
##                               (or each element if Array) exists as a key in the named data set
##   optional: Array[String]   - documented optional fields (informational; no enforcement)
##
## Entries whose key starts with "_" are treated as metadata and skipped.

## Validate a flat dict-of-entries (units, buildings, etc.)
## Returns the number of errors found. Errors are pushed via push_error.
static func validate_entries(filename: String, data: Dictionary, schema: Dictionary, ref_resolver: Callable = Callable()) -> int:
	var errors := 0
	var required: Array = schema.get("required", [])
	var types: Dictionary = schema.get("types", {})
	var refs: Dictionary = schema.get("refs", {})

	for entry_id in data.keys():
		if String(entry_id).begins_with("_"):
			continue
		var entry = data[entry_id]
		if not (entry is Dictionary):
			push_error("[schema] %s: entry '%s' is not a Dictionary" % [filename, entry_id])
			errors += 1
			continue

		# Required fields
		for field in required:
			if not entry.has(field):
				push_error("[schema] %s: entry '%s' missing required field '%s'" % [filename, entry_id, field])
				errors += 1

		# Type checks
		for field in types.keys():
			if not entry.has(field):
				continue
			var expected_type = types[field]
			var actual_type = typeof(entry[field])
			if not _type_matches(actual_type, expected_type):
				push_error("[schema] %s: entry '%s' field '%s' has wrong type (expected %s, got %s)" %
					[filename, entry_id, field, _type_name(expected_type), _type_name(actual_type)])
				errors += 1

		# Reference checks
		if ref_resolver.is_valid():
			for field in refs.keys():
				if not entry.has(field):
					continue
				var target_set: String = refs[field]
				var value = entry[field]
				if value is Array:
					for v in value:
						if not _ref_exists(ref_resolver, target_set, v):
							push_error("[schema] %s: entry '%s' field '%s' references unknown %s '%s'" %
								[filename, entry_id, field, target_set, str(v)])
							errors += 1
				elif value is String and value != "":
					if not _ref_exists(ref_resolver, target_set, value):
						push_error("[schema] %s: entry '%s' field '%s' references unknown %s '%s'" %
							[filename, entry_id, field, target_set, str(value)])
						errors += 1

	return errors

## Validate a tunables file structure (a single nested Dictionary, not entries).
## Schema is a Dictionary mapping dot-paths to types/required flags:
##   {"damage.base": TYPE_FLOAT, "max_combat_rounds": TYPE_INT, ...}
## Returns number of errors found.
static func validate_tunables(filename: String, data: Dictionary, expected_paths: Dictionary) -> int:
	var errors := 0
	for path in expected_paths.keys():
		var expected_type = expected_paths[path]
		var value = _resolve_path(data, path)
		if value == null:
			push_error("[tunables] %s: missing path '%s'" % [filename, path])
			errors += 1
			continue
		var actual_type = typeof(value)
		if not _type_matches(actual_type, expected_type):
			push_error("[tunables] %s: path '%s' has wrong type (expected %s, got %s)" %
				[filename, path, _type_name(expected_type), _type_name(actual_type)])
			errors += 1
	return errors

# ---- internals ----

static func _type_matches(actual: int, expected: int) -> bool:
	if actual == expected:
		return true
	# JSON has no int/float distinction — Godot's parser may return either.
	# Treat them as interchangeable when the schema specifies a numeric type.
	if (expected == TYPE_INT or expected == TYPE_FLOAT) and (actual == TYPE_INT or actual == TYPE_FLOAT):
		return true
	return false

static func _type_name(t: int) -> String:
	match t:
		TYPE_INT: return "int"
		TYPE_FLOAT: return "float"
		TYPE_STRING: return "string"
		TYPE_BOOL: return "bool"
		TYPE_ARRAY: return "array"
		TYPE_DICTIONARY: return "dict"
		_: return "type:%d" % t

static func _ref_exists(resolver: Callable, target_set: String, key) -> bool:
	var result = resolver.call(target_set, key)
	return bool(result)

static func _resolve_path(data: Dictionary, path: String):
	var parts = path.split(".")
	var node = data
	for p in parts:
		if not (node is Dictionary):
			return null
		if not node.has(p):
			return null
		node = node[p]
	return node
