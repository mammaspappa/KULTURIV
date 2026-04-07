class_name MpAction
extends RefCounted
## Defines multiplayer action types, validation, and server-side execution.
## Actions are sent by clients and executed immediately on the authoritative server.

enum ActionType {
	MOVE_UNIT,
	ATTACK_UNIT,
	FOUND_CITY,
	BUILD_IMPROVEMENT,
	SET_PRODUCTION,
	SET_RESEARCH,
	SET_CIVICS,
	DIPLOMACY_ACTION,
	FORTIFY_UNIT,
	SKIP_UNIT,
	AUTOMATE_UNIT,
	SLEEP_UNIT,
	CANCEL_ORDER,
}

## Create a serializable action dictionary
static func create(type: ActionType, params: Dictionary = {}) -> Dictionary:
	var action = params.duplicate()
	action["type"] = type
	return action

## Validate an action against current game state (server-side)
static func is_valid(action: Dictionary, player) -> bool:
	var action_type = action.get("type", -1)

	match action_type:
		ActionType.MOVE_UNIT:
			return _validate_move(action, player)
		ActionType.ATTACK_UNIT:
			return _validate_attack(action, player)
		ActionType.FOUND_CITY:
			return _validate_found_city(action, player)
		ActionType.BUILD_IMPROVEMENT:
			return _validate_build(action, player)
		ActionType.SET_PRODUCTION:
			return _validate_set_production(action, player)
		ActionType.SET_RESEARCH:
			return _validate_set_research(action, player)
		ActionType.SET_CIVICS:
			return _validate_set_civics(action, player)
		ActionType.DIPLOMACY_ACTION:
			return true  # Diplomacy validation is complex, handled in execution
		ActionType.FORTIFY_UNIT, ActionType.SKIP_UNIT, ActionType.SLEEP_UNIT, \
		ActionType.AUTOMATE_UNIT, ActionType.CANCEL_ORDER:
			return _validate_unit_order(action, player)
		_:
			return false

## Execute an action on the server and return the result
static func execute(action: Dictionary, player) -> Dictionary:
	var action_type = action.get("type", -1)

	match action_type:
		ActionType.MOVE_UNIT:
			return _execute_move(action, player)
		ActionType.ATTACK_UNIT:
			return _execute_attack(action, player)
		ActionType.FOUND_CITY:
			return _execute_found_city(action, player)
		ActionType.BUILD_IMPROVEMENT:
			return _execute_build(action, player)
		ActionType.SET_PRODUCTION:
			return _execute_set_production(action, player)
		ActionType.SET_RESEARCH:
			return _execute_set_research(action, player)
		ActionType.SET_CIVICS:
			return _execute_set_civics(action, player)
		ActionType.DIPLOMACY_ACTION:
			return _execute_diplomacy(action, player)
		ActionType.FORTIFY_UNIT:
			return _execute_fortify(action, player)
		ActionType.SKIP_UNIT:
			return _execute_skip(action, player)
		ActionType.SLEEP_UNIT:
			return _execute_sleep(action, player)
		ActionType.AUTOMATE_UNIT:
			return _execute_automate(action, player)
		ActionType.CANCEL_ORDER:
			return _execute_cancel_order(action, player)
		_:
			return {"success": false, "error": "Unknown action type"}

# =============================================================================
# VALIDATION HELPERS
# =============================================================================

static func _get_unit(action: Dictionary, player) -> Variant:
	var unit_index = action.get("unit_index", -1)
	if unit_index < 0 or unit_index >= player.units.size():
		return null
	return player.units[unit_index]

static func _get_city(action: Dictionary, player) -> Variant:
	var city_index = action.get("city_index", -1)
	if city_index < 0 or city_index >= player.cities.size():
		return null
	return player.cities[city_index]

static func _dict_to_vec2i(d: Dictionary) -> Vector2i:
	return Vector2i(d.get("x", 0), d.get("y", 0))

static func _vec2i_to_dict(v: Vector2i) -> Dictionary:
	return {"x": v.x, "y": v.y}

static func _validate_move(action: Dictionary, player) -> bool:
	var unit = _get_unit(action, player)
	if unit == null:
		return false
	if not unit.can_move():
		return false
	var target = _dict_to_vec2i(action.get("target_pos", {}))
	return target != Vector2i.ZERO or action.get("target_pos", {}).get("x", -1) == 0

static func _validate_attack(action: Dictionary, player) -> bool:
	var unit = _get_unit(action, player)
	if unit == null:
		return false
	var target_pos = _dict_to_vec2i(action.get("target_pos", {}))
	var target_units = GameManager.get_units_at(target_pos)
	for target_unit in target_units:
		if target_unit.player_owner != player:
			if unit.can_attack(target_unit):
				return true
	return false

static func _validate_found_city(action: Dictionary, player) -> bool:
	var unit = _get_unit(action, player)
	if unit == null:
		return false
	return unit.can_found_city()

static func _validate_build(action: Dictionary, player) -> bool:
	var unit = _get_unit(action, player)
	if unit == null:
		return false
	return unit.can_build_improvements()

static func _validate_set_production(action: Dictionary, player) -> bool:
	var city = _get_city(action, player)
	if city == null:
		return false
	var item_id = action.get("item_id", "")
	return item_id != ""

static func _validate_set_research(action: Dictionary, player) -> bool:
	var tech_id = action.get("tech_id", "")
	if tech_id == "":
		return false
	return player.can_research(tech_id)

static func _validate_set_civics(action: Dictionary, player) -> bool:
	var civics = action.get("civics", {})
	return not civics.is_empty()

static func _validate_unit_order(action: Dictionary, player) -> bool:
	var unit = _get_unit(action, player)
	return unit != null

# =============================================================================
# EXECUTION (server-side, mutates authoritative state)
# =============================================================================

static func _execute_move(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	var target = _dict_to_vec2i(action.get("target_pos", {}))
	var from_pos = unit.grid_position

	# Use pathfinding for multi-tile movement
	var grid = GameManager.hex_grid
	if grid == null:
		return {"success": false, "error": "No grid"}

	var PathfindingClass = load("res://scripts/map/pathfinding.gd")
	var pathfinder = PathfindingClass.new(grid, unit)
	var path = pathfinder.find_path_with_movement(unit.grid_position, target, unit.movement_remaining)

	if path.is_empty():
		return {"success": false, "error": "No path"}

	unit.move_along_path(path)

	# If destination not reached, set GOTO order
	if unit.grid_position != target:
		unit.current_order = unit.UnitOrder.GOTO
		unit.order_target = target

	return {
		"success": true,
		"unit_index": action.get("unit_index"),
		"from_pos": _vec2i_to_dict(from_pos),
		"to_pos": _vec2i_to_dict(unit.grid_position),
		"movement_remaining": unit.movement_remaining,
		"affected_positions": [_vec2i_to_dict(from_pos), _vec2i_to_dict(unit.grid_position)],
	}

static func _execute_attack(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	var target_pos = _dict_to_vec2i(action.get("target_pos", {}))
	var from_pos = unit.grid_position

	# Find enemy unit at target
	var target_unit = null
	var target_units = GameManager.get_units_at(target_pos)
	for tu in target_units:
		if tu.player_owner != player:
			target_unit = tu
			break

	if target_unit == null:
		return {"success": false, "error": "No target"}

	var combat_result = CombatSystem.resolve_combat(unit, target_unit)

	var result = {
		"success": true,
		"combat": true,
		"unit_index": action.get("unit_index"),
		"attacker_won": combat_result.get("attacker_won", false),
		"attacker_health": unit.health if is_instance_valid(unit) else 0.0,
		"defender_health": target_unit.health if is_instance_valid(target_unit) else 0.0,
		"from_pos": _vec2i_to_dict(from_pos),
		"target_pos": _vec2i_to_dict(target_pos),
		"affected_positions": [_vec2i_to_dict(from_pos), _vec2i_to_dict(target_pos)],
	}

	return result

static func _execute_found_city(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	var pos = unit.grid_position

	# Use GameWorld to found city (handles all the setup)
	if GameManager.game_world:
		GameManager.game_world.found_city(unit)
		return {
			"success": true,
			"city_founded": true,
			"position": _vec2i_to_dict(pos),
			"affected_positions": [_vec2i_to_dict(pos)],
		}

	return {"success": false, "error": "No game world"}

static func _execute_build(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	var improvement_id = action.get("improvement_id", "")

	if improvement_id == "":
		return {"success": false, "error": "No improvement specified"}

	unit.start_build(improvement_id)
	return {
		"success": true,
		"unit_index": action.get("unit_index"),
		"improvement_id": improvement_id,
		"affected_positions": [_vec2i_to_dict(unit.grid_position)],
	}

static func _execute_set_production(action: Dictionary, player) -> Dictionary:
	var city = _get_city(action, player)
	var item_id = action.get("item_id", "")

	city.set_production(item_id)
	return {
		"success": true,
		"city_index": action.get("city_index"),
		"item_id": item_id,
		"affected_positions": [_vec2i_to_dict(city.grid_position)],
	}

static func _execute_set_research(action: Dictionary, player) -> Dictionary:
	var tech_id = action.get("tech_id", "")
	player.start_research(tech_id)
	return {
		"success": true,
		"tech_id": tech_id,
		"affected_positions": [],
	}

static func _execute_set_civics(action: Dictionary, player) -> Dictionary:
	var civics = action.get("civics", {})
	CivicsSystem.change_civics(player, civics)
	return {
		"success": true,
		"civics": civics,
		"affected_positions": [],
	}

static func _execute_diplomacy(action: Dictionary, player) -> Dictionary:
	var diplo_action = action.get("action", "")
	var target_player_id = action.get("target_player_id", -1)
	var target_player = GameManager.get_player(target_player_id)

	if target_player == null:
		return {"success": false, "error": "Invalid target player"}

	match diplo_action:
		"declare_war":
			GameManager.declare_war(player, target_player)
			return {"success": true, "action": "declare_war", "target_player_id": target_player_id, "affected_positions": []}
		"make_peace":
			GameManager.make_peace(player, target_player)
			return {"success": true, "action": "make_peace", "target_player_id": target_player_id, "affected_positions": []}
		"open_borders":
			player.set_open_borders(target_player_id, true)
			target_player.set_open_borders(player.player_id, true)
			EventBus.open_borders_signed.emit(player, target_player)
			return {"success": true, "action": "open_borders", "target_player_id": target_player_id, "affected_positions": []}
		_:
			return {"success": false, "error": "Unknown diplomacy action"}

static func _execute_fortify(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	unit.fortify()
	return {
		"success": true,
		"unit_index": action.get("unit_index"),
		"affected_positions": [_vec2i_to_dict(unit.grid_position)],
	}

static func _execute_skip(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	unit.skip_turn()
	return {
		"success": true,
		"unit_index": action.get("unit_index"),
		"affected_positions": [_vec2i_to_dict(unit.grid_position)],
	}

static func _execute_sleep(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	unit.sleep()
	return {
		"success": true,
		"unit_index": action.get("unit_index"),
		"affected_positions": [_vec2i_to_dict(unit.grid_position)],
	}

static func _execute_automate(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	unit.automate()
	return {
		"success": true,
		"unit_index": action.get("unit_index"),
		"affected_positions": [_vec2i_to_dict(unit.grid_position)],
	}

static func _execute_cancel_order(action: Dictionary, player) -> Dictionary:
	var unit = _get_unit(action, player)
	unit.current_order = unit.UnitOrder.NONE
	unit.order_target = Vector2i.ZERO
	return {
		"success": true,
		"unit_index": action.get("unit_index"),
		"affected_positions": [_vec2i_to_dict(unit.grid_position)],
	}
