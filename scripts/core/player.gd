class_name Player
extends RefCounted
## Represents a player (human or AI) in the game.

var player_id: int = 0
var player_name: String = ""
var civilization_id: String = ""
var leader_id: String = ""
var is_human: bool = false
var team: int = -1
var color: Color = Color.WHITE

# Resources
var gold: int = 0
var gold_per_turn: int = 0
var science_per_turn: int = 0

# Research
var researched_techs: Array[String] = []
var current_research: String = ""
var research_progress: int = 0

# Diplomacy
var at_war_with: Array[int] = []
var open_borders_with: Array[int] = []
var defensive_pact_with: Array[int] = []
var met_players: Array[int] = []

# Religion
var state_religion: String = ""
var founded_religion: String = ""

# Entities (untyped to avoid circular dependency with Unit/City classes)
var units: Array = []
var cities: Array = []

# Score tracking
var score: int = 0

# AI personality (used by AI controller)
var ai_personality: Dictionary = {}

func _init() -> void:
	pass

func add_unit(unit) -> void:
	unit.owner = self
	units.append(unit)

func remove_unit(unit) -> void:
	units.erase(unit)

func add_city(city) -> void:
	city.owner = self
	cities.append(city)

func remove_city(city) -> void:
	cities.erase(city)

func has_tech(tech_id: String) -> bool:
	return tech_id in researched_techs

func can_research(tech_id: String) -> bool:
	if has_tech(tech_id):
		return false
	return DataManager.is_tech_available(tech_id, researched_techs)

func start_research(tech_id: String) -> void:
	if can_research(tech_id):
		current_research = tech_id
		research_progress = 0
		EventBus.research_started.emit(self, tech_id)

func complete_research() -> void:
	if current_research == "":
		return

	researched_techs.append(current_research)
	EventBus.research_completed.emit(self, current_research)

	# Check for unlocks
	var unlocks = DataManager.get_tech_unlocks(current_research)
	EventBus.tech_unlocked.emit(self, current_research)

	current_research = ""
	research_progress = 0

func get_research_output() -> int:
	var total = 0
	for city in cities:
		total += city.science_yield
	return total

func get_total_population() -> int:
	var total = 0
	for city in cities:
		total += city.population
	return total

func get_num_cities() -> int:
	return cities.size()

func get_num_units() -> int:
	return units.size()

func can_build_unit(unit_id: String) -> bool:
	var unit_data = DataManager.get_unit(unit_id)
	if unit_data.is_empty():
		return false

	# Check tech requirement
	var required_tech = unit_data.get("required_tech", "")
	if required_tech != "" and not has_tech(required_tech):
		return false

	# Check resource requirement
	var required_resource = unit_data.get("required_resource", "")
	if required_resource != "" and not has_resource(required_resource):
		return false

	return true

func can_build_building(building_id: String) -> bool:
	var building_data = DataManager.get_building(building_id)
	if building_data.is_empty():
		return false

	# Check tech requirement
	var required_tech = building_data.get("required_tech", "")
	if required_tech != "" and not has_tech(required_tech):
		return false

	return true

func has_resource(resource_id: String) -> bool:
	# Check if any city has access to this resource
	for city in cities:
		if city.has_resource(resource_id):
			return true
	return false

func get_available_resources() -> Array:
	var resources = []
	for city in cities:
		for resource in city.available_resources:
			if resource not in resources:
				resources.append(resource)
	return resources

func calculate_score() -> int:
	var s = 0
	# Population
	s += get_total_population() * 2
	# Land (tiles owned)
	for city in cities:
		s += city.territory.size()
	# Techs
	s += researched_techs.size() * 4
	# Wonders (special buildings)
	for city in cities:
		for building in city.buildings:
			var b_data = DataManager.get_building(building)
			if b_data.get("is_wonder", false):
				s += 10
	score = s
	return s

func to_dict() -> Dictionary:
	return {
		"player_id": player_id,
		"player_name": player_name,
		"civilization_id": civilization_id,
		"leader_id": leader_id,
		"is_human": is_human,
		"team": team,
		"color": color.to_html(),
		"gold": gold,
		"researched_techs": researched_techs,
		"current_research": current_research,
		"research_progress": research_progress,
		"at_war_with": at_war_with,
		"open_borders_with": open_borders_with,
		"defensive_pact_with": defensive_pact_with,
		"met_players": met_players,
		"state_religion": state_religion,
		"founded_religion": founded_religion,
	}

func from_dict(data: Dictionary) -> void:
	player_id = data.get("player_id", 0)
	player_name = data.get("player_name", "")
	civilization_id = data.get("civilization_id", "")
	leader_id = data.get("leader_id", "")
	is_human = data.get("is_human", false)
	team = data.get("team", -1)
	color = Color(data.get("color", "#FFFFFF"))
	gold = data.get("gold", 0)
	researched_techs.assign(data.get("researched_techs", []))
	current_research = data.get("current_research", "")
	research_progress = data.get("research_progress", 0)
	at_war_with.assign(data.get("at_war_with", []))
	open_borders_with.assign(data.get("open_borders_with", []))
	defensive_pact_with.assign(data.get("defensive_pact_with", []))
	met_players.assign(data.get("met_players", []))
	state_religion = data.get("state_religion", "")
	founded_religion = data.get("founded_religion", "")
