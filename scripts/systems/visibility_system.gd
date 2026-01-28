extends Node
## Manages fog of war and tile visibility for players.

const GameTileClass = preload("res://scripts/map/game_tile.gd")

func _ready() -> void:
	# Apply AI visibility bonuses when game starts
	EventBus.game_started.connect(_on_game_started)

func _on_game_started() -> void:
	# Give AI players their difficulty-based map visibility bonus
	apply_all_ai_visibility_bonuses()

## Refresh visibility for a player at the start of their turn
## This fogs previously visible tiles, then recalculates based on units/cities
func refresh_visibility(player) -> void:
	if player == null or GameManager.hex_grid == null:
		return

	var player_id = player.player_id

	# First, convert all VISIBLE tiles to FOGGED
	_fog_visible_tiles(player_id)

	# Recalculate visibility from all units
	for unit in player.units:
		_reveal_tiles_around(unit.grid_position, unit.get_visibility_range(), player_id)

	# Recalculate visibility from all cities (based on cultural borders)
	for city in player.cities:
		_reveal_city_territory(city, player_id)

	# Update wrap visuals for human player (so fog of war is synced on wrap edges)
	if player == GameManager.human_player:
		GameManager.hex_grid.update_wrap_visuals()

## Get extra visibility range beyond cultural borders for a city
func get_city_extra_visibility(city) -> int:
	# Base visibility is 2 tiles beyond cultural border
	var extra_range = 2

	# Check for buildings that increase sight
	if "lighthouse" in city.buildings:
		extra_range += 1
	if "observatory" in city.buildings:
		extra_range += 1

	return extra_range

## Reveal tiles for a city based on its territory (cultural borders) + extra range
func _reveal_city_territory(city, player_id: int) -> void:
	var grid = GameManager.hex_grid
	if grid == null or city == null:
		return

	var extra_range = get_city_extra_visibility(city)

	# For each tile in the city's territory, reveal tiles within extra_range
	for territory_pos in city.territory:
		var tiles_to_reveal = GridUtils.get_tiles_in_range(territory_pos, extra_range)
		tiles_to_reveal.append(territory_pos)

		for tile_pos in tiles_to_reveal:
			var wrapped_pos = GridUtils.wrap_position(tile_pos, grid.width, grid.height)
			var tile = grid.get_tile(wrapped_pos)
			if tile != null:
				tile.visibility[player_id] = GameTileClass.VisibilityState.VISIBLE

## Fog all currently visible tiles for a player
func _fog_visible_tiles(player_id: int) -> void:
	var grid = GameManager.hex_grid
	if grid == null:
		return

	for x in range(grid.width):
		for y in range(grid.height):
			var tile = grid.get_tile(Vector2i(x, y))
			if tile != null:
				var current_vis = tile.get_visibility_for_player(player_id)
				if current_vis == GameTileClass.VisibilityState.VISIBLE:
					tile.visibility[player_id] = GameTileClass.VisibilityState.FOGGED

## Reveal tiles around a position
func _reveal_tiles_around(center: Vector2i, sight_range: int, player_id: int) -> void:
	var grid = GameManager.hex_grid
	if grid == null:
		return

	var visible_tiles = GridUtils.get_tiles_in_range(center, sight_range)
	visible_tiles.append(center)

	for tile_pos in visible_tiles:
		# Wrap position for cylindrical maps
		var wrapped_pos = GridUtils.wrap_position(tile_pos, grid.width, grid.height)
		var tile = grid.get_tile(wrapped_pos)
		if tile != null:
			tile.visibility[player_id] = GameTileClass.VisibilityState.VISIBLE

## Reveal tiles for a unit (called when unit moves)
func reveal_for_unit(unit) -> void:
	if unit == null or unit.player_owner == null:
		print("[DEBUG] reveal_for_unit: unit or player_owner is null")
		return

	var player_id = unit.player_owner.player_id
	print("[DEBUG] reveal_for_unit: player_id=%d, pos=%s, range=%d" % [player_id, unit.grid_position, unit.get_visibility_range()])
	_reveal_tiles_around(unit.grid_position, unit.get_visibility_range(), player_id)

	# Update tile visuals in the revealed area
	_update_tile_visuals_around(unit.grid_position, unit.get_visibility_range())

## Reveal tiles for a city (called when city is founded or borders expand)
func reveal_for_city(city) -> void:
	if city == null or city.player_owner == null:
		return

	var player_id = city.player_owner.player_id

	# Reveal based on territory + extra range
	_reveal_city_territory(city, player_id)

	# Update tile visuals for the entire visible area
	_update_city_tile_visuals(city)

## Update tile visuals for a city's visible area (territory + extra range)
func _update_city_tile_visuals(city) -> void:
	var grid = GameManager.hex_grid
	if grid == null or city == null:
		return

	var extra_range = get_city_extra_visibility(city)
	var updated_tiles = {}  # Use dict to avoid duplicate updates

	for territory_pos in city.territory:
		var tiles = GridUtils.get_tiles_in_range(territory_pos, extra_range)
		tiles.append(territory_pos)

		for tile_pos in tiles:
			var wrapped_pos = GridUtils.wrap_position(tile_pos, grid.width, grid.height)
			if not updated_tiles.has(wrapped_pos):
				updated_tiles[wrapped_pos] = true
				var tile = grid.get_tile(wrapped_pos)
				if tile != null:
					tile.update_visuals()

## Update tile visuals in an area
func _update_tile_visuals_around(center: Vector2i, radius: int) -> void:
	var grid = GameManager.hex_grid
	if grid == null:
		return

	var tiles = GridUtils.get_tiles_in_range(center, radius)
	tiles.append(center)

	for tile_pos in tiles:
		var wrapped_pos = GridUtils.wrap_position(tile_pos, grid.width, grid.height)
		var tile = grid.get_tile(wrapped_pos)
		if tile != null:
			tile.update_visuals()

## Update all tile visuals (call after visibility refresh)
func update_all_tile_visuals() -> void:
	var grid = GameManager.hex_grid
	if grid == null:
		return

	for x in range(grid.width):
		for y in range(grid.height):
			var tile = grid.get_tile(Vector2i(x, y))
			if tile != null:
				tile.update_visuals()

## Check if a tile is visible to a player
func is_tile_visible_to_player(tile_pos: Vector2i, player) -> bool:
	if player == null or GameManager.hex_grid == null:
		return false

	var tile = GameManager.hex_grid.get_tile(tile_pos)
	if tile == null:
		return false

	return tile.is_visible_to(player.player_id)

## Check if a tile has been explored by a player
func is_tile_explored_by_player(tile_pos: Vector2i, player) -> bool:
	if player == null or GameManager.hex_grid == null:
		return false

	var tile = GameManager.hex_grid.get_tile(tile_pos)
	if tile == null:
		return false

	return tile.is_explored_by(player.player_id)

## Apply AI difficulty visibility bonus - reveals a percentage of the map for AI players
## at higher difficulties (Emperor: 25%, Immortal: 50%, Deity: 100%)
func apply_ai_visibility_bonus(player) -> void:
	if player == null or player.is_human or GameManager.hex_grid == null:
		return

	# Get handicap data for current difficulty (difficulty is an int level)
	var handicap = DataManager.get_handicap_by_level(GameManager.difficulty)
	if handicap == null:
		return

	var ai_bonuses = handicap.get("ai_bonuses", {})
	var visibility_percent = ai_bonuses.get("map_visibility_percent", 0)

	if visibility_percent <= 0:
		return

	var grid = GameManager.hex_grid
	var player_id = player.player_id
	var total_tiles = grid.width * grid.height
	var tiles_to_reveal = int(total_tiles * visibility_percent / 100.0)

	# Collect all unexplored tiles
	var unexplored_tiles: Array[Vector2i] = []
	for x in range(grid.width):
		for y in range(grid.height):
			var tile = grid.get_tile(Vector2i(x, y))
			if tile != null and not tile.is_explored_by(player_id):
				unexplored_tiles.append(Vector2i(x, y))

	# Shuffle and reveal the required number of tiles
	unexplored_tiles.shuffle()
	var revealed_count = 0

	for tile_pos in unexplored_tiles:
		if revealed_count >= tiles_to_reveal:
			break

		var tile = grid.get_tile(tile_pos)
		if tile != null:
			# Set to FOGGED (explored but not currently visible)
			tile.visibility[player_id] = GameTileClass.VisibilityState.FOGGED
			revealed_count += 1

## Apply visibility bonuses for all AI players at game start
func apply_all_ai_visibility_bonuses() -> void:
	for player in GameManager.players:
		if not player.is_human:
			apply_ai_visibility_bonus(player)
