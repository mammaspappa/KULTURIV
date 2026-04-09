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

func _env_bool(key: String, fallback: bool) -> bool:
	var val = OS.get_environment(key).to_lower()
	if val == "":
		return fallback
	return val in ["1", "true", "yes", "on"]

func _ready() -> void:
	start_time = Time.get_ticks_msec()
	max_turns = _env_int("SIM_MAX_TURNS", max_turns)

	# Optional deterministic seed for reproducible map generation / AI flavor rolls
	var sim_seed = _env_int("SIM_SEED", -1)
	if sim_seed >= 0:
		seed(sim_seed)
		print("SIM_SEED=%d (deterministic)" % sim_seed)

	# Default to disabling autosave when sim is headless — caller can override
	# explicitly with SIM_NO_AUTOSAVE=0 if they want autosaves.
	if OS.get_environment("SIM_NO_AUTOSAVE") == "":
		OS.set_environment("SIM_NO_AUTOSAVE", "1")

	# Optional AI parameter overrides file (used by evolutionary tuner).
	# SIM_AI_OVERRIDES=path — JSON structure:
	# { "rome": { "expansion.max_cities_divisor": 120, ... }, "persia": {...} }
	var overrides_path = OS.get_environment("SIM_AI_OVERRIDES")
	if overrides_path != "":
		_load_ai_overrides(overrides_path)

	# Create logger
	logger = SimLoggerClass.new()
	logger.name = "SimLogger"
	add_child(logger)

	# Wire AI controller to logger
	AIControllerRef.sim_logger = logger

	# Configure game settings
	var settings = _get_settings()

	print("=== AI SIMULATION STARTING ===")
	print("Map: %dx%d (%s), Players: %d, Difficulty: %d, Speed: %s, Barbarians: %s" % [
		settings.map_width, settings.map_height, settings.map_type,
		settings.num_players, settings.difficulty,
		["Quick", "Normal", "Epic", "Marathon"][settings.game_speed],
		"OFF" if settings.no_barbarians else "ON"])

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

	# Auto-introduce all non-barbarian players to each other
	# (In actual games, exploration handles this; in sims we want diplomacy to work)
	for p in GameManager.players:
		if p.is_barbarian():
			continue
		for other in GameManager.players:
			if other == p or other.is_barbarian():
				continue
			if other.player_id not in p.met_players:
				p.met_players.append(other.player_id)

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
	var civs_env = OS.get_environment("SIM_CIVS")
	var civs: Array = []
	if civs_env != "":
		for c in civs_env.split(","):
			var trimmed = c.strip_edges()
			if trimmed != "":
				civs.append(trimmed)
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
		"no_barbarians": _env_bool("SIM_NO_BARBARIANS", false),
		"civs": civs,
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
	TurnManager.game_ended = true

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

	# Optional compact results JSON for evolutionary tuner
	# SIM_RESULTS_OUT=path/to/result.json
	var results_path = OS.get_environment("SIM_RESULTS_OUT")
	if results_path != "":
		_write_results_json(results_path)

	# Clean up AI controller reference
	AIControllerRef.sim_logger = null

	# Exit
	call_deferred("_quit")

func _write_results_json(path: String) -> void:
	var result := {
		"turns": TurnManager.current_turn,
		"winner": "",
		"victory_type": "",
		"players": []
	}
	if logger and logger.winner_player:
		result["winner"] = logger.winner_player.civilization_id
		result["victory_type"] = logger.winner_victory_type
	for p in GameManager.players:
		if p.civilization_id == "barbarian":
			continue
		p.calculate_score()
		var mil = 0
		var wrk = 0
		var pop = 0
		var total_culture = 0
		var legendary_cities = 0
		for u in p.units:
			if u.get_strength() > 0:
				mil += 1
			if u.can_build_improvements():
				wrk += 1
		for c in p.cities:
			pop += c.population
			total_culture += c.culture
			if c.culture >= 50000:
				legendary_cities += 1
		result["players"].append({
			"civ": p.civilization_id,
			"leader": p.leader_id,
			"name": p.player_name,
			"score": p.score,
			"cities": p.cities.size(),
			"techs": p.researched_techs.size(),
			"pop": pop,
			"military": mil,
			"workers": wrk,
			"gold": p.gold,
			"gold_per_turn": p.gold_per_turn,
			"total_culture": total_culture,
			"legendary_cities": legendary_cities,
			"strategy": p.active_strategy,
			"eliminated": p.cities.is_empty(),
		})
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(result, "  "))
		file.close()
		print("Results written to: %s" % path)

func _load_ai_overrides(path: String) -> void:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to load AI overrides: " + path)
		return
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("Invalid AI overrides JSON (expected object): " + path)
		return
	GameManager.ai_overrides = parsed
	print("Loaded AI overrides for %d civs from %s" % [parsed.size(), path])
	for civ_id in parsed.keys():
		var count = (parsed[civ_id] as Dictionary).size() if parsed[civ_id] is Dictionary else 0
		print("  %s: %d override keys" % [civ_id, count])

func _quit() -> void:
	get_tree().quit()
