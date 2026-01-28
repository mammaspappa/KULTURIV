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
var science_rate: float = 1.0  # Percentage of commerce going to science (0.0 to 1.0)

# Research
var researched_techs: Array[String] = []
var traded_techs: Array[String] = []  # Techs received via trade (cannot be re-traded)
var current_research: String = ""
var research_progress: int = 0
var future_tech_count: int = 0  # Number of times Future Tech has been completed
var future_tech_happiness: int = 0  # Bonus happiness from Future Tech
var future_tech_health: int = 0  # Bonus health from Future Tech

# Diplomacy
var at_war_with: Array[int] = []
var open_borders_with: Array[int] = []
var defensive_pact_with: Array[int] = []
var trade_embargo_with: Array[int] = []
var met_players: Array[int] = []
var diplomacy_memory: Dictionary = {}  # player_id -> Array of memory entries

# Vassalage
var vassals: Array[int] = []  # Player IDs of civilizations that are vassals to this player
var master_id: int = -1  # Player ID of master if this player is a vassal (-1 if independent)

# Religion
var state_religion: String = ""
var founded_religion: String = ""

# Golden Age
var golden_age_turns: int = 0
var golden_ages_count: int = 0  # Number of golden ages this player has had

# Civics
var civics: Dictionary = {}
var anarchy_turns: int = 0

# Leader traits (cached from DataManager)
var traits: Array[String] = []

# Entities (untyped to avoid circular dependency with Unit/City classes)
var units: Array = []
var cities: Array = []

# Elimination tracking
var has_ever_had_city: bool = false

# Score tracking
var score: int = 0

# AI personality (used by AI controller)
var ai_personality: Dictionary = {}

func _init() -> void:
	pass

func add_unit(unit) -> void:
	unit.player_owner = self
	units.append(unit)

func remove_unit(unit) -> void:
	units.erase(unit)

func add_city(city) -> void:
	city.player_owner = self
	cities.append(city)
	has_ever_had_city = true

func remove_city(city) -> void:
	cities.erase(city)

func has_tech(tech_id: String) -> bool:
	return tech_id in researched_techs

func has_trait(trait_id: String) -> bool:
	return trait_id in traits

func is_in_anarchy() -> bool:
	return anarchy_turns > 0

func can_research(tech_id: String) -> bool:
	# Check if tech is repeatable (like Future Tech)
	var tech_data = DataManager.get_tech(tech_id)
	if tech_data.get("repeatable", false):
		# For repeatable techs, just check prerequisites
		return DataManager.is_tech_available(tech_id, researched_techs)

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

	# Calculate overflow before completing (use effective cost with diffusion)
	var tech_cost = get_effective_tech_cost(current_research)
	var overflow = max(0, research_progress - tech_cost)

	var tech_data = DataManager.get_tech(current_research)
	var is_repeatable = tech_data.get("repeatable", false)

	# Handle repeatable techs (like Future Tech)
	if is_repeatable:
		# Apply bonuses
		var unlocks = tech_data.get("unlocks", {})
		var bonus = unlocks.get("bonus_per_completion", {})
		if bonus.has("happiness"):
			future_tech_happiness += bonus.happiness
		if bonus.has("health"):
			future_tech_health += bonus.health
		future_tech_count += 1

		# Only add to researched_techs once
		if current_research not in researched_techs:
			researched_techs.append(current_research)
	else:
		researched_techs.append(current_research)

	EventBus.research_completed.emit(self, current_research)

	# Check for first to discover bonus
	_check_first_to_discover(current_research)

	# Check for unlocks
	var unlocks = DataManager.get_tech_unlocks(current_research)
	EventBus.tech_unlocked.emit(self, current_research)

	current_research = ""
	# Preserve overflow beakers for next research (cap at 50% of a typical tech cost)
	research_progress = min(overflow, 500)

func get_research_output() -> int:
	var total = 0
	for city in cities:
		total += city.science_yield
	return total

## Calculate tech diffusion modifier
## Tech is cheaper if more civs already have it
func get_tech_diffusion_modifier(tech_id: String) -> float:
	if tech_id == "" or GameManager.players.size() <= 1:
		return 1.0

	# Count how many other players have this tech
	var count = 0
	var known_civs = 0
	for other_player in GameManager.players:
		if other_player.player_id == player_id:
			continue
		if not met_players.has(other_player.player_id):
			continue
		known_civs += 1
		if other_player.has_tech(tech_id):
			count += 1

	if known_civs == 0:
		return 1.0

	# Each civ with the tech reduces cost by 5%, max 30% reduction
	var reduction = min(count * 0.05, 0.30)
	return 1.0 - reduction

## Get effective tech cost including diffusion
func get_effective_tech_cost(tech_id: String) -> int:
	var base_cost = DataManager.get_tech_cost(tech_id)
	base_cost = int(base_cost * GameManager.get_speed_multiplier())
	var diffusion = get_tech_diffusion_modifier(tech_id)
	return int(base_cost * diffusion)

# Golden Age functions
func is_in_golden_age() -> bool:
	return golden_age_turns > 0

func start_golden_age(turns: int = 8) -> void:
	if golden_age_turns <= 0:
		golden_ages_count += 1
		EventBus.golden_age_started.emit(self)
	golden_age_turns += turns

func process_golden_age() -> void:
	if golden_age_turns > 0:
		golden_age_turns -= 1
		if golden_age_turns <= 0:
			EventBus.golden_age_ended.emit(self)

func get_golden_age_production_bonus() -> float:
	return 1.0 if is_in_golden_age() else 0.0

func get_golden_age_commerce_bonus() -> float:
	return 1.0 if is_in_golden_age() else 0.0

func get_total_population() -> int:
	var total = 0
	for city in cities:
		total += city.population
	return total

## Check if this player is the first to discover a technology and award bonus
func _check_first_to_discover(tech_id: String) -> void:
	# Skip if tech already discovered by someone
	if GameManager.first_to_discover.has(tech_id):
		return

	# Skip repeatable techs
	var tech_data = DataManager.get_tech(tech_id)
	if tech_data.get("repeatable", false):
		return

	# This player is first to discover!
	GameManager.first_to_discover[tech_id] = player_id

	# Calculate bonus based on tech era
	var era = tech_data.get("era", "ancient")
	var bonus = _get_first_to_discover_bonus(era, tech_id)

	# Apply bonus
	if bonus.get("gold", 0) > 0:
		gold += bonus.gold

	if bonus.get("beakers", 0) > 0:
		research_progress += bonus.beakers

	if bonus.get("great_person_points", 0) > 0 and not cities.is_empty():
		# Add GP points to capital
		var capital = cities[0]
		var current_gp = capital.get_meta("gp_progress", 0)
		capital.set_meta("gp_progress", current_gp + bonus.great_person_points)

	EventBus.first_to_discover.emit(self, tech_id, bonus)

func _get_first_to_discover_bonus(era: String, tech_id: String) -> Dictionary:
	# Base bonus scales by era
	var era_multipliers = {
		"ancient": 1.0,
		"classical": 1.5,
		"medieval": 2.0,
		"renaissance": 2.5,
		"industrial": 3.0,
		"modern": 3.5,
		"future": 4.0
	}
	var multiplier = era_multipliers.get(era, 1.0)

	# Special bonuses for landmark techs
	var special_techs = {
		"writing": {"gold": 50, "beakers": 25},
		"alphabet": {"gold": 75, "beakers": 50},
		"mathematics": {"gold": 50, "beakers": 50},
		"philosophy": {"gold": 50, "beakers": 50, "great_person_points": 50},
		"astronomy": {"gold": 100, "beakers": 75},
		"printing_press": {"gold": 100, "beakers": 100},
		"scientific_method": {"gold": 150, "beakers": 150},
		"physics": {"gold": 150, "beakers": 150, "great_person_points": 100},
		"computers": {"gold": 200, "beakers": 200}
	}

	if special_techs.has(tech_id):
		return special_techs[tech_id]

	# Default bonus
	return {
		"gold": int(25 * multiplier),
		"beakers": int(15 * multiplier)
	}

func get_num_cities() -> int:
	return cities.size()

func get_num_units() -> int:
	return units.size()

func has_settlers() -> bool:
	for unit in units:
		if unit.can_found_city():
			return true
	return false

func is_eliminated() -> bool:
	## A player is eliminated if they have no cities AND either:
	## - They had a city before (it was destroyed), OR
	## - They have no settlers (can't found a new city)
	if not cities.is_empty():
		return false
	return has_ever_had_city or not has_settlers()

func can_build_unit(unit_id: String) -> bool:
	var unit_data = DataManager.get_unit(unit_id)
	if unit_data.is_empty():
		return false

	# Check if this is a unique unit restricted to specific civilization
	var unit_civ = unit_data.get("civilization", "")
	if unit_civ != "" and unit_civ != civilization_id:
		return false  # Can only build unique units of your own civilization

	# Check if this unit is replaced by a unique unit for this civilization
	# (e.g., Rome can't build Swordsman because Praetorian replaces it)
	if _is_unit_replaced_by_unique(unit_id):
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

## Check if a base unit is replaced by a unique unit for this civilization
func _is_unit_replaced_by_unique(unit_id: String) -> bool:
	# Search all units to find if any unique unit replaces this one for our civ
	for check_unit_id in DataManager.units:
		var check_unit = DataManager.units[check_unit_id]
		if check_unit.get("civilization", "") == civilization_id:
			if check_unit.get("replaces", "") == unit_id:
				return true  # Our civ has a unique unit that replaces this one
	return false

func can_build_building(building_id: String) -> bool:
	var building_data = DataManager.get_building(building_id)
	if building_data.is_empty():
		return false

	# Check if this is a unique building restricted to specific civilization
	var building_civ = building_data.get("civilization", "")
	if building_civ != "" and building_civ != civilization_id:
		return false  # Can only build unique buildings of your own civilization

	# Check if this building is replaced by a unique building for this civilization
	if _is_building_replaced_by_unique(building_id):
		return false

	# Check tech requirement
	var required_tech = building_data.get("required_tech", "")
	if required_tech != "" and not has_tech(required_tech):
		return false

	return true

## Check if a base building is replaced by a unique building for this civilization
func _is_building_replaced_by_unique(building_id: String) -> bool:
	# Search all buildings to find if any unique building replaces this one for our civ
	for check_building_id in DataManager.buildings:
		var check_building = DataManager.buildings[check_building_id]
		if check_building.get("civilization", "") == civilization_id:
			if check_building.get("replaces", "") == building_id:
				return true  # Our civ has a unique building that replaces this one
	return false

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
	var had_open_borders = other_id in open_borders_with
	if value and other_id not in open_borders_with:
		open_borders_with.append(other_id)
	elif not value:
		open_borders_with.erase(other_id)

	# Emit signal when open borders end
	if had_open_borders and not value:
		var other_player = GameManager.get_player(other_id)
		if other_player:
			EventBus.open_borders_ended.emit(self, other_player)

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

# Vassal methods
func is_vassal() -> bool:
	return master_id >= 0

func is_vassal_of(other_id: int) -> bool:
	return master_id == other_id

func has_vassal(other_id: int) -> bool:
	return other_id in vassals

func become_vassal_of(master: int) -> void:
	if master_id >= 0:
		# Already a vassal, remove from old master first
		var old_master = GameManager.get_player(master_id)
		if old_master:
			old_master.vassals.erase(player_id)

	master_id = master
	var new_master = GameManager.get_player(master)
	if new_master:
		if player_id not in new_master.vassals:
			new_master.vassals.append(player_id)
		# Vassals inherit master's wars and peace
		at_war_with = new_master.at_war_with.duplicate()
		# End any wars with master
		at_war_with.erase(master)

	EventBus.vassal_created.emit(self, new_master)

func gain_independence() -> void:
	if master_id < 0:
		return

	var old_master = GameManager.get_player(master_id)
	if old_master:
		old_master.vassals.erase(player_id)

	var old_master_id = master_id
	master_id = -1
	EventBus.vassal_freed.emit(self, old_master_id)

# Border permission check
func can_enter_borders_of(other_id: int) -> bool:
	## Check if this player's units can enter the borders of another player
	if other_id == player_id:
		return true  # Own borders

	if is_at_war_with(other_id):
		return true  # At war - can enter enemy territory

	if has_open_borders_with(other_id):
		return true  # Open borders agreement

	if has_vassal(other_id):
		return true  # Vassal's borders are open to master

	# Check if other player is our master (vassals can enter master's territory)
	if is_vassal_of(other_id):
		return true

	return false

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
		"traded_techs": traded_techs,
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
		"has_ever_had_city": has_ever_had_city,
		"science_rate": science_rate,
		"vassals": vassals,
		"master_id": master_id,
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
	traded_techs.assign(data.get("traded_techs", []))
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
	has_ever_had_city = data.get("has_ever_had_city", false)
	science_rate = data.get("science_rate", 1.0)
	vassals.assign(data.get("vassals", []))
	master_id = data.get("master_id", -1)
