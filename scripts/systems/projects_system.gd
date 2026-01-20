extends Node
## Manages projects including world wonders, national projects, and spaceship parts.

# Project data
var projects: Dictionary = {}

# Global project tracking (world wonders)
# Structure: { project_id: { "owner": player_id, "city": city_ref, "turn": int } }
var global_projects: Dictionary = {}

# Per-player project tracking
# Structure: { player_id: { project_id: count } }
var player_projects: Dictionary = {}

# Spaceship progress per player
# Structure: { player_id: { "parts": { part_id: count }, "ready": bool } }
var spaceship_progress: Dictionary = {}

func _ready() -> void:
	_load_project_data()
	EventBus.turn_ended.connect(_on_turn_ended)

func _load_project_data() -> void:
	var path = "res://data/projects.json"
	if not FileAccess.file_exists(path):
		push_warning("ProjectsSystem: Projects file not found")
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ProjectsSystem: Failed to open projects file")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("ProjectsSystem: JSON parse error: " + json.get_error_message())
		return

	projects = json.data
	projects.erase("_metadata")
	print("ProjectsSystem: Loaded %d projects" % projects.size())

# Initialize a player's project tracking
func initialize_player(player_id: int) -> void:
	if not player_projects.has(player_id):
		player_projects[player_id] = {}
	if not spaceship_progress.has(player_id):
		spaceship_progress[player_id] = {
			"parts": {},
			"ready": false
		}

# Check if a project can be built by a player
func can_build_project(project_id: String, player, city = null) -> Dictionary:
	var result = {"can_build": false, "reason": ""}

	if not projects.has(project_id):
		result.reason = "Unknown project"
		return result

	var project = projects[project_id]
	initialize_player(player.player_id)

	# Check tech requirement
	var tech_req = project.get("tech_required", "")
	if tech_req != "" and not player.has_tech(tech_req):
		result.reason = "Requires " + tech_req
		return result

	# Check victory prerequisite
	var victory_prereq = project.get("victory_prereq", "")
	if victory_prereq != "":
		# Check if this victory type is enabled
		if not VictorySystem.is_victory_enabled(victory_prereq):
			result.reason = "Victory type disabled"
			return result

	# Check prerequisite projects
	var prereq_projects = project.get("prereq_projects", [])
	for prereq in prereq_projects:
		if not has_player_completed_project(player.player_id, prereq):
			var prereq_name = get_project_name(prereq)
			result.reason = "Requires " + prereq_name
			return result

	# Check anyone prerequisite (someone in the world must have built it)
	var anyone_prereq = project.get("anyone_prereq_project", "")
	if anyone_prereq != "" and not global_projects.has(anyone_prereq):
		var prereq_name = get_project_name(anyone_prereq)
		result.reason = "Requires " + prereq_name + " (any player)"
		return result

	# Check global instance limit
	var max_global = project.get("max_global_instances", -1)
	if max_global > 0:
		var global_count = 0
		if global_projects.has(project_id):
			global_count = 1  # World wonders are unique
		if global_count >= max_global:
			result.reason = "Already built"
			return result

	# Check team/player instance limit
	var max_team = project.get("max_team_instances", -1)
	if max_team > 0:
		var player_count = player_projects[player.player_id].get(project_id, 0)
		if player_count >= max_team:
			result.reason = "Already built maximum"
			return result

	result.can_build = true
	return result

# Complete a project for a player
func complete_project(project_id: String, player, city) -> bool:
	var check = can_build_project(project_id, player, city)
	if not check.can_build:
		push_warning("ProjectsSystem: Cannot complete project - " + check.reason)
		return false

	var project = projects[project_id]
	initialize_player(player.player_id)

	# Record project completion
	var max_global = project.get("max_global_instances", -1)
	if max_global > 0 and max_global <= 1:
		# World wonder - only one exists
		global_projects[project_id] = {
			"owner": player.player_id,
			"city": city,
			"turn": TurnManager.current_turn if TurnManager else 0
		}

	# Increment player count
	if not player_projects[player.player_id].has(project_id):
		player_projects[player.player_id][project_id] = 0
	player_projects[player.player_id][project_id] += 1

	# Track spaceship parts
	if project.get("spaceship_part", false):
		if not spaceship_progress[player.player_id].parts.has(project_id):
			spaceship_progress[player.player_id].parts[project_id] = 0
		spaceship_progress[player.player_id].parts[project_id] += 1
		_check_spaceship_completion(player.player_id)

	# Apply project effects
	_apply_project_effects(project_id, project, player, city)

	# Emit signal
	EventBus.project_completed.emit(player.player_id, project_id, city)

	return true

func _apply_project_effects(project_id: String, project: Dictionary, player, city) -> void:
	var effects = project.get("effects", {})

	# Nukes enabled
	if effects.get("allows_nukes", false):
		# Set global flag that nukes are available
		GameManager.nukes_enabled = true
		EventBus.notification_added.emit("Nuclear weapons are now available!", "warning")

	# Tech share (The Internet)
	var tech_share = effects.get("tech_share", 0)
	if tech_share > 0:
		_apply_tech_share(player, tech_share)

	# Nuke interception (SDI)
	var nuke_intercept = effects.get("nuke_interception", 0)
	if nuke_intercept > 0:
		player.nuke_interception_chance = nuke_intercept

	# Enables spaceship building
	if effects.get("enables_spaceship", false):
		player.can_build_spaceship = true

func _apply_tech_share(player, threshold: int) -> void:
	# Grant techs that at least 'threshold' other civs have
	var all_players = GameManager.get_all_players() if GameManager else []
	var tech_counts = {}

	for other_player in all_players:
		if other_player.player_id == player.player_id:
			continue
		for tech_id in other_player.researched_techs:
			if not tech_counts.has(tech_id):
				tech_counts[tech_id] = 0
			tech_counts[tech_id] += 1

	var techs_gained = []
	for tech_id in tech_counts:
		if tech_counts[tech_id] >= threshold:
			if tech_id not in player.researched_techs:
				player.add_tech(tech_id)
				techs_gained.append(tech_id)

	if not techs_gained.is_empty():
		EventBus.notification_added.emit(
			"The Internet grants knowledge of %d technologies!" % techs_gained.size(),
			"science"
		)

func _check_spaceship_completion(player_id: int) -> void:
	var progress = spaceship_progress[player_id]
	var parts = progress.parts

	# Required parts for space race victory
	var required = {
		"ss_cockpit": 1,
		"ss_life_support": 1,
		"ss_stasis_chamber": 1,
		"ss_docking_bay": 1,
		"ss_engine": 1,      # Minimum 1, optimal 2
		"ss_casing": 1,      # Minimum 1, optimal 5
		"ss_thrusters": 1    # Minimum 1, optimal 5
	}

	# Check if minimum requirements are met
	var meets_minimum = true
	for part_id in required:
		var needed = required[part_id]
		var have = parts.get(part_id, 0)
		if have < needed:
			meets_minimum = false
			break

	progress.ready = meets_minimum

	if meets_minimum:
		EventBus.spaceship_ready.emit(player_id)
		# Calculate travel time based on optional parts
		var travel_time = _calculate_spaceship_travel_time(player_id)
		EventBus.notification_added.emit(
			"Spaceship ready for launch! Travel time: %d turns" % travel_time,
			"victory"
		)

func _calculate_spaceship_travel_time(player_id: int) -> int:
	var progress = spaceship_progress[player_id]
	var parts = progress.parts

	var base_time = 10  # Base travel time in turns

	# Engines reduce travel time
	var engines = parts.get("ss_engine", 0)
	if engines >= 2:
		base_time = int(base_time * 0.5)  # 50% faster with 2 engines

	# Thrusters reduce travel time
	var thrusters = parts.get("ss_thrusters", 0)
	var thruster_reduction = min(thrusters, 5) * 0.1  # Up to 50% reduction
	base_time = int(base_time * (1.0 - thruster_reduction))

	# Casings affect success rate, not time
	# Success rate checked separately

	return max(1, base_time)

# Launch the spaceship (win the game)
func launch_spaceship(player_id: int) -> bool:
	if not spaceship_progress.has(player_id):
		return false

	var progress = spaceship_progress[player_id]
	if not progress.ready:
		return false

	# Calculate success chance based on casings
	var parts = progress.parts
	var casings = parts.get("ss_casing", 0)

	# Each casing adds 20% success, 5 casings = 100%
	var success_chance = min(100, casings * 20)

	var roll = randi() % 100
	if roll < success_chance:
		# Success! Space race victory
		EventBus.spaceship_launched.emit(player_id, true)
		VictorySystem.check_space_race_victory(player_id)
		return true
	else:
		# Failure - lose some parts
		EventBus.spaceship_launched.emit(player_id, false)
		EventBus.notification_added.emit(
			"Spaceship launch failed! Some components were damaged.",
			"warning"
		)
		# Remove one random part
		var part_keys = parts.keys()
		if not part_keys.is_empty():
			var random_part = part_keys[randi() % part_keys.size()]
			parts[random_part] = max(0, parts[random_part] - 1)
			progress.ready = false
		return false

# Get spaceship progress for display
func get_spaceship_status(player_id: int) -> Dictionary:
	initialize_player(player_id)
	var progress = spaceship_progress[player_id]
	var parts = progress.parts

	return {
		"cockpit": {"have": parts.get("ss_cockpit", 0), "need": 1},
		"life_support": {"have": parts.get("ss_life_support", 0), "need": 1},
		"stasis_chamber": {"have": parts.get("ss_stasis_chamber", 0), "need": 1},
		"docking_bay": {"have": parts.get("ss_docking_bay", 0), "need": 1},
		"engine": {"have": parts.get("ss_engine", 0), "need": 2, "min": 1},
		"casing": {"have": parts.get("ss_casing", 0), "need": 5, "min": 1},
		"thrusters": {"have": parts.get("ss_thrusters", 0), "need": 5, "min": 1},
		"ready": progress.ready,
		"travel_time": _calculate_spaceship_travel_time(player_id) if progress.ready else -1
	}

# Check if player has completed a project
func has_player_completed_project(player_id: int, project_id: String) -> bool:
	if not player_projects.has(player_id):
		return false
	return player_projects[player_id].get(project_id, 0) > 0

# Get project count for player
func get_player_project_count(player_id: int, project_id: String) -> int:
	if not player_projects.has(player_id):
		return 0
	return player_projects[player_id].get(project_id, 0)

# Get who built a world wonder
func get_world_project_owner(project_id: String) -> Dictionary:
	return global_projects.get(project_id, {})

# Check if a world project has been built
func is_world_project_built(project_id: String) -> bool:
	return global_projects.has(project_id)

# Get all available projects for a player
func get_available_projects(player) -> Array:
	var available = []
	for project_id in projects:
		var check = can_build_project(project_id, player)
		if check.can_build:
			available.append(project_id)
	return available

# Get project data
func get_project(project_id: String) -> Dictionary:
	return projects.get(project_id, {})

func get_project_name(project_id: String) -> String:
	var project = get_project(project_id)
	return project.get("name", project_id.capitalize())

func get_project_cost(project_id: String) -> int:
	var project = get_project(project_id)
	return project.get("cost", 0)

func get_all_projects() -> Dictionary:
	return projects

func get_spaceship_parts() -> Array:
	var parts = []
	for project_id in projects:
		if projects[project_id].get("spaceship_part", false):
			parts.append(project_id)
	return parts

func get_world_projects() -> Array:
	var world = []
	for project_id in projects:
		if projects[project_id].get("type", "") == "world":
			world.append(project_id)
	return world

func get_national_projects() -> Array:
	var national = []
	for project_id in projects:
		if projects[project_id].get("type", "") == "national":
			national.append(project_id)
	return national

# Calculate production bonus for a project in a city
func get_production_bonus(project_id: String, city) -> int:
	var project = get_project(project_id)
	var bonus_production = project.get("bonus_production", {})

	var total_bonus = 0
	for resource_id in bonus_production:
		if city.has_access_to_resource(resource_id):
			total_bonus += bonus_production[resource_id]

	return total_bonus

func _on_turn_ended(_turn_number, _player) -> void:
	# Could process ongoing effects here
	pass

# Serialization
func to_dict() -> Dictionary:
	return {
		"global_projects": global_projects.duplicate(true),
		"player_projects": player_projects.duplicate(true),
		"spaceship_progress": spaceship_progress.duplicate(true)
	}

func from_dict(data: Dictionary) -> void:
	global_projects = data.get("global_projects", {})
	player_projects = data.get("player_projects", {})
	spaceship_progress = data.get("spaceship_progress", {})
