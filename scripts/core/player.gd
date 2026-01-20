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
var trade_embargo_with: Array[int] = []
var met_players: Array[int] = []
var diplomacy_memory: Dictionary = {}  # player_id -> Array of memory entries

# Religion
var state_religion: String = ""
var founded_religion: String = ""

# Civics
var civics: Dictionary = {}
var anarchy_turns: int = 0

# Leader traits (cached from DataManager)
var traits: Array[String] = []

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

func has_trait(trait_id: String) -> bool:
	return trait_id in traits

func is_in_anarchy() -> bool:
	return anarchy_turns > 0

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

# Diplomacy methods
func is_at_war_with(other_id: int) -> bool:
	return other_id in at_war_with

func declare_war_on(other_id: int) -> void:
	if other_id not in at_war_with:
		at_war_with.append(other_id)
	# End treaties
	open_borders_with.erase(other_id)
	defensive_pact_with.erase(other_id)

func make_peace_with(other_id: int) -> void:
	at_war_with.erase(other_id)

func has_open_borders_with(other_id: int) -> bool:
	return other_id in open_borders_with

func set_open_borders(other_id: int, value: bool) -> void:
	if value and other_id not in open_borders_with:
		open_borders_with.append(other_id)
	elif not value:
		open_borders_with.erase(other_id)

func has_defensive_pact_with(other_id: int) -> bool:
	return other_id in defensive_pact_with

func set_defensive_pact(other_id: int, value: bool) -> void:
	if value and other_id not in defensive_pact_with:
		defensive_pact_with.append(other_id)
	elif not value:
		defensive_pact_with.erase(other_id)

func has_trade_embargo_with(other_id: int) -> bool:
	return other_id in trade_embargo_with

func set_trade_embargo(other_id: int, value: bool) -> void:
	if value and other_id not in trade_embargo_with:
		trade_embargo_with.append(other_id)
	elif not value:
		trade_embargo_with.erase(other_id)

func get_relationship(other_id: int) -> String:
	## Returns relationship status: "friendly", "pleased", "cautious", "annoyed", "furious"
	if is_at_war_with(other_id):
		return "furious"

	# Calculate attitude based on various factors
	var attitude = _calculate_attitude(other_id)

	if attitude >= 8:
		return "friendly"
	elif attitude >= 4:
		return "pleased"
	elif attitude >= -3:
		return "cautious"
	elif attitude >= -7:
		return "annoyed"
	else:
		return "furious"

func _calculate_attitude(other_id: int) -> int:
	var attitude = 0

	# Base attitude from leader personality (if AI)
	if not is_human:
		var leader_data = DataManager.get_leader(leader_id) if DataManager else {}
		attitude += leader_data.get("base_attitude", 0)

	# Shared religion bonus
	var other = GameManager.get_player(other_id) if GameManager else null
	if other and state_religion != "" and state_religion == other.state_religion:
		attitude += 2

	# Treaty bonuses
	if has_open_borders_with(other_id):
		attitude += 1
	if has_defensive_pact_with(other_id):
		attitude += 2

	# Shared enemies
	if other:
		for enemy_id in at_war_with:
			if enemy_id in other.at_war_with:
				attitude += 1

	# Memory effects (from DiplomacySystem)
	if DiplomacySystem:
		attitude += DiplomacySystem.get_memory_attitude(player_id, other_id)

	return attitude

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
		"trade_embargo_with": trade_embargo_with,
		"met_players": met_players,
		"state_religion": state_religion,
		"founded_religion": founded_religion,
		"civics": civics,
		"anarchy_turns": anarchy_turns,
		"traits": traits,
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
	trade_embargo_with.assign(data.get("trade_embargo_with", []))
	met_players.assign(data.get("met_players", []))
	state_religion = data.get("state_religion", "")
	founded_religion = data.get("founded_religion", "")
	civics = data.get("civics", {})
	anarchy_turns = data.get("anarchy_turns", 0)
	traits.assign(data.get("traits", []))
