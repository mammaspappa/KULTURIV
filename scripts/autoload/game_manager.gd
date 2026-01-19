extends Node
## Manages overall game state, players, and game flow.

const GameStateClass = preload("res://scripts/core/game_state.gd")
const PlayerClass = preload("res://scripts/core/player.gd")

# Game settings
var map_width: int = 80
var map_height: int = 50
var wrap_x: bool = true  # Cylindrical map
var wrap_y: bool = false

# Game state
var current_game_state = null  # GameState
var players: Array = []
var human_player = null  # Player
var current_player_index: int = 0

# References
var game_grid = null  # GameGrid
var game_world: Node2D = null

# Game configuration
var difficulty: int = 4  # Prince difficulty (0-8 scale)
var game_speed: int = 1  # 0=Quick, 1=Normal, 2=Epic, 3=Marathon

# Speed multipliers for production/research
const SPEED_MULTIPLIERS = {
	0: 0.67,   # Quick
	1: 1.0,    # Normal
	2: 1.5,    # Epic
	3: 3.0     # Marathon
}

func _ready() -> void:
	pass

func start_new_game(settings: Dictionary) -> void:
	# Apply settings
	map_width = settings.get("map_width", 80)
	map_height = settings.get("map_height", 50)
	difficulty = settings.get("difficulty", 4)
	game_speed = settings.get("game_speed", 1)

	# Initialize game state
	current_game_state = GameStateClass.new()

	# Create players
	_create_players(settings)

	# Notify systems
	EventBus.game_started.emit()

func _create_players(settings: Dictionary) -> void:
	players.clear()

	var num_players = settings.get("num_players", 2)
	var human_civ = settings.get("human_civ", "rome")
	var human_leader = settings.get("human_leader", "julius_caesar")

	# Create human player
	human_player = PlayerClass.new()
	human_player.player_id = 0
	human_player.player_name = settings.get("player_name", "Player")
	human_player.civilization_id = human_civ
	human_player.leader_id = human_leader
	human_player.is_human = true
	human_player.team = 0
	human_player.color = _get_player_color(0)
	_initialize_player_techs(human_player)
	_initialize_player_civics(human_player)
	_initialize_player_traits(human_player)
	players.append(human_player)

	# Create AI players
	var ai_civs = _get_available_civs([human_civ])
	for i in range(1, num_players):
		var ai_player = PlayerClass.new()
		ai_player.player_id = i
		ai_player.civilization_id = ai_civs[i - 1] if i - 1 < ai_civs.size() else "barbarian"
		ai_player.leader_id = _get_leader_for_civ(ai_player.civilization_id)
		ai_player.player_name = DataManager.get_civ(ai_player.civilization_id).get("name", "Unknown")
		ai_player.is_human = false
		ai_player.team = i
		ai_player.color = _get_player_color(i)
		_initialize_player_techs(ai_player)
		_initialize_player_civics(ai_player)
		_initialize_player_traits(ai_player)
		players.append(ai_player)

func _initialize_player_techs(player) -> void:
	var starting_techs = DataManager.get_civ_starting_techs(player.civilization_id)
	for tech in starting_techs:
		player.researched_techs.append(tech)

func _initialize_player_civics(player) -> void:
	player.civics = CivicsSystem.get_default_civics()

func _initialize_player_traits(player) -> void:
	var leader_traits = DataManager.get_leader_traits(player.leader_id)
	for trait_id in leader_traits:
		player.traits.append(trait_id)

func _get_available_civs(exclude: Array) -> Array:
	var all_civs = DataManager.get_all_civs().keys()
	var available = []
	for civ in all_civs:
		if civ not in exclude and civ != "barbarian":
			available.append(civ)
	available.shuffle()
	return available

func _get_leader_for_civ(civ_id: String) -> String:
	var civ = DataManager.get_civ(civ_id)
	var leader_list = civ.get("leaders", [])
	if leader_list.is_empty():
		return ""
	return leader_list[0]

func _get_player_color(index: int) -> Color:
	var colors = [
		Color("#1E88E5"),  # Blue
		Color("#D32F2F"),  # Red
		Color("#388E3C"),  # Green
		Color("#FBC02D"),  # Yellow
		Color("#7B1FA2"),  # Purple
		Color("#F57C00"),  # Orange
		Color("#00796B"),  # Teal
		Color("#C2185B"),  # Pink
	]
	return colors[index % colors.size()]

func get_current_player():
	if current_player_index < players.size():
		return players[current_player_index]
	return null

func get_player(player_id: int):
	for player in players:
		if player.player_id == player_id:
			return player
	return null

func get_player_by_civ(civ_id: String):
	for player in players:
		if player.civilization_id == civ_id:
			return player
	return null

func get_speed_multiplier() -> float:
	return SPEED_MULTIPLIERS.get(game_speed, 1.0)

func is_at_war(player1, player2) -> bool:
	if player1 == null or player2 == null:
		return false
	return player2.player_id in player1.at_war_with

func are_allies(player1, player2) -> bool:
	if player1 == null or player2 == null:
		return false
	return player1.team == player2.team and player1.team >= 0

func declare_war(aggressor, target) -> void:
	if aggressor == null or target == null:
		return
	if target.player_id not in aggressor.at_war_with:
		aggressor.at_war_with.append(target.player_id)
	if aggressor.player_id not in target.at_war_with:
		target.at_war_with.append(aggressor.player_id)
	EventBus.war_declared.emit(aggressor, target)

func make_peace(player1, player2) -> void:
	if player1 == null or player2 == null:
		return
	player1.at_war_with.erase(player2.player_id)
	player2.at_war_with.erase(player1.player_id)
	EventBus.peace_declared.emit(player1, player2)

# Alias for backwards compatibility
var hex_grid:
	get: return game_grid
	set(value): game_grid = value

func can_enter_territory(unit_owner, territory_owner) -> bool:
	if unit_owner == null or territory_owner == null:
		return true
	if unit_owner == territory_owner:
		return true
	if is_at_war(unit_owner, territory_owner):
		return true
	if territory_owner.player_id in unit_owner.open_borders_with:
		return true
	return false

func get_all_units() -> Array:
	var all_units = []
	for player in players:
		all_units.append_array(player.units)
	return all_units

func get_all_cities() -> Array:
	var all_cities = []
	for player in players:
		all_cities.append_array(player.cities)
	return all_cities

func get_unit_at(hex: Vector2i):
	for player in players:
		for unit in player.units:
			if unit.grid_position == hex:
				return unit
	return null

func get_units_at(hex: Vector2i) -> Array:
	var units_here = []
	for player in players:
		for unit in player.units:
			if unit.grid_position == hex:
				units_here.append(unit)
	return units_here

func get_city_at(hex: Vector2i):
	for player in players:
		for city in player.cities:
			if city.grid_position == hex:
				return city
	return null
