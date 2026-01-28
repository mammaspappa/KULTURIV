extends Node
## Loads and provides access to all game data from JSON files.

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

# Data paths
const DATA_PATH = "res://data/"

func _ready() -> void:
	_load_all_data()

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

func _load_json(filename: String) -> Dictionary:
	var path = DATA_PATH + filename
	if not FileAccess.file_exists(path):
		push_warning("DataManager: File not found: " + path)
		return {}

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataManager: Failed to open: " + path)
		return {}

	var json_text = file.get_as_text()
	file.close()

	var json = JSON.new()
	var error = json.parse(json_text)
	if error != OK:
		push_error("DataManager: JSON parse error in " + filename + ": " + json.get_error_message())
		return {}

	return json.data

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
	var prereqs = get_tech_prerequisites(tech_id)
	if prereqs.is_empty():
		return true

	var tech = get_tech(tech_id)
	var prereq_type = tech.get("prereq_type", "AND")

	if prereq_type == "OR":
		for prereq in prereqs:
			if prereq in researched_techs:
				return true
		return false
	else:  # AND
		for prereq in prereqs:
			if prereq not in researched_techs:
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
