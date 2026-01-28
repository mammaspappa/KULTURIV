extends Node
## Handles barbarian spawning and behavior.

# Barbarian camp properties
const CAMP_SPAWN_INTERVAL = 10  # Turns between new camp spawn attempts
const MIN_CAMP_DISTANCE = 8    # Minimum tiles between camps
const CAMP_CITY_DISTANCE = 6   # Minimum distance from any city
const MAX_CAMPS = 15           # Maximum number of barbarian camps on map
const UNIT_SPAWN_INTERVAL = 5  # Turns between unit spawns per camp

# Barbarian camp data
var barbarian_camps: Array = []  # Array of Vector2i positions

# Reference to barbarian player
var barbarian_player = null

signal barbarian_camp_spawned(position)
signal barbarian_unit_spawned(unit, camp_position)

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

	# Process barbarian camp spawning
	if TurnManager.current_turn % CAMP_SPAWN_INTERVAL == 0:
		_try_spawn_camp()

	# Process unit spawning from existing camps
	_process_camp_spawning()

	# Process barbarian unit AI
	_process_barbarian_ai()

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
	if barbarian_camps.size() >= MAX_CAMPS:
		return

	var grid = GameManager.hex_grid
	if grid == null:
		return

	# Find valid position for camp
	var attempts = 0
	var max_attempts = 100

	while attempts < max_attempts:
		var x = randi() % grid.width
		var y = 10 + randi() % (grid.height - 20)  # Avoid poles

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

	# Check visibility - prefer fog/unexplored areas
	var visible_count = 0
	for player in GameManager.players:
		if player == barbarian_player:
			continue
		if tile.is_visible_to(player.player_id):
			visible_count += 1

	# Less likely to spawn in visible areas
	if visible_count > 0 and randf() < 0.7:
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
		# Update wrap visuals for cylindrical map
		if GameManager.hex_grid:
			GameManager.hex_grid.update_wrap_tile(pos)

	barbarian_camp_spawned.emit(pos)
	EventBus.notification_added.emit("Barbarian camp spotted!", "warning")

## Process unit spawning from camps
func _process_camp_spawning() -> void:
	if barbarian_player == null:
		return

	for camp_pos in barbarian_camps:
		# Check if camp still exists
		var tile = GameManager.hex_grid.get_tile(camp_pos)
		if tile == null or tile.improvement_id != "barbarian_camp":
			barbarian_camps.erase(camp_pos)
			continue

		# Spawn interval check
		if TurnManager.current_turn % UNIT_SPAWN_INTERVAL != 0:
			continue

		# Don't spawn too many units per camp
		var nearby_barbarians = _count_nearby_barbarian_units(camp_pos, 3)
		if nearby_barbarians >= 3:
			continue

		# Spawn a unit
		_spawn_barbarian_unit(camp_pos)

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

	# Determine unit type based on era/turn
	var unit_type = _get_barbarian_unit_type()

	# Find spawn position
	var spawn_pos = _find_spawn_position(camp_pos)
	if spawn_pos == Vector2i(-1, -1):
		return

	var unit = GameManager.game_world.spawn_unit(unit_type, spawn_pos, barbarian_player)
	if unit:
		barbarian_unit_spawned.emit(unit, camp_pos)

## Get appropriate barbarian unit type for current era
func _get_barbarian_unit_type() -> String:
	var turn = TurnManager.current_turn

	# Naval units near coast (10% chance)
	if randf() < 0.1:
		if turn < 100:
			return "galley"
		elif turn < 200:
			return "caravel"
		else:
			return "frigate"

	# Land units scale with game progress
	if turn < 30:
		return "warrior"
	elif turn < 60:
		if randf() < 0.7:
			return "warrior"
		else:
			return "archer"
	elif turn < 100:
		var roll = randf()
		if roll < 0.3:
			return "warrior"
		elif roll < 0.6:
			return "archer"
		elif roll < 0.85:
			return "axeman"
		else:
			return "chariot"
	elif turn < 150:
		var roll = randf()
		if roll < 0.25:
			return "archer"
		elif roll < 0.5:
			return "axeman"
		elif roll < 0.75:
			return "swordsman"
		else:
			return "horseman"
	else:
		var roll = randf()
		if roll < 0.2:
			return "swordsman"
		elif roll < 0.4:
			return "crossbowman"
		elif roll < 0.6:
			return "maceman"
		elif roll < 0.8:
			return "knight"
		else:
			return "longbowman"

## Find valid spawn position near camp
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
	# Priority 1: Attack adjacent enemies
	var adjacent_target = _find_adjacent_enemy(unit)
	if adjacent_target:
		CombatSystem.resolve_combat(unit, adjacent_target)
		return

	# Priority 2: Move toward nearby enemy units/improvements
	var nearby_target = _find_nearby_target(unit)
	if nearby_target:
		_move_toward(unit, nearby_target)
		return

	# Priority 3: Pillage improvements
	var tile = GameManager.hex_grid.get_tile(unit.grid_position)
	if tile and tile.improvement_id != "" and tile.improvement_id != "barbarian_camp":
		if tile.tile_owner != null and tile.tile_owner != barbarian_player:
			tile.improvement_id = ""
			tile.update_visuals()
			# Update wrap visuals for cylindrical map
			if GameManager.hex_grid:
				GameManager.hex_grid.update_wrap_tile(unit.grid_position)
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
func _find_nearby_target(unit) -> Vector2i:
	var grid = GameManager.hex_grid
	if grid == null:
		return Vector2i(-1, -1)

	var search_radius = 5
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
	var pathfinder = Pathfinding.new(GameManager.hex_grid, unit)
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

## Random movement for idle barbarians
func _random_move(unit) -> void:
	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	neighbors.shuffle()

	for neighbor_pos in neighbors:
		var tile = GameManager.hex_grid.get_tile(neighbor_pos)
		if tile == null:
			continue

		if not tile.is_passable() or tile.is_water():
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
		# Update wrap visuals for cylindrical map
		if GameManager.hex_grid:
			GameManager.hex_grid.update_wrap_tile(pos)

	# Award gold to capturing player
	EventBus.notification_added.emit("Barbarian camp destroyed! +25 Gold", "positive")

## Check if a position has a barbarian camp
func has_camp_at(pos: Vector2i) -> bool:
	return pos in barbarian_camps

## Get all barbarian camp positions
func get_camp_positions() -> Array:
	return barbarian_camps.duplicate()

# Serialization
func to_dict() -> Dictionary:
	var camps_data = []
	for pos in barbarian_camps:
		camps_data.append({"x": pos.x, "y": pos.y})

	return {
		"barbarian_camps": camps_data
	}

func from_dict(data: Dictionary) -> void:
	barbarian_camps.clear()
	var camps_data = data.get("barbarian_camps", [])
	for camp in camps_data:
		barbarian_camps.append(Vector2i(camp.x, camp.y))
