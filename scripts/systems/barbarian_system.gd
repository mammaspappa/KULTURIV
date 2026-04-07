extends Node
## Handles barbarian spawning and behavior.
## BTS mechanic: camps spawn in fog of war, and after ~1000 BC camps may
## evolve into aggressive barbarian civilizations.

const PlayerClass = preload("res://scripts/core/player.gd")
const PathfindingClass = preload("res://scripts/map/pathfinding.gd")
const CityClass = preload("res://scripts/entities/city.gd")

# Barbarian camp properties
const CAMP_SPAWN_INTERVAL = 10  # Turns between new camp spawn attempts
const MIN_CAMP_DISTANCE = 8    # Minimum tiles between camps
const CAMP_CITY_DISTANCE = 6   # Minimum distance from any city
const MAX_CAMPS = 15           # Maximum number of barbarian camps on map
const UNIT_SPAWN_INTERVAL = 5  # Turns between unit spawns per camp

# Barbarian city founding (base values for Normal speed, standard map)
const CITY_FOUNDING_BASE_MIN_TURN = 75  # ~1000 BC on Normal speed
const CITY_FOUNDING_BASE_INTERVAL = 5   # Check interval on Normal speed
const CITY_FOUNDING_BASE_CHANCE = 0.08  # 8% base chance per eligible camp
const CITY_FOUNDING_SCORE_BONUS = 0.005 # Extra chance per city site score point
const MAX_BARBARIAN_CIVS_BASE = 3       # Max barb civs on standard map

# Barbarian camp data
var barbarian_camps: Array = []  # Array of Vector2i positions

# Reference to barbarian player
var barbarian_player = null

# Track spawned barbarian civs
var barbarian_civ_count: int = 0

# City names for barbarian civilizations
const BARBARIAN_CITY_NAMES = [
	"Skull Keep", "Bloodfang", "Iron Maw", "Dreadfort", "Bonecrusher",
	"Ashfall", "Grimhold", "Wolfsbane", "Darkspire", "Ravencrest",
	"Thornwall", "Viperhold", "Wargoth", "Ironfist", "Blackthorn"
]

# Barbarian civ names
const BARBARIAN_CIV_NAMES = [
	"Horde of the Wastes", "Raiders of the North", "Marauders",
	"Iron Horde", "Warlords of the Steppe", "Pillagers"
]

signal barbarian_camp_spawned(position)
signal barbarian_unit_spawned(unit, camp_position)
signal barbarian_civ_spawned(player, city)

func _ready() -> void:
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.game_started.connect(_on_game_started)

func _on_game_started() -> void:
	# Find or create barbarian player
	_ensure_barbarian_player()

	# Spawn initial camps
	_spawn_initial_camps()

func _on_turn_ended(_turn_number: int, player) -> void:
	# Only process at end of all player turns
	if player != null and player != barbarian_player:
		return

	# Process barbarian camp spawning (scale interval with game speed)
	var camp_interval = max(1, int(CAMP_SPAWN_INTERVAL * GameManager.get_speed_multiplier()))
	if TurnManager.current_turn % camp_interval == 0:
		_try_spawn_camp()

	# Process unit spawning from existing camps
	_process_camp_spawning()

	# BTS: spontaneous barbarian spawning in fog of war (no camp needed)
	_try_spontaneous_spawn()

	# Process barbarian unit AI
	_process_barbarian_ai()

	# Check for barbarian city founding (BTS: camps evolve into aggressive civs)
	var min_turn = _get_scaled_min_turn()
	var interval = _get_scaled_interval()
	if TurnManager.current_turn >= min_turn and TurnManager.current_turn % interval == 0:
		_try_found_barbarian_city()

## Ensure barbarian player exists
func _ensure_barbarian_player() -> void:
	for player in GameManager.players:
		if player.civilization_id == "barbarian":
			barbarian_player = player
			return

	# Create barbarian player if doesn't exist
	var Player = load("res://scripts/core/player.gd")
	barbarian_player = Player.new()
	barbarian_player.player_id = -1  # Special ID for barbarians
	barbarian_player.civilization_id = "barbarian"
	barbarian_player.player_name = "Barbarians"
	barbarian_player.color = Color.RED
	barbarian_player.is_human = false
	GameManager.players.append(barbarian_player)

## Spawn initial barbarian camps at game start
func _spawn_initial_camps() -> void:
	var num_initial = 3 + randi() % 3  # 3-5 initial camps

	for i in range(num_initial):
		_try_spawn_camp()

## Try to spawn a new barbarian camp
func _try_spawn_camp() -> void:
	var grid = GameManager.hex_grid
	if grid == null:
		return

	# Scale max camps with map size
	var map_tiles = grid.width * grid.height
	var max_camps = clampi(map_tiles / 200, 3, MAX_CAMPS)
	if barbarian_camps.size() >= max_camps:
		return

	# Find valid position for camp
	var attempts = 0
	var max_attempts = 100

	while attempts < max_attempts:
		var x = randi() % grid.width
		var y_margin = min(10, grid.height / 4)
		var y_range = max(1, grid.height - y_margin * 2)
		var y = y_margin + randi() % y_range  # Avoid poles, safe on small maps

		var pos = Vector2i(x, y)
		if _is_valid_camp_position(pos):
			_create_camp(pos)
			return

		attempts += 1

## Check if position is valid for a barbarian camp
func _is_valid_camp_position(pos: Vector2i) -> bool:
	var grid = GameManager.hex_grid
	if grid == null:
		return false

	var tile = grid.get_tile(pos)
	if tile == null:
		return false

	# Must be passable land
	if not tile.is_passable() or tile.is_water():
		return false

	# Cannot be in owned territory
	if tile.tile_owner != null:
		return false

	# BTS: camps only spawn in fog of war — no civ units within 3 tiles
	var tiles_nearby = GridUtils.get_tiles_in_range(pos, 3)
	for near_pos in tiles_nearby:
		var units_here = GameManager.get_units_at(near_pos)
		for u in units_here:
			if u.player_owner != null and u.player_owner.civilization_id != "barbarian":
				return false  # Civ unit nearby, not in fog

	# Cannot have goody hut
	if tile.has_goody_hut:
		return false

	# Cannot have existing improvement
	if tile.improvement_id != "":
		return false

	# Check distance from existing camps
	for camp_pos in barbarian_camps:
		if GridUtils.chebyshev_distance(pos, camp_pos) < MIN_CAMP_DISTANCE:
			return false

	# Check distance from cities
	for player in GameManager.players:
		if player == barbarian_player:
			continue
		for city in player.cities:
			if GridUtils.chebyshev_distance(pos, city.grid_position) < CAMP_CITY_DISTANCE:
				return false

	# BTS: camps ONLY spawn in fog of war (not visible to any player)
	for player in GameManager.players:
		if player == barbarian_player:
			continue
		if tile.is_visible_to(player.player_id):
			return false

	return true

## Create a barbarian camp at position
func _create_camp(pos: Vector2i) -> void:
	barbarian_camps.append(pos)

	# Mark tile as having a camp (using improvement system)
	var tile = GameManager.hex_grid.get_tile(pos)
	if tile:
		tile.improvement_id = "barbarian_camp"
		tile.update_visuals()

	barbarian_camp_spawned.emit(pos)
	EventBus.notification_added.emit("Barbarian camp spotted!", "warning")

## Process unit spawning from camps
func _process_camp_spawning() -> void:
	if barbarian_player == null:
		return

	# Global barbarian unit cap (same as spontaneous spawn)
	var grid = GameManager.hex_grid
	var map_tiles = grid.width * grid.height if grid else 800
	var max_barb_units = clampi(map_tiles / 100, 4, 12)
	if barbarian_player.units.size() >= max_barb_units:
		return

	for camp_pos in barbarian_camps:
		# Check if camp still exists
		var tile = GameManager.hex_grid.get_tile(camp_pos)
		if tile == null or tile.improvement_id != "barbarian_camp":
			barbarian_camps.erase(camp_pos)
			continue

		# Spawn interval check (scale with game speed)
		var unit_interval = max(1, int(UNIT_SPAWN_INTERVAL * GameManager.get_speed_multiplier()))
		if TurnManager.current_turn % unit_interval != 0:
			continue

		# Don't spawn too many units per camp
		var nearby_barbarians = _count_nearby_barbarian_units(camp_pos, 3)
		if nearby_barbarians >= 3:
			continue

		# Spawn a unit
		_spawn_barbarian_unit(camp_pos)

## BTS: Barbarians spawn spontaneously in fog of war areas (no camp needed)
func _try_spontaneous_spawn() -> void:
	if barbarian_player == null or GameManager.hex_grid == null:
		return

	# Limit total barbarian units — scale with map size, cap lower for small maps
	var grid = GameManager.hex_grid
	var map_tiles = grid.width * grid.height if grid else 800
	var max_barb_units = clampi(map_tiles / 100, 4, 12)
	if barbarian_player.units.size() >= max_barb_units:
		return

	# Scale spawn frequency with game speed and map size
	var speed = GameManager.get_speed_multiplier()
	var spawn_interval = max(2, int(4 * speed))
	if TurnManager.current_turn % spawn_interval != 0:
		return

	# Try to find a valid fog-of-war tile
	var attempts = 0
	while attempts < 50:
		attempts += 1
		var x = randi() % grid.width
		var y_margin = min(5, grid.height / 4)
		var y_range = max(1, grid.height - y_margin * 2)
		var y = y_margin + randi() % y_range

		var pos = Vector2i(x, y)
		var tile = grid.get_tile(pos)
		if tile == null or not tile.is_passable() or tile.is_water():
			continue
		if tile.tile_owner != null:
			continue  # Not in civilized territory

		# Must be in fog of war — no civ units within 3 tiles
		var civ_nearby = false
		var tiles_nearby = GridUtils.get_tiles_in_range(pos, 3)
		for near_pos in tiles_nearby:
			var units_here = GameManager.get_units_at(near_pos)
			for u in units_here:
				if u.player_owner != null and u.player_owner.civilization_id != "barbarian":
					civ_nearby = true
					break
			if civ_nearby:
				break
		if civ_nearby:
			continue

		# Don't stack barbarians
		var existing = GameManager.get_units_at(pos)
		if not existing.is_empty():
			continue

		# Fog-bust: no barb unit within 3 tiles of another barb unit
		var barb_nearby = false
		for near_pos in tiles_nearby:
			for u in GameManager.get_units_at(near_pos):
				if u.player_owner != null and u.player_owner.civilization_id == "barbarian":
					barb_nearby = true
					break
			if barb_nearby:
				break
		if barb_nearby:
			continue

		# Spawn the unit
		var unit_type = _get_barbarian_unit_type()
		if GameManager.game_world:
			var unit = GameManager.game_world.spawn_unit(unit_type, pos, barbarian_player)
			if unit:
				unit.refresh_movement()  # Enable movement on spawn turn
		return

## Count barbarian units near a position
func _count_nearby_barbarian_units(pos: Vector2i, radius: int) -> int:
	var count = 0
	if barbarian_player == null:
		return 0

	for unit in barbarian_player.units:
		if GridUtils.chebyshev_distance(pos, unit.grid_position) <= radius:
			count += 1

	return count

## Spawn a barbarian unit from a camp
func _spawn_barbarian_unit(camp_pos: Vector2i) -> void:
	if GameManager.game_world == null:
		return

	# Try spawning a naval unit if camp is coastal (10% chance)
	if randf() < 0.1:
		var water_pos = _find_adjacent_water(camp_pos)
		if water_pos != Vector2i(-1, -1):
			var naval_type = _get_barbarian_naval_type()
			if naval_type != "":
				var unit = GameManager.game_world.spawn_unit(naval_type, water_pos, barbarian_player)
				if unit:
					unit.refresh_movement()  # Enable movement on spawn turn
					barbarian_unit_spawned.emit(unit, camp_pos)
				return

	# Spawn a land unit (camp spawns skip fog-bust — camps are meant to cluster units)
	var unit_type = _get_barbarian_unit_type()
	var spawn_pos = _find_spawn_position(camp_pos)
	if spawn_pos == Vector2i(-1, -1):
		return

	var unit = GameManager.game_world.spawn_unit(unit_type, spawn_pos, barbarian_player)
	if unit:
		unit.refresh_movement()  # Enable movement on spawn turn
		barbarian_unit_spawned.emit(unit, camp_pos)

## Get appropriate barbarian unit type based on real civ tech progress.
## BTS: first 2000 years are "animal era" — only animals spawn (represented as warriors).
## After that, military units based on 50% civ tech threshold.
func _get_barbarian_unit_type() -> String:
	# Animal era: first 2000 years (4000 BC → 2000 BC) — only animals
	if _is_animal_era():
		return "warrior"  # Animals represented as warriors
	# Build pool of units that barbarians can spawn based on civ tech progress
	var pool = _get_available_barb_units(false)
	if pool.is_empty():
		return "warrior"  # Fallback
	return pool[randi() % pool.size()]

## Check if we're in the animal era (first 2000 years of the game)
func _is_animal_era() -> bool:
	return TurnManager.current_year < -2000  # Before 2000 BC

## Get a naval unit type if enough civs have the tech, or "" if none available.
func _get_barbarian_naval_type() -> String:
	var pool = _get_available_barb_units(true)
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]

## Build pool of units barbarians can spawn. Requires >= 50% of real civs to
## have the required tech. naval_only filters to naval/land units.
func _get_available_barb_units(naval_only: bool) -> Array:
	# Count real (non-barbarian) civs
	var real_civs: Array = []
	for p in GameManager.players:
		if p.civilization_id != "barbarian":
			real_civs.append(p)
	var threshold = max(1, real_civs.size() / 2)  # 50% rounded down, min 1

	# Barbarian unit progression: unit_id -> required_tech
	# Land units (ordered by era)
	var land_units = {
		"warrior": "",               # Always available
		"archer": "archery",
		"axeman": "bronze_working",
		"chariot": "the_wheel",
		"spearman": "bronze_working",
		"swordsman": "iron_working",
		"horseman": "horseback_riding",
		"crossbowman": "machinery",
		"maceman": "machinery",
		"longbowman": "machinery",
		"knight": "guilds",
		"musketman": "gunpowder",
		"grenadier": "chemistry",
		"rifleman": "rifling",
	}
	# Naval units
	var naval_units = {
		"galley": "sailing",
		"caravel": "astronomy",
		"frigate": "astronomy",
	}

	var source = naval_units if naval_only else land_units
	var pool: Array = []

	for unit_id in source:
		var req_tech = source[unit_id]
		if req_tech == "":
			pool.append(unit_id)
			continue
		# Count how many real civs have this tech
		var have_count = 0
		for civ in real_civs:
			if civ.has_tech(req_tech):
				have_count += 1
		if have_count >= threshold:
			pool.append(unit_id)

	# Bias toward more advanced units: keep only the top half of available units
	# (so once swordsmen unlock, warriors become rare)
	if pool.size() > 2:
		var keep = max(2, pool.size() / 2)
		pool = pool.slice(pool.size() - keep)

	return pool

## Check if any barbarian unit is within range of a position (for fog-busting)
func _barb_unit_within_range(pos: Vector2i, radius: int) -> bool:
	if barbarian_player == null:
		return false
	for unit in barbarian_player.units:
		if is_instance_valid(unit) and GridUtils.chebyshev_distance(pos, unit.grid_position) <= radius:
			return true
	# Also check spawned barbarian civ units
	for p in GameManager.players:
		if p.civilization_id == "barbarian" and p.player_id != -1:
			for unit in p.units:
				if is_instance_valid(unit) and GridUtils.chebyshev_distance(pos, unit.grid_position) <= radius:
					return true
	return false

## Find an adjacent water tile for spawning naval units
func _find_adjacent_water(pos: Vector2i) -> Vector2i:
	var grid = GameManager.hex_grid
	if grid == null:
		return Vector2i(-1, -1)
	var neighbors = GridUtils.get_neighbors(pos)
	neighbors.shuffle()
	for n_pos in neighbors:
		var tile = grid.get_tile(n_pos)
		if tile and tile.is_water() and GameManager.get_unit_at(n_pos) == null:
			return n_pos
	return Vector2i(-1, -1)

## Find valid spawn position near camp (land only)
func _find_spawn_position(camp_pos: Vector2i) -> Vector2i:
	var grid = GameManager.hex_grid
	if grid == null:
		return Vector2i(-1, -1)

	# Check camp tile first
	var camp_tile = grid.get_tile(camp_pos)
	if camp_tile and GameManager.get_unit_at(camp_pos) == null:
		return camp_pos

	# Check adjacent tiles
	var neighbors = GridUtils.get_neighbors(camp_pos)
	neighbors.shuffle()

	for neighbor_pos in neighbors:
		var tile = grid.get_tile(neighbor_pos)
		if tile and tile.is_passable() and not tile.is_water():
			if GameManager.get_unit_at(neighbor_pos) == null:
				return neighbor_pos

	return Vector2i(-1, -1)

## Process AI for barbarian units
func _process_barbarian_ai() -> void:
	if barbarian_player == null:
		return

	for unit in barbarian_player.units:
		if unit.movement_remaining <= 0:
			continue

		_process_single_barbarian(unit)

## Process AI for a single barbarian unit
func _process_single_barbarian(unit) -> void:
	# Animal era: animals wander randomly, attack lone units they stumble on,
	# but avoid cities and don't pillage. They're a nuisance, not a threat.
	if _is_animal_era():
		# Attack adjacent non-city units only (animals don't siege cities)
		var adjacent_target = _find_adjacent_enemy(unit)
		if adjacent_target:
			# Don't attack units in cities
			if GameManager.get_city_at(adjacent_target.grid_position) == null:
				CombatSystem.resolve_combat(unit, adjacent_target)
				return
		# Flee from cities/civ territory
		var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
		if tile and tile.tile_owner != null and tile.tile_owner != barbarian_player:
			_random_move(unit)
			return
		# Wander randomly
		_random_move(unit)
		return

	# === Post-animal era: full barbarian behavior ===

	# Priority 1: Attack adjacent enemies
	var adjacent_target = _find_adjacent_enemy(unit)
	if adjacent_target:
		CombatSystem.resolve_combat(unit, adjacent_target)
		return

	# Priority 2: Move toward nearby enemy units/improvements
	var nearby_target = _find_nearby_target(unit)
	if nearby_target != Vector2i(-1, -1):
		_move_toward(unit, nearby_target)
		return

	# Priority 3: Pillage improvements
	var tile = GameManager.hex_grid.get_tile(unit.grid_position)
	if tile and tile.improvement_id != "" and tile.improvement_id != "barbarian_camp":
		if tile.tile_owner != null and tile.tile_owner != barbarian_player:
			tile.improvement_id = ""
			tile.update_visuals()
			EventBus.notification_added.emit("Barbarians pillaged an improvement!", "warning")
			return

	# Priority 4: Random movement
	_random_move(unit)

## Find adjacent enemy unit to attack
func _find_adjacent_enemy(unit):
	var neighbors = GridUtils.get_neighbors(unit.grid_position)

	for neighbor_pos in neighbors:
		var target = GameManager.get_unit_at(neighbor_pos)
		if target and target.player_owner != barbarian_player:
			return target

	return null

## Find nearby target (enemy unit or improvement to pillage)
## BTS: barbarians have normal sight range (2 tiles), not omniscient vision
func _find_nearby_target(unit) -> Vector2i:
	var grid = GameManager.hex_grid
	if grid == null:
		return Vector2i(-1, -1)

	var search_radius = 2  # Normal unit sight range
	var best_target = Vector2i(-1, -1)
	var best_priority = 0

	var tiles_in_range = GridUtils.get_tiles_in_range(unit.grid_position, search_radius)

	for pos in tiles_in_range:
		# Check for enemy units
		var target_unit = GameManager.get_unit_at(pos)
		if target_unit and target_unit.player_owner != barbarian_player:
			var dist = GridUtils.chebyshev_distance(unit.grid_position, pos)
			var priority = 100 - dist  # Higher priority for closer units
			if priority > best_priority:
				best_priority = priority
				best_target = pos

		# Check for improvements to pillage
		var tile = grid.get_tile(pos)
		if tile and tile.improvement_id != "" and tile.improvement_id != "barbarian_camp":
			if tile.tile_owner != null and tile.tile_owner != barbarian_player:
				var dist = GridUtils.chebyshev_distance(unit.grid_position, pos)
				var priority = 50 - dist
				if priority > best_priority:
					best_priority = priority
					best_target = pos

	return best_target

## Move unit toward a target position
func _move_toward(unit, target_pos: Vector2i) -> void:
	var pathfinder = PathfindingClass.new(GameManager.hex_grid, unit)
	var path = pathfinder.find_path(unit.grid_position, target_pos)

	if path.size() > 1:
		var next_pos = path[1]
		var tile = GameManager.hex_grid.get_tile(next_pos)
		if tile and tile.is_passable():
			var cost = tile.get_total_movement_cost()
			if unit.movement_remaining >= cost:
				unit.grid_position = next_pos
				unit.movement_remaining -= cost
				unit.position = GridUtils.grid_to_pixel(next_pos)

## Random movement for idle barbarians (handles both land and naval units)
func _random_move(unit) -> void:
	var is_naval = unit.get_unit_class() == "naval"
	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	neighbors.shuffle()

	for neighbor_pos in neighbors:
		var tile = GameManager.hex_grid.get_tile(neighbor_pos)
		if tile == null:
			continue

		if not tile.is_passable():
			continue

		# Naval units move on water, land units on land
		if is_naval and not tile.is_water():
			continue
		if not is_naval and tile.is_water():
			continue

		if GameManager.get_unit_at(neighbor_pos) != null:
			continue

		var cost = tile.get_total_movement_cost()
		if unit.movement_remaining >= cost:
			unit.grid_position = neighbor_pos
			unit.movement_remaining -= cost
			unit.position = GridUtils.grid_to_pixel(neighbor_pos)
			return

## Destroy a barbarian camp (called when captured)
func destroy_camp(pos: Vector2i) -> void:
	if pos in barbarian_camps:
		barbarian_camps.erase(pos)

	var tile = GameManager.hex_grid.get_tile(pos)
	if tile and tile.improvement_id == "barbarian_camp":
		tile.improvement_id = ""
		tile.update_visuals()

	# Award gold to capturing player
	EventBus.notification_added.emit("Barbarian camp destroyed! +25 Gold", "positive")

## Check if a position has a barbarian camp
func has_camp_at(pos: Vector2i) -> bool:
	return pos in barbarian_camps

## Get all barbarian camp positions
func get_camp_positions() -> Array:
	return barbarian_camps.duplicate()

# ============ BARBARIAN CITY FOUNDING ============
# BTS mechanic: camps in fog of war can evolve into aggressive barbarian civs.
# Better locations have higher chance. The new civ is permanently hostile.

## Get min turn scaled by game speed (Marathon=3x more turns, Quick=0.67x)
func _get_scaled_min_turn() -> int:
	return int(CITY_FOUNDING_BASE_MIN_TURN * GameManager.get_speed_multiplier())

## Get check interval scaled by game speed
func _get_scaled_interval() -> int:
	return max(1, int(CITY_FOUNDING_BASE_INTERVAL * GameManager.get_speed_multiplier()))

## Get max barbarian civs scaled by map size
func _get_max_barbarian_civs() -> int:
	var map_tiles = GameManager.map_width * GameManager.map_height
	# Standard map ~4000 tiles = 3 civs, larger maps get more, smaller get fewer
	var scale = float(map_tiles) / 4000.0
	return clampi(int(MAX_BARBARIAN_CIVS_BASE * scale), 1, 6)

## Try to found a barbarian city from an eligible camp
func _try_found_barbarian_city() -> void:
	if barbarian_civ_count >= _get_max_barbarian_civs():
		return

	var grid = GameManager.hex_grid
	if grid == null:
		return

	# Score each camp and check eligibility
	var eligible_camps: Array = []

	for camp_pos in barbarian_camps:
		# Camp must still be in fog of war (not visible to any player)
		var tile = grid.get_tile(camp_pos)
		if tile == null:
			continue

		var in_fog = true
		for player in GameManager.players:
			if player == barbarian_player:
				continue
			if tile.is_visible_to(player.player_id):
				in_fog = false
				break

		if not in_fog:
			continue

		# Must be far enough from existing cities
		var too_close = false
		for player in GameManager.players:
			for city in player.cities:
				if GridUtils.chebyshev_distance(camp_pos, city.grid_position) < CAMP_CITY_DISTANCE:
					too_close = true
					break
			if too_close:
				break
		if too_close:
			continue

		# Score the site (reuse logic similar to ai_strategy)
		var site_score = _score_barbarian_city_site(camp_pos)
		if site_score < 30:
			continue  # Not a good enough location

		# Higher score = higher chance of spawning
		var spawn_chance = CITY_FOUNDING_BASE_CHANCE + site_score * CITY_FOUNDING_SCORE_BONUS
		spawn_chance = clamp(spawn_chance, 0.0, 0.5)

		eligible_camps.append({"position": camp_pos, "score": site_score, "chance": spawn_chance})

	if eligible_camps.is_empty():
		return

	# Sort by score descending — best camps try first
	eligible_camps.sort_custom(func(a, b): return a.score > b.score)

	# Try to spawn from the best camp
	for camp_data in eligible_camps:
		if randf() < camp_data.chance:
			_create_barbarian_civilization(camp_data.position, camp_data.score)
			return  # Only one per check interval

## Score a position for barbarian city founding (simplified version of ai_strategy scoring)
func _score_barbarian_city_site(pos: Vector2i) -> int:
	var grid = GameManager.hex_grid
	if grid == null:
		return 0

	var score = 0
	var food_count = 0

	# Evaluate tiles in radius 2 (city working radius)
	var tiles = GridUtils.get_tiles_in_range(pos, 2)
	for tile_pos in tiles:
		var tile = grid.get_tile(tile_pos)
		if tile == null:
			continue
		score += tile.get_food() * 4
		score += tile.get_production() * 3
		score += tile.get_commerce() * 2
		if tile.get_food() >= 1:
			food_count += 1
		if tile.resource_id != "":
			score += 15

	# Need minimum food
	if food_count < 2:
		return 0

	# Fresh water bonus
	var center_tile = grid.get_tile(pos)
	if center_tile and center_tile.has_fresh_water():
		score += 10

	# Coastal bonus
	var neighbors = GridUtils.get_neighbors(pos)
	for n_pos in neighbors:
		var n_tile = grid.get_tile(n_pos)
		if n_tile and n_tile.is_water():
			score += 8
			break

	return max(0, score)

## Create a new aggressive barbarian civilization from a camp
func _create_barbarian_civilization(camp_pos: Vector2i, site_score: int) -> void:
	# Remove camp
	barbarian_camps.erase(camp_pos)

	var tile = GameManager.hex_grid.get_tile(camp_pos)
	if tile:
		tile.improvement_id = ""

	# Create new player
	var new_player = PlayerClass.new()
	new_player.player_id = GameManager.players.size()
	new_player.civilization_id = "barbarian"
	new_player.is_human = false
	new_player.team = new_player.player_id  # Own team (hostile to all)
	new_player.color = _get_barbarian_color()

	# Give them a barbarian civ identity
	var civ_name = BARBARIAN_CIV_NAMES[barbarian_civ_count % BARBARIAN_CIV_NAMES.size()]
	new_player.player_name = civ_name

	# Aggressive personality — warlike, refuses peace, no trade
	new_player.ai_personality = {
		"base_peace_weight": 0,     # Never wants peace
		"warmonger_respect": 0,     # Doesn't respect strength
		"max_war_rand": 10,         # Very high war chance (10% per turn)
		"make_peace_rand": 200,     # Almost never considers peace
		"dogpile_war_rand": 5,      # Loves dogpiling
		"raze_city_prob": 80,       # Razes most captured cities
		"build_unit_prob": 60,      # Heavy military production
		"wonder_construct_rand": 0, # Never builds wonders
		"espionage_weight": 0,      # No espionage
		"base_attitude": -5,        # Hostile to everyone
	}

	# Give era-appropriate techs
	_grant_era_techs(new_player)

	# Starting gold scales with game progress
	new_player.gold = 50 + TurnManager.current_turn

	# Set aggressive civics (if available)
	new_player.civics = CivicsSystem.get_default_civics()

	GameManager.players.append(new_player)

	# Create the city
	var city_name = BARBARIAN_CITY_NAMES[(barbarian_civ_count * 3 + randi() % 3) % BARBARIAN_CITY_NAMES.size()]
	var city = CityClass.new(camp_pos, city_name)
	city.original_owner_id = new_player.player_id
	city.founder_civ_id = "barbarian"
	new_player.add_city(city)

	# Add to scene tree
	if GameManager.game_world and GameManager.game_world.entity_layer:
		GameManager.game_world.entity_layer.add_child(city)

	# Give starting population based on era
	var bonus_pop = TurnManager.current_turn / 50  # 1-2 extra pop at later turns
	for _i in range(bonus_pop):
		city.population += 1

	# Give palace and basic buildings
	city.buildings.append("palace")
	city.buildings.append("barracks")
	city.calculate_yields()

	# Set tile ownership
	for tile_pos in city.territory:
		var t = GameManager.hex_grid.get_tile(tile_pos)
		if t:
			t.tile_owner = new_player
			t.city_owner = city
			t.update_visuals()

	# Spawn garrison units
	var num_units = 2 + randi() % 2  # 2-3 starting units
	var unit_type = _get_barbarian_unit_type()
	for _i in range(num_units):
		var spawn_pos = _find_spawn_position(camp_pos)
		if spawn_pos != Vector2i(-1, -1) and GameManager.game_world:
			GameManager.game_world.spawn_unit(unit_type, spawn_pos, new_player)

	# Declare war on all known players (permanently hostile)
	for player in GameManager.players:
		if player == new_player or player == barbarian_player:
			continue
		GameManager.declare_war(new_player, player)
		new_player.met_players.append(player.player_id)
		if new_player.player_id not in player.met_players:
			player.met_players.append(new_player.player_id)

	barbarian_civ_count += 1
	barbarian_civ_spawned.emit(new_player, city)
	EventBus.notification_added.emit("The %s have risen from the wilderness!" % civ_name, "warning")

## Grant era-appropriate techs to a barbarian civ
func _grant_era_techs(player) -> void:
	var speed = GameManager.get_speed_multiplier()
	var normalized_turn = TurnManager.current_turn / speed

	# Always start with ancient techs
	var basic_techs = ["agriculture", "hunting", "mining", "the_wheel", "archery", "bronze_working", "warrior_code"]
	for tech_id in basic_techs:
		if tech_id not in player.researched_techs:
			player.researched_techs.append(tech_id)

	# Add more techs based on game progression (normalized to Normal speed)
	if normalized_turn >= 100:
		var classical_techs = ["iron_working", "horseback_riding", "construction", "mathematics"]
		for tech_id in classical_techs:
			if tech_id not in player.researched_techs:
				player.researched_techs.append(tech_id)

	if normalized_turn >= 150:
		var medieval_techs = ["machinery", "engineering", "civil_service", "feudalism"]
		for tech_id in medieval_techs:
			if tech_id not in player.researched_techs:
				player.researched_techs.append(tech_id)

## Get a color for the new barbarian civilization
func _get_barbarian_color() -> Color:
	var colors = [
		Color("#8B0000"),  # Dark red
		Color("#4B0082"),  # Indigo
		Color("#556B2F"),  # Dark olive
		Color("#8B4513"),  # Saddle brown
		Color("#2F4F4F"),  # Dark slate
		Color("#800080"),  # Purple
	]
	return colors[barbarian_civ_count % colors.size()]

# Serialization
func to_dict() -> Dictionary:
	var camps_data = []
	for pos in barbarian_camps:
		camps_data.append({"x": pos.x, "y": pos.y})

	return {
		"barbarian_camps": camps_data,
		"barbarian_civ_count": barbarian_civ_count
	}

func from_dict(data: Dictionary) -> void:
	barbarian_camps.clear()
	var camps_data = data.get("barbarian_camps", [])
	for camp in camps_data:
		barbarian_camps.append(Vector2i(camp.x, camp.y))
	barbarian_civ_count = data.get("barbarian_civ_count", 0)
