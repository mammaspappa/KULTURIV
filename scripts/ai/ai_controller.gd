extends Node
## AI controller for computer-controlled players.
## Uses leader personality (flavor values) to make decisions.
## Applies difficulty bonuses based on game settings.

const PathfindingClass = preload("res://scripts/map/pathfinding.gd")
const UnitClass = preload("res://scripts/entities/unit.gd")

# Flavor thresholds for decision making
const HIGH_FLAVOR = 7
const MEDIUM_FLAVOR = 4
const LOW_FLAVOR = 2

## Execute a full turn for an AI player
func execute_turn(player) -> void:
	if player.is_human:
		return

	# Get leader flavor values for personality-based decisions
	var flavor = _get_leader_flavor(player)

	# Process diplomacy first
	_process_diplomacy(player, flavor)

	# Process research
	_process_research(player, flavor)

	# Process espionage
	_process_espionage(player, flavor)

	# Process units
	for unit in player.units.duplicate():
		if unit == null or not is_instance_valid(unit):
			continue
		_process_unit_ai(unit, player, flavor)

	# Process cities
	for city in player.cities:
		_process_city_ai(city, player, flavor)

## Get leader flavor values
func _get_leader_flavor(player) -> Dictionary:
	var leader_data = DataManager.get_leader(player.leader_id)
	return leader_data.get("flavor", {
		"military": 5,
		"gold": 5,
		"science": 5,
		"culture": 5,
		"religion": 5,
		"expansion": 5,
		"growth": 5,
		"production": 5
	})

## Get difficulty bonuses for AI
func _get_ai_bonuses() -> Dictionary:
	var handicap_id = DataManager.get_handicap_id_by_level(GameManager.difficulty)
	return DataManager.get_ai_bonuses(handicap_id)

## Process AI diplomacy decisions
func _process_diplomacy(player, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)

	for other in GameManager.players:
		if other == player or other.player_id not in player.met_players:
			continue

		# Skip if at war
		if GameManager.is_at_war(player, other):
			_consider_peace(player, other, military_flavor)
			continue

		# Consider treaties
		_consider_treaties(player, other, flavor)

		# Consider trade
		_consider_trade(player, other, flavor)

		# Consider war
		_consider_war(player, other, flavor)

## Consider making peace
func _consider_peace(player, other, military_flavor: int) -> void:
	# Calculate power ratio
	var our_power = DiplomacySystem._calculate_power(player)
	var their_power = DiplomacySystem._calculate_power(other)

	# More likely to seek peace if losing
	if our_power < their_power * 0.7:
		# We're losing, try to make peace
		if other.is_human:
			# AI will accept peace offers from human more readily when losing
			return

		# Both AI - negotiate peace
		if their_power < our_power * 1.5:  # They're not crushing us
			GameManager.make_peace(player, other)
	elif military_flavor < MEDIUM_FLAVOR and our_power < their_power * 1.2:
		# Non-aggressive AI seeks peace when not winning decisively
		if randf() < 0.3:
			GameManager.make_peace(player, other)

## Consider treaties (open borders, defensive pact)
func _consider_treaties(player, other, flavor: Dictionary) -> void:
	var attitude = DiplomacySystem.calculate_attitude(player, other)

	# Open borders - easier to get
	if other.player_id not in player.open_borders_with:
		if attitude >= -2:  # Cautious or better
			var expansion_flavor = flavor.get("expansion", 5)
			if expansion_flavor >= MEDIUM_FLAVOR or attitude >= 3:
				# Propose open borders
				if not other.is_human:
					if DiplomacySystem.would_accept_proposal(player, other, "open_borders"):
						player.open_borders_with.append(other.player_id)
						other.open_borders_with.append(player.player_id)
						EventBus.open_borders_signed.emit(player, other)

	# Defensive pact - requires good relations
	if other.player_id not in player.defensive_pact_with:
		if attitude >= 3:  # Pleased or better
			var military_flavor = flavor.get("military", 5)
			# Low military AI wants protection, high military wants allies
			if military_flavor < LOW_FLAVOR or attitude >= 5:
				if not other.is_human:
					if DiplomacySystem.would_accept_proposal(player, other, "defensive_pact"):
						player.defensive_pact_with.append(other.player_id)
						other.defensive_pact_with.append(player.player_id)
						EventBus.defensive_pact_signed.emit(player, other)

## Consider trade deals
func _consider_trade(player, other, flavor: Dictionary) -> void:
	# Only trade occasionally to avoid spam
	if randf() > 0.2:
		return

	var gold_flavor = flavor.get("gold", 5)
	var science_flavor = flavor.get("science", 5)

	# Check if we have tradeable techs
	var our_techs = TradeSystem.get_tradeable_techs(player, other)
	var their_techs = TradeSystem.get_tradeable_techs(other, player)

	if our_techs.is_empty() and their_techs.is_empty():
		return

	# Create a trade proposal
	var proposal = TradeSystem.create_proposal(player, other)

	# Tech for tech trade
	if not our_techs.is_empty() and not their_techs.is_empty():
		TradeSystem.add_tech_to_offer(proposal, true, our_techs[0])
		TradeSystem.add_tech_to_offer(proposal, false, their_techs[0])

		if TradeSystem.is_proposal_valid(proposal):
			if not other.is_human:
				if TradeSystem.would_ai_accept(proposal, other.player_id):
					EventBus.trade_accepted.emit(player, other, proposal)
			else:
				# Propose to human player
				EventBus.trade_proposed.emit(player, other, proposal)

## Consider declaring war
func _consider_war(player, other, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)
	var expansion_flavor = flavor.get("expansion", 5)

	# Non-aggressive AI rarely declares war unprovoked
	if military_flavor < MEDIUM_FLAVOR:
		return

	var attitude = DiplomacySystem.calculate_attitude(player, other)

	# Only attack enemies or those we dislike
	if attitude > -2:
		return

	# Check military power
	var our_power = DiplomacySystem._calculate_power(player)
	var their_power = DiplomacySystem._calculate_power(other)

	# Need significant advantage
	var required_ratio = 1.5 - (military_flavor - 5) * 0.1  # Aggressive AI needs less advantage
	required_ratio = max(1.2, required_ratio)

	if our_power > their_power * required_ratio:
		# Check if they have a defensive pact ally we'd also fight
		var pact_allies_power = 0
		for ally_id in other.defensive_pact_with:
			var ally = GameManager.get_player(ally_id)
			if ally and ally != player:
				pact_allies_power += DiplomacySystem._calculate_power(ally)

		if our_power > (their_power + pact_allies_power) * required_ratio:
			# Declare war with some randomness
			if randf() < 0.3 * (military_flavor / 10.0):
				GameManager.declare_war(player, other)

## Process AI espionage decisions
func _process_espionage(player, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)
	var gold_flavor = flavor.get("gold", 5)
	var science_flavor = flavor.get("science", 5)

	# AI uses espionage more when aggressive or behind in tech
	var espionage_priority = (military_flavor + gold_flavor) / 2

	# Only do espionage occasionally (25-50% chance per turn based on personality)
	if randf() > 0.25 + espionage_priority * 0.025:
		return

	# Find best target (enemies or rivals)
	var best_target = null
	var best_target_score = -1

	for other in GameManager.players:
		if other == player or other.player_id not in player.met_players:
			continue

		# Calculate target priority
		var target_score = 0

		# Prefer enemies
		if GameManager.is_at_war(player, other):
			target_score += 50

		# Prefer those with more tech
		target_score += (other.researched_techs.size() - player.researched_techs.size()) * 5

		# Prefer those we dislike
		var attitude = DiplomacySystem.calculate_attitude(player, other)
		target_score -= attitude * 3

		# Check if we have espionage points against them
		var points = EspionageSystem.get_espionage_points(player.player_id, other.player_id)
		if points < 50:
			continue  # Not enough points to do anything

		if target_score > best_target_score:
			best_target_score = target_score
			best_target = other

	if best_target == null:
		return

	# Find best mission to execute
	var target_city = best_target.cities[0] if not best_target.cities.is_empty() else null
	var available_missions = EspionageSystem.get_available_missions(player, best_target, target_city)

	if available_missions.is_empty():
		return

	# Prioritize missions based on personality
	var best_mission = null
	var best_mission_score = -1

	for mission_id in available_missions:
		var mission_score = _score_espionage_mission(mission_id, player, best_target, target_city, flavor)
		if mission_score > best_mission_score:
			best_mission_score = mission_score
			best_mission = mission_id

	if best_mission != null:
		var result = EspionageSystem.execute_mission(best_mission, player, best_target, target_city)
		# AI doesn't need to react to results, just execute

## Score an espionage mission based on AI personality
func _score_espionage_mission(mission_id: String, player, target, target_city, flavor: Dictionary) -> int:
	var score = 10  # Base score

	var military_flavor = flavor.get("military", 5)
	var gold_flavor = flavor.get("gold", 5)
	var science_flavor = flavor.get("science", 5)

	match mission_id:
		"steal_treasury":
			score += gold_flavor * 5
		"steal_technology":
			score += science_flavor * 8
			# Higher priority if behind in tech
			if target.researched_techs.size() > player.researched_techs.size():
				score += 30
		"sabotage_production":
			score += military_flavor * 4
			# Higher priority if at war
			if GameManager.is_at_war(player, target):
				score += 20
		"destroy_building":
			score += military_flavor * 3
		"incite_revolt":
			score += military_flavor * 5
			if GameManager.is_at_war(player, target):
				score += 25
		"poison_water", "spread_unhappiness":
			score += military_flavor * 2
			if GameManager.is_at_war(player, target):
				score += 15
		"counter_espionage":
			score += 5  # Defensive, lower priority for AI
		"see_demographics", "investigate_city", "see_research":
			score += 5  # Information gathering, low priority
		"force_civic_change", "force_religion_change":
			score += military_flavor * 3

	# Reduce score for risky missions if AI is cautious (low military flavor)
	var mission_data = DataManager.get_espionage_mission(mission_id)
	if mission_data:
		var discovery_chance = mission_data.get("discovery_chance", 0)
		if discovery_chance > 50 and military_flavor < MEDIUM_FLAVOR:
			score -= 20

	return score

func _process_unit_ai(unit, player, flavor: Dictionary) -> void:
	if unit.has_acted or unit.movement_remaining <= 0:
		return

	# Skip if currently building
	if unit.current_order == UnitClass.UnitOrder.BUILD:
		return

	# Settler: find good city location
	if unit.can_found_city():
		_settler_ai(unit, player, flavor)
		return

	# Worker: build improvements
	if unit.can_build_improvements():
		_worker_ai(unit, player, flavor)
		return

	# Combat unit: attack or explore
	_combat_unit_ai(unit, player, flavor)

func _settler_ai(unit, player, flavor: Dictionary) -> void:
	# If on good tile, found city
	if _is_good_city_location(unit.grid_position, player):
		if GameManager.game_world:
			GameManager.game_world.found_city(unit)
		return

	# Move toward better location
	var target = _find_best_city_location(unit, player, flavor)
	if target != Vector2i(-1, -1):
		_move_toward(unit, target)

func _worker_ai(unit, player, flavor: Dictionary) -> void:
	var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
	if tile == null:
		return

	var production_flavor = flavor.get("production", 5)
	var growth_flavor = flavor.get("growth", 5)
	var gold_flavor = flavor.get("gold", 5)

	# If on owned tile without improvement, build one
	if tile.tile_owner == player and tile.improvement_id == "" and tile.road_level == 0:
		var improvements = ImprovementSystem.get_available_improvements(unit, tile)

		if not improvements.is_empty():
			var chosen = _choose_improvement(tile, improvements, production_flavor, growth_flavor, gold_flavor)
			if chosen != "":
				ImprovementSystem.start_build(unit, chosen)
				return

		# Build road if no improvement available
		if ImprovementSystem.can_build_road(unit, tile):
			ImprovementSystem.start_build_road(unit)
			return

	# Move to unimproved owned tile
	var target = _find_unimproved_tile(unit, player)
	if target != Vector2i(-1, -1):
		_move_toward(unit, target)
	else:
		# Fortify if nothing to do
		unit.fortify()

## Choose improvement based on tile and AI preferences
func _choose_improvement(tile, improvements: Array, prod_flavor: int, growth_flavor: int, gold_flavor: int) -> String:
	# Score each improvement
	var best_imp = ""
	var best_score = -1

	for imp_id in improvements:
		var score = 0
		var imp_data = DataManager.get_improvement(imp_id)
		var yields = imp_data.get("yields", {})

		# Score based on yields and flavor
		score += yields.get("food", 0) * growth_flavor
		score += yields.get("production", 0) * prod_flavor
		score += yields.get("commerce", 0) * gold_flavor

		# Bonus for resource improvements
		if tile.resource_id != "":
			var res_data = DataManager.get_resource(tile.resource_id)
			var required_imp = res_data.get("improvement", "")
			if imp_id == required_imp:
				score += 50  # Big bonus for connecting resources

		if score > best_score:
			best_score = score
			best_imp = imp_id

	return best_imp

func _combat_unit_ai(unit, player, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)

	# Check for nearby enemies
	var enemies = _find_nearby_enemies(unit, player, 3)
	if not enemies.is_empty():
		var target = _pick_best_target(unit, enemies, military_flavor)
		if target:
			var odds = CombatSystem.calculate_odds(unit, target)
			# Aggressive AI takes more risks
			var min_odds = 0.5 - (military_flavor - 5) * 0.05
			min_odds = clamp(min_odds, 0.3, 0.6)

			if odds.win_chance > min_odds:
				if GridUtils.are_adjacent(unit.grid_position, target.grid_position):
					CombatSystem.resolve_combat(unit, target)
					return
				else:
					_move_toward(unit, target.grid_position)
					return

	# Defend cities if needed
	for city in player.cities:
		var garrison = GameManager.get_units_at(city.grid_position)
		var has_military = false
		for g_unit in garrison:
			if g_unit.player_owner == player and g_unit.get_strength() > 0:
				has_military = true
				break
		if not has_military:
			_move_toward(unit, city.grid_position)
			if unit.grid_position == city.grid_position:
				unit.fortify()
			return

	# Explore unexplored tiles
	var unexplored = _find_nearest_unexplored(unit, player)
	if unexplored != Vector2i(-1, -1):
		_move_toward(unit, unexplored)
		return

	# Fortify if nothing to do
	unit.fortify()

## Pick best target from enemies
func _pick_best_target(unit, enemies: Array, military_flavor: int):
	var best_target = null
	var best_score = -INF

	for enemy in enemies:
		var odds = CombatSystem.calculate_odds(unit, enemy)
		var score = odds.win_chance * 100

		# Bonus for killing shot
		if enemy.health <= unit.get_strength() * 10:
			score += 20

		# Aggressive AI prefers attacking
		score += military_flavor * 2

		if score > best_score:
			best_score = score
			best_target = enemy

	return best_target

func _process_city_ai(city, player, flavor: Dictionary) -> void:
	if city.current_production != "":
		return

	var military_flavor = flavor.get("military", 5)
	var science_flavor = flavor.get("science", 5)
	var growth_flavor = flavor.get("growth", 5)
	var production_flavor = flavor.get("production", 5)
	var culture_flavor = flavor.get("culture", 5)
	var expansion_flavor = flavor.get("expansion", 5)

	# Apply difficulty bonuses
	var bonuses = _get_ai_bonuses()
	var prod_bonus = bonuses.get("production_percent", 0)

	# Count units
	var num_units = player.units.size()
	var num_cities = player.cities.size()
	var military_units = 0
	var workers = 0
	for u in player.units:
		if u.get_strength() > 0:
			military_units += 1
		if u.can_build_improvements():
			workers += 1

	# Calculate desired military based on flavor
	var desired_military = num_cities * (1 + military_flavor / 5)

	# Need military?
	if military_units < desired_military:
		var unit_to_build = _get_best_military_unit(city, player, military_flavor)
		if unit_to_build != "":
			city.set_production(unit_to_build)
			return

	# Need settler? Based on expansion flavor
	var max_cities = 4 + expansion_flavor
	if num_cities < max_cities and city.population >= 3:
		if city.can_build_unit("settler"):
			city.set_production("settler")
			return

	# Need worker?
	var desired_workers = num_cities * (1 + production_flavor / 10)
	if workers < desired_workers:
		if city.can_build_unit("worker"):
			city.set_production("worker")
			return

	# Build infrastructure based on flavor
	var building_to_build = _get_best_building(city, player, flavor)
	if building_to_build != "":
		city.set_production(building_to_build)
		return

	# Default to military
	var unit_to_build = _get_best_military_unit(city, player, military_flavor)
	if unit_to_build != "":
		city.set_production(unit_to_build)

func _process_research(player, flavor: Dictionary) -> void:
	if player.current_research != "":
		return

	# Find available techs
	var available_techs = []
	for tech_id in DataManager.techs:
		if player.can_research(tech_id):
			available_techs.append(tech_id)

	if available_techs.is_empty():
		return

	# Prioritize techs based on leader flavor
	var best_tech = available_techs[0]
	var best_score = -INF

	for tech_id in available_techs:
		var score = _evaluate_tech(tech_id, player, flavor)
		if score > best_score:
			best_score = score
			best_tech = tech_id

	player.start_research(best_tech)

func _evaluate_tech(tech_id: String, player, flavor: Dictionary) -> float:
	var score = 0.0
	var tech = DataManager.get_tech(tech_id)
	var unlocks = tech.get("unlocks", {})

	var military_flavor = flavor.get("military", 5)
	var science_flavor = flavor.get("science", 5)
	var gold_flavor = flavor.get("gold", 5)
	var culture_flavor = flavor.get("culture", 5)
	var religion_flavor = flavor.get("religion", 5)

	# Value units - more if military focused
	if unlocks.has("units"):
		score += unlocks.units.size() * 10 * (military_flavor / 5.0)

	# Value buildings
	if unlocks.has("buildings"):
		for building_id in unlocks.buildings:
			var building = DataManager.get_building(building_id)
			var effects = building.get("effects", {})

			# Science buildings
			if effects.has("science_percent") or effects.has("science"):
				score += 15 * (science_flavor / 5.0)
			# Gold buildings
			if effects.has("gold_percent") or effects.has("gold"):
				score += 10 * (gold_flavor / 5.0)
			# Culture buildings
			if effects.has("culture"):
				score += 10 * (culture_flavor / 5.0)
			# Military buildings
			if effects.has("experience") or effects.has("happiness"):
				score += 8 * (military_flavor / 5.0)

			score += 5  # Base building value

	# Value improvements
	if unlocks.has("improvements"):
		score += unlocks.improvements.size() * 3

	# Religion techs
	if unlocks.has("religions"):
		score += 20 * (religion_flavor / 5.0)

	# Cheaper is better
	var cost = DataManager.get_tech_cost(tech_id)
	score += max(0, 50 - cost / 20)

	return score

# Helper functions
func _is_good_city_location(pos: Vector2i, player) -> bool:
	# Check not too close to other cities
	for city in GameManager.get_all_cities():
		if GridUtils.chebyshev_distance(pos, city.grid_position) < 4:
			return false

	# Check has enough good tiles nearby
	var good_tiles = 0
	if GameManager.hex_grid == null:
		return false

	var tiles = GridUtils.get_tiles_in_range(pos, 2)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile != null and tile.get_food() >= 2:
			good_tiles += 1

	return good_tiles >= 3

func _find_best_city_location(unit, player, flavor: Dictionary) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_score = -1

	var growth_flavor = flavor.get("growth", 5)
	var production_flavor = flavor.get("production", 5)
	var gold_flavor = flavor.get("gold", 5)

	# Search in expanding rings
	for radius in range(1, 15):
		var tiles = GridUtils.get_tiles_at_range(unit.grid_position, radius)
		for tile_pos in tiles:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null or not tile.is_passable() or tile.is_water():
				continue

			if _is_good_city_location(tile_pos, player):
				var score = _evaluate_city_location(tile_pos, growth_flavor, production_flavor, gold_flavor)
				if score > best_score:
					best_score = score
					best_pos = tile_pos

		if best_pos != Vector2i(-1, -1):
			break

	return best_pos

func _evaluate_city_location(pos: Vector2i, growth_flavor: int, prod_flavor: int, gold_flavor: int) -> int:
	var score = 0
	var tiles = GridUtils.get_tiles_in_range(pos, 2)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile != null:
			score += tile.get_food() * growth_flavor
			score += tile.get_production() * prod_flavor
			score += tile.get_commerce() * gold_flavor
			if tile.resource_id != "":
				score += 15  # Resources are always valuable
	return score

func _move_toward(unit, target: Vector2i) -> void:
	if GameManager.hex_grid == null:
		return

	var pathfinder = PathfindingClass.new(GameManager.hex_grid, unit)
	var path = pathfinder.find_path_with_movement(
		unit.grid_position, target, unit.movement_remaining
	)

	if path.size() > 0:
		# Move along path as far as possible
		for pos in path:
			if unit.movement_remaining > 0:
				unit.move_to(pos)
			else:
				break

func _find_unimproved_tile(unit, player) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_dist = INF

	# Check owned tiles
	for city in player.cities:
		for tile_pos in city.territory:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null:
				continue
			if tile.improvement_id == "" and tile.road_level == 0 and not tile.is_water():
				var dist = GridUtils.chebyshev_distance(unit.grid_position, tile_pos)
				if dist < best_dist:
					best_dist = dist
					best_pos = tile_pos

	return best_pos

func _find_nearby_enemies(unit, player, range_val: int) -> Array:
	var enemies = []
	if GameManager.hex_grid == null:
		return enemies

	var tiles = GridUtils.get_tiles_in_range(unit.grid_position, range_val)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile == null:
			continue
		var enemy = GameManager.get_unit_at(tile_pos)
		if enemy != null and enemy.player_owner != player:
			if GameManager.is_at_war(player, enemy.player_owner):
				enemies.append(enemy)

	return enemies

func _find_nearest_unexplored(unit, player) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_dist = INF

	# Visibility state constant
	const UNEXPLORED = 0

	# Search in expanding rings
	for radius in range(1, 20):
		var tiles = GridUtils.get_tiles_at_range(unit.grid_position, radius)
		for tile_pos in tiles:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null:
				continue

			var visibility = tile.get_visibility_for_player(player.player_id)
			if visibility == UNEXPLORED:
				# Check if we can actually reach a tile next to it
				var neighbors = GridUtils.get_neighbors(tile_pos)
				for neighbor in neighbors:
					var neighbor_tile = GameManager.hex_grid.get_tile(neighbor)
					if neighbor_tile != null and neighbor_tile.is_passable() and not neighbor_tile.is_water():
						var dist = GridUtils.chebyshev_distance(unit.grid_position, neighbor)
						if dist < best_dist:
							best_dist = dist
							best_pos = neighbor

		if best_pos != Vector2i(-1, -1):
			break

	return best_pos

func _get_best_military_unit(city, player, military_flavor: int) -> String:
	# Prefer strongest available
	var best_unit = ""
	var best_strength = 0

	for unit_id in DataManager.units:
		if not city.can_build_unit(unit_id):
			continue

		var unit_data = DataManager.get_unit(unit_id)
		var strength = DataManager.get_unit_strength(unit_id)
		var unit_class = unit_data.get("unit_class", "")

		# Combat classes
		if unit_class in ["melee", "mounted", "gunpowder", "archery", "armor", "siege"] and strength > best_strength:
			best_strength = strength
			best_unit = unit_id

	return best_unit

func _get_best_building(city, player, flavor: Dictionary) -> String:
	var science_flavor = flavor.get("science", 5)
	var gold_flavor = flavor.get("gold", 5)
	var culture_flavor = flavor.get("culture", 5)
	var military_flavor = flavor.get("military", 5)
	var growth_flavor = flavor.get("growth", 5)
	var production_flavor = flavor.get("production", 5)

	# Score buildings based on flavor
	var best_building = ""
	var best_score = -1

	for building_id in DataManager.buildings:
		if not city.can_build_building(building_id):
			continue

		var building = DataManager.get_building(building_id)
		var effects = building.get("effects", {})
		var score = 0

		# Science
		if effects.has("science_percent"):
			score += effects.science_percent * science_flavor / 5
		if effects.has("science"):
			score += effects.science * science_flavor

		# Gold
		if effects.has("gold_percent"):
			score += effects.gold_percent * gold_flavor / 5
		if effects.has("gold"):
			score += effects.gold * gold_flavor

		# Culture
		if effects.has("culture"):
			score += effects.culture * culture_flavor

		# Military
		if effects.has("experience"):
			score += effects.experience * military_flavor * 2
		if effects.has("happiness"):
			score += effects.happiness * 5

		# Growth
		if effects.has("food"):
			score += effects.food * growth_flavor * 2
		if effects.has("health"):
			score += effects.health * growth_flavor

		# Production
		if effects.has("production"):
			score += effects.production * production_flavor * 2
		if effects.has("production_percent"):
			score += effects.production_percent * production_flavor / 5

		# Reduce score by cost (prefer cheaper when scores are similar)
		var cost = building.get("cost", 100)
		score -= cost / 50

		if score > best_score:
			best_score = score
			best_building = building_id

	return best_building
