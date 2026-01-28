extends Node
## Manages espionage mechanics including spy placement, missions, and espionage points.

# Espionage points accumulated against each player
# Structure: { player_id: { target_player_id: points } }
var espionage_points: Dictionary = {}

# Spies in cities
# Structure: { city_id: [spy_unit1, spy_unit2, ...] }
var spies_in_cities: Dictionary = {}

# Active counter-espionage bonuses
# Structure: { player_id: { "bonus": int, "turns_remaining": int } }
var counter_espionage_active: Dictionary = {}

# Mission cooldowns (prevent spam)
# Structure: { player_id: { mission_id: turns_until_available } }
var mission_cooldowns: Dictionary = {}

# Exposed spies (recently discovered)
# Structure: { spy_unit: { "by_player": player_id, "turn": int } }
var exposed_spies: Dictionary = {}

# Mission data
var missions: Dictionary = {}

func _ready() -> void:
	_load_mission_data()
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.unit_destroyed.connect(_on_unit_destroyed)

func _load_mission_data() -> void:
	var path = "res://data/espionage_missions.json"
	if not FileAccess.file_exists(path):
		push_warning("EspionageSystem: Missions file not found")
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("EspionageSystem: Failed to open missions file")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("EspionageSystem: JSON parse error: " + json.get_error_message())
		return

	missions = json.data
	# Remove metadata
	missions.erase("_metadata")
	print("EspionageSystem: Loaded %d espionage missions" % missions.size())

# Initialize espionage for a player
func initialize_player(player_id: int) -> void:
	if not espionage_points.has(player_id):
		espionage_points[player_id] = {}
	if not mission_cooldowns.has(player_id):
		mission_cooldowns[player_id] = {}
	if not counter_espionage_active.has(player_id):
		counter_espionage_active[player_id] = {"bonus": 0, "turns_remaining": 0}

# Get espionage points against a target
func get_espionage_points(player_id: int, target_id: int) -> int:
	if not espionage_points.has(player_id):
		return 0
	return espionage_points[player_id].get(target_id, 0)

# Add espionage points against a target
func add_espionage_points(player_id: int, target_id: int, amount: int) -> void:
	initialize_player(player_id)
	if not espionage_points[player_id].has(target_id):
		espionage_points[player_id][target_id] = 0
	espionage_points[player_id][target_id] += amount
	EventBus.espionage_points_changed.emit(player_id, target_id, espionage_points[player_id][target_id])

# Spend espionage points on a mission
func spend_espionage_points(player_id: int, target_id: int, amount: int) -> bool:
	var current = get_espionage_points(player_id, target_id)
	if current < amount:
		return false
	espionage_points[player_id][target_id] -= amount
	EventBus.espionage_points_changed.emit(player_id, target_id, espionage_points[player_id][target_id])
	return true

# Calculate espionage points generated per turn
func calculate_espionage_generation(player) -> int:
	var base_points = 0

	# From cities
	for city in player.cities:
		base_points += _calculate_city_espionage(city)

	# From buildings (intelligence agency, etc.)
	# Base generation is small without dedicated buildings
	base_points += 1  # Minimum 1 point per turn

	return base_points

func _calculate_city_espionage(city) -> int:
	var points = 0

	# Buildings that generate espionage
	if city.has_building("intelligence_agency"):
		points += 4
	if city.has_building("security_bureau"):
		points += 2

	# Specialists (spy specialists if implemented)
	# points += city.get_specialist_count("spy") * 2

	return points

# Place a spy in a city
func place_spy_in_city(spy_unit, city) -> bool:
	if not spy_unit or not city:
		return false

	# Verify unit is a spy type
	var unit_data = DataManager.get_unit(spy_unit.unit_id)
	if not unit_data.get("abilities", []).has("spy"):
		return false

	var city_id = city.get_instance_id()
	if not spies_in_cities.has(city_id):
		spies_in_cities[city_id] = []

	if spy_unit in spies_in_cities[city_id]:
		return false  # Already in city

	spies_in_cities[city_id].append(spy_unit)
	EventBus.spy_placed.emit(spy_unit, city)
	return true

# Remove a spy from a city
func remove_spy_from_city(spy_unit, city) -> void:
	var city_id = city.get_instance_id()
	if spies_in_cities.has(city_id):
		spies_in_cities[city_id].erase(spy_unit)
		if spies_in_cities[city_id].is_empty():
			spies_in_cities.erase(city_id)

# Check if player has spy in city
func has_spy_in_city(player_id: int, city) -> bool:
	var city_id = city.get_instance_id()
	if not spies_in_cities.has(city_id):
		return false

	for spy in spies_in_cities[city_id]:
		if spy.owner_id == player_id:
			return true
	return false

# Get available missions for a player against a target
func get_available_missions(player, target_player, target_city = null) -> Array:
	var available = []
	var player_id = player.player_id
	var target_id = target_player.player_id
	var points = get_espionage_points(player_id, target_id)

	for mission_id in missions:
		var mission = missions[mission_id]

		# Check cost
		var cost = calculate_mission_cost(mission_id, player, target_player, target_city)
		if points < cost:
			continue

		# Check tech requirement
		if mission.tech_required != "" and not player.has_tech(mission.tech_required):
			continue

		# Check spy requirement
		if mission.requires_spy_in_city:
			if target_city == null or not has_spy_in_city(player_id, target_city):
				continue

		# Check target type compatibility
		var target_type = mission.target_type
		if target_type == "city" and target_city == null:
			continue
		if target_type == "building" and target_city == null:
			continue

		# Check cooldown
		if mission_cooldowns.has(player_id) and mission_cooldowns[player_id].get(mission_id, 0) > 0:
			continue

		available.append(mission_id)

	return available

# Calculate actual mission cost (modified by various factors)
func calculate_mission_cost(mission_id: String, player, target_player, target_city = null) -> int:
	var mission = missions.get(mission_id, {})
	var base_cost = mission.get("base_cost", 100)
	var cost = base_cost

	# Distance modifier (if targeting a city)
	if target_city != null and not player.cities.is_empty():
		var min_distance = 999
		for city in player.cities:
			var dist = _calculate_city_distance(city, target_city)
			min_distance = min(min_distance, dist)
		cost = int(cost * (1.0 + min_distance * 0.05))

	# Counter-espionage modifier
	if counter_espionage_active.has(target_player.player_id):
		var ce = counter_espionage_active[target_player.player_id]
		if ce.turns_remaining > 0:
			cost = int(cost * (1.0 + ce.bonus / 100.0))

	# Relationship modifier (costs more against friends)
	var relations = target_player.get_relationship(player.player_id)
	if relations == "friendly":
		cost = int(cost * 1.5)
	elif relations == "war":
		cost = int(cost * 0.75)

	return cost

func _calculate_city_distance(city1, city2) -> int:
	# Simple manhattan distance
	var pos1 = city1.position if city1.has_method("get") else Vector2i.ZERO
	var pos2 = city2.position if city2.has_method("get") else Vector2i.ZERO
	return abs(pos1.x - pos2.x) + abs(pos1.y - pos2.y)

# Execute an espionage mission
func execute_mission(mission_id: String, player, target_player, target_city = null, target_building: String = "") -> Dictionary:
	var result = {
		"success": false,
		"discovered": false,
		"spy_captured": false,
		"effects": {},
		"message": ""
	}

	if not missions.has(mission_id):
		result.message = "Invalid mission"
		return result

	var mission = missions[mission_id]
	var player_id = player.player_id
	var target_id = target_player.player_id

	# Calculate and spend cost
	var cost = calculate_mission_cost(mission_id, player, target_player, target_city)
	if not spend_espionage_points(player_id, target_id, cost):
		result.message = "Insufficient espionage points"
		return result

	# Calculate success chance
	var success_chance = _calculate_success_chance(mission, player, target_player, target_city)
	var roll = randf() * 100

	if roll <= success_chance:
		result.success = true
		result.effects = _apply_mission_effects(mission_id, mission, player, target_player, target_city, target_building)
		result.message = "Mission successful: " + mission.name
	else:
		result.message = "Mission failed: " + mission.name

	# Check for discovery
	var discovery_chance = mission.get("discovery_chance", 0)
	# Increase discovery chance on failure
	if not result.success:
		discovery_chance = min(100, discovery_chance + 20)

	# Counter-espionage increases discovery
	if counter_espionage_active.has(target_id):
		var ce = counter_espionage_active[target_id]
		if ce.turns_remaining > 0:
			discovery_chance = min(100, discovery_chance + ce.bonus / 2)

	var discovery_roll = randf() * 100
	if discovery_roll <= discovery_chance:
		result.discovered = true
		_handle_discovery(player, target_player, mission_id)

		# Chance to capture spy if one was used
		if mission.requires_spy_in_city and target_city != null:
			if randf() < 0.5:  # 50% capture chance on discovery
				result.spy_captured = _capture_spy(player_id, target_city)

	# Set cooldown for some missions
	var cooldown = mission.get("cooldown_turns", 0)
	if cooldown > 0:
		if not mission_cooldowns.has(player_id):
			mission_cooldowns[player_id] = {}
		mission_cooldowns[player_id][mission_id] = cooldown

	# Emit event
	EventBus.espionage_mission_executed.emit(player_id, target_id, mission_id, result)

	return result

func _calculate_success_chance(mission: Dictionary, player, target_player, target_city) -> float:
	var base_chance = mission.get("success_chance_base", 50)
	var chance = float(base_chance)

	# Spy in city bonus
	if target_city != null and has_spy_in_city(player.player_id, target_city):
		chance += 15

	# Experience bonus from successful past missions (could track this)

	# Building bonuses
	for city in player.cities:
		if city.has_building("intelligence_agency"):
			chance += 10
			break

	# Counter-espionage penalty
	if counter_espionage_active.has(target_player.player_id):
		var ce = counter_espionage_active[target_player.player_id]
		if ce.turns_remaining > 0:
			chance -= ce.bonus / 4

	return clamp(chance, 5, 95)  # Always 5-95% chance

func _apply_mission_effects(mission_id: String, mission: Dictionary, player, target_player, target_city, target_building: String) -> Dictionary:
	var effects = mission.get("effects", {})
	var applied = {}

	match mission_id:
		"see_demographics":
			# Reveal target's demographics (population, land, techs, etc.)
			applied["demographics_revealed"] = true
			# Would actually reveal this info in the UI

		"investigate_city":
			# Reveal all city info
			if target_city:
				applied["city_revealed"] = target_city.city_name
				applied["buildings"] = target_city.buildings.duplicate()
				applied["production"] = target_city.current_production

		"see_research":
			# Reveal current research
			applied["current_research"] = target_player.current_research
			applied["research_progress"] = target_player.research_progress

		"steal_treasury":
			# Steal gold
			var percent = effects.get("steal_gold_percent", 25)
			var max_gold = effects.get("max_gold", 500)
			var stolen = min(int(target_player.gold * percent / 100.0), max_gold)
			target_player.gold -= stolen
			player.gold += stolen
			applied["gold_stolen"] = stolen

		"sabotage_production":
			# Destroy production progress
			if target_city:
				var lost = target_city.production_progress
				target_city.production_progress = 0
				applied["production_destroyed"] = lost

		"destroy_building":
			# Destroy a specific building
			if target_city and target_building != "":
				if target_city.has_building(target_building):
					target_city.remove_building(target_building)
					applied["building_destroyed"] = target_building

		"destroy_improvement":
			# Would need to target a specific tile
			applied["improvement_destroyed"] = true

		"incite_revolt":
			# Cause city revolt
			if target_city:
				var turns = effects.get("revolt_turns", 3)
				target_city.revolt_turns = turns
				applied["revolt_turns"] = turns

		"poison_water":
			# Apply health penalty
			if target_city:
				var penalty = effects.get("health_penalty", -4)
				var duration = effects.get("duration_turns", 5)
				target_city.apply_health_modifier(penalty, duration)
				applied["health_penalty"] = penalty
				applied["duration"] = duration

		"spread_unhappiness":
			# Apply happiness penalty
			if target_city:
				var penalty = effects.get("happiness_penalty", -3)
				var duration = effects.get("duration_turns", 5)
				target_city.apply_happiness_modifier(penalty, duration)
				applied["happiness_penalty"] = penalty
				applied["duration"] = duration

		"counter_espionage":
			# Boost own counter-espionage
			var bonus = effects.get("counter_espionage_bonus", 50)
			var duration = effects.get("duration_turns", 10)
			counter_espionage_active[player.player_id] = {
				"bonus": bonus,
				"turns_remaining": duration
			}
			applied["counter_espionage_active"] = true

		"steal_technology":
			# Steal a random tech
			var stealable = _get_stealable_techs(player, target_player)
			if not stealable.is_empty():
				var stolen_tech = stealable[randi() % stealable.size()]
				player.add_tech(stolen_tech)
				applied["tech_stolen"] = stolen_tech
				EventBus.research_completed.emit(player, stolen_tech)

		"switch_civic":
			# Force civic change (complex - would need UI)
			applied["civic_change_forced"] = true

		"switch_religion":
			# Force religion change
			applied["religion_change_forced"] = true

		"expose_spy":
			# Find and capture enemy spy in own territory
			var captured = _expose_enemy_spy(player)
			applied["spy_exposed"] = captured

	return applied

func _get_stealable_techs(player, target_player) -> Array:
	var stealable = []
	for tech_id in target_player.researched_techs:
		if tech_id not in player.researched_techs:
			stealable.append(tech_id)
	return stealable

func _handle_discovery(player, target_player, mission_id: String) -> void:
	# Diplomatic penalty
	if GameManager.has_method("get_diplomacy_system"):
		var diplomacy = GameManager.get_diplomacy_system()
		if diplomacy:
			diplomacy.add_memory(target_player.player_id, player.player_id, "ESPIONAGE_DISCOVERED", -5, 30)

	# Notify target player
	EventBus.espionage_discovered.emit(target_player.player_id, player.player_id, mission_id)

func _capture_spy(player_id: int, city) -> bool:
	var city_id = city.get_instance_id()
	if not spies_in_cities.has(city_id):
		return false

	for spy in spies_in_cities[city_id]:
		if spy.owner_id == player_id:
			# Capture and destroy the spy
			spies_in_cities[city_id].erase(spy)
			EventBus.spy_captured.emit(spy, city)
			spy.destroy()
			return true

	return false

func _expose_enemy_spy(player) -> bool:
	# Look for enemy spies in player's cities
	for city in player.cities:
		var city_id = city.get_instance_id()
		if spies_in_cities.has(city_id):
			for spy in spies_in_cities[city_id]:
				if spy.owner_id != player.player_id:
					# Found enemy spy - capture
					spies_in_cities[city_id].erase(spy)
					EventBus.spy_captured.emit(spy, city)
					spy.destroy()
					return true
	return false

# Activate counter-espionage for a player
func activate_counter_espionage(player_id: int, bonus: int = 50, duration: int = 10) -> void:
	counter_espionage_active[player_id] = {
		"bonus": bonus,
		"turns_remaining": duration
	}

# Process turn end
func _on_turn_ended(_turn_number, _current_player) -> void:
	# Decay cooldowns
	for player_id in mission_cooldowns:
		var cooldowns = mission_cooldowns[player_id]
		for mission_id in cooldowns.keys():
			cooldowns[mission_id] -= 1
			if cooldowns[mission_id] <= 0:
				cooldowns.erase(mission_id)

	# Decay counter-espionage
	for player_id in counter_espionage_active:
		var ce = counter_espionage_active[player_id]
		if ce.turns_remaining > 0:
			ce.turns_remaining -= 1

func _on_unit_destroyed(unit) -> void:
	# Remove spy from any city they were in
	for city_id in spies_in_cities.keys():
		if unit in spies_in_cities[city_id]:
			spies_in_cities[city_id].erase(unit)
			if spies_in_cities[city_id].is_empty():
				spies_in_cities.erase(city_id)
			break

# Get mission data
func get_mission(mission_id: String) -> Dictionary:
	return missions.get(mission_id, {})

func get_all_missions() -> Dictionary:
	return missions

# Serialization
func to_dict() -> Dictionary:
	return {
		"espionage_points": espionage_points.duplicate(true),
		"counter_espionage_active": counter_espionage_active.duplicate(true),
		"mission_cooldowns": mission_cooldowns.duplicate(true)
	}

func from_dict(data: Dictionary) -> void:
	espionage_points = data.get("espionage_points", {})
	counter_espionage_active = data.get("counter_espionage_active", {})
	mission_cooldowns = data.get("mission_cooldowns", {})
