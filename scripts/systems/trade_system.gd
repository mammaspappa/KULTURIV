extends Node
## Handles trade agreements and resource trading between players.

# Active trades
var active_trades: Array = []  # Array of TradeAgreement dictionaries

# Trade agreement structure
# {
#   "id": int,
#   "from_player_id": int,
#   "to_player_id": int,
#   "from_offers": {"gold": int, "gold_per_turn": int, "resources": Array, "techs": Array},
#   "to_offers": {"gold": int, "gold_per_turn": int, "resources": Array, "techs": Array},
#   "duration": int,  # turns remaining (-1 for permanent like techs)
#   "accepted": bool
# }

var next_trade_id: int = 1

func _ready() -> void:
	# Connect signals
	EventBus.trade_proposed.connect(_on_trade_proposed)
	EventBus.trade_accepted.connect(_on_trade_accepted)
	EventBus.trade_rejected.connect(_on_trade_rejected)
	EventBus.all_turns_completed.connect(_on_turn_completed)

## Create a new trade proposal
func create_proposal(from_player, to_player) -> Dictionary:
	return {
		"id": next_trade_id,
		"from_player_id": from_player.player_id,
		"to_player_id": to_player.player_id,
		"from_offers": {
			"gold": 0,
			"gold_per_turn": 0,
			"resources": [],
			"techs": []
		},
		"to_offers": {
			"gold": 0,
			"gold_per_turn": 0,
			"resources": [],
			"techs": []
		},
		"duration": 20,  # Default 20 turns for resource trades
		"accepted": false
	}

## Add gold to an offer
func add_gold_to_offer(proposal: Dictionary, is_from_player: bool, amount: int) -> void:
	var offers = proposal["from_offers"] if is_from_player else proposal["to_offers"]
	offers["gold"] = amount

## Add gold per turn to an offer
func add_gpt_to_offer(proposal: Dictionary, is_from_player: bool, amount: int) -> void:
	var offers = proposal["from_offers"] if is_from_player else proposal["to_offers"]
	offers["gold_per_turn"] = amount

## Add a resource to an offer
func add_resource_to_offer(proposal: Dictionary, is_from_player: bool, resource_id: String) -> void:
	var offers = proposal["from_offers"] if is_from_player else proposal["to_offers"]
	if resource_id not in offers["resources"]:
		offers["resources"].append(resource_id)

## Add a tech to an offer
func add_tech_to_offer(proposal: Dictionary, is_from_player: bool, tech_id: String) -> void:
	var offers = proposal["from_offers"] if is_from_player else proposal["to_offers"]
	if tech_id not in offers["techs"]:
		offers["techs"].append(tech_id)
		proposal["duration"] = -1  # Tech trades are permanent

## Check if a proposal is valid
func is_proposal_valid(proposal: Dictionary) -> bool:
	var from_player = GameManager.get_player(proposal["from_player_id"])
	var to_player = GameManager.get_player(proposal["to_player_id"])

	if from_player == null or to_player == null:
		return false

	# Can't trade with self
	if from_player == to_player:
		return false

	# Can't trade if at war
	if GameManager.is_at_war(from_player, to_player):
		return false

	# Check from_player can provide what they offer
	var from_offers = proposal["from_offers"]
	if from_offers["gold"] > from_player.gold:
		return false

	for resource_id in from_offers["resources"]:
		if not from_player.has_resource(resource_id):
			return false

	for tech_id in from_offers["techs"]:
		if not from_player.has_tech(tech_id):
			return false

	# Check to_player can provide what they offer
	var to_offers = proposal["to_offers"]
	if to_offers["gold"] > to_player.gold:
		return false

	for resource_id in to_offers["resources"]:
		if not to_player.has_resource(resource_id):
			return false

	for tech_id in to_offers["techs"]:
		if not to_player.has_tech(tech_id):
			return false

	# Tech trading requires at least one player to have Alphabet
	var has_tech_trade = not from_offers["techs"].is_empty() or not to_offers["techs"].is_empty()
	if has_tech_trade and not can_trade_techs(from_player, to_player):
		return false

	# Proposal must offer something from both sides or be one-sided gift
	var from_has_offer = from_offers["gold"] > 0 or from_offers["gold_per_turn"] > 0 or not from_offers["resources"].is_empty() or not from_offers["techs"].is_empty()
	var to_has_offer = to_offers["gold"] > 0 or to_offers["gold_per_turn"] > 0 or not to_offers["resources"].is_empty() or not to_offers["techs"].is_empty()

	return from_has_offer or to_has_offer

## Execute a trade agreement
func execute_trade(proposal: Dictionary) -> void:
	var from_player = GameManager.get_player(proposal["from_player_id"])
	var to_player = GameManager.get_player(proposal["to_player_id"])

	if from_player == null or to_player == null:
		return

	var from_offers = proposal["from_offers"]
	var to_offers = proposal["to_offers"]

	# Transfer immediate gold
	if from_offers["gold"] > 0:
		from_player.gold -= from_offers["gold"]
		to_player.gold += from_offers["gold"]

	if to_offers["gold"] > 0:
		to_player.gold -= to_offers["gold"]
		from_player.gold += to_offers["gold"]

	# Transfer techs immediately
	for tech_id in from_offers["techs"]:
		if tech_id not in to_player.researched_techs:
			to_player.researched_techs.append(tech_id)
			EventBus.tech_unlocked.emit(to_player, tech_id)

	for tech_id in to_offers["techs"]:
		if tech_id not in from_player.researched_techs:
			from_player.researched_techs.append(tech_id)
			EventBus.tech_unlocked.emit(from_player, tech_id)

	# Mark trade as active if it has ongoing components
	if from_offers["gold_per_turn"] > 0 or to_offers["gold_per_turn"] > 0 or not from_offers["resources"].is_empty() or not to_offers["resources"].is_empty():
		proposal["accepted"] = true
		proposal["id"] = next_trade_id
		next_trade_id += 1
		active_trades.append(proposal)

## Process ongoing trades each turn
func process_trades() -> void:
	var expired = []

	for trade in active_trades:
		var from_player = GameManager.get_player(trade["from_player_id"])
		var to_player = GameManager.get_player(trade["to_player_id"])

		if from_player == null or to_player == null:
			expired.append(trade)
			continue

		# Check if war broke out
		if GameManager.is_at_war(from_player, to_player):
			expired.append(trade)
			continue

		var from_offers = trade["from_offers"]
		var to_offers = trade["to_offers"]

		# Transfer gold per turn
		if from_offers["gold_per_turn"] > 0:
			if from_player.gold >= from_offers["gold_per_turn"]:
				from_player.gold -= from_offers["gold_per_turn"]
				to_player.gold += from_offers["gold_per_turn"]
			else:
				# Can't pay, cancel trade
				expired.append(trade)
				continue

		if to_offers["gold_per_turn"] > 0:
			if to_player.gold >= to_offers["gold_per_turn"]:
				to_player.gold -= to_offers["gold_per_turn"]
				from_player.gold += to_offers["gold_per_turn"]
			else:
				expired.append(trade)
				continue

		# Decrease duration
		if trade["duration"] > 0:
			trade["duration"] -= 1
			if trade["duration"] <= 0:
				expired.append(trade)

	# Remove expired trades
	for trade in expired:
		active_trades.erase(trade)

## Get tradeable resources for a player
func get_tradeable_resources(player) -> Array:
	if player == null:
		return []

	var available = player.get_available_resources()
	var tradeable = []

	for resource_id in available:
		# Check if resource is already being traded away
		var already_trading = false
		for trade in active_trades:
			if trade["from_player_id"] == player.player_id:
				if resource_id in trade["from_offers"]["resources"]:
					already_trading = true
					break
			if trade["to_player_id"] == player.player_id:
				if resource_id in trade["to_offers"]["resources"]:
					already_trading = true
					break

		if not already_trading:
			tradeable.append(resource_id)

	return tradeable

## Check if two players can trade techs (requires at least one to have Alphabet)
func can_trade_techs(player1, player2) -> bool:
	if player1 == null or player2 == null:
		return false
	return player1.has_tech("alphabet") or player2.has_tech("alphabet")

## Get techs that can be traded to another player
func get_tradeable_techs(from_player, to_player) -> Array:
	if from_player == null or to_player == null:
		return []

	# Tech trading requires at least one player to have Alphabet
	if not can_trade_techs(from_player, to_player):
		return []

	var tradeable = []

	for tech_id in from_player.researched_techs:
		# Player has tech, other doesn't
		if tech_id not in to_player.researched_techs:
			# Other player must have prerequisites
			if DataManager.is_tech_available(tech_id, to_player.researched_techs):
				tradeable.append(tech_id)

	return tradeable

## Calculate AI evaluation of a trade proposal
func evaluate_trade_for_ai(proposal: Dictionary, ai_player_id: int) -> float:
	var score = 0.0

	var from_player = GameManager.get_player(proposal["from_player_id"])
	var to_player = GameManager.get_player(proposal["to_player_id"])

	if from_player == null or to_player == null:
		return -1000.0

	var is_from = ai_player_id == proposal["from_player_id"]
	var ai_receives = proposal["to_offers"] if is_from else proposal["from_offers"]
	var ai_gives = proposal["from_offers"] if is_from else proposal["to_offers"]

	# Value what AI receives
	score += ai_receives["gold"] * 1.0
	score += ai_receives["gold_per_turn"] * proposal["duration"] * 0.8
	score += ai_receives["resources"].size() * 30.0
	score += ai_receives["techs"].size() * 100.0

	# Subtract what AI gives
	score -= ai_gives["gold"] * 1.0
	score -= ai_gives["gold_per_turn"] * proposal["duration"] * 0.8
	score -= ai_gives["resources"].size() * 35.0  # AI values own resources slightly more
	score -= ai_gives["techs"].size() * 120.0  # AI is reluctant to give techs

	return score

## Check if AI would accept a trade
func would_ai_accept(proposal: Dictionary, ai_player_id: int) -> bool:
	var score = evaluate_trade_for_ai(proposal, ai_player_id)
	return score >= 0

## Cancel an active trade
func cancel_trade(trade_id: int) -> void:
	for trade in active_trades:
		if trade["id"] == trade_id:
			active_trades.erase(trade)
			return

## Get active trades for a player
func get_active_trades_for_player(player_id: int) -> Array:
	var trades = []
	for trade in active_trades:
		if trade["from_player_id"] == player_id or trade["to_player_id"] == player_id:
			trades.append(trade)
	return trades

## Get resources being received by a player through trade
func get_imported_resources(player_id: int) -> Array:
	var imported = []

	for trade in active_trades:
		if trade["from_player_id"] == player_id:
			imported.append_array(trade["to_offers"]["resources"])
		elif trade["to_player_id"] == player_id:
			imported.append_array(trade["from_offers"]["resources"])

	return imported

func _on_trade_proposed(from_player, to_player, offer: Dictionary) -> void:
	if offer.is_empty():
		# Create new empty proposal
		offer = create_proposal(from_player, to_player)

	# If AI player, evaluate and respond
	if not to_player.is_human:
		if would_ai_accept(offer, to_player.player_id):
			EventBus.trade_accepted.emit(from_player, to_player, offer)
		else:
			EventBus.trade_rejected.emit(from_player, to_player)

func _on_trade_accepted(from_player, to_player, offer: Dictionary) -> void:
	if is_proposal_valid(offer):
		execute_trade(offer)

func _on_trade_rejected(_from_player, _to_player) -> void:
	# Just emit the signal, UI handles feedback
	pass

func _on_turn_completed(_turn: int) -> void:
	process_trades()
