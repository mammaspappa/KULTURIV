extends Node
## Handles victory condition checking.
##
## Tunables live in data/tunables/victory.json — accessed via DataManager.get_tunable("victory.*").
## Turn limit is the Normal speed base (BTS: Quick=330, Normal=500, Epic=750, Marathon=1500),
## scaled by game speed multiplier at check time.

func _max_turns_base() -> int:
	return int(DataManager.get_tunable("victory.max_turns", 500))

func _domination_land_percent() -> float:
	return float(DataManager.get_tunable("victory.domination_land_percent", 0.55))

func _domination_pop_percent() -> float:
	return float(DataManager.get_tunable("victory.domination_pop_percent", 0.55))

func _cultural_threshold() -> int:
	return int(DataManager.get_tunable("victory.cultural_threshold", 50000))

func _cultural_cities_needed() -> int:
	return int(DataManager.get_tunable("victory.cultural_cities_needed", 3))

# Cached land tile count (recalculated when map changes)
var _total_land_tiles: int = 0
var _land_tiles_dirty: bool = true

## Check all victory conditions
## Returns {achieved: bool, player: Player, type: String} or empty dict
func check_victory() -> Dictionary:
	for player in GameManager.players:
		if _is_barbarian_civ(player):
			continue  # Barbarian civs can't win
		if player.cities.is_empty():
			continue

		# Conquest victory - all other civs eliminated
		if _check_conquest(player):
			return {"achieved": true, "player": player, "type": "conquest"}

		# Domination victory - control 66% of land and population
		if _check_domination(player):
			return {"achieved": true, "player": player, "type": "domination"}

		# Cultural victory - 3 cities with legendary culture
		if _check_cultural(player):
			return {"achieved": true, "player": player, "type": "cultural"}

		# Space Race victory - build spaceship
		if _check_space_race(player):
			return {"achieved": true, "player": player, "type": "space"}

	# Score victory at turn limit (scaled by game speed)
	var max_turns = int(_max_turns_base() * GameManager.get_speed_multiplier())
	if TurnManager.current_turn >= max_turns:
		var winner = _get_highest_score_player()
		return {"achieved": true, "player": winner, "type": "score"}

	return {}

func _is_barbarian_civ(p) -> bool:
	return p.player_id == -1 or p.is_barbarian()

func _check_conquest(player) -> bool:
	# All other non-barbarian civs must be eliminated
	for other_player in GameManager.players:
		if other_player == player:
			continue
		if _is_barbarian_civ(other_player):
			continue
		if not other_player.is_eliminated():
			return false
	return true

func _check_domination(player) -> bool:
	# Check land percentage (of total map land, not just claimed land)
	var land_percent = _get_player_land_percent(player)

	# Check population percentage (of total world population, excluding barbarians)
	var total_pop = 0
	var player_pop = 0
	for p in GameManager.players:
		if _is_barbarian_civ(p):
			continue
		for city in p.cities:
			total_pop += city.population
			if p == player:
				player_pop += city.population

	if total_pop == 0:
		return false

	var pop_percent = float(player_pop) / total_pop

	return land_percent >= _domination_land_percent() and pop_percent >= _domination_pop_percent()

func _check_cultural(player) -> bool:
	var threshold := _cultural_threshold()
	var legendary_cities = 0
	for city in player.cities:
		if city.culture >= threshold:
			legendary_cities += 1

	return legendary_cities >= _cultural_cities_needed()

func _check_space_race(player) -> bool:
	# Space race victory requires:
	#   1. Apollo Program built (tracked as a project, not building)
	#   2. All spaceship parts built (tracked in ProjectsSystem.spaceship_progress)
	#   3. Spaceship launched and travel time elapsed
	if ProjectsSystem == null:
		return false
	# Apollo is a national project — check if this player has it
	var player_apollo = ProjectsSystem.player_projects.get(player.player_id, {}).get("apollo_program", 0)
	if player_apollo < 1:
		return false
	# Has the spaceship arrived at the destination (launched + travel time elapsed)?
	var progress = ProjectsSystem.spaceship_progress.get(player.player_id, {})
	if not progress.get("launched", false):
		return false
	var arrival_turn = progress.get("arrival_turn", -1)
	if arrival_turn < 0:
		return false
	var current_turn = TurnManager.current_turn if TurnManager else 0
	return current_turn >= arrival_turn

## Called by ProjectsSystem.launch_spaceship on successful launch.
## Sets the victory flag immediately (for when travel time is 0 or 1 turn).
func check_space_race_victory(player_id: int) -> void:
	var player = GameManager.get_player(player_id) if GameManager else null
	if player == null:
		return
	# Only trigger victory if the spaceship has actually arrived
	if _check_space_race(player):
		_apply_vote_victory(player_id, "space")

## Get total land tiles on the map (cached)
func _get_total_land_tiles() -> int:
	if _land_tiles_dirty or _total_land_tiles == 0:
		_recalculate_land_tiles()
	return _total_land_tiles

## Recalculate total land tiles on the map
func _recalculate_land_tiles() -> void:
	_total_land_tiles = 0
	var grid = GameManager.hex_grid
	if grid == null:
		return

	for x in range(grid.width):
		for y in range(grid.height):
			var tile = grid.get_tile(Vector2i(x, y))
			if tile != null and not tile.is_water():
				_total_land_tiles += 1

	_land_tiles_dirty = false

## Get the number of land tiles owned by a player
func _get_player_owned_tiles(player) -> int:
	var owned = 0
	var grid = GameManager.hex_grid
	if grid == null:
		return 0

	for x in range(grid.width):
		for y in range(grid.height):
			var tile = grid.get_tile(Vector2i(x, y))
			if tile != null and not tile.is_water() and tile.tile_owner == player:
				owned += 1

	return owned

## Get percentage of total land owned by player
func _get_player_land_percent(player) -> float:
	var total = _get_total_land_tiles()
	if total == 0:
		return 0.0
	var owned = _get_player_owned_tiles(player)
	return float(owned) / total

## Mark land tiles cache as dirty (call when map changes)
func invalidate_land_cache() -> void:
	_land_tiles_dirty = true

func _get_highest_score_player():
	var best_player = null
	var best_score = -1

	for player in GameManager.players:
		if _is_barbarian_civ(player):
			continue
		player.calculate_score()
		if player.score > best_score:
			best_score = player.score
			best_player = player

	if best_player == null and not GameManager.players.is_empty():
		best_player = GameManager.players[0]

	return best_player

## Called by VotingSystem when a diplomatic victory vote passes
func check_diplomatic_victory(player_id: int) -> void:
	_apply_vote_victory(player_id, "diplomatic")

## Called by VotingSystem when a religious (Apostolic Palace) victory vote passes
func check_religious_victory(player_id: int) -> void:
	_apply_vote_victory(player_id, "religious")

func _apply_vote_victory(player_id: int, victory_type: String) -> void:
	var player = null
	for p in GameManager.players:
		if p.player_id == player_id:
			player = p
			break

	if player == null:
		return

	if GameManager.current_game_state:
		GameManager.current_game_state.victory_achieved = true
		GameManager.current_game_state.victory_type = victory_type
		GameManager.current_game_state.winner_player_id = player_id
	EventBus.victory_achieved.emit(player, victory_type)
	EventBus.game_over.emit(player, victory_type)

## Get victory progress for UI display
func get_victory_progress(player) -> Dictionary:
	var progress = {}

	# Conquest progress (exclude barbarian civs)
	var total_civs = 0
	var eliminated = 0
	for p in GameManager.players:
		if _is_barbarian_civ(p):
			continue
		if p == player:
			continue
		total_civs += 1
		if p.is_eliminated():
			eliminated += 1
	progress["conquest"] = {
		"eliminated": eliminated,
		"total_rivals": total_civs,
		"percent": float(eliminated) / total_civs if total_civs > 0 else 0
	}

	# Domination progress (exclude barbarian civs)
	var total_pop = 0
	var player_pop = 0
	for p in GameManager.players:
		if _is_barbarian_civ(p):
			continue
		for city in p.cities:
			total_pop += city.population
			if p == player:
				player_pop += city.population

	var land_percent = _get_player_land_percent(player)
	var pop_percent = float(player_pop) / max(total_pop, 1)
	progress["domination"] = {
		"land_percent": land_percent,
		"pop_percent": pop_percent,
		"land_needed": _domination_land_percent(),
		"pop_needed": _domination_pop_percent(),
		"total_land_tiles": _get_total_land_tiles(),
		"player_land_tiles": _get_player_owned_tiles(player)
	}

	# Cultural progress
	var cultural_threshold := _cultural_threshold()
	var legendary = 0
	var highest_culture = 0
	for city in player.cities:
		if city.culture >= cultural_threshold:
			legendary += 1
		highest_culture = max(highest_culture, city.culture)
	progress["cultural"] = {
		"legendary_cities": legendary,
		"needed": _cultural_cities_needed(),
		"highest_culture": highest_culture,
		"threshold": cultural_threshold
	}

	# Space race progress
	var has_apollo = false
	var parts_built = 0
	var required_parts = ["ss_cockpit", "ss_casing", "ss_thrusters", "ss_stasis_chamber", "ss_life_support", "ss_engine"]
	for city in player.cities:
		if "apollo_program" in city.buildings:
			has_apollo = true
		for part in required_parts:
			if part in city.buildings:
				parts_built += 1
	progress["space"] = {
		"has_apollo": has_apollo,
		"parts_built": parts_built,
		"parts_needed": required_parts.size()
	}

	# Score
	player.calculate_score()
	var scaled_max_turns = int(_max_turns_base() * GameManager.get_speed_multiplier())
	progress["score"] = {
		"current": player.score,
		"turns_remaining": scaled_max_turns - TurnManager.current_turn
	}

	return progress
