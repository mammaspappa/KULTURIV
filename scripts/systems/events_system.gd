extends Node
## Manages random events that occur during gameplay.

# Event data
var events: Dictionary = {}

# Events that have already occurred (for non-recurring events)
# Structure: { event_id: [player_ids who experienced it] }
var occurred_events: Dictionary = {}

# Active temporary effects from events
# Structure: { player_id: [{ "type": str, "value": int, "turns_remaining": int, "city": city_ref }] }
var active_effects: Dictionary = {}

# Event cooldowns per player
# Structure: { player_id: { event_id: turns_until_available } }
var event_cooldowns: Dictionary = {}

# Event queue (pending events to show)
var pending_events: Array = []

# Configuration
var events_enabled: bool = true
var base_event_chance: int = 10  # % chance per turn per city

func _ready() -> void:
	_load_event_data()
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_ended.connect(_on_turn_ended)

func _load_event_data() -> void:
	var path = "res://data/events.json"
	if not FileAccess.file_exists(path):
		push_warning("EventsSystem: Events file not found")
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("EventsSystem: Failed to open events file")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("EventsSystem: JSON parse error: " + json.get_error_message())
		return

	events = json.data
	events.erase("_metadata")
	print("EventsSystem: Loaded %d random events" % events.size())

# Initialize player tracking
func initialize_player(player_id: int) -> void:
	if not active_effects.has(player_id):
		active_effects[player_id] = []
	if not event_cooldowns.has(player_id):
		event_cooldowns[player_id] = {}

# Enable/disable events
func set_events_enabled(enabled: bool) -> void:
	events_enabled = enabled

# Check for random events at turn start
func _on_turn_started(_turn_number, player) -> void:
	if not events_enabled:
		return
	if player == null:
		return

	initialize_player(player.player_id)

	# Check each city for possible events
	for city in player.cities:
		_check_for_events(player, city)

# Process active effects at turn end
func _on_turn_ended(_turn_number, player) -> void:
	if player == null:
		return

	initialize_player(player.player_id)

	# Decrease duration of active effects
	var effects_to_remove = []
	for i in range(active_effects[player.player_id].size()):
		var effect = active_effects[player.player_id][i]
		effect.turns_remaining -= 1
		if effect.turns_remaining <= 0:
			effects_to_remove.append(i)

	# Remove expired effects (in reverse order to preserve indices)
	effects_to_remove.reverse()
	for idx in effects_to_remove:
		active_effects[player.player_id].remove_at(idx)

	# Decrease cooldowns
	for event_id in event_cooldowns[player.player_id].keys():
		event_cooldowns[player.player_id][event_id] -= 1
		if event_cooldowns[player.player_id][event_id] <= 0:
			event_cooldowns[player.player_id].erase(event_id)

func _check_for_events(player, city) -> void:
	# Roll for event chance
	if randi() % 100 >= base_event_chance:
		return

	# Get valid events for this city
	var valid_events = _get_valid_events(player, city)
	if valid_events.is_empty():
		return

	# Weight-based random selection
	var total_weight: int = 0
	for event_id in valid_events:
		total_weight += int(events[event_id].get("weight", 100))

	var roll = randi() % total_weight
	var cumulative = 0
	var selected_event = ""

	for event_id in valid_events:
		cumulative += events[event_id].get("weight", 100)
		if roll < cumulative:
			selected_event = event_id
			break

	if selected_event != "":
		_trigger_event(selected_event, player, city)

func _get_valid_events(player, city) -> Array:
	var valid = []
	var current_turn = TurnManager.current_turn if TurnManager else 0

	for event_id in events:
		var event = events[event_id]
		var triggers = event.get("triggers", {})

		# Check if non-recurring event already occurred for this player
		if not event.get("recurring", true):
			if occurred_events.has(event_id) and player.player_id in occurred_events[event_id]:
				continue

		# Check cooldown
		if event_cooldowns[player.player_id].get(event_id, 0) > 0:
			continue

		# Check triggers
		if not _check_triggers(triggers, player, city, current_turn):
			continue

		valid.append(event_id)

	return valid

func _check_triggers(triggers: Dictionary, player, city, current_turn: int) -> bool:
	# Minimum turn requirement
	if triggers.get("min_turn", 0) > current_turn:
		return false

	# Population requirements
	if triggers.get("min_population", 0) > city.population:
		return false

	# Feature requirement
	var req_feature = triggers.get("requires_feature", "")
	if req_feature != "":
		if not _city_has_feature_nearby(city, req_feature):
			return false

	# Terrain requirement
	var req_terrains = triggers.get("requires_terrain", [])
	if not req_terrains.is_empty():
		if not _city_has_terrain_nearby(city, req_terrains):
			return false

	# Improvement requirement
	var req_improvement = triggers.get("requires_improvement", "")
	if req_improvement != "":
		if not _city_has_improvement_nearby(city, req_improvement):
			return false

	# Building requirement
	var req_building = triggers.get("has_building", "")
	if req_building != "" and not city.has_building(req_building):
		return false

	# Road requirement
	if triggers.get("has_road", false):
		if not _city_has_road(city):
			return false

	# State religion requirement
	if triggers.get("has_state_religion", false):
		if player.state_religion == "":
			return false

	# Met players requirement
	if triggers.get("has_met_players", false):
		if player.met_players.is_empty():
			return false

	# Happiness checks
	if triggers.get("positive_happiness", false):
		if city.get_happiness() <= city.get_unhappiness():
			return false

	if triggers.get("negative_happiness", false):
		if city.get_happiness() >= city.get_unhappiness():
			return false

	# Health checks
	if triggers.get("positive_food", false):
		if city.get_food_surplus() <= 0:
			return false

	if triggers.get("negative_health", false):
		if city.get_health() >= city.get_unhealthiness():
			return false

	# Culture requirement
	var min_culture = triggers.get("min_culture", 0)
	if min_culture > 0 and city.culture < min_culture:
		return false

	# Check if any religions have been founded
	if triggers.get("religions_founded", false):
		if ReligionSystem and ReligionSystem.get_founded_religions().is_empty():
			return false

	# No resource on plot (for discoveries)
	if triggers.get("no_resource", false):
		# Would check tiles around city for resource-less improvements
		pass

	return true

func _city_has_feature_nearby(city, feature_id: String) -> bool:
	# Check worked tiles for the feature
	if not GameManager or not GameManager.game_grid:
		return false

	var worked_tiles = city.get_worked_tiles() if city.has_method("get_worked_tiles") else []
	for tile_pos in worked_tiles:
		var tile = GameManager.game_grid.get_tile(tile_pos.x, tile_pos.y)
		if tile and tile.feature == feature_id:
			return true
	return false

func _city_has_terrain_nearby(city, terrain_ids: Array) -> bool:
	if not GameManager or not GameManager.game_grid:
		return false

	var worked_tiles = city.get_worked_tiles() if city.has_method("get_worked_tiles") else []
	for tile_pos in worked_tiles:
		var tile = GameManager.game_grid.get_tile(tile_pos.x, tile_pos.y)
		if tile and tile.terrain in terrain_ids:
			return true
	return false

func _city_has_improvement_nearby(city, improvement_id: String) -> bool:
	if not GameManager or not GameManager.game_grid:
		return false

	var worked_tiles = city.get_worked_tiles() if city.has_method("get_worked_tiles") else []
	for tile_pos in worked_tiles:
		var tile = GameManager.game_grid.get_tile(tile_pos.x, tile_pos.y)
		if tile and tile.improvement == improvement_id:
			return true
	return false

func _city_has_road(city) -> bool:
	if not GameManager or not GameManager.game_grid:
		return false

	var city_tile = GameManager.game_grid.get_tile(city.position.x, city.position.y)
	return city_tile and city_tile.has_road

func _trigger_event(event_id: String, player, city) -> void:
	var event = events[event_id]

	# Format description with city name
	var description = event.get("description", "An event has occurred.")
	description = description.replace("{city}", city.city_name)

	# Create event data for UI
	var event_data = {
		"id": event_id,
		"name": event.get("name", "Event"),
		"description": description,
		"category": event.get("category", "misc"),
		"choices": _get_available_choices(event, player),
		"player_id": player.player_id,
		"city": city
	}

	# Set cooldown
	event_cooldowns[player.player_id][event_id] = 10  # 10 turn cooldown between same events

	# AI players make choices automatically
	if not player.is_human:
		_ai_handle_event(event_data, player)
		return

	# Queue the event for human player
	pending_events.append(event_data)

	# Emit signal for UI
	EventBus.random_event_triggered.emit(event_data)

## AI automatically handles event choices
func _ai_handle_event(event_data: Dictionary, player) -> void:
	var choices = event_data.choices
	if choices.is_empty():
		return

	# Evaluate each choice and pick the best one based on AI personality
	var best_choice = 0
	var best_score = -INF

	for i in range(choices.size()):
		var choice = choices[i]
		var score = _ai_evaluate_choice(choice, player)
		if score > best_score:
			best_score = score
			best_choice = i

	# Apply the chosen option
	process_event_choice(event_data, best_choice)

## AI evaluates a choice based on effects and personality
func _ai_evaluate_choice(choice: Dictionary, player) -> float:
	var score = 0.0
	var effects = choice.get("effects", {})

	# Get AI leader flavors for weighting
	var leader_data = DataManager.get_leader(player.leader_id) if DataManager else {}
	var flavors = leader_data.get("flavor", {})
	var gold_flavor = flavors.get("gold", 5) / 10.0
	var military_flavor = flavors.get("military", 5) / 10.0
	var science_flavor = flavors.get("science", 5) / 10.0
	var culture_flavor = flavors.get("culture", 5) / 10.0
	var religion_flavor = flavors.get("religion", 5) / 10.0

	for effect_type in effects:
		var value = effects[effect_type]
		if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
			continue

		match effect_type:
			"gold":
				score += value * gold_flavor
			"gold_per_turn":
				score += value * 10 * gold_flavor  # Per-turn is worth more
			"production":
				score += value * military_flavor
			"food":
				score += value * 0.5
			"research":
				score += value * science_flavor
			"culture":
				score += value * culture_flavor
			"happiness":
				score += value * 3  # Happiness is valuable
			"health":
				score += value * 2
			"experience":
				score += value * military_flavor
			"population":
				score += value * 5  # Population is very valuable
			"free_unit":
				score += 50 * military_flavor

	# Penalty for risky choices
	var risk = choice.get("risk", 0)
	if risk > 0:
		score -= risk * 10

	return score

func _get_available_choices(event: Dictionary, player) -> Array:
	var available = []
	var choices = event.get("choices", [])

	for choice in choices:
		# Check tech requirement
		var req_tech = choice.get("requires_tech", "")
		if req_tech != "" and not player.has_tech(req_tech):
			continue

		# Check civic requirement
		var req_civic = choice.get("requires_civic", "")
		if req_civic != "":
			var current_civics = CivicsSystem.get_player_civics(player.player_id) if CivicsSystem else {}
			var has_civic = false
			for category in current_civics:
				if current_civics[category] == req_civic:
					has_civic = true
					break
			if not has_civic:
				continue

		available.append(choice)

	return available

# Process player's choice for an event
func process_event_choice(event_data: Dictionary, choice_index: int) -> Dictionary:
	var result = {
		"success": true,
		"effects_applied": []
	}

	if choice_index < 0 or choice_index >= event_data.choices.size():
		result.success = false
		return result

	var choice = event_data.choices[choice_index]
	var effects = choice.get("effects", {})
	var player = GameManager.get_player(event_data.player_id) if GameManager else null
	var city = event_data.city

	if player == null:
		result.success = false
		return result

	# Apply effects
	for effect_type in effects:
		var value = effects[effect_type]
		_apply_effect(effect_type, value, player, city, result)

	# Mark non-recurring event as occurred
	var event_id = event_data.id
	var event = events.get(event_id, {})
	if not event.get("recurring", true):
		if not occurred_events.has(event_id):
			occurred_events[event_id] = []
		occurred_events[event_id].append(player.player_id)

	# Remove from pending
	pending_events.erase(event_data)

	EventBus.random_event_resolved.emit(event_data.player_id, event_id, choice_index)

	return result

func _apply_effect(effect_type: String, value, player, city, result: Dictionary) -> void:
	match effect_type:
		"gold":
			player.gold += value
			result.effects_applied.append("Gold: %+d" % value)

		"population":
			if city:
				city.population = max(1, city.population + value)
				result.effects_applied.append("Population: %+d" % value)

		"food_bonus":
			if city:
				city.food_stockpile += value
				result.effects_applied.append("Food: %+d" % value)

		"culture":
			if city:
				city.culture += value
				result.effects_applied.append("Culture: %+d" % value)

		"happiness", "happiness_bonus":
			var turns = value
			if effect_type == "happiness":
				turns = 0  # Permanent until we track turns
			_add_temporary_effect(player.player_id, "happiness", value, turns, city)
			result.effects_applied.append("Happiness: %+d" % value)

		"happiness_turns":
			pass  # Handled with happiness

		"health":
			_add_temporary_effect(player.player_id, "health", value, 0, city)
			result.effects_applied.append("Health: %+d" % value)

		"health_turns":
			pass  # Handled with health

		"production_bonus":
			if city:
				city.production_progress += value
				result.effects_applied.append("Production: %+d" % value)

		"production_penalty":
			if city:
				city.production_progress = max(0, city.production_progress + value)
				result.effects_applied.append("Production: %+d" % value)

		"research_bonus":
			player.research_progress += value
			result.effects_applied.append("Research: %+d" % value)

		"gold_per_turn":
			var turns = value
			_add_temporary_effect(player.player_id, "gold_per_turn", value, turns, null)
			result.effects_applied.append("Gold per turn: %+d" % value)

		"remove_feature":
			# Would need to find and remove the feature
			result.effects_applied.append("Feature removed")

		"pillage_improvement":
			# Would need to find and pillage an improvement
			result.effects_applied.append("Improvement pillaged")

		"great_people_points":
			if city and city.has_method("add_great_people_points"):
				city.add_great_people_points(value)
			result.effects_applied.append("Great People Points: %+d" % value)

		"diplomatic_favor":
			# Would improve relations with a random met player
			result.effects_applied.append("Diplomatic favor gained")

		"diplomatic_penalty":
			# Would decrease relations with a random met player
			result.effects_applied.append("Diplomatic penalty")

		"espionage_points":
			# Add espionage points against random rival
			if EspionageSystem and not player.met_players.is_empty():
				var target = player.met_players[randi() % player.met_players.size()]
				EspionageSystem.add_espionage_points(player.player_id, target, value)
			result.effects_applied.append("Espionage points: %+d" % value)

		"espionage_defense":
			if EspionageSystem:
				EspionageSystem.activate_counter_espionage(player.player_id, value, 10)
			result.effects_applied.append("Espionage defense: %+d%%" % value)

		"defense_bonus":
			if city:
				_add_temporary_effect(player.player_id, "defense", value, 10, city)
			result.effects_applied.append("Defense: %+d%%" % value)

		"spawn_enemy_unit":
			# Would spawn a barbarian unit near the city
			result.effects_applied.append("Enemy unit spawned!")

		"spread_random_religion":
			if city and ReligionSystem:
				var religions = ReligionSystem.get_founded_religions()
				if not religions.is_empty():
					var religion = religions[randi() % religions.size()]
					ReligionSystem.spread_religion(religion, city)
			result.effects_applied.append("Religion spread to city")

		"revolt_chance":
			# Roll for city revolt
			if randi() % 100 < value and city:
				city.revolt_turns = 2
				result.effects_applied.append("City revolts!")
			else:
				result.effects_applied.append("Revolt avoided")

func _add_temporary_effect(player_id: int, effect_type: String, value: int, duration: int, city) -> void:
	initialize_player(player_id)
	active_effects[player_id].append({
		"type": effect_type,
		"value": value,
		"turns_remaining": duration if duration > 0 else 999,
		"city": city
	})

# Get active effect total for a player/city
func get_active_effect(player_id: int, effect_type: String, city = null) -> int:
	if not active_effects.has(player_id):
		return 0

	var total = 0
	for effect in active_effects[player_id]:
		if effect.type == effect_type:
			if city == null or effect.city == null or effect.city == city:
				total += effect.value

	return total

# Get pending events for a player
func get_pending_events(player_id: int) -> Array:
	var player_events = []
	for event_data in pending_events:
		if event_data.player_id == player_id:
			player_events.append(event_data)
	return player_events

# Check if there are pending events
func has_pending_events(player_id: int) -> bool:
	for event_data in pending_events:
		if event_data.player_id == player_id:
			return true
	return false

# Get event data
func get_event(event_id: String) -> Dictionary:
	return events.get(event_id, {})

func get_all_events() -> Dictionary:
	return events

# Serialization
func to_dict() -> Dictionary:
	return {
		"occurred_events": occurred_events.duplicate(true),
		"event_cooldowns": event_cooldowns.duplicate(true),
		"events_enabled": events_enabled
	}

func from_dict(data: Dictionary) -> void:
	occurred_events = data.get("occurred_events", {})
	event_cooldowns = data.get("event_cooldowns", {})
	events_enabled = data.get("events_enabled", true)
