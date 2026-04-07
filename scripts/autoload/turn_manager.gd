extends Node
## Manages turn progression and per-turn processing for all players.

const UnitClass = preload("res://scripts/entities/unit.gd")
const PathfindingClass = preload("res://scripts/map/pathfinding.gd")

signal turn_processing_started()
signal turn_processing_finished()

var current_turn: int = 1
var current_year: int = -4000
var is_processing: bool = false
var game_ended: bool = false

# Year progression (Civ4 style)
const YEAR_PROGRESSION = [
	{"until_turn": 50, "years_per_turn": 40},    # Ancient: 40 years/turn
	{"until_turn": 100, "years_per_turn": 25},   # Classical: 25 years/turn
	{"until_turn": 150, "years_per_turn": 20},   # Medieval: 20 years/turn
	{"until_turn": 200, "years_per_turn": 10},   # Renaissance: 10 years/turn
	{"until_turn": 280, "years_per_turn": 5},    # Industrial: 5 years/turn
	{"until_turn": 350, "years_per_turn": 2},    # Modern: 2 years/turn
	{"until_turn": 9999, "years_per_turn": 1},   # Future: 1 year/turn
]

func _ready() -> void:
	EventBus.player_eliminated.connect(_on_player_eliminated)

func _on_player_eliminated(player) -> void:
	# Immediately check for conquest/domination victory when a player is eliminated
	var victory = VictorySystem.check_victory()
	if not victory.is_empty() and victory.get("achieved", false):
		game_ended = true
		if GameManager.current_game_state:
			GameManager.current_game_state.victory_achieved = true
			GameManager.current_game_state.victory_type = victory.type
			GameManager.current_game_state.winner_player_id = victory.player.player_id
		EventBus.victory_achieved.emit(victory.player, victory.type)
		EventBus.game_over.emit(victory.player, victory.type)

func start_game() -> void:
	current_turn = 1
	current_year = -4000
	game_ended = false
	_update_all_connectivity()
	_start_turn_for_player(GameManager.get_current_player())

func end_turn() -> void:
	if is_processing or game_ended:
		return

	var current_player = GameManager.get_current_player()
	if current_player == null:
		return

	# End current player's turn
	_end_turn_for_player(current_player)

	# Move to next player
	GameManager.current_player_index += 1

	# Check if all players have gone
	if GameManager.current_player_index >= GameManager.players.size():
		_complete_round()
	else:
		# Start next player's turn
		_start_turn_for_player(GameManager.get_current_player())

func _start_turn_for_player(player) -> void:
	if player == null or game_ended:
		return

	# Base barbarian player (id=-1): only refresh movement, skip all civ systems
	# Spawned barbarian civs (id >= 0) get full turn processing like normal AI
	if player.civilization_id == "barbarian" and player.player_id == -1:
		for unit in player.units:
			unit.refresh_movement()
			unit.has_acted = false
		# Process barbarian unit AI directly (simple attack/pillage logic)
		BarbarianSystem._process_barbarian_ai()
		call_deferred("end_turn")
		return

	# Process worker builds first (before refreshing movement)
	for unit in player.units:
		if unit.current_order == UnitClass.UnitOrder.BUILD:
			ImprovementSystem.process_build(unit)

	# Refresh unit movement points
	for unit in player.units:
		unit.refresh_movement()
		unit.has_acted = false

	# Process automated workers
	for unit in player.units:
		if unit.current_order == UnitClass.UnitOrder.AUTOMATE:
			unit.process_automation()

	# Process GOTO orders (multi-turn movement)
	for unit in player.units:
		if unit.current_order == UnitClass.UnitOrder.GOTO and unit.can_move():
			_process_goto_order(unit)

	# Process cities
	for city in player.cities:
		_process_city_turn_start(city)

	# Process gold (sum gold_yield from all cities)
	_process_gold(player)

	# Process research
	_process_research(player)

	# Process espionage (from buildings + commerce slider)
	_process_espionage(player)

	# Refresh visibility for the player (fog of war)
	VisibilitySystem.refresh_visibility(player)
	VisibilitySystem.update_all_tile_visuals()

	# Emit turn_started AFTER movement is refreshed so UI updates correctly
	EventBus.turn_started.emit(current_turn, player)

	# If human player has no research, open tech tree
	if player.is_human and player.current_research == "":
		EventBus.show_tech_tree.emit()

	# If AI, execute AI turn
	if not player.is_human:
		_execute_ai_turn(player)
		# Auto-advance to next player after AI turn
		call_deferred("end_turn")

func _end_turn_for_player(player) -> void:
	if player == null:
		return

	EventBus.turn_ended.emit(current_turn, player)

	# Process golden age countdown
	player.process_golden_age()

	# Heal units in friendly territory or fortified
	for unit in player.units:
		_process_unit_healing(unit)

func _complete_round() -> void:
	# All players have taken their turn
	GameManager.current_player_index = 0
	_ai_bonus_cache = {}  # Clear difficulty bonus cache each round

	# Update trade connectivity (road/river/coast BFS from capital)
	_update_all_connectivity()

	# Process culture radiation and tile ownership
	_process_culture_ownership()

	# Check culture flipping
	_check_culture_flipping()

	# Advance turn counter
	current_turn += 1
	_advance_year()

	EventBus.all_turns_completed.emit(current_turn)

	# Check for victory conditions
	var victory = VictorySystem.check_victory()
	if not victory.is_empty() and victory.get("achieved", false):
		if GameManager.current_game_state:
			GameManager.current_game_state.victory_achieved = true
			GameManager.current_game_state.victory_type = victory.type
			GameManager.current_game_state.winner_player_id = victory.player.player_id
		game_ended = true
		EventBus.victory_achieved.emit(victory.player, victory.type)
		EventBus.game_over.emit(victory.player, victory.type)
		return  # Don't start new round if game is over

	# Start next round with first player
	_start_turn_for_player(GameManager.get_current_player())

func _advance_year() -> void:
	var years_to_add = 1
	# Scale turn thresholds by game speed so Quick reaches Modern era faster
	var speed = GameManager.get_speed_multiplier()
	for progression in YEAR_PROGRESSION:
		var scaled_turn = int(progression.until_turn * speed)
		if current_turn <= scaled_turn:
			years_to_add = progression.years_per_turn
			break

	current_year += years_to_add

func _process_city_turn_start(city) -> void:
	# Calculate yields
	city.calculate_yields()

	# Check if building a settler (food → production conversion)
	var building_settler = false
	if city.current_production != "":
		var unit_data = DataManager.get_unit(city.current_production)
		if not unit_data.is_empty() and unit_data.get("food_cost", 0) > 0:
			building_settler = true

	# Process food and growth
	if building_settler:
		# Civ4 BTS: food surplus goes to production, city does NOT grow
		# Food deficit still causes starvation
		if city.food_surplus < 0:
			city.food_stockpile += city.food_surplus
			if city.food_stockpile < 0:
				city.starve()
		# Positive food surplus is NOT added to stockpile (goes to production below)
	else:
		var food_to_add = city.food_surplus
		# Apply AI difficulty growth bonus
		if city.player_owner and not city.player_owner.is_human and food_to_add > 0:
			var ai_bonuses = _get_ai_difficulty_bonuses()
			food_to_add = int(food_to_add * ai_bonuses.get("growth_percent", 100) / 100.0)
		city.food_stockpile += food_to_add
		if city.food_stockpile >= city.food_needed_for_growth():
			city.grow()
		elif city.food_stockpile < 0:
			city.starve()

	# Process resistance
	if city.resistance_turns > 0:
		city.resistance_turns -= 1
		return  # No production, growth, or culture during resistance

	# Process production
	if city.current_production != "":
		var production = city.production_yield
		# Settlers: add food surplus as bonus production (Civ4 BTS mechanic)
		if building_settler and city.food_surplus > 0:
			production += city.food_surplus

		var is_unit = not DataManager.get_unit(city.current_production).is_empty()
		var building_data = DataManager.get_building(city.current_production) if not is_unit else {}
		var is_wonder = building_data.get("wonder_type", "") != ""

		# BTS: Stone/Marble give +50% wonder production
		if is_wonder and city.player_owner:
			var wonder_resource_bonus = 0.0
			for res_id in ["stone", "marble"]:
				if city.player_owner.has_resource(res_id):
					var res_data = DataManager.get_resource(res_id)
					wonder_resource_bonus += res_data.get("wonder_bonus", 0.0)
			if wonder_resource_bonus > 0.0:
				production = int(production * (1.0 + wonder_resource_bonus))

		# BTS: Industrious trait gives +50% wonder production
		if is_wonder and city.player_owner and city.player_owner.has_trait("industrious"):
			production = int(production * 1.5)

		# BTS: Expansive trait gives +50% settler and worker production
		if is_unit and city.player_owner and city.player_owner.has_trait("expansive"):
			if city.current_production in ["settler", "worker"]:
				production = int(production * 1.5)

		# Apply AI difficulty production bonus
		if city.player_owner and not city.player_owner.is_human:
			var ai_bonuses = _get_ai_difficulty_bonuses()
			var train_pct = ai_bonuses.get("train_percent", 100) / 100.0
			var construct_pct = ai_bonuses.get("construct_percent", 100) / 100.0
			if is_unit:
				production = int(production * train_pct)
			else:
				production = int(production * construct_pct)
		city.production_progress += production
		var cost = city.get_production_cost()
		if city.production_progress >= cost:
			city.complete_production()

	# Process culture
	city.culture += city.culture_yield
	city.radiate_culture()  # BTS-style culture radiation to tiles
	city.check_border_expansion()

func _process_gold(player) -> void:
	# Calculate gold per turn from all cities
	var total_gold = 0
	for city in player.cities:
		total_gold += city.gold_yield

	# --- City Maintenance (distance + city count) ---
	var num_cities = player.cities.size()
	var capital_pos = player.cities[0].grid_position if not player.cities.is_empty() else Vector2i.ZERO
	# Find actual capital
	for city in player.cities:
		if "palace" in city.buildings:
			capital_pos = city.grid_position
			break

	# Find secondary capitals (Forbidden Palace, Versailles)
	var palace_positions = [capital_pos]
	for city in player.cities:
		for building_id in city.buildings:
			var effects = DataManager.get_building_effects(building_id)
			if effects.get("second_palace", false):
				palace_positions.append(city.grid_position)

	var city_maintenance = 0
	for city in player.cities:
		# Distance maintenance: use nearest capital/palace (BTS mechanic)
		var min_dist = INF
		for palace_pos in palace_positions:
			var d = GridUtils.chebyshev_distance(city.grid_position, palace_pos)
			if d < min_dist:
				min_dist = d
		var dist_cost = int(min_dist * 0.5)

		# Check for civic that removes distance maintenance (State Property)
		if CivicsSystem and CivicsSystem.has_civic_effect(player, "no_distance_maintenance"):
			dist_cost = 0

		# Courthouse/maintenance_reduction buildings reduce maintenance by 50%
		for building_id in city.buildings:
			var effects = DataManager.get_building_effects(building_id)
			var reduction = effects.get("maintenance_reduction", 0.0)
			if reduction > 0:
				dist_cost = int(dist_cost * (1.0 - reduction))

		# City count maintenance: 0.5 gold per total city
		var count_cost = int((num_cities - 1) * 0.5)

		city_maintenance += dist_cost + count_cost

	# --- Unit Supply Costs ---
	var military_count = 0
	for unit in player.units:
		if DataManager.get_unit_strength(unit.unit_id) > 0:
			military_count += 1

	var free_units = num_cities + 2  # Base free supply
	# Civic bonuses for free units
	if CivicsSystem:
		var civic_effects = CivicsSystem.get_civic_effects(player)
		free_units += civic_effects.get("free_units", 0)

	var excess_units = max(0, military_count - free_units)
	var unit_supply_cost = excess_units  # 1 gold per excess unit

	# --- Inflation (BTS-style: gradual, normalized by game speed so Marathon doesn't over-inflate) ---
	var normalized_turn = current_turn / GameManager.get_speed_multiplier()
	var inflation_rate = min(1.0 + normalized_turn * 0.001, 1.5)
	city_maintenance = int(city_maintenance * inflation_rate)
	unit_supply_cost = int(unit_supply_cost * inflation_rate)

	# --- War Weariness ---
	if player.at_war_with.size() > 0:
		player.war_weariness += player.at_war_with.size()
	else:
		player.war_weariness = max(0, player.war_weariness - 2)

	# --- Civic Upkeep (BTS: scales by number of cities and upkeep level) ---
	var civic_upkeep = 0
	if CivicsSystem:
		civic_upkeep = CivicsSystem.get_civic_upkeep(player)
		# BTS Organized trait: -50% civic upkeep
		if player.has_trait("organized"):
			civic_upkeep = civic_upkeep / 2

	# --- Corporation Maintenance ---
	var corp_maintenance = 0
	if CorporationSystem:
		corp_maintenance = CorporationSystem.calculate_player_maintenance(player)

	# --- Total ---
	var total_costs = city_maintenance + unit_supply_cost + civic_upkeep + corp_maintenance
	player.gold_per_turn = total_gold - total_costs

	# Add to player's gold treasury
	player.gold += player.gold_per_turn

	# Gold deficit handling: disband excess military units if bankrupt
	if player.gold < 0:
		# Disband cheapest military unit to recover
		var weakest_unit = null
		var weakest_strength = 999
		for unit in player.units:
			var strength = DataManager.get_unit_strength(unit.unit_id)
			if strength > 0 and strength < weakest_strength:
				# Don't disband units in cities (garrison)
				if GameManager.get_city_at(unit.grid_position) == null:
					weakest_strength = strength
					weakest_unit = unit
		if weakest_unit:
			weakest_unit.die()
			EventBus.notification_added.emit("%s disbanded a unit due to bankruptcy!" % player.player_name)
		player.gold = 0

## Get AI difficulty bonuses (cached per round)
var _ai_bonus_cache: Dictionary = {}
func _get_ai_difficulty_bonuses() -> Dictionary:
	if not _ai_bonus_cache.is_empty():
		return _ai_bonus_cache
	var handicap_id = DataManager.get_handicap_id_by_level(GameManager.difficulty)
	_ai_bonus_cache = DataManager.get_ai_bonuses(handicap_id)
	return _ai_bonus_cache

func _process_research(player) -> void:
	if player.current_research == "":
		return

	player.research_progress += player.get_research_output()
	var cost = DataManager.get_tech_cost(player.current_research)
	cost = int(cost * GameManager.get_speed_multiplier())

	if player.research_progress >= cost:
		player.complete_research()

func _process_espionage(player) -> void:
	if not EspionageSystem:
		return

	# Building-based espionage generation
	var esp_points = EspionageSystem.calculate_espionage_generation(player)

	# Commerce slider-based espionage
	for city in player.cities:
		if city.has_meta("espionage_from_commerce"):
			esp_points += city.get_meta("espionage_from_commerce")

	# Distribute espionage points to all known rivals (evenly for now)
	if esp_points > 0 and not player.met_players.is_empty():
		var per_target = max(1, esp_points / player.met_players.size())
		for target_id in player.met_players:
			EspionageSystem.add_espionage_points(player.player_id, target_id, per_target)

func _process_culture_ownership() -> void:
	# Resolve tile ownership based on culture values (BTS-style)
	if GameManager.hex_grid == null:
		return

	for x in range(GameManager.hex_grid.width):
		for y in range(GameManager.hex_grid.height):
			var tile = GameManager.hex_grid.get_tile(Vector2i(x, y))
			if tile == null or tile.tile_culture.size() < 2:
				continue  # Skip tiles with culture from only 1 player
			tile.resolve_culture_ownership()

func _check_culture_flipping() -> void:
	# Civ4 culture flip: if rival culture dominates a city's territory, chance it defects
	# BTS allows any city to flip but larger cities are much harder
	for player in GameManager.players:
		for city in player.cities.duplicate():  # duplicate to avoid modifying during iteration
			# Count rival tiles in city territory
			var rival_tiles = 0
			var total_tiles = city.territory.size()
			var dominant_rival = null
			var rival_tile_counts = {}

			for tile_pos in city.territory:
				var tile = GameManager.hex_grid.get_tile(tile_pos) if GameManager.hex_grid else null
				if tile and tile.tile_owner != null and tile.tile_owner != player:
					rival_tiles += 1
					var rid = tile.tile_owner.player_id
					rival_tile_counts[rid] = rival_tile_counts.get(rid, 0) + 1

			if total_tiles == 0:
				continue

			# Need >75% rival culture to have flip chance
			if float(rival_tiles) / total_tiles < 0.75:
				continue

			# Find dominant rival
			var max_count = 0
			for rid in rival_tile_counts:
				if rival_tile_counts[rid] > max_count:
					max_count = rival_tile_counts[rid]
					dominant_rival = GameManager.get_player(rid)

			if dominant_rival == null:
				continue

			# Garrison reduces flip chance
			var garrison = GameManager.get_units_at(city.grid_position)
			var garrison_count = 0
			for u in garrison:
				if u.player_owner == player and u.get_strength() > 0:
					garrison_count += 1

			# Flip chance scales inversely with population (BTS: larger cities harder to flip)
			var base_chance = 0.05 / max(1, city.population - 2)
			var flip_chance = base_chance - garrison_count * 0.02
			if randf() < flip_chance:
				# City flips to rival
				city.transfer_to(dominant_rival)
				city.resistance_turns = 0
				city.calculate_yields()
				EventBus.notification_added.emit("%s has defected to %s!" % [city.city_name, dominant_rival.player_name])

func _process_goto_order(unit) -> void:
	if unit.order_target == Vector2i.ZERO or unit.grid_position == unit.order_target:
		unit.current_order = UnitClass.UnitOrder.NONE
		return

	var grid = GameManager.hex_grid
	if grid == null:
		return

	var pathfinder = PathfindingClass.new(grid, unit)
	var path = pathfinder.find_path_with_movement(unit.grid_position, unit.order_target, unit.movement_remaining)
	if not path.is_empty():
		unit.move_along_path(path)

	# Check if arrived
	if unit.grid_position == unit.order_target:
		unit.current_order = UnitClass.UnitOrder.NONE

func _process_unit_healing(unit) -> void:
	if unit.health >= unit.max_health:
		return

	var heal_amount = 0

	# Check if in city
	var city = GameManager.get_city_at(unit.grid_position)
	if city != null and city.player_owner == unit.player_owner:
		heal_amount = 20  # Heal 20% in friendly city
	elif unit.is_fortified:
		heal_amount = 10  # Heal 10% when fortified
	elif _is_in_friendly_territory(unit):
		heal_amount = 10  # Heal 10% in friendly territory
	else:
		heal_amount = 5   # Heal 5% in neutral/enemy territory

	unit.heal(heal_amount)

func _is_in_friendly_territory(unit) -> bool:
	if GameManager.hex_grid == null:
		return false
	var tile = GameManager.hex_grid.get_tile(unit.grid_position)
	if tile == null:
		return false
	return tile.tile_owner == unit.player_owner

func _execute_ai_turn(player) -> void:
	is_processing = true
	turn_processing_started.emit()

	# Use the AI controller for decision making
	AIController.execute_turn(player)

	is_processing = false
	turn_processing_finished.emit()

func get_year_string() -> String:
	if current_year < 0:
		return str(abs(current_year)) + " BC"
	else:
		return str(current_year) + " AD"

func get_era() -> String:
	if current_year < -1000:
		return "Ancient"
	elif current_year < 500:
		return "Classical"
	elif current_year < 1400:
		return "Medieval"
	elif current_year < 1700:
		return "Renaissance"
	elif current_year < 1900:
		return "Industrial"
	elif current_year < 2000:
		return "Modern"
	else:
		return "Future"

func _update_all_connectivity() -> void:
	for player in GameManager.players:
		if player.cities.is_empty():
			continue
		player.update_connectivity()
