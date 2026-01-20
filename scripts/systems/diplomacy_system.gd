extends Node
## Manages diplomatic relations, attitude calculations, and diplomacy memory.

# Attitude levels
enum Attitude { FURIOUS, ANNOYED, CAUTIOUS, PLEASED, FRIENDLY }

# Memory event types
enum MemoryType {
	DECLARED_WAR,
	MADE_PEACE,
	SIGNED_OPEN_BORDERS,
	CANCELLED_OPEN_BORDERS,
	SIGNED_DEFENSIVE_PACT,
	CANCELLED_DEFENSIVE_PACT,
	GAVE_TRIBUTE,
	REFUSED_TRIBUTE,
	SHARED_TECH,
	SHARED_RELIGION,
	WORST_ENEMY_OF_FRIEND,
	TRADED_WITH_ENEMY,
	HELPED_IN_WAR
}

# Memory decay rates (per turn)
const MEMORY_DECAY = {
	MemoryType.DECLARED_WAR: 0.02,        # Very slow decay
	MemoryType.MADE_PEACE: 0.05,
	MemoryType.SIGNED_OPEN_BORDERS: 0.1,
	MemoryType.CANCELLED_OPEN_BORDERS: 0.05,
	MemoryType.SIGNED_DEFENSIVE_PACT: 0.1,
	MemoryType.CANCELLED_DEFENSIVE_PACT: 0.03,
	MemoryType.GAVE_TRIBUTE: 0.1,
	MemoryType.REFUSED_TRIBUTE: 0.05,
	MemoryType.SHARED_TECH: 0.1,
	MemoryType.SHARED_RELIGION: 0.0,       # Never decays
	MemoryType.WORST_ENEMY_OF_FRIEND: 0.03,
	MemoryType.TRADED_WITH_ENEMY: 0.05,
	MemoryType.HELPED_IN_WAR: 0.05
}

# Memory attitude effects
const MEMORY_EFFECTS = {
	MemoryType.DECLARED_WAR: -8,
	MemoryType.MADE_PEACE: 1,
	MemoryType.SIGNED_OPEN_BORDERS: 1,
	MemoryType.CANCELLED_OPEN_BORDERS: -2,
	MemoryType.SIGNED_DEFENSIVE_PACT: 2,
	MemoryType.CANCELLED_DEFENSIVE_PACT: -4,
	MemoryType.GAVE_TRIBUTE: 2,
	MemoryType.REFUSED_TRIBUTE: -2,
	MemoryType.SHARED_TECH: 3,
	MemoryType.SHARED_RELIGION: 2,
	MemoryType.WORST_ENEMY_OF_FRIEND: -3,
	MemoryType.TRADED_WITH_ENEMY: -2,
	MemoryType.HELPED_IN_WAR: 4
}

# Diplomacy memory storage: player_id -> {target_id -> [{type, strength, turns}]}
var diplomacy_memory: Dictionary = {}

# Worst enemy tracking: player_id -> target_id
var worst_enemies: Dictionary = {}

func _ready() -> void:
	# Connect to diplomacy signals
	EventBus.war_declared.connect(_on_war_declared)
	EventBus.peace_declared.connect(_on_peace_declared)
	EventBus.open_borders_signed.connect(_on_open_borders_signed)
	EventBus.defensive_pact_signed.connect(_on_defensive_pact_signed)
	EventBus.trade_accepted.connect(_on_trade_accepted)
	EventBus.all_turns_completed.connect(_on_turn_completed)

## Calculate attitude between two players
func calculate_attitude(from_player, to_player) -> int:
	if from_player == null or to_player == null:
		return 0

	var score = 0

	# Base attitude from leader personality
	var leader = DataManager.get_leader(from_player.leader_id)
	var base_attitude = leader.get("base_attitude", 0)
	score += base_attitude

	# War status (overwhelming negative)
	if GameManager.is_at_war(from_player, to_player):
		return -10

	# Treaty bonuses
	if to_player.player_id in from_player.open_borders_with:
		score += 1

	if to_player.player_id in from_player.defensive_pact_with:
		score += 3

	# Shared religion
	if from_player.state_religion != "" and from_player.state_religion == to_player.state_religion:
		score += 3

	# Different religion penalty
	if from_player.state_religion != "" and to_player.state_religion != "" and from_player.state_religion != to_player.state_religion:
		score -= 1

	# Same worst enemy bonus
	var our_enemy = worst_enemies.get(from_player.player_id, -1)
	var their_enemy = worst_enemies.get(to_player.player_id, -1)
	if our_enemy >= 0 and our_enemy == their_enemy:
		score += 2

	# They are our worst enemy
	if our_enemy == to_player.player_id:
		score -= 3

	# Shared civics bonus
	if from_player.civics and to_player.civics:
		var shared_civics = 0
		for category in from_player.civics:
			if from_player.civics.get(category, "") == to_player.civics.get(category, ""):
				shared_civics += 1
		if shared_civics >= 3:
			score += 1

	# Power ratio (stronger = more respect from AI)
	var our_power = _calculate_power(from_player)
	var their_power = _calculate_power(to_player)
	if their_power > our_power * 2:
		score += 1  # Respect the powerful
	elif our_power > their_power * 2:
		score -= 1  # Contempt for the weak

	# Memory effects
	score += _get_memory_attitude(from_player.player_id, to_player.player_id)

	return score

## Convert attitude score to level
func get_attitude_level(score: int) -> Attitude:
	if score <= -5:
		return Attitude.FURIOUS
	elif score <= -2:
		return Attitude.ANNOYED
	elif score <= 2:
		return Attitude.CAUTIOUS
	elif score <= 5:
		return Attitude.PLEASED
	else:
		return Attitude.FRIENDLY

## Get attitude as string
func get_attitude_string(from_player, to_player) -> String:
	var score = calculate_attitude(from_player, to_player)
	var level = get_attitude_level(score)

	match level:
		Attitude.FURIOUS:
			return "Furious"
		Attitude.ANNOYED:
			return "Annoyed"
		Attitude.CAUTIOUS:
			return "Cautious"
		Attitude.PLEASED:
			return "Pleased"
		Attitude.FRIENDLY:
			return "Friendly"

	return "Unknown"

## Get detailed attitude breakdown
func get_attitude_breakdown(from_player, to_player) -> Array:
	var breakdown = []

	if from_player == null or to_player == null:
		return breakdown

	# Base attitude
	var leader = DataManager.get_leader(from_player.leader_id)
	var base = leader.get("base_attitude", 0)
	if base != 0:
		breakdown.append({"reason": "Base attitude", "value": base})

	# War
	if GameManager.is_at_war(from_player, to_player):
		breakdown.append({"reason": "At war!", "value": -10})
		return breakdown

	# Treaties
	if to_player.player_id in from_player.open_borders_with:
		breakdown.append({"reason": "Open Borders", "value": 1})

	if to_player.player_id in from_player.defensive_pact_with:
		breakdown.append({"reason": "Defensive Pact", "value": 3})

	# Religion
	if from_player.state_religion != "" and from_player.state_religion == to_player.state_religion:
		var rel_name = DataManager.get_religion(from_player.state_religion).get("name", "religion")
		breakdown.append({"reason": "Shared %s" % rel_name, "value": 3})
	elif from_player.state_religion != "" and to_player.state_religion != "" and from_player.state_religion != to_player.state_religion:
		breakdown.append({"reason": "Different religion", "value": -1})

	# Worst enemy
	var our_enemy = worst_enemies.get(from_player.player_id, -1)
	var their_enemy = worst_enemies.get(to_player.player_id, -1)
	if our_enemy >= 0 and our_enemy == their_enemy:
		breakdown.append({"reason": "Shared enemy", "value": 2})

	if our_enemy == to_player.player_id:
		breakdown.append({"reason": "You are our worst enemy!", "value": -3})

	# Memory effects (summarized)
	var memory_total = _get_memory_attitude(from_player.player_id, to_player.player_id)
	if memory_total > 0:
		breakdown.append({"reason": "Past actions (positive)", "value": memory_total})
	elif memory_total < 0:
		breakdown.append({"reason": "Past actions (negative)", "value": memory_total})

	return breakdown

## Add a memory event
func add_memory(player_id: int, target_id: int, memory_type: MemoryType, strength: float = 1.0) -> void:
	if not diplomacy_memory.has(player_id):
		diplomacy_memory[player_id] = {}
	if not diplomacy_memory[player_id].has(target_id):
		diplomacy_memory[player_id][target_id] = []

	# Check if similar memory exists, strengthen it instead
	for memory in diplomacy_memory[player_id][target_id]:
		if memory["type"] == memory_type:
			memory["strength"] = min(memory["strength"] + strength, 3.0)  # Cap at 3x
			memory["turns"] = 0  # Reset decay
			return

	diplomacy_memory[player_id][target_id].append({
		"type": memory_type,
		"strength": strength,
		"turns": 0
	})

## Get total attitude modifier from memory (public wrapper)
func get_memory_attitude(player_id: int, target_id: int) -> int:
	return _get_memory_attitude(player_id, target_id)

## Get total attitude modifier from memory
func _get_memory_attitude(player_id: int, target_id: int) -> int:
	if not diplomacy_memory.has(player_id):
		return 0
	if not diplomacy_memory[player_id].has(target_id):
		return 0

	var total = 0.0
	for memory in diplomacy_memory[player_id][target_id]:
		var base_effect = MEMORY_EFFECTS.get(memory["type"], 0)
		total += base_effect * memory["strength"]

	return int(total)

## Calculate military power
func _calculate_power(player) -> int:
	if player == null:
		return 0

	var power = 0

	# Units
	for unit in player.units:
		var unit_data = DataManager.get_unit(unit.unit_id)
		power += unit_data.get("strength", 0) * 10

	# Cities
	power += player.cities.size() * 50

	# Population
	power += player.get_total_population() * 5

	return power

## Update worst enemy for a player
func update_worst_enemy(player_id: int) -> void:
	var player = GameManager.get_player(player_id)
	if player == null:
		return

	var worst_id = -1
	var worst_score = 0

	for other in GameManager.players:
		if other.player_id == player_id:
			continue
		if other.player_id not in player.met_players:
			continue

		var score = calculate_attitude(player, other)
		if score < worst_score:
			worst_score = score
			worst_id = other.player_id

	if worst_id >= 0:
		worst_enemies[player_id] = worst_id

## Process memory decay each turn
func _process_memory_decay() -> void:
	for player_id in diplomacy_memory:
		for target_id in diplomacy_memory[player_id]:
			var memories = diplomacy_memory[player_id][target_id]
			var to_remove = []

			for memory in memories:
				memory["turns"] += 1
				var decay_rate = MEMORY_DECAY.get(memory["type"], 0.05)
				memory["strength"] -= decay_rate

				if memory["strength"] <= 0:
					to_remove.append(memory)

			for memory in to_remove:
				memories.erase(memory)

## Check if player would accept a diplomatic proposal
func would_accept_proposal(from_player, to_player, proposal_type: String) -> bool:
	var attitude_score = calculate_attitude(to_player, from_player)
	var attitude = get_attitude_level(attitude_score)

	match proposal_type:
		"open_borders":
			return attitude >= Attitude.CAUTIOUS
		"defensive_pact":
			return attitude >= Attitude.PLEASED
		"peace":
			# Always willing to consider peace, but may demand tribute
			return true
		"trade":
			return attitude >= Attitude.ANNOYED

	return false

## Get peace demands (what AI wants to make peace)
func get_peace_demands(winner, loser) -> Dictionary:
	var demands = {
		"gold": 0,
		"gold_per_turn": 0,
		"techs": [],
		"resources": [],
		"cities": []
	}

	# Calculate power difference
	var winner_power = _calculate_power(winner)
	var loser_power = _calculate_power(loser)

	if winner_power <= loser_power:
		return demands  # No demands if not winning

	var power_ratio = float(winner_power) / max(1, loser_power)

	# Gold demands
	if power_ratio > 1.5:
		demands["gold"] = mini(loser.gold, int(loser.gold * (power_ratio - 1.0)))

	# Gold per turn
	if power_ratio > 2.0:
		demands["gold_per_turn"] = 5

	# Tech demands (if crushing)
	if power_ratio > 3.0:
		var tradeable = TradeSystem.get_tradeable_techs(loser, winner)
		if not tradeable.is_empty():
			demands["techs"].append(tradeable[0])

	return demands

# Signal handlers
func _on_war_declared(aggressor, target) -> void:
	# Both sides remember
	add_memory(target.player_id, aggressor.player_id, MemoryType.DECLARED_WAR)

	# Third parties who had defensive pact with target
	for player in GameManager.players:
		if player == aggressor or player == target:
			continue
		if target.player_id in player.defensive_pact_with:
			add_memory(player.player_id, aggressor.player_id, MemoryType.DECLARED_WAR, 0.5)

func _on_peace_declared(player1, player2) -> void:
	add_memory(player1.player_id, player2.player_id, MemoryType.MADE_PEACE)
	add_memory(player2.player_id, player1.player_id, MemoryType.MADE_PEACE)

func _on_open_borders_signed(player1, player2) -> void:
	add_memory(player1.player_id, player2.player_id, MemoryType.SIGNED_OPEN_BORDERS)
	add_memory(player2.player_id, player1.player_id, MemoryType.SIGNED_OPEN_BORDERS)

func _on_defensive_pact_signed(player1, player2) -> void:
	add_memory(player1.player_id, player2.player_id, MemoryType.SIGNED_DEFENSIVE_PACT)
	add_memory(player2.player_id, player1.player_id, MemoryType.SIGNED_DEFENSIVE_PACT)

func _on_trade_accepted(from_player, to_player, offer: Dictionary) -> void:
	# Tech sharing creates positive memory
	var from_offers = offer.get("from_offers", {})
	var to_offers = offer.get("to_offers", {})

	if not from_offers.get("techs", []).is_empty():
		add_memory(to_player.player_id, from_player.player_id, MemoryType.SHARED_TECH)

	if not to_offers.get("techs", []).is_empty():
		add_memory(from_player.player_id, to_player.player_id, MemoryType.SHARED_TECH)

func _on_turn_completed(_turn: int) -> void:
	_process_memory_decay()

	# Update worst enemies for all players
	for player in GameManager.players:
		update_worst_enemy(player.player_id)
