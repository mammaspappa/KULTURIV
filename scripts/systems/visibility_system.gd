extends Node
## Manages fog of war and tile visibility for players.

const GameTileClass = preload("res://scripts/map/game_tile.gd")

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

	# Recalculate visibility from all cities
	for city in player.cities:
		_reveal_tiles_around(city.grid_position, get_city_visibility_range(city), player_id)

## Get visibility range for a city
func get_city_visibility_range(city) -> int:
	# Base city visibility is 2, can be increased by buildings
	var base_range = 2

	# Check for buildings that increase sight
	if "lighthouse" in city.buildings:
		base_range += 1
	if "observatory" in city.buildings:
		base_range += 1

	return base_range

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

## Reveal tiles for a city (called when city is founded)
func reveal_for_city(city) -> void:
	if city == null or city.player_owner == null:
		return

	var player_id = city.player_owner.player_id
	var sight_range = get_city_visibility_range(city)
	_reveal_tiles_around(city.grid_position, sight_range, player_id)

	# Update tile visuals
	_update_tile_visuals_around(city.grid_position, sight_range)

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
