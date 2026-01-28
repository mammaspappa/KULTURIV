extends Node
## Handles tribal villages (goody huts) - discoverable rewards on the map.

# Possible rewards when discovering a goody hut
enum GoodyReward {
	GOLD,          # Bonus gold
	TECH,          # Free technology (ancient era)
	MAP,           # Reveals surrounding area
	EXPERIENCE,    # XP for discovering unit
	UNIT,          # Free unit (warrior or scout)
	SETTLER,       # Free settler (rare)
	POPULATION,    # +1 population to nearest city
	BARBARIANS,    # Triggers barbarian attack!
}

# Reward weights (higher = more common)
const REWARD_WEIGHTS = {
	GoodyReward.GOLD: 30,
	GoodyReward.TECH: 15,
	GoodyReward.MAP: 20,
	GoodyReward.EXPERIENCE: 15,
	GoodyReward.UNIT: 10,
	GoodyReward.SETTLER: 2,
	GoodyReward.POPULATION: 5,
	GoodyReward.BARBARIANS: 3,
}

signal goody_hut_discovered(unit, tile, reward_type, reward_value)

func _ready() -> void:
	# Connect to unit movement to detect goody hut discovery
	EventBus.unit_moved.connect(_on_unit_moved)

## Called when a unit moves - check if they discovered a goody hut
func _on_unit_moved(unit, _from_hex, to_hex) -> void:
	if unit == null or unit.player_owner == null:
		return

	var tile = GameManager.hex_grid.get_tile(to_hex) if GameManager.hex_grid else null
	if tile == null or not tile.has_goody_hut:
		return

	# Discovered a goody hut!
	_discover_goody_hut(unit, tile)

## Discover a goody hut and give rewards
func _discover_goody_hut(unit, tile) -> void:
	var player = unit.player_owner

	# Remove the goody hut
	tile.has_goody_hut = false
	tile.update_visuals()

	# Determine reward
	var reward_type = _pick_reward(player, unit)
	var reward_value = _apply_reward(player, unit, tile, reward_type)

	# Emit signal for UI notification
	goody_hut_discovered.emit(unit, tile, reward_type, reward_value)

	# Create notification message
	var message = _get_reward_message(reward_type, reward_value)
	EventBus.notification_added.emit(message, "discovery")

## Pick a random reward based on weights
func _pick_reward(player, unit) -> GoodyReward:
	# Calculate total weight
	var total_weight = 0
	var valid_rewards = {}

	for reward in REWARD_WEIGHTS:
		var weight = REWARD_WEIGHTS[reward]

		# Adjust weights based on conditions
		if reward == GoodyReward.TECH:
			# Only if there are ancient techs to discover
			var available_techs = _get_discoverable_techs(player)
			if available_techs.is_empty():
				continue
			weight = int(weight * 0.5) if player.researched_techs.size() > 10 else weight

		elif reward == GoodyReward.SETTLER:
			# Rare, and only if player has few cities
			if player.cities.size() > 3:
				weight = 1

		elif reward == GoodyReward.POPULATION:
			# Only if player has at least one city
			if player.cities.is_empty():
				continue

		elif reward == GoodyReward.BARBARIANS:
			# More likely in early game
			weight = int(weight * 1.5) if GameManager.turn_number < 50 else weight

		valid_rewards[reward] = weight
		total_weight += weight

	# Pick random reward
	var roll = randi() % total_weight
	var current = 0

	for reward in valid_rewards:
		current += valid_rewards[reward]
		if roll < current:
			return reward

	return GoodyReward.GOLD  # Fallback

## Apply the reward and return the value/description
func _apply_reward(player, unit, tile, reward_type: GoodyReward):
	match reward_type:
		GoodyReward.GOLD:
			var amount = 25 + randi() % 76  # 25-100 gold
			player.gold += amount
			return amount

		GoodyReward.TECH:
			var techs = _get_discoverable_techs(player)
			if not techs.is_empty():
				var tech = techs[randi() % techs.size()]
				player.add_tech(tech)
				var tech_data = DataManager.get_tech(tech)
				return tech_data.get("name", tech)
			return null

		GoodyReward.MAP:
			var radius = 3 + randi() % 3  # Reveal 3-5 tiles radius
			_reveal_map_area(player, tile.grid_position, radius)
			return radius

		GoodyReward.EXPERIENCE:
			var xp = 10 + randi() % 11  # 10-20 XP
			unit.experience += xp
			return xp

		GoodyReward.UNIT:
			var unit_type = "warrior" if randf() < 0.7 else "scout"
			_spawn_free_unit(player, tile.grid_position, unit_type)
			var unit_data = DataManager.get_unit(unit_type)
			return unit_data.get("name", unit_type)

		GoodyReward.SETTLER:
			_spawn_free_unit(player, tile.grid_position, "settler")
			return "Settler"

		GoodyReward.POPULATION:
			var city = _get_nearest_city(player, tile.grid_position)
			if city:
				city.population += 1
				return city.city_name
			return null

		GoodyReward.BARBARIANS:
			_spawn_barbarians_near(tile.grid_position)
			return "Barbarians!"

	return null

## Get techs that can be discovered from goody huts (ancient era only)
func _get_discoverable_techs(player) -> Array:
	var available = []

	for tech_id in DataManager.techs:
		if tech_id.begins_with("_"):
			continue

		if tech_id in player.researched_techs:
			continue

		var tech = DataManager.get_tech(tech_id)
		var era = tech.get("era", "ancient")

		# Only ancient era techs from goody huts
		if era != "ancient":
			continue

		# Check prerequisites are met
		var prereqs = tech.get("prerequisites", [])
		var prereqs_met = true
		for prereq in prereqs:
			if prereq not in player.researched_techs:
				prereqs_met = false
				break

		if prereqs_met:
			available.append(tech_id)

	return available

## Reveal map area around position
func _reveal_map_area(player, center: Vector2i, radius: int) -> void:
	if GameManager.hex_grid == null:
		return

	var tiles = GridUtils.get_tiles_in_range(center, radius)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile:
			tile.set_visibility_for_player(player.player_id, tile.VisibilityState.VISIBLE)

	EventBus.fog_updated.emit(player)

## Spawn a free unit near position
func _spawn_free_unit(player, pos: Vector2i, unit_type: String) -> void:
	if GameManager.game_world == null:
		return

	# Find valid spawn position
	var spawn_pos = _find_valid_spawn_position(pos, player)
	if spawn_pos == Vector2i(-1, -1):
		spawn_pos = pos

	GameManager.game_world.spawn_unit(unit_type, spawn_pos, player)

## Find a valid position to spawn a unit
func _find_valid_spawn_position(center: Vector2i, player) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	# Check center first
	var center_tile = GameManager.hex_grid.get_tile(center)
	if center_tile and center_tile.is_passable() and not center_tile.is_water():
		if GameManager.get_unit_at(center) == null:
			return center

	# Check adjacent tiles
	var neighbors = GridUtils.get_neighbors(center)
	for neighbor_pos in neighbors:
		var tile = GameManager.hex_grid.get_tile(neighbor_pos)
		if tile and tile.is_passable() and not tile.is_water():
			if GameManager.get_unit_at(neighbor_pos) == null:
				return neighbor_pos

	return Vector2i(-1, -1)

## Get nearest city to position
func _get_nearest_city(player, pos: Vector2i):
	var nearest = null
	var nearest_dist = INF

	for city in player.cities:
		var dist = GridUtils.chebyshev_distance(pos, city.grid_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = city

	return nearest

## Spawn barbarians near position (hostile response)
func _spawn_barbarians_near(pos: Vector2i) -> void:
	if GameManager.game_world == null:
		return

	# Get barbarian player
	var barbarian_player = null
	for player in GameManager.players:
		if player.civilization_id == "barbarian":
			barbarian_player = player
			break

	if barbarian_player == null:
		return

	# Spawn 1-2 barbarian warriors
	var num_barbarians = 1 + randi() % 2
	for i in range(num_barbarians):
		var spawn_pos = _find_valid_spawn_position(pos, barbarian_player)
		if spawn_pos != Vector2i(-1, -1):
			GameManager.game_world.spawn_unit("warrior", spawn_pos, barbarian_player)

## Get reward message for notifications
func _get_reward_message(reward_type: GoodyReward, value) -> String:
	match reward_type:
		GoodyReward.GOLD:
			return "Tribal village! Found %d gold!" % value
		GoodyReward.TECH:
			return "Tribal village! Learned %s!" % value if value else "Tribal village!"
		GoodyReward.MAP:
			return "Tribal village! Map revealed!"
		GoodyReward.EXPERIENCE:
			return "Tribal village! Unit gained %d experience!" % value
		GoodyReward.UNIT:
			return "Tribal village! A %s joins us!" % value
		GoodyReward.SETTLER:
			return "Tribal village! A settler joins us!"
		GoodyReward.POPULATION:
			return "Tribal village! %s gains population!" % value if value else "Tribal village!"
		GoodyReward.BARBARIANS:
			return "Tribal village was a trap! Barbarians attack!"

	return "Tribal village discovered!"

## Place goody huts on the map during generation
static func place_goody_huts(grid, density: float = 0.02) -> int:
	var placed = 0
	var width = grid.width
	var height = grid.height

	for y in range(height):
		for x in range(width):
			var tile = grid.get_tile(Vector2i(x, y))
			if tile == null:
				continue

			# Only on land, non-mountain, unowned tiles
			if tile.is_water() or tile.terrain_id == "mountain":
				continue

			# Random chance based on density
			if randf() < density:
				# Don't place too close to map edges (starting positions)
				if y > 5 and y < height - 5:
					tile.has_goody_hut = true
					placed += 1

	return placed
