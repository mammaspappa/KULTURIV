extends Node
## Manages turn progression and per-turn processing for all players.

const UnitClass = preload("res://scripts/entities/unit.gd")

signal turn_processing_started()
signal turn_processing_finished()

var current_turn: int = 1
var current_year: int = -4000
var is_processing: bool = false

# Year progression (Civ4 style)
const YEAR_PROGRESSION = [
	{"until_turn": 50, "years_per_turn": 40},    # Ancient: 40 years/turn
	{"until_turn": 100, "years_per_turn": 25},   # Classical: 25 years/turn
	{"until_turn": 150, "years_per_turn": 20},   # Medieval: 20 years/turn
	{"until_turn": 200, "years_per_turn": 10},   # Renaissance: 10 years/turn
	{"until_turn": 280, "years_per_turn": 5},    # Industrial: 5 years/turn
	{"until_turn": 350, "years_per_turn": 2},    # Modern: 2 years/turn
	{"until_turn": 9999, "years_per_turn": 1},   # Future: 1 year/turn
]

func _ready() -> void:
	pass

func start_game() -> void:
	current_turn = 1
	current_year = -4000
	_start_turn_for_player(GameManager.get_current_player())

func end_turn() -> void:
	if is_processing:
		return

	var current_player = GameManager.get_current_player()
	if current_player == null:
		return

	# End current player's turn
	_end_turn_for_player(current_player)

	# Move to next player
	GameManager.current_player_index += 1

	# Check if all players have gone
	if GameManager.current_player_index >= GameManager.players.size():
		_complete_round()
	else:
		# Start next player's turn
		_start_turn_for_player(GameManager.get_current_player())

func _start_turn_for_player(player) -> void:
	if player == null:
		return

	# Process worker builds first (before refreshing movement)
	for unit in player.units:
		if unit.current_order == UnitClass.UnitOrder.BUILD:
			ImprovementSystem.process_build(unit)

	# Refresh unit movement points
	for unit in player.units:
		unit.refresh_movement()
		unit.has_acted = false

	# Process automated workers
	for unit in player.units:
		if unit.current_order == UnitClass.UnitOrder.AUTOMATE:
			unit.process_automation()

	# Process cities
	for city in player.cities:
		_process_city_turn_start(city)

	# Process gold (sum gold_yield from all cities)
	_process_gold(player)

	# Process research
	_process_research(player)

	# Refresh visibility for the player (fog of war)
	VisibilitySystem.refresh_visibility(player)
	VisibilitySystem.update_all_tile_visuals()

	# Emit turn_started AFTER movement is refreshed so UI updates correctly
	EventBus.turn_started.emit(current_turn, player)

	# If AI, execute AI turn
	if not player.is_human:
		_execute_ai_turn(player)
		# Auto-advance to next player after AI turn
		call_deferred("end_turn")

func _end_turn_for_player(player) -> void:
	if player == null:
		return

	EventBus.turn_ended.emit(current_turn, player)

	# Process golden age countdown
	player.process_golden_age()

	# Heal units in friendly territory or fortified
	for unit in player.units:
		_process_unit_healing(unit)

func _complete_round() -> void:
	# All players have taken their turn
	GameManager.current_player_index = 0

	# Advance turn counter
	current_turn += 1
	_advance_year()

	EventBus.all_turns_completed.emit(current_turn)

	# Check for victory conditions
	var victory = VictorySystem.check_victory()
	if not victory.is_empty() and victory.get("achieved", false):
		if GameManager.current_game_state:
			GameManager.current_game_state.victory_achieved = true
			GameManager.current_game_state.victory_type = victory.type
			GameManager.current_game_state.winner_player_id = victory.player.player_id
		EventBus.victory_achieved.emit(victory.player, victory.type)
		EventBus.game_over.emit(victory.player, victory.type)
		return  # Don't start new round if game is over

	# Start next round with first player
	_start_turn_for_player(GameManager.get_current_player())

func _advance_year() -> void:
	var years_to_add = 1
	for progression in YEAR_PROGRESSION:
		if current_turn <= progression.until_turn:
			years_to_add = progression.years_per_turn
			break

	# Apply game speed multiplier
	years_to_add = int(years_to_add * GameManager.get_speed_multiplier())
	if years_to_add < 1:
		years_to_add = 1

	current_year += years_to_add

func _process_city_turn_start(city) -> void:
	# Calculate yields
	city.calculate_yields()

	# Process food and growth
	city.food_stockpile += city.food_surplus
	if city.food_stockpile >= city.food_needed_for_growth():
		city.grow()
	elif city.food_stockpile < 0:
		city.starve()

	# Process production
	if city.current_production != "":
		city.production_progress += city.production_yield
		var cost = city.get_production_cost()
		if city.production_progress >= cost:
			city.complete_production()

	# Process culture
	city.culture += city.culture_yield
	city.check_border_expansion()

func _process_gold(player) -> void:
	# Calculate gold per turn from all cities
	var total_gold = 0
	for city in player.cities:
		total_gold += city.gold_yield

	# Subtract unit maintenance costs (basic implementation)
	var unit_maintenance = player.units.size()  # 1 gold per unit

	# Calculate net gold per turn
	player.gold_per_turn = total_gold - unit_maintenance

	# Add to player's gold treasury
	player.gold += player.gold_per_turn

	# Ensure gold doesn't go below 0 (could add deficit handling later)
	if player.gold < 0:
		player.gold = 0

func _process_research(player) -> void:
	if player.current_research == "":
		return

	player.research_progress += player.get_research_output()
	var cost = DataManager.get_tech_cost(player.current_research)
	cost = int(cost * GameManager.get_speed_multiplier())

	if player.research_progress >= cost:
		player.complete_research()

func _process_unit_healing(unit) -> void:
	if unit.health >= unit.max_health:
		return

	var heal_amount = 0

	# Check if in city
	var city = GameManager.get_city_at(unit.grid_position)
	if city != null and city.player_owner == unit.player_owner:
		heal_amount = 20  # Heal 20% in friendly city
	elif unit.is_fortified:
		heal_amount = 10  # Heal 10% when fortified
	elif _is_in_friendly_territory(unit):
		heal_amount = 10  # Heal 10% in friendly territory
	else:
		heal_amount = 5   # Heal 5% in neutral/enemy territory

	unit.heal(heal_amount)

func _is_in_friendly_territory(unit) -> bool:
	if GameManager.hex_grid == null:
		return false
	var tile = GameManager.hex_grid.get_tile(unit.grid_position)
	if tile == null:
		return false
	return tile.tile_owner == unit.player_owner

func _execute_ai_turn(player) -> void:
	is_processing = true
	turn_processing_started.emit()

	# Use the AI controller for decision making
	AIController.execute_turn(player)

	is_processing = false
	turn_processing_finished.emit()

func get_year_string() -> String:
	if current_year < 0:
		return str(abs(current_year)) + " BC"
	else:
		return str(current_year) + " AD"

func get_era() -> String:
	if current_year < -1000:
		return "Ancient"
	elif current_year < 500:
		return "Classical"
	elif current_year < 1400:
		return "Medieval"
	elif current_year < 1700:
		return "Renaissance"
	elif current_year < 1900:
		return "Industrial"
	elif current_year < 2000:
		return "Modern"
	else:
		return "Future"
