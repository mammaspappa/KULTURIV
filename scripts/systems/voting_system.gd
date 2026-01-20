extends Node
## Manages UN and Apostolic Palace voting systems.

# Vote data
var vote_sources: Dictionary = {}
var resolutions: Dictionary = {}

# Active vote sources (buildings constructed)
# Structure: { "united_nations": { "owner": player_id, "city": city_ref }, ... }
var active_vote_sources: Dictionary = {}

# Secretary General / Pope per vote source
# Structure: { "united_nations": player_id, "apostolic_palace": player_id }
var secretaries: Dictionary = {}

# Turn counters for vote scheduling
# Structure: { "united_nations": turns_until_vote, ... }
var vote_timers: Dictionary = {}

# Active resolutions (passed votes in effect)
# Structure: [{ "resolution_id": str, "vote_source": str, "turn_passed": int, "target": optional }]
var active_resolutions: Array = []

# Current pending vote (if any)
var pending_vote: Dictionary = {}

# Vote results storage
var vote_history: Array = []

func _ready() -> void:
	_load_vote_data()
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.city_building_constructed.connect(_on_building_constructed)

func _load_vote_data() -> void:
	var path = "res://data/votes.json"
	if not FileAccess.file_exists(path):
		push_warning("VotingSystem: Votes file not found")
		return

	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("VotingSystem: Failed to open votes file")
		return

	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()

	if error != OK:
		push_error("VotingSystem: JSON parse error: " + json.get_error_message())
		return

	var data = json.data
	vote_sources = data.get("vote_sources", {})
	resolutions = data.get("resolutions", {})
	data.erase("_metadata")
	print("VotingSystem: Loaded %d vote sources and %d resolutions" % [vote_sources.size(), resolutions.size()])

func _on_building_constructed(city, building_id: String) -> void:
	# Check if a vote source building was constructed
	for source_id in vote_sources:
		var source = vote_sources[source_id]
		if source.get("building_required", "") == building_id:
			_activate_vote_source(source_id, city)
			break

func _activate_vote_source(source_id: String, city) -> void:
	if active_vote_sources.has(source_id):
		return  # Already active

	active_vote_sources[source_id] = {
		"owner": city.owner_id,
		"city": city
	}

	var source = vote_sources[source_id]
	vote_timers[source_id] = source.get("vote_interval", 5)

	EventBus.vote_source_activated.emit(source_id, city)
	EventBus.notification_added.emit(
		source.get("name", source_id) + " has been founded!",
		"diplomacy"
	)

func _on_turn_started(turn_number, _player) -> void:
	# Process vote timers
	for source_id in vote_timers.keys():
		vote_timers[source_id] -= 1

		if vote_timers[source_id] <= 0:
			var source = vote_sources.get(source_id, {})
			vote_timers[source_id] = source.get("vote_interval", 5)

			# Time for a vote!
			_initiate_vote_session(source_id)

# Get vote power for a player
func get_vote_power(player_id: int, source_id: String) -> int:
	var source = vote_sources.get(source_id, {})
	var vote_type = source.get("vote_type", "population")

	if vote_type == "population":
		return _get_population_votes(player_id)
	elif vote_type == "religion":
		return _get_religion_votes(player_id, source_id)

	return 0

func _get_population_votes(player_id: int) -> int:
	var player = GameManager.get_player(player_id) if GameManager else null
	if player == null:
		return 0

	var total = 0
	for city in player.cities:
		total += city.population
	return total

func _get_religion_votes(player_id: int, source_id: String) -> int:
	# For Apostolic Palace, only cities with the state religion count
	var player = GameManager.get_player(player_id) if GameManager else null
	if player == null:
		return 0

	var ap_religion = _get_apostolic_palace_religion()
	if ap_religion == "":
		return 0

	var total = 0
	for city in player.cities:
		if city.has_religion(ap_religion):
			total += city.population
	return total

func _get_apostolic_palace_religion() -> String:
	# The AP's religion is the state religion of whoever built it
	if not active_vote_sources.has("apostolic_palace"):
		return ""

	var owner_id = active_vote_sources["apostolic_palace"].owner
	var owner = GameManager.get_player(owner_id) if GameManager else null
	if owner:
		return owner.state_religion
	return ""

# Get total vote power across all eligible voters
func get_total_votes(source_id: String) -> int:
	var total = 0
	var players = GameManager.get_all_players() if GameManager else []

	for player in players:
		if _is_eligible_voter(player.player_id, source_id):
			total += get_vote_power(player.player_id, source_id)

	return total

func _is_eligible_voter(player_id: int, source_id: String) -> bool:
	var source = vote_sources.get(source_id, {})

	if source.get("vote_type", "") == "religion":
		# Must have state religion matching AP
		var player = GameManager.get_player(player_id) if GameManager else null
		if player == null:
			return false
		var ap_religion = _get_apostolic_palace_religion()
		return player.state_religion == ap_religion

	return true  # Population votes are open to all

# Initiate a vote session
func _initiate_vote_session(source_id: String) -> void:
	# First, check if we need to elect a secretary
	if not secretaries.has(source_id) or secretaries[source_id] == -1:
		_initiate_secretary_election(source_id)
		return

	# Otherwise, secretary proposes a resolution
	var secretary_id = secretaries[source_id]
	var available = get_available_resolutions(source_id)

	if available.is_empty():
		return

	# For AI secretary, pick a resolution
	var player = GameManager.get_player(secretary_id) if GameManager else null
	if player and not player.is_human:
		var resolution_id = _ai_choose_resolution(secretary_id, available, source_id)
		if resolution_id != "":
			start_vote(source_id, resolution_id, secretary_id)
	else:
		# Human secretary - emit signal for UI
		EventBus.vote_session_started.emit(source_id, secretary_id, available)

func _initiate_secretary_election(source_id: String) -> void:
	var candidates = _get_secretary_candidates(source_id)
	if candidates.size() < 2:
		return

	pending_vote = {
		"source_id": source_id,
		"resolution_id": "secretary_general" if source_id == "united_nations" else "elect_pope",
		"candidates": candidates,
		"votes": {},
		"is_election": true
	}

	EventBus.secretary_election_started.emit(source_id, candidates)

func _get_secretary_candidates(source_id: String) -> Array:
	# Top 2 vote power players are candidates
	var players = GameManager.get_all_players() if GameManager else []
	var candidates = []

	for player in players:
		if _is_eligible_voter(player.player_id, source_id):
			candidates.append({
				"player_id": player.player_id,
				"votes": get_vote_power(player.player_id, source_id)
			})

	candidates.sort_custom(func(a, b): return a.votes > b.votes)
	return candidates.slice(0, 2)

# Start a vote on a resolution
func start_vote(source_id: String, resolution_id: String, proposer_id: int, target = null) -> void:
	var resolution = resolutions.get(resolution_id, {})

	pending_vote = {
		"source_id": source_id,
		"resolution_id": resolution_id,
		"proposer_id": proposer_id,
		"target": target,
		"votes": {},
		"is_election": false
	}

	EventBus.vote_started.emit(source_id, resolution_id, proposer_id)

	# AI players vote immediately
	var players = GameManager.get_all_players() if GameManager else []
	for player in players:
		if not player.is_human and _is_eligible_voter(player.player_id, source_id):
			var vote = _ai_decide_vote(player.player_id, resolution_id, proposer_id, target)
			cast_vote(player.player_id, vote)

# Cast a vote
func cast_vote(player_id: int, vote_for: bool) -> void:
	if pending_vote.is_empty():
		return

	var source_id = pending_vote.source_id
	if not _is_eligible_voter(player_id, source_id):
		return

	var vote_power = get_vote_power(player_id, source_id)
	pending_vote.votes[player_id] = {
		"vote_for": vote_for,
		"power": vote_power
	}

	# Check if all votes are in
	var players = GameManager.get_all_players() if GameManager else []
	var all_voted = true
	for player in players:
		if _is_eligible_voter(player.player_id, source_id):
			if not pending_vote.votes.has(player.player_id):
				all_voted = false
				break

	if all_voted:
		_tally_votes()

# Cast vote in secretary election
func cast_secretary_vote(player_id: int, candidate_id: int) -> void:
	if pending_vote.is_empty() or not pending_vote.get("is_election", false):
		return

	var source_id = pending_vote.source_id
	if not _is_eligible_voter(player_id, source_id):
		return

	var vote_power = get_vote_power(player_id, source_id)
	pending_vote.votes[player_id] = {
		"candidate": candidate_id,
		"power": vote_power
	}

	# Check if all votes are in
	var players = GameManager.get_all_players() if GameManager else []
	var all_voted = true
	for player in players:
		if _is_eligible_voter(player.player_id, source_id):
			if not pending_vote.votes.has(player.player_id):
				all_voted = false
				break

	if all_voted:
		_tally_secretary_election()

func _tally_votes() -> void:
	var resolution = resolutions.get(pending_vote.resolution_id, {})
	var threshold = resolution.get("population_threshold", 51)
	var total_votes = get_total_votes(pending_vote.source_id)

	var votes_for = 0
	var votes_against = 0

	for player_id in pending_vote.votes:
		var vote_data = pending_vote.votes[player_id]
		if vote_data.vote_for:
			votes_for += vote_data.power
		else:
			votes_against += vote_data.power

	var percent_for = (votes_for * 100) / max(1, total_votes)
	var passed = percent_for >= threshold

	# Record result
	var result = {
		"source_id": pending_vote.source_id,
		"resolution_id": pending_vote.resolution_id,
		"votes_for": votes_for,
		"votes_against": votes_against,
		"percent_for": percent_for,
		"threshold": threshold,
		"passed": passed,
		"turn": TurnManager.current_turn if TurnManager else 0
	}
	vote_history.append(result)

	if passed:
		_apply_resolution(pending_vote.resolution_id, pending_vote.source_id, pending_vote.target)

	EventBus.vote_completed.emit(pending_vote.source_id, pending_vote.resolution_id, passed, result)
	pending_vote = {}

func _tally_secretary_election() -> void:
	var candidate_votes = {}

	for player_id in pending_vote.votes:
		var vote_data = pending_vote.votes[player_id]
		var candidate = vote_data.candidate
		if not candidate_votes.has(candidate):
			candidate_votes[candidate] = 0
		candidate_votes[candidate] += vote_data.power

	# Find winner
	var winner = -1
	var max_votes = 0
	for candidate in candidate_votes:
		if candidate_votes[candidate] > max_votes:
			max_votes = candidate_votes[candidate]
			winner = candidate

	var source_id = pending_vote.source_id
	secretaries[source_id] = winner

	EventBus.secretary_elected.emit(source_id, winner)

	var source = vote_sources.get(source_id, {})
	var player = GameManager.get_player(winner) if GameManager else null
	if player:
		EventBus.notification_added.emit(
			player.civ_name + " has been elected " + source.get("secretary_title", "Secretary") + "!",
			"diplomacy"
		)

	pending_vote = {}

func _apply_resolution(resolution_id: String, source_id: String, target) -> void:
	var resolution = resolutions.get(resolution_id, {})
	var effects = resolution.get("effects", {})

	# Victory
	if effects.get("victory", false):
		var secretary_id = secretaries.get(source_id, -1)
		if secretary_id >= 0:
			VictorySystem.check_diplomatic_victory(secretary_id) if VictorySystem else null

	# Trade routes
	var trade_routes = effects.get("trade_routes", 0)
	if trade_routes > 0:
		active_resolutions.append({
			"resolution_id": resolution_id,
			"source_id": source_id,
			"effect": "trade_routes",
			"value": trade_routes
		})

	# Free trade
	if effects.get("free_trade", false):
		active_resolutions.append({
			"resolution_id": resolution_id,
			"source_id": source_id,
			"effect": "free_trade"
		})

	# No nukes
	if effects.get("no_nukes", false):
		active_resolutions.append({
			"resolution_id": resolution_id,
			"source_id": source_id,
			"effect": "no_nukes"
		})
		GameManager.nukes_banned = true if GameManager else null

	# Force civic
	var force_civic = effects.get("force_civic", "")
	if force_civic != "":
		_force_all_civics(force_civic, source_id)

	# Open borders
	if effects.get("open_borders", false):
		_force_open_borders(source_id)

	# Defensive pact
	if effects.get("defensive_pact", false):
		_force_defensive_pacts(source_id)

	# Force peace
	if effects.get("force_peace", false) and target:
		_force_peace(target)

	# Force no trade
	if effects.get("force_no_trade", false) and target:
		_force_embargo(target, source_id)

	# Force war
	if effects.get("force_war", false) and target:
		_force_war(target, source_id)

	# Assign city
	if effects.get("assign_city", false) and target:
		_assign_city(target)

func _force_all_civics(civic_id: String, source_id: String) -> void:
	var players = GameManager.get_all_players() if GameManager else []
	for player in players:
		if _is_eligible_voter(player.player_id, source_id):
			if CivicsSystem:
				var category = CivicsSystem.get_civic_category(civic_id)
				CivicsSystem.change_civic(player.player_id, category, civic_id)

func _force_open_borders(source_id: String) -> void:
	var players = GameManager.get_all_players() if GameManager else []
	var eligible = []
	for player in players:
		if _is_eligible_voter(player.player_id, source_id):
			eligible.append(player.player_id)

	for i in range(eligible.size()):
		for j in range(i + 1, eligible.size()):
			var p1 = GameManager.get_player(eligible[i]) if GameManager else null
			var p2 = GameManager.get_player(eligible[j]) if GameManager else null
			if p1 and p2:
				p1.set_open_borders(eligible[j], true)
				p2.set_open_borders(eligible[i], true)

func _force_defensive_pacts(source_id: String) -> void:
	var players = GameManager.get_all_players() if GameManager else []
	var eligible = []
	for player in players:
		if _is_eligible_voter(player.player_id, source_id):
			eligible.append(player.player_id)

	for i in range(eligible.size()):
		for j in range(i + 1, eligible.size()):
			var p1 = GameManager.get_player(eligible[i]) if GameManager else null
			var p2 = GameManager.get_player(eligible[j]) if GameManager else null
			if p1 and p2:
				p1.set_defensive_pact(eligible[j], true)
				p2.set_defensive_pact(eligible[i], true)

func _force_peace(target) -> void:
	# Force peace with all players at war with target
	var players = GameManager.get_all_players() if GameManager else []
	for player in players:
		if player.is_at_war_with(target.player_id):
			player.make_peace_with(target.player_id)
			EventBus.peace_declared.emit(player, target)

func _force_embargo(target, source_id: String) -> void:
	var players = GameManager.get_all_players() if GameManager else []
	for player in players:
		if _is_eligible_voter(player.player_id, source_id) and player.player_id != target.player_id:
			player.set_trade_embargo(target.player_id, true)

func _force_war(target, source_id: String) -> void:
	var players = GameManager.get_all_players() if GameManager else []
	for player in players:
		if _is_eligible_voter(player.player_id, source_id) and player.player_id != target.player_id:
			if not player.is_at_war_with(target.player_id):
				player.declare_war_on(target.player_id)
				EventBus.war_declared.emit(player, target)

func _assign_city(target) -> void:
	# Target should be { city: city_ref, new_owner: player_id }
	if target.has("city") and target.has("new_owner"):
		var city = target.city
		var new_owner_id = target.new_owner
		city.transfer_to(new_owner_id)
		EventBus.city_captured.emit(city, city.owner_id, new_owner_id)

# AI decision making
func _ai_choose_resolution(player_id: int, available: Array, source_id: String) -> String:
	# Simple AI: prioritize victory, then beneficial resolutions
	for res_id in available:
		var effects = resolutions[res_id].get("effects", {})
		if effects.get("victory", false):
			return res_id

	# Otherwise pick randomly from available
	if not available.is_empty():
		return available[randi() % available.size()]

	return ""

func _ai_decide_vote(player_id: int, resolution_id: String, proposer_id: int, target) -> bool:
	var resolution = resolutions.get(resolution_id, {})
	var effects = resolution.get("effects", {})

	# Victory vote - support proposer if we ARE the proposer or allied
	if effects.get("victory", false):
		if player_id == proposer_id:
			return true
		# Check relationship
		var player = GameManager.get_player(player_id) if GameManager else null
		var proposer = GameManager.get_player(proposer_id) if GameManager else null
		if player and proposer:
			var relations = player.get_relationship(proposer_id)
			return relations in ["friendly", "pleased"]

	# Force war against us - obviously vote no
	if effects.get("force_war", false) and target and target.player_id == player_id:
		return false

	# Embargo against us
	if effects.get("force_no_trade", false) and target and target.player_id == player_id:
		return false

	# Most other resolutions: vote based on relationship with proposer
	var player = GameManager.get_player(player_id) if GameManager else null
	if player:
		var relations = player.get_relationship(proposer_id)
		if relations in ["friendly", "pleased"]:
			return true
		elif relations in ["furious", "annoyed"]:
			return false

	return randf() > 0.5  # Random tie-breaker

# Get available resolutions for a vote source
func get_available_resolutions(source_id: String) -> Array:
	var available = []
	for res_id in resolutions:
		var res = resolutions[res_id]
		var sources = res.get("vote_source", [])
		if source_id in sources:
			available.append(res_id)
	return available

# Check if a resolution is active
func is_resolution_active(resolution_id: String) -> bool:
	for res in active_resolutions:
		if res.resolution_id == resolution_id:
			return true
	return false

# Get active resolution effect value
func get_resolution_effect(effect_type: String) -> int:
	for res in active_resolutions:
		if res.get("effect", "") == effect_type:
			return res.get("value", 1)
	return 0

# Get secretary for a vote source
func get_secretary(source_id: String) -> int:
	return secretaries.get(source_id, -1)

# Check if nukes are banned
func are_nukes_banned() -> bool:
	return is_resolution_active("nuclear_non_proliferation")

# Get vote source data
func get_vote_source(source_id: String) -> Dictionary:
	return vote_sources.get(source_id, {})

func get_all_vote_sources() -> Dictionary:
	return vote_sources

func get_resolution(resolution_id: String) -> Dictionary:
	return resolutions.get(resolution_id, {})

# Serialization
func to_dict() -> Dictionary:
	return {
		"active_vote_sources": active_vote_sources.duplicate(true),
		"secretaries": secretaries.duplicate(),
		"vote_timers": vote_timers.duplicate(),
		"active_resolutions": active_resolutions.duplicate(true),
		"vote_history": vote_history.duplicate(true)
	}

func from_dict(data: Dictionary) -> void:
	active_vote_sources = data.get("active_vote_sources", {})
	secretaries = data.get("secretaries", {})
	vote_timers = data.get("vote_timers", {})
	active_resolutions = data.get("active_resolutions", [])
	vote_history = data.get("vote_history", [])
