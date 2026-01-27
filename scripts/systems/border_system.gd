extends Node
## Handles border-related logic including forced unit movement when borders change.

func _ready() -> void:
	# Connect to relevant signals
	EventBus.city_borders_expanded.connect(_on_city_borders_expanded)
	EventBus.peace_declared.connect(_on_peace_declared)
	EventBus.open_borders_ended.connect(_on_open_borders_ended)
	EventBus.war_declared.connect(_on_war_declared)

func _on_city_borders_expanded(city) -> void:
	on_borders_change(city)

func _on_peace_declared(player1, player2) -> void:
	on_peace_declared(player1.player_id, player2.player_id)

func _on_open_borders_ended(player1, player2) -> void:
	on_open_borders_ended(player1.player_id, player2.player_id)

func _on_war_declared(aggressor, target) -> void:
	on_war_declared(aggressor.player_id, target.player_id)

## Called when a city's borders change - check for units that need to be expelled
## This handles expansion, capture, or any other border modifications
func on_borders_change(city) -> void:
	if city == null or city.player_owner == null:
		return

	var owner = city.player_owner
	var expelled_units = []

	# Check all tiles in the city's territory for foreign units
	for tile_pos in city.territory:
		var units_at_pos = GameManager.get_units_at(tile_pos)
		for unit in units_at_pos:
			if unit.player_owner == null:
				continue
			if unit.player_owner == owner:
				continue

			# Check if this unit is allowed in the borders
			if not unit.player_owner.can_enter_borders_of(owner.player_id):
				expelled_units.append(unit)

	# Expel the units
	if not expelled_units.is_empty():
		_expel_units(expelled_units, owner)

## Called when open borders agreement ends between two players
func on_open_borders_ended(player1_id: int, player2_id: int) -> void:
	var player1 = GameManager.get_player(player1_id)
	var player2 = GameManager.get_player(player2_id)

	if player1 == null or player2 == null:
		return

	# Expel player1's units from player2's territory
	var expelled_from_p2 = _get_units_to_expel(player1, player2)
	if not expelled_from_p2.is_empty():
		_expel_units(expelled_from_p2, player2)

	# Expel player2's units from player1's territory
	var expelled_from_p1 = _get_units_to_expel(player2, player1)
	if not expelled_from_p1.is_empty():
		_expel_units(expelled_from_p1, player1)

## Called when war is declared - all units of both sides must leave enemy territory
## When A declares war on B: A's units leave B's borders, B's units leave A's borders
func on_war_declared(aggressor_id: int, target_id: int) -> void:
	var aggressor = GameManager.get_player(aggressor_id)
	var target = GameManager.get_player(target_id)

	if aggressor == null or target == null:
		return

	# Expel aggressor's units from target's territory
	var aggressor_units_to_expel = _get_units_in_territory(aggressor, target)
	if not aggressor_units_to_expel.is_empty():
		_expel_units(aggressor_units_to_expel, target)

	# Expel target's units from aggressor's territory
	var target_units_to_expel = _get_units_in_territory(target, aggressor)
	if not target_units_to_expel.is_empty():
		_expel_units(target_units_to_expel, aggressor)

## Get all units of unit_owner that are inside territory_owner's borders
func _get_units_in_territory(unit_owner, territory_owner) -> Array:
	var units_in_territory = []

	for unit in unit_owner.units:
		var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
		if tile == null:
			continue

		# Check if unit is in territory_owner's borders
		if tile.tile_owner == territory_owner:
			units_in_territory.append(unit)

	return units_in_territory

## Called when peace is declared - units inside enemy territory must leave
func on_peace_declared(player1_id: int, player2_id: int) -> void:
	var player1 = GameManager.get_player(player1_id)
	var player2 = GameManager.get_player(player2_id)

	if player1 == null or player2 == null:
		return

	# After peace, check if units need to be expelled (only if no open borders)
	if not player1.has_open_borders_with(player2_id):
		var expelled_from_p2 = _get_units_to_expel(player1, player2)
		if not expelled_from_p2.is_empty():
			_expel_units(expelled_from_p2, player2)

	if not player2.has_open_borders_with(player1_id):
		var expelled_from_p1 = _get_units_to_expel(player2, player1)
		if not expelled_from_p1.is_empty():
			_expel_units(expelled_from_p1, player1)

## Get all units of unit_owner that are inside territory_owner's borders and shouldn't be there
func _get_units_to_expel(unit_owner, territory_owner) -> Array:
	var to_expel = []

	for unit in unit_owner.units:
		var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
		if tile == null:
			continue

		# Check if unit is in territory_owner's borders
		if tile.tile_owner == territory_owner:
			# Check if unit is allowed
			if not unit_owner.can_enter_borders_of(territory_owner.player_id):
				to_expel.append(unit)

	return to_expel

## Expel units from a territory, moving them to the nearest valid tile
func _expel_units(units: Array, territory_owner) -> void:
	for unit in units:
		_expel_unit(unit, territory_owner)

	if not units.is_empty() and units[0].player_owner != null:
		EventBus.units_expelled_from_borders.emit(territory_owner, units)

## Expel a single unit to the nearest valid tile outside the territory
func _expel_unit(unit, territory_owner) -> void:
	var grid = GameManager.hex_grid
	if grid == null:
		return

	var current_pos = unit.grid_position
	var best_pos: Vector2i = Vector2i(-1, -1)
	var best_distance = INF

	# Search outward for a valid tile
	for radius in range(1, 20):  # Search up to 20 tiles away
		var tiles = GridUtils.get_tiles_in_circular_range(current_pos, float(radius))

		for tile_pos in tiles:
			var wrapped_pos = GridUtils.wrap_position(tile_pos, grid.width, grid.height)
			var tile = grid.get_tile(wrapped_pos)

			if tile == null:
				continue

			# Check if this tile is a valid destination
			if not _is_valid_expel_destination(unit, tile, territory_owner):
				continue

			var dist = GridUtils.euclidean_distance(current_pos, wrapped_pos)
			if dist < best_distance:
				best_distance = dist
				best_pos = wrapped_pos

		# Found a valid tile at this radius, stop searching
		if best_pos.x >= 0:
			break

	# Teleport unit to the best position
	if best_pos.x >= 0:
		unit.teleport_to(best_pos)
		# Unit loses all movement after being expelled
		unit.movement_remaining = 0
		unit.has_acted = true
		print("[BorderSystem] Unit %s expelled from %s territory to %s" % [unit.unit_id, territory_owner.player_name, best_pos])
	else:
		# No valid tile found - this shouldn't normally happen
		# As a fallback, try to find the unit's nearest city
		_expel_to_nearest_city(unit)

## Check if a tile is a valid destination for an expelled unit
func _is_valid_expel_destination(unit, tile, territory_owner) -> bool:
	# Must be passable
	if not tile.is_passable():
		return false

	# Water check
	if tile.is_water() and unit.get_unit_class() != "naval":
		return false

	# Must not be in the expelling player's territory
	if tile.tile_owner == territory_owner:
		return false

	# Must be allowed to enter (own territory, neutral, or has permission)
	if tile.tile_owner != null and unit.player_owner != null:
		if tile.tile_owner != unit.player_owner:
			if not unit.player_owner.can_enter_borders_of(tile.tile_owner.player_id):
				return false

	return true

## Fallback: teleport unit to nearest owned city
func _expel_to_nearest_city(unit) -> void:
	if unit.player_owner == null or unit.player_owner.cities.is_empty():
		# No cities - unit is destroyed
		print("[BorderSystem] Unit %s has nowhere to go and is destroyed" % unit.unit_id)
		unit.die()
		return

	var current_pos = unit.grid_position
	var nearest_city = null
	var best_distance = INF

	for city in unit.player_owner.cities:
		var dist = GridUtils.euclidean_distance(current_pos, city.grid_position)
		if dist < best_distance:
			best_distance = dist
			nearest_city = city

	if nearest_city != null:
		unit.teleport_to(nearest_city.grid_position)
		unit.movement_remaining = 0
		unit.has_acted = true
		print("[BorderSystem] Unit %s expelled to city %s" % [unit.unit_id, nearest_city.city_name])

## Check all units on the map for border violations (call at turn start or after diplomacy changes)
func check_all_border_violations() -> void:
	for player in GameManager.players:
		_check_player_border_violations(player)

## Check a specific player's units for border violations
func _check_player_border_violations(player) -> void:
	var units_to_expel: Dictionary = {}  # territory_owner -> [units]

	for unit in player.units:
		var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
		if tile == null or tile.tile_owner == null:
			continue

		if tile.tile_owner == player:
			continue

		# Check if unit is allowed
		if not player.can_enter_borders_of(tile.tile_owner.player_id):
			if not units_to_expel.has(tile.tile_owner):
				units_to_expel[tile.tile_owner] = []
			units_to_expel[tile.tile_owner].append(unit)

	# Expel units grouped by territory owner
	for territory_owner in units_to_expel:
		_expel_units(units_to_expel[territory_owner], territory_owner)
