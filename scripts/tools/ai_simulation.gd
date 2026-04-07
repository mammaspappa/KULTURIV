extends Node
## AI Self-Play Simulation Runner.
## Runs a full game with all AI players and logs results.
##
## Usage: godot --headless scenes/tools/ai_simulation.tscn

const SimLoggerClass = preload("res://scripts/tools/sim_logger.gd")
const GameWorldClass = preload("res://scripts/core/game_world.gd")
const AIControllerRef = preload("res://scripts/ai/ai_controller.gd")

var game_world: Node2D
var logger: Node
var game_finished: bool = false
var start_time: int
var max_turns: int = 500

func _env_int(key: String, fallback: int) -> int:
	var val = OS.get_environment(key)
	return int(val) if val != "" else fallback

func _env_str(key: String, fallback: String) -> String:
	var val = OS.get_environment(key)
	return val if val != "" else fallback

func _ready() -> void:
	start_time = Time.get_ticks_msec()
	max_turns = _env_int("SIM_MAX_TURNS", max_turns)

	# Create logger
	logger = SimLoggerClass.new()
	logger.name = "SimLogger"
	add_child(logger)

	# Wire AI controller to logger
	AIControllerRef.sim_logger = logger

	# Configure game settings
	var settings = _get_settings()

	print("=== AI SIMULATION STARTING ===")
	print("Map: %dx%d (%s), Players: %d, Difficulty: %d, Speed: %s" % [
		settings.map_width, settings.map_height, settings.map_type,
		settings.num_players, settings.difficulty,
		["Quick", "Normal", "Epic", "Marathon"][settings.game_speed]])

	# Initialize game
	GameManager.start_new_game(settings)

	# Override: make ALL players AI-controlled
	if GameManager.human_player:
		GameManager.human_player.is_human = false

	# Create game world (generates map, places units)
	game_world = GameWorldClass.new()
	game_world.name = "GameWorld"
	add_child(game_world)
	GameManager.game_world = game_world

	# Initialize map and start game
	game_world.initialize_game(settings)

	# Connect completion signals
	EventBus.victory_achieved.connect(_on_victory)
	EventBus.game_over.connect(_on_game_over)
	EventBus.all_turns_completed.connect(_on_round_complete)

	# Log initial state
	print("Players:")
	for p in GameManager.players:
		var civ_name = DataManager.get_civ(p.civilization_id).get("name", "Unknown")
		var leader_name = DataManager.get_leader(p.leader_id).get("name", "Unknown")
		print("  %s (%s) — %s" % [civ_name, leader_name, p.civilization_id])
	print("")

	# Initial snapshot
	logger.log_state_snapshot()

func _get_settings() -> Dictionary:
	# Settings from environment variables, with defaults
	return {
		"map_width": _env_int("SIM_MAP_W", 84),
		"map_height": _env_int("SIM_MAP_H", 52),
		"map_type": _env_str("SIM_MAP_TYPE", "pangaea"),
		"num_players": _env_int("SIM_PLAYERS", 2),
		"difficulty": _env_int("SIM_DIFFICULTY", 4),
		"game_speed": _env_int("SIM_SPEED", 0),
		"human_civ": "rome",
		"human_leader": "julius_caesar",
		"player_name": "Rome",
		"ai_aggressiveness": _env_str("SIM_AGGRESSION", "normal"),
	}

func _on_round_complete(turn: int) -> void:
	if game_finished:
		return

	# State snapshot every 25 turns
	if turn % 25 == 0:
		logger.log_state_snapshot()

	# Anomaly detection each turn
	logger.check_anomalies()

	# Safety limit
	if turn >= max_turns:
		print("\n  Max turns (%d) reached, ending simulation." % max_turns)
		_end_game()

func _on_victory(player, victory_type: String) -> void:
	_end_game()

func _on_game_over(_player, _victory_type: String) -> void:
	_end_game()

func _end_game() -> void:
	if game_finished:
		return
	game_finished = true
	# Stop the turn manager from processing further turns
	TurnManager.set_process(false)
	TurnManager.is_processing = true  # Block end_turn() calls

func _process(_delta: float) -> void:
	if game_finished:
		_finish()
		set_process(false)

func _finish() -> void:
	var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0

	# Final snapshot
	logger.log_state_snapshot()

	# Write output
	logger.write_summary(elapsed)
	logger.write_log_file()

	# Clean up AI controller reference
	AIControllerRef.sim_logger = null

	# Exit
	call_deferred("_quit")

func _quit() -> void:
	get_tree().quit()
