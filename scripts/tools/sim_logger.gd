extends Node
## Structured logger for AI simulation runs.
## Captures game events, AI decisions, anomalies, and state snapshots.
## Outputs JSON Lines log file and human-readable summary.

var log_entries: Array = []
var key_events: Array = []
var anomalies: Array = []
var errors: Array = []
var winner_player = null
var winner_victory_type: String = ""

# Anomaly tracking
var negative_gold_turns: Dictionary = {}
var empty_production_turns: Dictionary = {}

# Streaming log file handle
var _log_file: FileAccess = null
var _log_path: String = ""

func _ready() -> void:
	_open_log_file()
	_connect_events()

func _open_log_file() -> void:
	var dir = DirAccess.open("res://")
	if dir and not dir.dir_exists("sim_output"):
		dir.make_dir("sim_output")

	var timestamp = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_").substr(0, 15)
	_log_path = "res://sim_output/sim_%s.jsonl" % timestamp
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log_file == null:
		_log_path = "user://sim_%s.jsonl" % timestamp
		_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log_file:
		print("Log file: %s" % _log_path)

func _connect_events() -> void:
	EventBus.war_declared.connect(_on_war_declared)
	EventBus.peace_declared.connect(_on_peace_declared)
	EventBus.research_completed.connect(_on_research_completed)
	EventBus.religion_founded.connect(_on_religion_founded)
	EventBus.city_founded.connect(_on_city_founded)
	EventBus.city_captured.connect(_on_city_captured)
	EventBus.city_destroyed.connect(_on_city_destroyed)
	EventBus.wonder_built.connect(_on_wonder_built)
	EventBus.great_person_born.connect(_on_great_person_born)
	EventBus.unit_destroyed.connect(_on_unit_destroyed)
	EventBus.victory_achieved.connect(_on_victory_achieved)
	EventBus.civic_changed.connect(_on_civic_changed)
	EventBus.state_religion_adopted.connect(_on_state_religion_adopted)
	EventBus.player_eliminated.connect(_on_player_eliminated)

# --- Core logging ---

func log_entry(data: Dictionary) -> void:
	data["turn"] = TurnManager.current_turn
	data["year"] = TurnManager.get_year_string()
	log_entries.append(data)
	# Write immediately so data survives crashes
	if _log_file:
		_log_file.store_line(JSON.stringify(data))
		_log_file.flush()

func log_decision(player_name: String, category: String, action: String, detail: String, reason: String) -> void:
	log_entry({
		"type": "ai_decision",
		"player": player_name,
		"category": category,
		"action": action,
		"detail": detail,
		"reason": reason
	})

func _log_event(event_name: String, description: String, extra: Dictionary = {}) -> void:
	var data = extra.duplicate()
	data["type"] = "game_event"
	data["event"] = event_name
	data["description"] = description
	log_entry(data)
	key_events.append({"turn": TurnManager.current_turn, "text": description})

func _log_anomaly(message: String) -> void:
	var entry = "Turn %d: %s" % [TurnManager.current_turn, message]
	anomalies.append(entry)
	log_entry({"type": "anomaly", "message": message})

func log_victory(player, victory_type: String) -> void:
	winner_player = player
	winner_victory_type = victory_type
	_log_event("victory", "%s achieved %s Victory!" % [player.player_name, victory_type.capitalize()])

# --- Event handlers ---

func _on_war_declared(aggressor, target) -> void:
	_log_event("war_declared", "%s declared war on %s" % [aggressor.player_name, target.player_name])

func _on_peace_declared(p1, p2) -> void:
	_log_event("peace_declared", "%s and %s made peace" % [p1.player_name, p2.player_name])

func _on_research_completed(player, tech: String) -> void:
	var tech_name = DataManager.get_tech(tech).get("name", tech)
	_log_event("research_completed", "%s researched %s" % [player.player_name, tech_name],
		{"player": player.player_name, "tech": tech})

func _on_religion_founded(player, religion_id: String, city) -> void:
	var rel_name = DataManager.get_religion(religion_id).get("name", religion_id)
	var city_name = city.city_name if city else "Unknown"
	_log_event("religion_founded", "%s founded in %s by %s" % [rel_name, city_name, player.player_name])

func _on_city_founded(city, founder_unit) -> void:
	var founder_name = "Unknown"
	if founder_unit and founder_unit.player_owner:
		founder_name = founder_unit.player_owner.player_name
	elif city.player_owner:
		founder_name = city.player_owner.player_name
	_log_event("city_founded", "%s founded %s at (%d,%d)" % [founder_name, city.city_name, city.grid_position.x, city.grid_position.y])

func _on_city_captured(city, old_owner, new_owner) -> void:
	var old_name = old_owner.player_name if old_owner else "Unknown"
	var new_name = new_owner.player_name if new_owner else "Unknown"
	_log_event("city_captured", "%s captured %s from %s" % [new_name, city.city_name, old_name])

func _on_city_destroyed(city) -> void:
	_log_event("city_destroyed", "%s was razed" % city.city_name)

func _on_wonder_built(wonder_id: String, player_id: int, wonder_type: String) -> void:
	var player = GameManager.get_player(player_id)
	var player_name = player.player_name if player else "Unknown"
	var building = DataManager.get_building(wonder_id)
	var wonder_name = building.get("name", wonder_id)
	_log_event("wonder_built", "%s built %s (%s)" % [player_name, wonder_name, wonder_type])

func _on_great_person_born(city, gp_type: String) -> void:
	var owner_name = city.player_owner.player_name if city.player_owner else "Unknown"
	_log_event("great_person_born", "Great %s born in %s (%s)" % [gp_type.capitalize(), city.city_name, owner_name])

func _on_unit_destroyed(unit) -> void:
	if unit == null:
		return
	var owner_name = unit.player_owner.player_name if unit.player_owner else "Unknown"
	log_entry({"type": "game_event", "event": "unit_destroyed", "description": "%s lost a %s" % [owner_name, unit.unit_id]})

func _on_player_eliminated(player) -> void:
	_log_event("player_eliminated", "%s has been eliminated!" % player.player_name)

func _on_victory_achieved(player, victory_type: String) -> void:
	log_victory(player, victory_type)

func _on_civic_changed(player, category: String, civic_id: String) -> void:
	log_entry({"type": "game_event", "event": "civic_changed",
		"description": "%s adopted %s (%s)" % [player.player_name, civic_id, category]})

func _on_state_religion_adopted(player, religion: String) -> void:
	if player == null:
		return
	var rel_name = "No State Religion"
	if religion != "":
		rel_name = DataManager.get_religion(religion).get("name", religion)
	log_entry({"type": "game_event", "event": "state_religion_changed",
		"description": "%s adopted %s" % [player.player_name, rel_name]})

# --- State snapshots ---

func log_state_snapshot() -> void:
	var players_data = []
	for p in GameManager.players:
		p.calculate_score()
		var military = 0
		for u in p.units:
			if u.get_strength() > 0:
				military += 1
		players_data.append({
			"name": p.player_name, "civ": p.civilization_id,
			"cities": p.cities.size(), "units": p.units.size(),
			"military": military, "gold": p.gold, "gold_per_turn": p.gold_per_turn,
			"techs": p.researched_techs.size(), "score": p.score,
			"state_religion": p.state_religion,
			"at_war_with": p.at_war_with.duplicate()
		})
	log_entry({"type": "state_snapshot", "players": players_data})

	# Print progress to stdout
	var parts = []
	for pd in players_data:
		if pd.cities > 0:
			parts.append("%s: %d pts, %d cities" % [pd.name, pd.score, pd.cities])
		else:
			parts.append("%s: ELIMINATED" % pd.name)
	print("  Turn %d (%s) — %s" % [TurnManager.current_turn, TurnManager.get_year_string(), ", ".join(parts)])

# --- Anomaly detection ---

func check_anomalies() -> void:
	for p in GameManager.players:
		if p.cities.is_empty():
			continue

		# Negative gold spiral
		if p.gold < 0:
			negative_gold_turns[p.player_id] = negative_gold_turns.get(p.player_id, 0) + 1
			if negative_gold_turns[p.player_id] == 10:
				_log_anomaly("%s has had negative gold for 10+ turns (gold=%d, gpt=%d)" % [
					p.player_name, p.gold, p.gold_per_turn])
		else:
			negative_gold_turns[p.player_id] = 0

		# Empty production (skip base barbarian player — camp cities don't produce)
		if p.civilization_id == "barbarian" and p.player_id == -1:
			continue
		for city in p.cities:
			var key = "%s_%s" % [p.player_name, city.city_name]
			if city.current_production == "":
				empty_production_turns[key] = empty_production_turns.get(key, 0) + 1
				if empty_production_turns[key] == 5:
					_log_anomaly("City %s (%s) has no production for 5+ turns" % [city.city_name, p.player_name])
			else:
				empty_production_turns[key] = 0

		# Zombie player (no cities but has units — shouldn't happen long-term)
		if p.cities.is_empty() and not p.units.is_empty() and p.units.size() > 3:
			_log_anomaly("%s has no cities but %d units still alive" % [p.player_name, p.units.size()])

# --- Output ---

func write_log_file() -> void:
	# File was written continuously via log_entry() — just close it
	if _log_file:
		_log_file.close()
		_log_file = null
		print("\nLog file closed: %s (%d entries)" % [_log_path, log_entries.size()])
	else:
		print("\nWARNING: No log file was open")

func write_summary(elapsed_seconds: float) -> void:
	print("\n=== AI SIMULATION COMPLETE ===")

	if winner_player:
		print("Winner: %s (%s Victory) at Turn %d (%s)" % [
			winner_player.player_name, winner_victory_type.capitalize(),
			TurnManager.current_turn, TurnManager.get_year_string()])
	else:
		print("No winner (max turns reached)")

	print("Duration: %d turns, %.1f seconds\n" % [TurnManager.current_turn, elapsed_seconds])

	print("Player Summary:")
	for p in GameManager.players:
		p.calculate_score()
		var marker = " <- WINNER" if p == winner_player else ""
		if p.cities.is_empty():
			print("  %s: Score %d — ELIMINATED%s" % [p.player_name, p.score, marker])
		else:
			print("  %s: Score %d — %d cities, %d units, %d techs, %d gold%s" % [
				p.player_name, p.score, p.cities.size(), p.units.size(),
				p.researched_techs.size(), p.gold, marker])

	if not key_events.is_empty():
		print("\nKey Events (last 25):")
		var events_to_show = key_events.slice(max(0, key_events.size() - 25))
		for ev in events_to_show:
			print("  Turn %d: %s" % [ev.turn, ev.text])

	if not anomalies.is_empty():
		print("\nAnomalies Detected: %d" % anomalies.size())
		for a in anomalies.slice(0, 15):
			print("  %s" % a)

	print("\nErrors: %d" % errors.size())
	for e in errors.slice(0, 10):
		print("  %s" % e)
