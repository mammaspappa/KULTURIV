extends Node
## Loads and provides access to all game data from JSON files.

const SchemaValidatorClass = preload("res://scripts/core/schema_validator.gd")

# Data dictionaries
var terrains: Dictionary = {}
var features: Dictionary = {}
var resources: Dictionary = {}
var improvements: Dictionary = {}
var units: Dictionary = {}
var buildings: Dictionary = {}
var techs: Dictionary = {}
var civs: Dictionary = {}
var leaders: Dictionary = {}
var promotions: Dictionary = {}
var religions: Dictionary = {}
var victories: Dictionary = {}
var civics: Dictionary = {}
var specialists: Dictionary = {}
var handicaps: Dictionary = {}
var corporations: Dictionary = {}
var espionage_missions: Dictionary = {}
var projects: Dictionary = {}
var random_events: Dictionary = {}
var votes: Dictionary = {}

# Tunables: balance constants loaded from data/tunables/*.json.
# Keyed by file basename (without extension): tunables.combat, tunables.cities, etc.
var tunables: Dictionary = {}

# Data paths
const DATA_PATH = "res://data/"
const TUNABLES_PATH = "res://data/tunables/"
# Mods are loaded from `user://mods/<mod_id>/data/` and `.../data/tunables/`.
# Each mod's contents are deep-merged on top of the base data — adding new ids extends,
# overwriting existing ids overrides. The load order is alphabetical by mod_id, so a mod
# named "z_balance_tweaks" wins over "a_baseline".
const MODS_PATH = "user://mods/"

# Loaded mod ids in load order, for diagnostics and the optional in-game mod list.
var loaded_mods: Array[String] = []

func _ready() -> void:
	_load_all_data()
	_load_all_tunables()
	_load_all_mods()
	_validate_data()

func _load_all_data() -> void:
	terrains = _load_json("terrains.json")
	features = _load_json("features.json")
	resources = _load_json("resources.json")
	improvements = _load_json("improvements.json")
	units = _load_json("units.json")
	buildings = _load_json("buildings.json")
	techs = _load_json("techs.json")
	civs = _load_json("civs.json")
	leaders = _load_json("leaders.json")
	promotions = _load_json("promotions.json")
	religions = _load_json("religions.json")
	victories = _load_json("victories.json")
	civics = _load_json("civics.json")
	specialists = _load_json("specialists.json")
	handicaps = _load_json("handicaps.json")
	corporations = _load_json("corporations.json")
	espionage_missions = _load_json("espionage_missions.json")
	projects = _load_json("projects.json")
	random_events = _load_json("events.json")
	votes = _load_json("votes.json")
	print("DataManager: All data loaded")

func _load_all_tunables() -> void:
	# Load every *.json file in data/tunables/ as a top-level key in `tunables`.
	var dir = DirAccess.open(TUNABLES_PATH)
	if dir == null:
		push_warning("DataManager: tunables directory not found: " + TUNABLES_PATH)
		return
	dir.list_dir_begin()
	var filename = dir.get_next()
	while filename != "":
		if not dir.current_is_dir() and filename.ends_with(".json"):
			var key = filename.get_basename()
			tunables[key] = _load_json_at(TUNABLES_PATH + filename, filename)
		filename = dir.get_next()
	dir.list_dir_end()
	print("DataManager: Loaded %d tunables files" % tunables.size())

## Scan user://mods/ for installed mods and merge their data on top of the base.
## Each mod is a directory containing a `data/` subdirectory mirroring res://data/.
## Files inside `data/tunables/` are deep-merged into `tunables`; files at `data/` are
## merged into the corresponding top-level dict (units, buildings, etc.).
##
## A simple `mod.json` manifest at the mod root is optional but lets the mod declare a
## display name and load priority. Without it, the directory name is used as the id.
func _load_all_mods() -> void:
	var dir = DirAccess.open(MODS_PATH)
	if dir == null:
		# No mods installed — perfectly normal.
		return
	var mod_ids: Array[String] = []
	dir.list_dir_begin()
	var entry = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			mod_ids.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	mod_ids.sort()  # Deterministic alphabetical order; later mods win.
	for mod_id in mod_ids:
		_load_single_mod(mod_id)
	loaded_mods = mod_ids
	if not loaded_mods.is_empty():
		GameLog.info("data", "loaded %d mod(s): %s" % [loaded_mods.size(), ", ".join(loaded_mods)])

func _load_single_mod(mod_id: String) -> void:
	var mod_root = MODS_PATH + mod_id + "/"
	var data_root = mod_root + "data/"

	# Merge top-level data files.
	var dir = DirAccess.open(data_root)
	if dir != null:
		dir.list_dir_begin()
		var f = dir.get_next()
		while f != "":
			if not dir.current_is_dir() and f.ends_with(".json"):
				_merge_mod_data_file(mod_id, data_root + f, f)
			f = dir.get_next()
		dir.list_dir_end()

	# Merge tunables.
	var tun_root = data_root + "tunables/"
	var tun_dir = DirAccess.open(tun_root)
	if tun_dir != null:
		tun_dir.list_dir_begin()
		var f2 = tun_dir.get_next()
		while f2 != "":
			if not tun_dir.current_is_dir() and f2.ends_with(".json"):
				_merge_mod_tunable_file(mod_id, tun_root + f2, f2)
			f2 = tun_dir.get_next()
		tun_dir.list_dir_end()

func _merge_mod_data_file(mod_id: String, path: String, filename: String) -> void:
	var mod_data = _load_json_at(path, "[mod %s] %s" % [mod_id, filename])
	if mod_data.is_empty():
		return
	# Map filename → target dict on this DataManager.
	var target_dict = _data_dict_for_filename(filename)
	if target_dict == null:
		GameLog.warn("data", "[mod %s] %s does not match any known data file" % [mod_id, filename])
		return
	for key in mod_data.keys():
		target_dict[key] = mod_data[key]
	GameLog.info("data", "[mod %s] merged %d entries from %s" % [mod_id, mod_data.size(), filename])

func _merge_mod_tunable_file(mod_id: String, path: String, filename: String) -> void:
	var mod_data = _load_json_at(path, "[mod %s] tunables/%s" % [mod_id, filename])
	if mod_data.is_empty():
		return
	var key = filename.get_basename()
	if not tunables.has(key):
		tunables[key] = {}
	tunables[key] = _deep_merge(tunables[key], mod_data)
	GameLog.info("data", "[mod %s] merged tunables/%s" % [mod_id, filename])

## Deep-merge `overlay` over `base`. Nested dicts are merged recursively;
## scalars and arrays are replaced wholesale (which is the modders' usual expectation —
## redefining a list means redefining a list).
func _deep_merge(base: Dictionary, overlay: Dictionary) -> Dictionary:
	for k in overlay.keys():
		var v = overlay[k]
		if v is Dictionary and base.get(k, null) is Dictionary:
			base[k] = _deep_merge(base[k], v)
		else:
			base[k] = v
	return base

func _data_dict_for_filename(filename: String):
	match filename:
		"terrains.json": return terrains
		"features.json": return features
		"resources.json": return resources
		"improvements.json": return improvements
		"units.json": return units
		"buildings.json": return buildings
		"techs.json": return techs
		"civs.json": return civs
		"leaders.json": return leaders
		"promotions.json": return promotions
		"religions.json": return religions
		"victories.json": return victories
		"civics.json": return civics
		"specialists.json": return specialists
		"handicaps.json": return handicaps
		"corporations.json": return corporations
		"espionage_missions.json": return espionage_missions
		"projects.json": return projects
		"events.json": return random_events
		"votes.json": return votes
		_: return null

## Resolve a dot-separated path inside `tunables` (e.g. "combat.damage.base").
## Returns `default` if the path is missing. Always check the value type at call site.
func get_tunable(path: String, default = null):
	var parts = path.split(".")
	var node = tunables
	for p in parts:
		if not (node is Dictionary) or not node.has(p):
			return default
		node = node[p]
	return node

func _load_json(filename: String) -> Dictionary:
	return _load_json_at(DATA_PATH + filename, filename)

func _load_json_at(path: String, label: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		GameLog.warn("data", "file not found: " + path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		GameLog.error("data", "failed to open: " + path)
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		GameLog.error("data", "JSON parse error in %s: %s" % [label, json.get_error_message()])
		return {}

	return json.data

# Cross-reference resolver used by schema validator's `refs` checks.
# Given a data set name and a key, returns truthy if the key exists in that set.
func _resolve_ref(set_name: String, key) -> bool:
	var key_str := str(key)
	match set_name:
		"techs": return techs.has(key_str)
		"units": return units.has(key_str)
		"buildings": return buildings.has(key_str)
		"civs": return civs.has(key_str)
		"resources": return resources.has(key_str)
		"terrains": return terrains.has(key_str)
		"features": return features.has(key_str)
		"improvements": return improvements.has(key_str)
		"promotions": return promotions.has(key_str)
		"religions": return religions.has(key_str)
		"civics": return civics.has(key_str)
		"specialists": return specialists.has(key_str)
		"projects": return projects.has(key_str)
		"eras": return _eras_data().has(key_str)
		_:
			push_warning("DataManager: unknown ref set '%s'" % set_name)
			return true  # don't flag if we can't resolve

func _eras_data() -> Dictionary:
	# Eras are stored as part of the project data via DataManager.eras-style accessors below.
	# Access via the `eras` key if the loader supports it; otherwise fall back to empty.
	return tunables.get("year_progression", {})

## Run schema validation across all loaded data and tunables.
## Errors are pushed via push_error() with file:key context. The game continues to run
## (callers fall back to defaults), but the editor console highlights data bugs loudly.
func _validate_data() -> void:
	var resolver := Callable(self, "_resolve_ref")
	var total := 0

	# Entry-style files
	total += SchemaValidatorClass.validate_entries("units.json", units, {
		"required": ["name", "cost"],
		"types": {
			"name": TYPE_STRING,
			"cost": TYPE_INT,
			"strength": TYPE_FLOAT,
			"movement": TYPE_INT,
			"unit_class": TYPE_STRING,
			"abilities": TYPE_ARRAY,
			"required_tech": TYPE_STRING
		},
		"refs": {
			"required_tech": "techs"
		}
	}, resolver)

	total += SchemaValidatorClass.validate_entries("buildings.json", buildings, {
		"required": ["name", "cost"],
		"types": {
			"name": TYPE_STRING,
			"cost": TYPE_INT,
			"required_tech": TYPE_STRING,
			"effects": TYPE_DICTIONARY
		},
		"refs": {
			"required_tech": "techs"
		}
	}, resolver)

	total += SchemaValidatorClass.validate_entries("techs.json", techs, {
		"required": ["name", "cost"],
		"types": {
			"name": TYPE_STRING,
			"cost": TYPE_INT,
			"prerequisites": TYPE_ARRAY,
			"or_prerequisites": TYPE_ARRAY
		},
		"refs": {
			"prerequisites": "techs",
			"or_prerequisites": "techs"
		}
	}, resolver)

	total += SchemaValidatorClass.validate_entries("improvements.json", improvements, {
		"required": ["name"],
		"types": {
			"name": TYPE_STRING,
			"yields": TYPE_DICTIONARY,
			"valid_terrains": TYPE_ARRAY,
			"required_tech": TYPE_STRING
		},
		"refs": {
			"required_tech": "techs"
		}
	}, resolver)

	total += SchemaValidatorClass.validate_entries("civs.json", civs, {
		"required": ["name"],
		"types": {
			"name": TYPE_STRING,
			"unique_unit": TYPE_STRING,
			"unique_building": TYPE_STRING,
			"starting_techs": TYPE_ARRAY,
			"traits": TYPE_ARRAY
		},
		"refs": {
			"starting_techs": "techs"
		}
	}, resolver)

	total += SchemaValidatorClass.validate_entries("religions.json", religions, {
		"required": ["name"],
		"types": {"name": TYPE_STRING}
	}, resolver)

	# Tunables files
	total += SchemaValidatorClass.validate_tunables("combat.json", tunables.get("combat", {}), {
		"damage.base": TYPE_FLOAT,
		"damage.strength_multiplier": TYPE_FLOAT,
		"damage.min": TYPE_FLOAT,
		"damage.max": TYPE_FLOAT,
		"max_combat_rounds": TYPE_INT,
		"withdraw_threshold": TYPE_FLOAT,
		"barbarian_bonus": TYPE_FLOAT
	})

	total += SchemaValidatorClass.validate_tunables("cities.json", tunables.get("cities", {}), {
		"culture_thresholds": TYPE_ARRAY,
		"draft.anger_turns": TYPE_INT,
		"draft.pop_cost": TYPE_INT,
		"draft.max_per_turn": TYPE_INT,
		"whip.production_per_pop": TYPE_INT,
		"whip.anger_turns": TYPE_INT
	})

	total += SchemaValidatorClass.validate_tunables("religion.json", tunables.get("religion", {}), {
		"base_spread_chance": TYPE_FLOAT,
		"happiness.holy_city": TYPE_INT,
		"happiness.with_building": TYPE_INT,
		"founding_techs": TYPE_DICTIONARY
	})

	total += SchemaValidatorClass.validate_tunables("barbarians.json", tunables.get("barbarians", {}), {
		"camp.spawn_interval": TYPE_INT,
		"camp.min_distance": TYPE_INT,
		"camp.city_distance": TYPE_INT,
		"camp.max_camps": TYPE_INT,
		"camp.unit_spawn_interval": TYPE_INT,
		"city_founding.base_min_turn": TYPE_INT,
		"city_founding.base_chance": TYPE_FLOAT,
		"city_founding.max_civs_base": TYPE_INT
	})

	total += SchemaValidatorClass.validate_tunables("victory.json", tunables.get("victory", {}), {
		"max_turns": TYPE_INT,
		"domination_land_percent": TYPE_FLOAT,
		"domination_pop_percent": TYPE_FLOAT,
		"cultural_threshold": TYPE_INT,
		"cultural_cities_needed": TYPE_INT
	})

	total += SchemaValidatorClass.validate_tunables("civics.json", tunables.get("civics", {}), {
		"upkeep_costs": TYPE_DICTIONARY,
		"base_anarchy_turns": TYPE_INT,
		"default_civics": TYPE_DICTIONARY
	})

	total += SchemaValidatorClass.validate_tunables("great_people.json", tunables.get("great_people", {}), {
		"base_threshold": TYPE_INT,
		"threshold_increase_per_birth": TYPE_INT,
		"philosophical_trait_multiplier": TYPE_FLOAT,
		"building_gp_map": TYPE_DICTIONARY
	})

	total += SchemaValidatorClass.validate_tunables("mapgen.json", tunables.get("mapgen", {}), {
		"thresholds.sea_level": TYPE_FLOAT,
		"thresholds.mountain": TYPE_FLOAT,
		"thresholds.hill": TYPE_FLOAT,
		"plates.fractal.continental_count_min": TYPE_INT
	})

	total += SchemaValidatorClass.validate_tunables("units.json", tunables.get("units", {}), {
		"position_history_length": TYPE_INT,
		"great_general.combat_bonus": TYPE_FLOAT,
		"great_general.xp_bonus": TYPE_FLOAT
	})

	total += SchemaValidatorClass.validate_tunables("year_progression.json", tunables.get("year_progression", {}), {
		"progression": TYPE_ARRAY
	})

	if total > 0:
		push_warning("DataManager: schema validation found %d issue(s) — see errors above" % total)
	else:
		print("DataManager: schema validation passed")

# Terrain accessors
func get_terrain(terrain_id: String) -> Dictionary:
	return terrains.get(terrain_id, {})

func get_terrain_color(terrain_id: String) -> Color:
	var terrain = get_terrain(terrain_id)
	if terrain.has("color"):
		return Color(terrain.color)
	return Color.MAGENTA  # Error color

func get_terrain_movement_cost(terrain_id: String) -> int:
	var terrain = get_terrain(terrain_id)
	return terrain.get("movement_cost", 1)

func is_terrain_passable(terrain_id: String) -> bool:
	var terrain = get_terrain(terrain_id)
	return terrain.get("passable", true)

func get_terrain_yields(terrain_id: String) -> Dictionary:
	var terrain = get_terrain(terrain_id)
	return terrain.get("yields", {"food": 0, "production": 0, "commerce": 0})

func get_terrain_defense_bonus(terrain_id: String) -> float:
	var terrain = get_terrain(terrain_id)
	return terrain.get("defense_bonus", 0.0)

# Feature accessors
func get_feature(feature_id: String) -> Dictionary:
	return features.get(feature_id, {})

func get_feature_yields(feature_id: String) -> Dictionary:
	var feature = get_feature(feature_id)
	return feature.get("yields", {"food": 0, "production": 0, "commerce": 0})

func get_feature_movement_cost(feature_id: String) -> int:
	var feature = get_feature(feature_id)
	return feature.get("movement_cost", 0)

func get_feature_defense_bonus(feature_id: String) -> float:
	var feature = get_feature(feature_id)
	return feature.get("defense_bonus", 0.0)

# Resource accessors
func get_resource(resource_id: String) -> Dictionary:
	return resources.get(resource_id, {})

func get_resource_yields(resource_id: String) -> Dictionary:
	var resource = get_resource(resource_id)
	return resource.get("yields", {"food": 0, "production": 0, "commerce": 0})

func is_resource_strategic(resource_id: String) -> bool:
	var resource = get_resource(resource_id)
	return resource.get("type", "") == "strategic"

func is_resource_luxury(resource_id: String) -> bool:
	var resource = get_resource(resource_id)
	return resource.get("type", "") == "luxury"

# Improvement accessors
func get_improvement(improvement_id: String) -> Dictionary:
	return improvements.get(improvement_id, {})

func get_improvement_yields(improvement_id: String) -> Dictionary:
	var improvement = get_improvement(improvement_id)
	return improvement.get("yields", {"food": 0, "production": 0, "commerce": 0})

# Unit accessors
func get_unit(unit_id: String) -> Dictionary:
	var unit = units.get(unit_id, {})
	if unit is Dictionary:
		return unit
	return {}

func get_unit_strength(unit_id: String) -> float:
	var unit = get_unit(unit_id)
	return unit.get("strength", 0.0)

func get_unit_movement(unit_id: String) -> int:
	var unit = get_unit(unit_id)
	return unit.get("movement", 1)

func get_unit_cost(unit_id: String) -> int:
	var unit = get_unit(unit_id)
	return unit.get("cost", 0)

func get_unit_abilities(unit_id: String) -> Array:
	var unit = get_unit(unit_id)
	return unit.get("abilities", [])

func can_unit_found_city(unit_id: String) -> bool:
	return "found_city" in get_unit_abilities(unit_id)

func can_unit_build_improvements(unit_id: String) -> bool:
	return "build_improvements" in get_unit_abilities(unit_id)

# Building accessors
func get_building(building_id: String) -> Dictionary:
	var building = buildings.get(building_id, {})
	if building is Dictionary:
		return building
	return {}

func get_building_cost(building_id: String) -> int:
	var building = get_building(building_id)
	return building.get("cost", 0)

func get_building_maintenance(building_id: String) -> int:
	var building = get_building(building_id)
	return building.get("maintenance", 0)

func get_building_effects(building_id: String) -> Dictionary:
	var building = get_building(building_id)
	return building.get("effects", {})

# Tech accessors
func get_tech(tech_id: String) -> Dictionary:
	var tech = techs.get(tech_id, {})
	if tech is Dictionary:
		return tech
	return {}

func get_tech_cost(tech_id: String) -> int:
	var tech = get_tech(tech_id)
	return tech.get("cost", 0)

func get_tech_prerequisites(tech_id: String) -> Array:
	var tech = get_tech(tech_id)
	return tech.get("prerequisites", [])

func get_tech_unlocks(tech_id: String) -> Dictionary:
	var tech = get_tech(tech_id)
	return tech.get("unlocks", {})

func is_tech_available(tech_id: String, researched_techs: Array) -> bool:
	var tech = get_tech(tech_id)

	# BTS tech tree: AND prerequisites (all must be met) + OR prerequisites (at least one)
	var and_prereqs = tech.get("prerequisites", [])
	var or_prereqs = tech.get("or_prerequisites", [])

	# Check AND prerequisites: ALL must be researched
	for prereq in and_prereqs:
		if prereq not in researched_techs:
			return false

	# Check OR prerequisites: at least ONE must be researched (if any exist)
	if not or_prereqs.is_empty():
		var has_any = false
		for prereq in or_prereqs:
			if prereq in researched_techs:
				has_any = true
				break
		if not has_any:
			return false

	return true

# Civilization accessors
func get_civ(civ_id: String) -> Dictionary:
	var civ = civs.get(civ_id, {})
	if civ is Dictionary:
		return civ
	return {}

func get_civ_unique_unit(civ_id: String) -> String:
	var civ = get_civ(civ_id)
	return civ.get("unique_unit", "")

func get_civ_unique_building(civ_id: String) -> String:
	var civ = get_civ(civ_id)
	return civ.get("unique_building", "")

func get_civ_starting_techs(civ_id: String) -> Array:
	var civ = get_civ(civ_id)
	return civ.get("starting_techs", [])

# Leader accessors
func get_leader(leader_id: String) -> Dictionary:
	var leader = leaders.get(leader_id, {})
	if leader is Dictionary:
		return leader
	return {}

func get_leader_traits(leader_id: String) -> Array:
	var leader = get_leader(leader_id)
	return leader.get("traits", [])

# Promotion accessors
func get_promotion(promotion_id: String) -> Dictionary:
	return promotions.get(promotion_id, {})

func get_promotion_effects(promotion_id: String) -> Dictionary:
	var promotion = get_promotion(promotion_id)
	return promotion.get("effects", {})

func get_promotion_prerequisites(promotion_id: String) -> Array:
	var promotion = get_promotion(promotion_id)
	return promotion.get("prerequisites", [])

# Religion accessors
func get_religion(religion_id: String) -> Dictionary:
	return religions.get(religion_id, {})

# Victory accessors
func get_victory(victory_id: String) -> Dictionary:
	return victories.get(victory_id, {})

func get_all_victory_types() -> Array:
	return victories.keys()

# Civic accessors
func get_civic(civic_id: String) -> Dictionary:
	return civics.get(civic_id, {})

func get_civic_name(civic_id: String) -> String:
	var civic = get_civic(civic_id)
	return civic.get("name", civic_id)

func get_civic_category(civic_id: String) -> String:
	var civic = get_civic(civic_id)
	return civic.get("category", "")

func get_civics_by_category(category: String) -> Array:
	var result = []
	for civic_id in civics:
		if civic_id.begins_with("_"):
			continue  # Skip metadata
		if civics[civic_id].get("category", "") == category:
			result.append(civic_id)
	return result

func get_all_civics() -> Dictionary:
	return civics

# Specialist accessors
func get_specialist(specialist_id: String) -> Dictionary:
	return specialists.get(specialist_id, {})

func get_specialist_name(specialist_id: String) -> String:
	var specialist = get_specialist(specialist_id)
	return specialist.get("name", specialist_id.capitalize())

func get_specialist_yields(specialist_id: String) -> Dictionary:
	var specialist = get_specialist(specialist_id)
	return specialist.get("yields", {})

func get_specialist_commerces(specialist_id: String) -> Dictionary:
	var specialist = get_specialist(specialist_id)
	return specialist.get("commerces", {})

func get_specialist_gp_points(specialist_id: String) -> int:
	var specialist = get_specialist(specialist_id)
	return specialist.get("great_people_points", 0)

func get_specialist_gp_type(specialist_id: String) -> String:
	var specialist = get_specialist(specialist_id)
	return specialist.get("great_people_type", "")

func get_all_specialists() -> Dictionary:
	return specialists

func get_visible_specialists() -> Array:
	var result = []
	for specialist_id in specialists:
		if specialist_id.begins_with("_"):
			continue
		var spec = specialists[specialist_id]
		if spec.get("visible", false):
			result.append(specialist_id)
	return result

# Utility functions
func get_all_units() -> Dictionary:
	return units

func get_all_buildings() -> Dictionary:
	return buildings

func get_all_techs() -> Dictionary:
	return techs

func get_all_civs() -> Dictionary:
	return civs

func get_units_by_era(era: String) -> Array:
	var result = []
	for unit_id in units:
		if units[unit_id].get("era", "") == era:
			result.append(unit_id)
	return result

func get_buildings_by_era(era: String) -> Array:
	var result = []
	for building_id in buildings:
		if buildings[building_id].get("era", "") == era:
			result.append(building_id)
	return result

# Handicap accessors
func get_handicap(handicap_id: String) -> Dictionary:
	return handicaps.get(handicap_id, {})

func get_handicap_by_level(level: int) -> Dictionary:
	for handicap_id in handicaps:
		var h = handicaps[handicap_id]
		if h.get("level", -1) == level:
			return h
	return {}

func get_handicap_name(handicap_id: String) -> String:
	var h = get_handicap(handicap_id)
	return h.get("name", handicap_id.capitalize())

func get_ai_bonuses(handicap_id: String) -> Dictionary:
	var h = get_handicap(handicap_id)
	return h.get("ai_bonuses", {})

func get_human_bonuses(handicap_id: String) -> Dictionary:
	var h = get_handicap(handicap_id)
	return h.get("human_bonuses", {})

func get_all_handicaps() -> Dictionary:
	return handicaps

func get_handicap_id_by_level(level: int) -> String:
	for handicap_id in handicaps:
		var h = handicaps[handicap_id]
		if h.get("level", -1) == level:
			return handicap_id
	return "prince"  # Default

# Corporation accessors
func get_corporation(corporation_id: String) -> Dictionary:
	return corporations.get(corporation_id, {})

func get_corporation_name(corporation_id: String) -> String:
	var corp = get_corporation(corporation_id)
	return corp.get("name", corporation_id.capitalize())

func get_all_corporations() -> Dictionary:
	return corporations

func get_corporations_by_founder(gp_type: String) -> Array:
	var result = []
	for corp_id in corporations:
		if corp_id.begins_with("_"):
			continue
		var corp = corporations[corp_id]
		if corp.get("founded_by", "") == gp_type:
			result.append(corp_id)
	return result

# Espionage mission accessors
func get_espionage_mission(mission_id: String) -> Dictionary:
	return espionage_missions.get(mission_id, {})

func get_espionage_mission_name(mission_id: String) -> String:
	var mission = get_espionage_mission(mission_id)
	return mission.get("name", mission_id.capitalize())

func get_all_espionage_missions() -> Dictionary:
	return espionage_missions

func get_espionage_missions_by_target_type(target_type: String) -> Array:
	var result = []
	for mission_id in espionage_missions:
		if mission_id.begins_with("_"):
			continue
		var mission = espionage_missions[mission_id]
		if mission.get("target_type", "") == target_type:
			result.append(mission_id)
	return result

func get_espionage_missions_requiring_spy() -> Array:
	var result = []
	for mission_id in espionage_missions:
		if mission_id.begins_with("_"):
			continue
		var mission = espionage_missions[mission_id]
		if mission.get("requires_spy_in_city", false):
			result.append(mission_id)
	return result

# Project accessors
func get_project(project_id: String) -> Dictionary:
	return projects.get(project_id, {})

func get_project_name(project_id: String) -> String:
	var project = get_project(project_id)
	return project.get("name", project_id.capitalize())

func get_project_cost(project_id: String) -> int:
	var project = get_project(project_id)
	return project.get("cost", 0)

func get_all_projects() -> Dictionary:
	return projects

func get_projects_by_type(project_type: String) -> Array:
	var result = []
	for project_id in projects:
		if project_id.begins_with("_"):
			continue
		var project = projects[project_id]
		if project.get("type", "") == project_type:
			result.append(project_id)
	return result

func get_spaceship_parts() -> Array:
	var result = []
	for project_id in projects:
		if project_id.begins_with("_"):
			continue
		var project = projects[project_id]
		if project.get("spaceship_part", false):
			result.append(project_id)
	return result

# Random event accessors
func get_random_event(event_id: String) -> Dictionary:
	return random_events.get(event_id, {})

func get_random_event_name(event_id: String) -> String:
	var event = get_random_event(event_id)
	return event.get("name", event_id.capitalize())

func get_all_random_events() -> Dictionary:
	return random_events

func get_random_events_by_category(category: String) -> Array:
	var result = []
	for event_id in random_events:
		if event_id.begins_with("_"):
			continue
		var event = random_events[event_id]
		if event.get("category", "") == category:
			result.append(event_id)
	return result

# Vote/Resolution accessors
func get_vote_source(source_id: String) -> Dictionary:
	var sources = votes.get("vote_sources", {})
	return sources.get(source_id, {})

func get_all_vote_sources() -> Dictionary:
	return votes.get("vote_sources", {})

func get_resolution(resolution_id: String) -> Dictionary:
	var resolutions = votes.get("resolutions", {})
	return resolutions.get(resolution_id, {})

func get_resolution_name(resolution_id: String) -> String:
	var resolution = get_resolution(resolution_id)
	return resolution.get("name", resolution_id.capitalize())

func get_all_resolutions() -> Dictionary:
	return votes.get("resolutions", {})

func get_resolutions_by_source(source_id: String) -> Array:
	var result = []
	var resolutions = votes.get("resolutions", {})
	for res_id in resolutions:
		var res = resolutions[res_id]
		var sources = res.get("vote_source", [])
		if source_id in sources:
			result.append(res_id)
	return result
