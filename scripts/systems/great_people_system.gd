extends Node
## Handles great people generation and abilities.

const UnitClass = preload("res://scripts/entities/unit.gd")

# Great person types
enum GreatPersonType {
	GREAT_PROPHET,
	GREAT_ARTIST,
	GREAT_SCIENTIST,
	GREAT_MERCHANT,
	GREAT_ENGINEER,
	GREAT_GENERAL
}

# Great person point requirements (increases with each GP born)
const BASE_GP_THRESHOLD = 100
const GP_THRESHOLD_INCREASE = 50

# Track great people born per player
var great_people_born: Dictionary = {}  # player_id -> count

func _ready() -> void:
	# Connect to turn events
	EventBus.all_turns_completed.connect(_on_turn_completed)

## Process great person points for all cities
func process_great_people() -> void:
	for city in GameManager.get_all_cities():
		_process_city_gp(city)

func _process_city_gp(city) -> void:
	if city == null or city.player_owner == null:
		return

	# Calculate GP points generated this turn
	var gp_points = _calculate_gp_points(city)

	if gp_points <= 0:
		return

	# Get or initialize city GP progress (stored in city as custom property)
	if not city.has_meta("gp_progress"):
		city.set_meta("gp_progress", 0)
	if not city.has_meta("gp_type_weights"):
		city.set_meta("gp_type_weights", {})

	var current_progress = city.get_meta("gp_progress")
	current_progress += gp_points
	city.set_meta("gp_progress", current_progress)

	# Track type weights
	var weights = city.get_meta("gp_type_weights")
	_add_gp_weights(city, weights, gp_points)
	city.set_meta("gp_type_weights", weights)

	# Check for great person birth
	var threshold = _get_threshold(city.player_owner)
	if current_progress >= threshold:
		_birth_great_person(city, weights)
		city.set_meta("gp_progress", 0)
		city.set_meta("gp_type_weights", {})

func _calculate_gp_points(city) -> int:
	var points = 0

	# Get GP points from city's specialists and buildings
	var gp_breakdown = city.get_great_people_points()
	for gp_type in gp_breakdown:
		points += gp_breakdown[gp_type]

	# Settled great people bonus
	if city.has_meta("settled_great_people"):
		var settled = city.get_meta("settled_great_people")
		points += settled.size() * 2

	# Civic modifier (Pacifism: +100% GP rate in cities with state religion)
	if city.player_owner:
		var civic_effects = CivicsSystem.get_civic_effects(city.player_owner)
		var gp_modifier = civic_effects.get("great_people_modifier", 0)
		if gp_modifier > 0 and civic_effects.get("requires_state_religion", false):
			# Only applies if city has state religion
			if city.player_owner.state_religion in city.religions:
				points = int(points * (1.0 + gp_modifier / 100.0))

	return points

func _add_gp_weights(city, weights: Dictionary, _points: int) -> void:
	# Get GP type weights from city specialists
	var gp_breakdown = city.get_great_people_points()

	for gp_type in gp_breakdown:
		weights[gp_type] = weights.get(gp_type, 0) + gp_breakdown[gp_type]

	# Also add building-based weights for buildings without specific GP types
	for building_id in city.buildings:
		var effects = DataManager.get_building_effects(building_id)
		var building_gp = effects.get("great_person_points", 0)
		var building_gp_type = effects.get("great_person_type", "")

		# If building doesn't specify a type, infer from building category
		if building_gp > 0 and building_gp_type == "":
			if building_id in ["library", "university", "academy", "oxford_university"]:
				weights["scientist"] = weights.get("scientist", 0) + building_gp
			elif building_id in ["market", "bank", "grocer", "wall_street"]:
				weights["merchant"] = weights.get("merchant", 0) + building_gp
			elif building_id in ["forge", "factory", "ironworks"]:
				weights["engineer"] = weights.get("engineer", 0) + building_gp
			elif building_id in ["monument", "theater", "colosseum"]:
				weights["artist"] = weights.get("artist", 0) + building_gp
			elif building_id in ["temple", "monastery", "cathedral"]:
				weights["prophet"] = weights.get("prophet", 0) + building_gp

func _get_threshold(player) -> int:
	var player_id = player.player_id
	var born_count = great_people_born.get(player_id, 0)
	return BASE_GP_THRESHOLD + (born_count * GP_THRESHOLD_INCREASE)

func _birth_great_person(city, weights: Dictionary) -> void:
	if city == null or city.player_owner == null:
		return

	# Determine type based on weights
	var gp_type = _determine_gp_type(weights)

	# Increment counter
	var player_id = city.player_owner.player_id
	great_people_born[player_id] = great_people_born.get(player_id, 0) + 1

	# Create the great person as a unit
	var unit_id = _get_gp_unit_id(gp_type)
	if unit_id != "":
		var unit = UnitClass.new(unit_id, city.grid_position)
		city.player_owner.add_unit(unit)

		if GameManager.game_world:
			GameManager.game_world.add_child(unit)

		EventBus.unit_created.emit(unit)

	EventBus.great_person_born.emit(city, gp_type)

func _determine_gp_type(weights: Dictionary) -> String:
	if weights.is_empty():
		# Default to random
		var types = ["prophet", "artist", "scientist", "merchant", "engineer"]
		return types[randi() % types.size()]

	# Weighted random selection
	var total: int = 0
	for weight in weights.values():
		total += int(weight)

	var roll = randi() % max(1, total)
	var current = 0

	for gp_type in weights:
		current += weights[gp_type]
		if roll < current:
			return gp_type

	return "scientist"  # Default

func _get_gp_unit_id(gp_type: String) -> String:
	match gp_type:
		"prophet":
			return "great_prophet"
		"artist":
			return "great_artist"
		"scientist":
			return "great_scientist"
		"merchant":
			return "great_merchant"
		"engineer":
			return "great_engineer"
		_:
			return "great_scientist"

## Use great person abilities
func use_great_person(unit, ability: String) -> bool:
	if unit == null or unit.player_owner == null:
		return false

	var player = unit.player_owner
	var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
	var city = GameManager.get_city_at(unit.grid_position)

	match ability:
		"settle":
			return _settle_great_person(unit, city)
		"golden_age":
			return _start_golden_age(unit, player)
		"discover_tech":
			return _discover_tech(unit, player)
		"trade_mission":
			return _trade_mission(unit, player, city)
		"hurry_production":
			return _hurry_production(unit, city)
		"spread_religion":
			return _spread_religion(unit, city)
		"culture_bomb":
			return _culture_bomb(unit, tile)
		"build_shrine":
			return _build_shrine(unit, city)
		_:
			return false

func _settle_great_person(unit, city) -> bool:
	if city == null or city.player_owner != unit.player_owner:
		return false

	# Track settled great people
	if not city.has_meta("settled_great_people"):
		city.set_meta("settled_great_people", [])

	var settled = city.get_meta("settled_great_people")
	settled.append(unit.unit_id)
	city.set_meta("settled_great_people", settled)

	# Remove unit
	unit.die()
	return true

func _start_golden_age(unit, player) -> bool:
	# Calculate golden age length (8 base, increases with number of golden ages)
	var base_turns = 8
	var turns = base_turns - player.golden_ages_count  # Each golden age is shorter
	turns = max(turns, 4)  # Minimum 4 turns

	player.start_golden_age(turns)

	# Remove unit
	unit.die()
	return true

func _discover_tech(unit, player) -> bool:
	# Get available techs
	var available = []
	for tech_id in DataManager.techs:
		if player.can_research(tech_id):
			available.append(tech_id)

	if available.is_empty():
		return false

	# Research a random available tech
	var tech = available[randi() % available.size()]
	player.researched_techs.append(tech)
	EventBus.research_completed.emit(player, tech)

	# Remove unit
	unit.die()
	return true

func _trade_mission(unit, player, city) -> bool:
	# Must be in a foreign city
	if city == null or city.player_owner == player:
		return false

	# Gain gold based on distance from capital
	var capital = player.cities[0] if not player.cities.is_empty() else null
	var gold = 500  # Base gold

	if capital:
		var distance = GridUtils.chebyshev_distance(city.grid_position, capital.grid_position)
		gold += distance * 50

	player.gold += gold

	# Remove unit
	unit.die()
	return true

func _hurry_production(unit, city) -> bool:
	if city == null or city.player_owner != unit.player_owner:
		return false

	if city.current_production == "":
		return false

	# Complete current production instantly
	var cost = city.get_production_cost()
	city.production_progress = cost

	# Remove unit
	unit.die()
	return true

func _spread_religion(unit, city) -> bool:
	if city == null:
		return false

	# Spread founder's religion
	var founder_religion = unit.player_owner.founded_religion if unit.player_owner else ""

	if founder_religion == "":
		# Spread most common religion
		var religions = {}
		for c in GameManager.get_all_cities():
			for r in c.religions:
				religions[r] = religions.get(r, 0) + 1

		if religions.is_empty():
			return false

		var best_religion = ""
		var best_count = 0
		for r in religions:
			if religions[r] > best_count:
				best_count = religions[r]
				best_religion = r

		founder_religion = best_religion

	if founder_religion != "" and founder_religion not in city.religions:
		ReligionSystem.spread_religion(city, founder_religion)

	# Remove unit
	unit.die()
	return true

func _culture_bomb(unit, tile) -> bool:
	if tile == null or unit.player_owner == null:
		return false

	# Claim this tile and surrounding tiles
	var positions = [tile.grid_position]
	positions.append_array(GridUtils.get_neighbors(tile.grid_position))

	for pos in positions:
		var t = GameManager.hex_grid.get_tile(pos) if GameManager.hex_grid else null
		if t and t.tile_owner != unit.player_owner:
			# Find nearest city to assign
			var nearest_city = null
			var nearest_dist = INF

			for city in unit.player_owner.cities:
				var dist = GridUtils.chebyshev_distance(pos, city.grid_position)
				if dist < nearest_dist:
					nearest_dist = dist
					nearest_city = city

			if nearest_city:
				t.tile_owner = unit.player_owner
				t.city_owner = nearest_city
				if pos not in nearest_city.territory:
					nearest_city.territory.append(pos)
				t.update_visuals()

	# Remove unit
	unit.die()
	return true

func _build_shrine(unit, city) -> bool:
	if city == null or city.player_owner != unit.player_owner:
		return false

	# Must be in the holy city
	if city.holy_city_of == "":
		return false

	# Get the shrine building for this religion
	var religion_data = DataManager.get_religion(city.holy_city_of)
	var shrine_building = religion_data.get("shrine", "")
	if shrine_building == "":
		return false

	# Check if shrine already exists
	if city.has_building(shrine_building):
		return false

	# Build the shrine
	city.add_building(shrine_building)
	EventBus.city_production_completed.emit(city, shrine_building)

	# Remove unit
	unit.die()
	return true

## Check if Great Prophet can build a shrine in this city
func can_build_shrine(unit, city) -> bool:
	if city == null or unit == null:
		return false
	if city.player_owner != unit.player_owner:
		return false
	if city.holy_city_of == "":
		return false

	var religion_data = DataManager.get_religion(city.holy_city_of)
	var shrine_building = religion_data.get("shrine", "")
	if shrine_building == "":
		return false

	return not city.has_building(shrine_building)

## Get available abilities for a great person unit
func get_available_abilities(unit) -> Array:
	if unit == null:
		return []

	var abilities = []
	var unit_id = unit.unit_id

	match unit_id:
		"great_prophet":
			abilities = ["settle", "golden_age", "spread_religion", "build_shrine"]
		"great_artist":
			abilities = ["settle", "golden_age", "culture_bomb"]
		"great_scientist":
			abilities = ["settle", "golden_age", "discover_tech"]
		"great_merchant":
			abilities = ["settle", "golden_age", "trade_mission"]
		"great_engineer":
			abilities = ["settle", "golden_age", "hurry_production"]
		"great_general":
			abilities = ["settle", "golden_age"]

	return abilities

func _on_turn_completed(_turn: int) -> void:
	process_great_people()
