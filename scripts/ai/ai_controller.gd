extends Node
## AI controller for computer-controlled players.

const PathfindingClass = preload("res://scripts/map/pathfinding.gd")
const UnitClass = preload("res://scripts/entities/unit.gd")

## Execute a full turn for an AI player
func execute_turn(player) -> void:
	if player.is_human:
		return

	# Process research first
	_process_research(player)

	# Process units
	for unit in player.units.duplicate():  # Duplicate to avoid modification during iteration
		if unit == null or not is_instance_valid(unit):
			continue
		_process_unit_ai(unit, player)

	# Process cities
	for city in player.cities:
		_process_city_ai(city, player)

func _process_unit_ai(unit, player) -> void:
	if unit.has_acted or unit.movement_remaining <= 0:
		return

	# Skip if currently building
	if unit.current_order == UnitClass.UnitOrder.BUILD:
		return

	# Settler: find good city location
	if unit.can_found_city():
		_settler_ai(unit, player)
		return

	# Worker: build improvements
	if unit.can_build_improvements():
		_worker_ai(unit, player)
		return

	# Combat unit: attack or explore
	_combat_unit_ai(unit, player)

func _settler_ai(unit, player) -> void:
	# If on good tile, found city
	if _is_good_city_location(unit.grid_position, player):
		if GameManager.game_world:
			GameManager.game_world.found_city(unit)
		return

	# Move toward better location
	var target = _find_best_city_location(unit, player)
	if target != Vector2i(-1, -1):
		_move_toward(unit, target)

func _worker_ai(unit, player) -> void:
	var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
	if tile == null:
		return

	# If on owned tile without improvement, build one
	if tile.owner == player and tile.improvement_id == "" and tile.road_level == 0:
		var improvements = ImprovementSystem.get_available_improvements(unit, tile)

		if not improvements.is_empty():
			# Prefer farms for food, mines for production
			if "farm" in improvements and tile.terrain_id in ["grassland", "plains", "flood_plains"]:
				ImprovementSystem.start_build(unit, "farm")
				return
			elif "mine" in improvements and tile.terrain_id in ["hills"]:
				ImprovementSystem.start_build(unit, "mine")
				return
			elif "lumber_mill" in improvements and tile.feature_id == "forest":
				ImprovementSystem.start_build(unit, "lumber_mill")
				return
			elif "plantation" in improvements:
				ImprovementSystem.start_build(unit, "plantation")
				return
			elif "camp" in improvements:
				ImprovementSystem.start_build(unit, "camp")
				return
			elif "pasture" in improvements:
				ImprovementSystem.start_build(unit, "pasture")
				return
			else:
				ImprovementSystem.start_build(unit, improvements[0])
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

func _combat_unit_ai(unit, player) -> void:
	# Check for nearby enemies
	var enemies = _find_nearby_enemies(unit, player, 3)
	if not enemies.is_empty():
		var target = enemies[0]
		# Attack if we can win
		var odds = CombatSystem.calculate_odds(unit, target)
		if odds.win_chance > 0.4:
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
			if g_unit.owner == player and g_unit.get_strength() > 0:
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

func _process_city_ai(city, player) -> void:
	if city.current_production != "":
		return

	# Production priorities
	var num_units = player.units.size()
	var num_cities = player.cities.size()
	var military_units = 0
	for u in player.units:
		if u.get_strength() > 0:
			military_units += 1

	# Need military?
	if military_units < num_cities * 2:
		var unit_to_build = _get_best_military_unit(city, player)
		if unit_to_build != "":
			city.set_production(unit_to_build)
			return

	# Need settler?
	if num_cities < 6 and city.population >= 3:
		if city.can_build_unit("settler"):
			city.set_production("settler")
			return

	# Need worker?
	var worker_count = 0
	for u in player.units:
		if u.can_build_improvements():
			worker_count += 1
	if worker_count < num_cities:
		if city.can_build_unit("worker"):
			city.set_production("worker")
			return

	# Build infrastructure
	var building_to_build = _get_best_building(city, player)
	if building_to_build != "":
		city.set_production(building_to_build)
		return

	# Default to military
	var unit_to_build = _get_best_military_unit(city, player)
	if unit_to_build != "":
		city.set_production(unit_to_build)

func _process_research(player) -> void:
	if player.current_research != "":
		return

	# Find available techs
	var available_techs = []
	for tech_id in DataManager.techs:
		if player.can_research(tech_id):
			available_techs.append(tech_id)

	if available_techs.is_empty():
		return

	# Prioritize techs that unlock units/buildings
	var best_tech = available_techs[0]
	var best_score = 0

	for tech_id in available_techs:
		var score = _evaluate_tech(tech_id, player)
		if score > best_score:
			best_score = score
			best_tech = tech_id

	player.start_research(best_tech)

func _evaluate_tech(tech_id: String, player) -> int:
	var score = 0
	var tech = DataManager.get_tech(tech_id)
	var unlocks = tech.get("unlocks", {})

	# Value units
	if unlocks.has("units"):
		score += unlocks.units.size() * 10

	# Value buildings
	if unlocks.has("buildings"):
		score += unlocks.buildings.size() * 5

	# Value improvements
	if unlocks.has("improvements"):
		score += unlocks.improvements.size() * 3

	# Cheaper is better
	var cost = DataManager.get_tech_cost(tech_id)
	score += max(0, 100 - cost / 10)

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

func _find_best_city_location(unit, player) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_score = -1

	# Search in expanding rings
	for radius in range(1, 15):
		var tiles = GridUtils.get_tiles_at_range(unit.grid_position, radius)
		for tile_pos in tiles:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null or not tile.is_passable() or tile.is_water():
				continue

			if _is_good_city_location(tile_pos, player):
				var score = _evaluate_city_location(tile_pos)
				if score > best_score:
					best_score = score
					best_pos = tile_pos

		if best_pos != Vector2i(-1, -1):
			break

	return best_pos

func _evaluate_city_location(pos: Vector2i) -> int:
	var score = 0
	var tiles = GridUtils.get_tiles_in_range(pos, 2)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile != null:
			score += tile.get_food() * 3
			score += tile.get_production() * 2
			score += tile.get_commerce()
			if tile.resource_id != "":
				score += 5
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
		if enemy != null and enemy.owner != player:
			if GameManager.is_at_war(player, enemy.owner):
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

func _get_best_military_unit(city, player) -> String:
	# Prefer strongest available
	var best_unit = ""
	var best_strength = 0

	for unit_id in DataManager.units:
		if not city.can_build_unit(unit_id):
			continue

		var unit_data = DataManager.get_unit(unit_id)
		var strength = DataManager.get_unit_strength(unit_id)
		var unit_class = unit_data.get("unit_class", "")

		if unit_class in ["melee", "mounted", "gunpowder", "archery"] and strength > best_strength:
			best_strength = strength
			best_unit = unit_id

	return best_unit

func _get_best_building(city, player) -> String:
	# Priority order
	var priority = [
		"granary",      # Food storage
		"barracks",     # Military XP
		"library",      # Science
		"monument",     # Culture
		"market",       # Gold
		"forge",        # Production
		"university",   # More science
		"courthouse",   # Reduce maintenance
		"aqueduct",     # Health
		"colosseum",    # Happiness
		"bank",         # More gold
		"factory",      # More production
	]

	for building_id in priority:
		if city.can_build_building(building_id):
			return building_id

	# Try any available building
	for building_id in DataManager.buildings:
		if city.can_build_building(building_id):
			return building_id

	return ""
