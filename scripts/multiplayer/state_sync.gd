class_name StateSync
extends RefCounted
## Handles state serialization (server → client) and application (client-side).
## Respects fog of war — each client only receives what their player can see.

const MpActionClass = preload("res://scripts/multiplayer/mp_action.gd")

# =============================================================================
# SERVER-SIDE: Collect state for a specific player
# =============================================================================

## Collect full turn-boundary state for a player (sent at start of each turn)
static func collect_turn_state_for_player(player) -> Dictionary:
	var state = {
		"turn": TurnManager.current_turn,
		"year": TurnManager.current_year,
		"player_id": player.player_id,
		"player_state": player.to_dict(),
		"own_units": _collect_own_units(player),
		"own_cities": _collect_own_cities(player),
		"visible_enemy_units": _collect_visible_enemy_units(player),
		"visible_enemy_cities": _collect_visible_enemy_cities(player),
		"tile_updates": _collect_visible_tiles(player),
		"notifications": [],  # Populated by caller if needed
		"game_state": {},
	}

	# Include global game state info
	if GameManager.current_game_state:
		state["game_state"] = {
			"founded_religions": GameManager.current_game_state.founded_religions.duplicate(),
			"religion_founder": GameManager.current_game_state.religion_founder.duplicate(),
			"world_wonders_built": GameManager.world_wonders_built.duplicate(),
		}

	return state

static func _collect_own_units(player) -> Array:
	var units = []
	for unit in player.units:
		units.append(unit.to_dict())
	return units

static func _collect_own_cities(player) -> Array:
	var cities = []
	for city in player.cities:
		cities.append(city.to_dict())
	return cities

static func _collect_visible_enemy_units(player) -> Array:
	var visible_units = []
	for other_player in GameManager.players:
		if other_player.player_id == player.player_id:
			continue
		for unit in other_player.units:
			if _is_position_visible_to_player(unit.grid_position, player):
				visible_units.append({
					"unit_id": unit.unit_id,
					"player_id": other_player.player_id,
					"grid_position": {"x": unit.grid_position.x, "y": unit.grid_position.y},
					"health": unit.health,
					"max_health": unit.max_health,
					"is_fortified": unit.is_fortified,
					"promotions": unit.promotions.duplicate(),
				})
	return visible_units

static func _collect_visible_enemy_cities(player) -> Array:
	var visible_cities = []
	for other_player in GameManager.players:
		if other_player.player_id == player.player_id:
			continue
		for city in other_player.cities:
			if _is_position_visible_to_player(city.grid_position, player):
				visible_cities.append({
					"city_name": city.city_name,
					"player_id": other_player.player_id,
					"grid_position": {"x": city.grid_position.x, "y": city.grid_position.y},
					"population": city.population,
					"culture": city.culture,
					"buildings": city.buildings.duplicate(),
					"has_walls": "walls" in city.buildings or "castle" in city.buildings,
				})
	return visible_cities

static func _collect_visible_tiles(player) -> Array:
	var tiles = []
	if GameManager.hex_grid == null:
		return tiles

	for x in range(GameManager.hex_grid.width):
		for y in range(GameManager.hex_grid.height):
			var pos = Vector2i(x, y)
			if _is_position_visible_to_player(pos, player):
				var tile = GameManager.hex_grid.get_tile(pos)
				if tile:
					tiles.append({
						"x": x,
						"y": y,
						"terrain_id": tile.terrain_id,
						"feature_id": tile.feature_id,
						"resource_id": tile.resource_id,
						"improvement_id": tile.improvement_id,
						"road_level": tile.road_level,
						"owner_id": tile.tile_owner.player_id if tile.tile_owner else -1,
					})

	return tiles

static func _is_position_visible_to_player(pos: Vector2i, player) -> bool:
	if GameManager.hex_grid == null:
		return false
	var tile = GameManager.hex_grid.get_tile(pos)
	if tile == null:
		return false
	var vis_state = tile.get_visibility_for_player(player.player_id)
	return vis_state == 2  # 2 = visible (not fog/unexplored)

# =============================================================================
# SERVER-SIDE: Filter action results for fog of war
# =============================================================================

## Filter an action result to only include information visible to a specific player
static func filter_result_for_player(result: Dictionary, player) -> Dictionary:
	var filtered = result.duplicate()

	# Remove internal data that shouldn't be sent to other players
	filtered.erase("unit_index")
	filtered.erase("city_index")

	# For combat, include limited info
	if result.get("combat", false):
		# Other players just see the combat happened and the outcome
		filtered["observer_view"] = true

	return filtered

# =============================================================================
# CLIENT-SIDE: Apply state updates
# =============================================================================

## Apply a full turn-boundary state update from the server
static func apply_turn_state(state: Dictionary) -> void:
	var player_id = state.get("player_id", -1)
	var player = GameManager.get_player(player_id)
	if player == null:
		return

	# Update player data
	var player_state = state.get("player_state", {})
	if not player_state.is_empty():
		player.from_dict(player_state)

	# Rebuild own units
	_apply_own_units(player, state.get("own_units", []))

	# Rebuild own cities
	_apply_own_cities(player, state.get("own_cities", []))

	# Update visible enemy units
	_apply_visible_enemy_units(state.get("visible_enemy_units", []))

	# Update visible enemy cities
	_apply_visible_enemy_cities(state.get("visible_enemy_cities", []))

	# Update tiles
	_apply_tile_updates(state.get("tile_updates", []))

	# Update game state
	var game_state_data = state.get("game_state", {})
	if not game_state_data.is_empty() and GameManager.current_game_state:
		if game_state_data.has("founded_religions"):
			GameManager.current_game_state.founded_religions = game_state_data.founded_religions
		if game_state_data.has("religion_founder"):
			GameManager.current_game_state.religion_founder = game_state_data.religion_founder
		if game_state_data.has("world_wonders_built"):
			GameManager.world_wonders_built = game_state_data.world_wonders_built

	# Refresh visibility
	VisibilitySystem.refresh_visibility(player)
	VisibilitySystem.update_all_tile_visuals()

static func _apply_own_units(player, units_data: Array) -> void:
	# Update existing units or create new ones from server data
	# For now, sync unit state from server data
	for unit_data in units_data:
		var found = false
		for unit in player.units:
			# Match by grid position and unit type (since unit_index may shift)
			var data_pos = Vector2i(unit_data.get("grid_position", {}).get("x", 0),
									unit_data.get("grid_position", {}).get("y", 0))
			if unit.grid_position == data_pos and unit.unit_id == unit_data.get("unit_id", ""):
				unit.from_dict(unit_data)
				unit.update_visual()
				found = true
				break
		# New unit from server (e.g., produced this turn)
		if not found:
			var UnitClass = load("res://scripts/entities/unit.gd")
			var new_unit = UnitClass.new()
			new_unit.from_dict(unit_data)
			player.add_unit(new_unit)
			if GameManager.game_world:
				var entity_layer = GameManager.game_world.get_node_or_null("EntityLayer")
				if entity_layer:
					entity_layer.add_child(new_unit)

static func _apply_own_cities(player, cities_data: Array) -> void:
	for city_data in cities_data:
		var found = false
		for city in player.cities:
			var data_pos = Vector2i(city_data.get("grid_position", {}).get("x", 0),
									city_data.get("grid_position", {}).get("y", 0))
			if city.grid_position == data_pos:
				city.from_dict(city_data)
				found = true
				break
		if not found:
			var CityClass = load("res://scripts/entities/city.gd")
			var new_city = CityClass.new()
			new_city.from_dict(city_data)
			player.add_city(new_city)
			if GameManager.game_world:
				var entity_layer = GameManager.game_world.get_node_or_null("EntityLayer")
				if entity_layer:
					entity_layer.add_child(new_city)

static func _apply_visible_enemy_units(enemy_units_data: Array) -> void:
	# Update or create temporary representations of visible enemy units
	# These are display-only on the client
	for unit_data in enemy_units_data:
		var pos = Vector2i(unit_data.get("grid_position", {}).get("x", 0),
						   unit_data.get("grid_position", {}).get("y", 0))
		var owner_id = unit_data.get("player_id", -1)
		var owner = GameManager.get_player(owner_id)
		if owner == null:
			continue

		# Check if unit already exists at this position
		var found = false
		for unit in owner.units:
			if unit.grid_position == pos and unit.unit_id == unit_data.get("unit_id", ""):
				unit.health = unit_data.get("health", 100.0)
				unit.max_health = unit_data.get("max_health", 100.0)
				unit.is_fortified = unit_data.get("is_fortified", false)
				unit.update_visual()
				found = true
				break

		if not found:
			var UnitClass = load("res://scripts/entities/unit.gd")
			var new_unit = UnitClass.new(unit_data.get("unit_id", "warrior"), pos)
			new_unit.health = unit_data.get("health", 100.0)
			new_unit.max_health = unit_data.get("max_health", 100.0)
			new_unit.is_fortified = unit_data.get("is_fortified", false)
			owner.add_unit(new_unit)
			if GameManager.game_world:
				var entity_layer = GameManager.game_world.get_node_or_null("EntityLayer")
				if entity_layer:
					entity_layer.add_child(new_unit)

static func _apply_visible_enemy_cities(enemy_cities_data: Array) -> void:
	for city_data in enemy_cities_data:
		var pos = Vector2i(city_data.get("grid_position", {}).get("x", 0),
						   city_data.get("grid_position", {}).get("y", 0))
		var owner_id = city_data.get("player_id", -1)
		var owner = GameManager.get_player(owner_id)
		if owner == null:
			continue

		# Update existing city info
		for city in owner.cities:
			if city.grid_position == pos:
				city.city_name = city_data.get("city_name", city.city_name)
				city.population = city_data.get("population", city.population)
				city.culture = city_data.get("culture", city.culture)
				break

static func _apply_tile_updates(tile_updates: Array) -> void:
	if GameManager.hex_grid == null:
		return

	for tile_data in tile_updates:
		var pos = Vector2i(tile_data.get("x", 0), tile_data.get("y", 0))
		var tile = GameManager.hex_grid.get_tile(pos)
		if tile == null:
			continue

		if tile_data.has("improvement_id"):
			tile.improvement_id = tile_data.improvement_id
		if tile_data.has("road_level"):
			tile.road_level = tile_data.road_level
		if tile_data.has("resource_id"):
			tile.resource_id = tile_data.resource_id
		if tile_data.has("owner_id"):
			var owner_id = tile_data.owner_id
			tile.tile_owner = GameManager.get_player(owner_id) if owner_id >= 0 else null

		tile.update_visuals()

# =============================================================================
# CLIENT-SIDE: Apply individual action results (real-time during turn)
# =============================================================================

## Apply an action result received from the server during the turn
static func apply_action_result(action_data: Dictionary, result: Dictionary) -> void:
	if not result.get("success", false):
		return

	var action_type = action_data.get("type", -1)

	match action_type:
		MpActionClass.ActionType.MOVE_UNIT:
			_apply_move_result(result)
		MpActionClass.ActionType.ATTACK_UNIT:
			_apply_combat_result(result)
		MpActionClass.ActionType.FOUND_CITY:
			_apply_found_city_result(result)
		MpActionClass.ActionType.SET_RESEARCH:
			_apply_research_result(result)
		_:
			pass  # Most other actions are reflected in turn-boundary sync

static func _apply_move_result(result: Dictionary) -> void:
	var player = GameManager.get_local_player()
	if player == null:
		return

	var unit_index = result.get("unit_index", -1)
	if unit_index < 0 or unit_index >= player.units.size():
		return

	var unit = player.units[unit_index]
	var to_pos = Vector2i(result.get("to_pos", {}).get("x", 0),
						  result.get("to_pos", {}).get("y", 0))

	# Animate unit to new position
	unit.grid_position = to_pos
	unit.movement_remaining = result.get("movement_remaining", 0.0)
	unit._animate_move_to(to_pos)
	unit._update_visibility()

static func _apply_combat_result(result: Dictionary) -> void:
	# Combat results are complex — for now, the turn-boundary sync handles full state
	# During the turn, we just trigger the combat visual effects
	if result.get("observer_view", false):
		# We're an observer — just note that combat happened
		var target_pos = Vector2i(result.get("target_pos", {}).get("x", 0),
								 result.get("target_pos", {}).get("y", 0))
		EventBus.notification_added.emit("Combat at (%d, %d)" % [target_pos.x, target_pos.y], "")

static func _apply_found_city_result(result: Dictionary) -> void:
	# City founding is fully handled by turn-boundary sync
	var pos = result.get("position", {})
	if not pos.is_empty():
		EventBus.notification_added.emit("City founded at (%d, %d)" % [pos.get("x", 0), pos.get("y", 0)], "")

static func _apply_research_result(result: Dictionary) -> void:
	var player = GameManager.get_local_player()
	if player:
		player.current_research = result.get("tech_id", "")
		player.research_progress = 0
