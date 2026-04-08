extends RefCounted
## Strategic planning layer for AI players.
## Evaluates world state and creates prioritized objectives (city sites, war targets, defense).
## Called by AIController once per turn, before unit processing.

## Main entry point — updates all strategic objectives for a player.
static func update_strategy(player, flavor: Dictionary) -> void:
	if player == null or player.cities.is_empty():
		return

	var strategy = player.ai_strategy

	# Initialize structure if empty
	if strategy.is_empty():
		strategy["city_sites"] = []
		strategy["war_targets"] = []
		strategy["defense_needs"] = []
		strategy["last_full_eval"] = 0
		strategy["last_city_count"] = 0
		strategy["desired_settlers"] = 0

	# Clean stale data (dead units, captured cities)
	_clean_stale_data(player)

	# Defense needs — every turn (cheap)
	_evaluate_defense_needs(player)

	# City sites — every 5 turns or when city count changes
	var city_count_changed = player.cities.size() != strategy.get("last_city_count", 0)
	var turns_since_eval = TurnManager.current_turn - strategy.get("last_full_eval", 0)
	if turns_since_eval >= 5 or city_count_changed or strategy.city_sites.is_empty():
		_evaluate_city_sites(player, flavor)
		strategy["last_full_eval"] = TurnManager.current_turn
		strategy["last_city_count"] = player.cities.size()

	# War targets — when at war
	if not player.at_war_with.is_empty():
		_evaluate_war_targets(player, flavor)
	else:
		strategy["war_targets"] = []

	# Calculate desired settlers
	var unassigned_sites = 0
	for site in strategy.city_sites:
		if site.get("assigned_unit_id", -1) == -1:
			unassigned_sites += 1
	# Count existing settlers
	var existing_settlers = 0
	for unit in player.units:
		if unit.can_found_city():
			existing_settlers += 1
	strategy["desired_settlers"] = max(0, unassigned_sites - existing_settlers)

# ============ CITY SETTLEMENT ============

static func _evaluate_city_sites(player, flavor: Dictionary) -> void:
	var grid = GameManager.hex_grid
	if grid == null:
		return

	var growth_flavor = flavor.get("growth", 5)
	var prod_flavor = flavor.get("production", 5)
	var gold_flavor = flavor.get("gold", 5)

	# Find capital position for distance scoring
	var capital_pos = player.cities[0].grid_position
	for city in player.cities:
		if "palace" in city.buildings:
			capital_pos = city.grid_position
			break

	# Gather all existing city positions (for distance checks)
	var own_city_positions: Array[Vector2i] = []
	for city in player.cities:
		own_city_positions.append(city.grid_position)

	var other_city_positions: Array[Vector2i] = []
	for other in GameManager.players:
		if other == player:
			continue
		for city in other.cities:
			other_city_positions.append(city.grid_position)

	# Score candidate tiles
	var candidates: Array = []  # [{position, score}]

	for x in range(grid.width):
		for y in range(grid.height):
			var pos = Vector2i(x, y)
			var tile = grid.get_tile(pos)
			if tile == null or tile.is_water() or not tile.is_passable():
				continue
			# Fog of war: only consider explored tiles for city sites
			if tile.get_visibility_for_player(player.player_id) == 0:
				continue

			# Skip if too close to own cities
			var too_close_own = false
			for cp in own_city_positions:
				if GridUtils.chebyshev_distance(pos, cp) < 4:
					too_close_own = true
					break
			if too_close_own:
				continue

			# Skip if too close to other players' cities
			var too_close_other = false
			for cp in other_city_positions:
				if GridUtils.chebyshev_distance(pos, cp) < 3:
					too_close_other = true
					break
			if too_close_other:
				continue

			# Skip if city already exists here
			if GameManager.get_city_at(pos) != null:
				continue

			# Only consider tiles in own territory, unclaimed, or ally territory
			if tile.tile_owner != null and tile.tile_owner != player:
				if not player.can_enter_borders_of(tile.tile_owner.player_id):
					continue

			# Score this site
			var score = _score_city_site(pos, capital_pos, own_city_positions, other_city_positions,
				growth_flavor, prod_flavor, gold_flavor)

			if score > 0:
				candidates.append({"position": pos, "score": score, "assigned_unit_id": -1})

	# Sort by score descending and keep top 5
	candidates.sort_custom(func(a, b): return a.score > b.score)
	var new_sites = candidates.slice(0, 5)

	# Preserve existing assignments: if an old site's position matches a new site, carry over the unit_id
	var old_sites = player.ai_strategy.get("city_sites", [])
	for new_site in new_sites:
		for old_site in old_sites:
			if old_site.position == new_site.position and old_site.get("assigned_unit_id", -1) != -1:
				new_site["assigned_unit_id"] = old_site["assigned_unit_id"]
				break

	player.ai_strategy["city_sites"] = new_sites

static func _score_city_site(pos: Vector2i, capital_pos: Vector2i,
		own_positions: Array, other_positions: Array,
		growth_flavor: int, prod_flavor: int, gold_flavor: int) -> int:
	var grid = GameManager.hex_grid
	if grid == null:
		return 0

	var score = 0

	# Evaluate Big Fat Cross (radius 2) yields
	var tiles = GridUtils.get_tiles_in_range(pos, 2)
	var food_count = 0
	var resource_count = 0
	for tile_pos in tiles:
		var tile = grid.get_tile(tile_pos)
		if tile == null:
			continue
		score += tile.get_food() * growth_flavor
		score += tile.get_production() * prod_flavor
		score += tile.get_commerce() * gold_flavor
		if tile.get_food() >= 1:
			food_count += 1
		if tile.resource_id != "":
			var res_data = DataManager.get_resource(tile.resource_id)
			resource_count += 1
			if res_data.get("type", "") == "strategic":
				score += 20
			else:
				score += 15

	# Must have minimum food tiles
	if food_count < 2:
		return 0

	# Fresh water bonus (river or lake adjacent)
	var center_tile = grid.get_tile(pos)
	if center_tile and center_tile.has_fresh_water():
		score += 10

	# Coastal bonus (adjacent ocean tile for trade routes)
	var neighbors = GridUtils.get_neighbors(pos)
	for n_pos in neighbors:
		var n_tile = grid.get_tile(n_pos)
		if n_tile and n_tile.is_water():
			score += 8
			break

	# Distance from capital (prefer not too far)
	var dist_to_capital = GridUtils.chebyshev_distance(pos, capital_pos)
	if dist_to_capital > 10:
		score -= (dist_to_capital - 10) * 2

	# Optimal spacing from own cities (5-8 tiles is ideal)
	var min_own_dist = 999
	for cp in own_positions:
		min_own_dist = mini(min_own_dist, GridUtils.chebyshev_distance(pos, cp))
	if min_own_dist >= 5 and min_own_dist <= 8:
		score += 10  # Ideal spacing
	elif min_own_dist > 12:
		score -= 5  # Too isolated

	# Enemy proximity penalty
	for cp in other_positions:
		if GridUtils.chebyshev_distance(pos, cp) < 5:
			score -= 15
			break

	# Penalize sites in foreign territory (harder to reach without open borders)
	if center_tile.tile_owner != null:
		var is_own = false
		for cp in own_positions:
			if GridUtils.chebyshev_distance(pos, cp) <= 5:
				is_own = true
				break
		if not is_own:
			score -= 30

	return max(0, score)

static func get_best_unassigned_site(player) -> Dictionary:
	for site in player.ai_strategy.get("city_sites", []):
		if site.get("assigned_unit_id", -1) == -1:
			return site
	return {}

static func assign_settler_to_site(player, unit, site: Dictionary) -> void:
	site["assigned_unit_id"] = unit.get_instance_id()

static func clear_assignment(player, unit) -> void:
	var uid = unit.get_instance_id()
	for site in player.ai_strategy.get("city_sites", []):
		if site.get("assigned_unit_id", -1) == uid:
			site["assigned_unit_id"] = -1
	for target in player.ai_strategy.get("war_targets", []):
		target.get("assigned_units", []).erase(uid)
	for defense in player.ai_strategy.get("defense_needs", []):
		defense.get("assigned_units", []).erase(uid)

# ============ WAR TARGETS ============

static func _evaluate_war_targets(player, flavor: Dictionary) -> void:
	var targets: Array = []

	# Count our siege units for viability assessment
	var our_siege = 0
	for u in player.units:
		var udata = DataManager.get_unit(u.unit_id)
		if udata.get("unit_class", "") == "siege":
			our_siege += 1

	for enemy_id in player.at_war_with:
		var enemy = GameManager.get_player(enemy_id)
		if enemy == null:
			continue

		for city in enemy.cities:
			var priority = 50

			# Distance from nearest own city
			var min_dist = 999
			for own_city in player.cities:
				min_dist = mini(min_dist, GridUtils.chebyshev_distance(city.grid_position, own_city.grid_position))
			priority -= min_dist  # Closer = higher priority

			# Smaller cities are easier
			if city.population <= 3:
				priority += 10
			elif city.population >= 8:
				priority -= 10

			# Capital is high value
			if city.is_capital():
				priority += 20

			# Near our border
			if min_dist <= 6:
				priority += 15

			# === Stack awareness: evaluate defender strength ===
			# Count defenders at city
			var defenders = 0
			var units_at_city = GameManager.get_units_at(city.grid_position)
			for u in units_at_city:
				if u.player_owner == enemy and u.get_strength() > 0:
					defenders += 1

			# Fewer defenders = higher priority
			if defenders <= 1:
				priority += 15  # Lightly defended — easy target
			elif defenders >= 4:
				priority -= 15  # Heavily garrisoned — costly assault

			# Check for defensive buildings (walls, castle)
			for building_id in city.buildings:
				var effects = DataManager.get_building_effects(building_id)
				if effects.get("defense", 0.0) > 0:
					priority -= 10
					break

			# Having siege units makes all targets more viable
			if our_siege > 0:
				priority += 10

			# Calculate desired force size based on defenders
			var desired_size = max(3, 3 + (defenders - 1) * 2)
			desired_size = min(desired_size, 10)

			targets.append({
				"city_position": city.grid_position,
				"city_name": city.city_name,
				"owner_id": enemy_id,
				"priority": priority,
				"desired_size": desired_size,
				"assigned_units": []
			})

	targets.sort_custom(func(a, b): return a.priority > b.priority)
	player.ai_strategy["war_targets"] = targets.slice(0, 5)

static func get_war_target_for_unit(player, unit) -> Dictionary:
	for target in player.ai_strategy.get("war_targets", []):
		var assigned = target.get("assigned_units", [])
		var desired_size = target.get("desired_size", 5 if target.get("priority", 0) > 60 else 3)
		if assigned.size() < desired_size:
			# Assign this unit
			assigned.append(unit.get_instance_id())
			return target
	return {}

# ============ DEFENSE ============

static func _evaluate_defense_needs(player) -> void:
	var needs: Array = []

	for city in player.cities:
		var threat_level = 0

		# Count nearby enemy units
		var tiles = GridUtils.get_tiles_in_range(city.grid_position, 5)
		for tile_pos in tiles:
			var units_here = GameManager.get_units_at(tile_pos)
			for u in units_here:
				if u.player_owner != player and u.get_strength() > 0:
					if GameManager.is_at_war(player, u.player_owner):
						threat_level += 2
					elif u.player_owner.civilization_id == "barbarian":
						threat_level += 1

		# Check garrison
		var garrison_strength = 0
		var garrison_units = GameManager.get_units_at(city.grid_position)
		for u in garrison_units:
			if u.player_owner == player and u.get_strength() > 0:
				garrison_strength += 1

		if garrison_strength == 0:
			threat_level += 1

		if threat_level > 0:
			needs.append({
				"city_position": city.grid_position,
				"city_name": city.city_name,
				"threat_level": threat_level,
				"garrison_strength": garrison_strength,
				"assigned_units": []
			})

	needs.sort_custom(func(a, b): return a.threat_level > b.threat_level)
	player.ai_strategy["defense_needs"] = needs

static func get_city_needing_garrison(player, unit) -> Dictionary:
	for need in player.ai_strategy.get("defense_needs", []):
		if need.threat_level > 0 and need.garrison_strength == 0:
			var assigned = need.get("assigned_units", [])
			if assigned.size() < 2:
				assigned.append(unit.get_instance_id())
				return need
	return {}

# ============ PRODUCTION ADVICE ============

static func get_production_advice(player, city, flavor: Dictionary) -> String:
	var strategy = player.ai_strategy
	if strategy.is_empty():
		return ""

	# Need settlers for expansion?
	# Allow multiple settlers in flight in parallel — the previous "one settler
	# in production at a time" guard meant only one city could expand at a time,
	# leaving large gaps where the AI built warriors instead. Cap parallelism so
	# we don't drain food/gold from every city at once.
	var desired_settlers = strategy.get("desired_settlers", 0)
	if desired_settlers > 0:
		var settlers_in_production = 0
		for c in player.cities:
			if c.current_production == "settler":
				settlers_in_production += 1
		# Allow up to ceil(desired_settlers / 2), capped at 2 simultaneous
		# settler builds across the civ (so an empire of 4+ cities can pump
		# out two colonists in parallel, but a 1-city empire still queues them).
		var max_parallel = clampi(int(ceil(desired_settlers / 2.0)), 1, 2)
		if settlers_in_production < max_parallel:
			return "settler"

	# Need military for war targets?
	if not strategy.get("war_targets", []).is_empty():
		var military_count = 0
		for u in player.units:
			if u.get_strength() > 0:
				military_count += 1
		# Want at least 3 military per war target
		var desired = strategy.war_targets.size() * 3
		if military_count < desired:
			return ""  # Let existing military logic pick the best unit

	return ""

# ============ CLEANUP ============

static func _clean_stale_data(player) -> void:
	var strategy = player.ai_strategy

	# Clean city site assignments (dead settlers)
	for site in strategy.get("city_sites", []):
		var uid = site.get("assigned_unit_id", -1)
		if uid != -1:
			var found = false
			for unit in player.units:
				if unit.get_instance_id() == uid:
					found = true
					break
			if not found:
				site["assigned_unit_id"] = -1

	# Clean war target assignments
	for target in strategy.get("war_targets", []):
		var valid_units: Array = []
		for uid in target.get("assigned_units", []):
			for unit in player.units:
				if unit.get_instance_id() == uid:
					valid_units.append(uid)
					break
		target["assigned_units"] = valid_units

	# Remove war targets for cities that no longer exist or peace made
	var valid_targets: Array = []
	for target in strategy.get("war_targets", []):
		if target.owner_id in player.at_war_with:
			var city = GameManager.get_city_at(target.city_position)
			if city != null:
				valid_targets.append(target)
	strategy["war_targets"] = valid_targets

	# Clean defense assignments
	for defense in strategy.get("defense_needs", []):
		var valid_units: Array = []
		for uid in defense.get("assigned_units", []):
			for unit in player.units:
				if unit.get_instance_id() == uid:
					valid_units.append(uid)
					break
		defense["assigned_units"] = valid_units
