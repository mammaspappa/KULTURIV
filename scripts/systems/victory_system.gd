extends Node
## Handles victory condition checking.

const MAX_TURNS = 500
const DOMINATION_LAND_PERCENT = 0.66
const DOMINATION_POP_PERCENT = 0.66
const CULTURAL_THRESHOLD = 50000
const CULTURAL_CITIES_NEEDED = 3

## Check all victory conditions
## Returns {achieved: bool, player: Player, type: String} or empty dict
func check_victory() -> Dictionary:
	for player in GameManager.players:
		if player.cities.is_empty():
			continue

		# Conquest victory - all other civs eliminated
		if _check_conquest(player):
			return {"achieved": true, "player": player, "type": "conquest"}

		# Domination victory - control 66% of land and population
		if _check_domination(player):
			return {"achieved": true, "player": player, "type": "domination"}

		# Cultural victory - 3 cities with legendary culture
		if _check_cultural(player):
			return {"achieved": true, "player": player, "type": "cultural"}

		# Space Race victory - build spaceship
		if _check_space_race(player):
			return {"achieved": true, "player": player, "type": "space"}

	# Score victory at turn limit
	if TurnManager.current_turn >= MAX_TURNS:
		var winner = _get_highest_score_player()
		return {"achieved": true, "player": winner, "type": "score"}

	return {}

func _check_conquest(player) -> bool:
	# All other civs must have no cities
	for other_player in GameManager.players:
		if other_player == player:
			continue
		if not other_player.cities.is_empty():
			return false
	return true

func _check_domination(player) -> bool:
	var total_land = 0
	var player_land = 0
	var total_pop = 0
	var player_pop = 0

	for p in GameManager.players:
		for city in p.cities:
			total_land += city.territory.size()
			total_pop += city.population
			if p == player:
				player_land += city.territory.size()
				player_pop += city.population

	if total_land == 0 or total_pop == 0:
		return false

	var land_percent = float(player_land) / total_land
	var pop_percent = float(player_pop) / total_pop

	return land_percent >= DOMINATION_LAND_PERCENT and pop_percent >= DOMINATION_POP_PERCENT

func _check_cultural(player) -> bool:
	var legendary_cities = 0
	for city in player.cities:
		if city.culture >= CULTURAL_THRESHOLD:
			legendary_cities += 1

	return legendary_cities >= CULTURAL_CITIES_NEEDED

func _check_space_race(player) -> bool:
	# Check for spaceship parts (simplified - check for specific buildings/wonders)
	var required_parts = ["ss_cockpit", "ss_casing", "ss_thrusters", "ss_stasis_chamber", "ss_life_support", "ss_engine"]
	var parts_built = 0

	for city in player.cities:
		for part in required_parts:
			if part in city.buildings:
				parts_built += 1

	# Also check for Apollo Program as prerequisite
	var has_apollo = false
	for city in player.cities:
		if "apollo_program" in city.buildings:
			has_apollo = true
			break

	return has_apollo and parts_built >= required_parts.size()

func _get_highest_score_player():
	var best_player = GameManager.players[0]
	var best_score = -1

	for player in GameManager.players:
		player.calculate_score()
		if player.score > best_score:
			best_score = player.score
			best_player = player

	return best_player

## Get victory progress for UI display
func get_victory_progress(player) -> Dictionary:
	var progress = {}

	# Conquest progress
	var total_civs = GameManager.players.size()
	var eliminated = 0
	for p in GameManager.players:
		if p != player and p.cities.is_empty():
			eliminated += 1
	progress["conquest"] = {
		"current": eliminated,
		"needed": total_civs - 1,
		"percent": float(eliminated) / (total_civs - 1) if total_civs > 1 else 0
	}

	# Domination progress
	var total_land = 0
	var player_land = 0
	var total_pop = 0
	var player_pop = 0
	for p in GameManager.players:
		for city in p.cities:
			total_land += city.territory.size()
			total_pop += city.population
			if p == player:
				player_land += city.territory.size()
				player_pop += city.population

	var land_percent = float(player_land) / max(total_land, 1)
	var pop_percent = float(player_pop) / max(total_pop, 1)
	progress["domination"] = {
		"land_percent": land_percent,
		"pop_percent": pop_percent,
		"land_needed": DOMINATION_LAND_PERCENT,
		"pop_needed": DOMINATION_POP_PERCENT
	}

	# Cultural progress
	var legendary = 0
	var highest_culture = 0
	for city in player.cities:
		if city.culture >= CULTURAL_THRESHOLD:
			legendary += 1
		highest_culture = max(highest_culture, city.culture)
	progress["cultural"] = {
		"legendary_cities": legendary,
		"needed": CULTURAL_CITIES_NEEDED,
		"highest_culture": highest_culture,
		"threshold": CULTURAL_THRESHOLD
	}

	# Space race progress
	var has_apollo = false
	var parts_built = 0
	var required_parts = ["ss_cockpit", "ss_casing", "ss_thrusters", "ss_stasis_chamber", "ss_life_support", "ss_engine"]
	for city in player.cities:
		if "apollo_program" in city.buildings:
			has_apollo = true
		for part in required_parts:
			if part in city.buildings:
				parts_built += 1
	progress["space"] = {
		"has_apollo": has_apollo,
		"parts_built": parts_built,
		"parts_needed": required_parts.size()
	}

	# Score
	player.calculate_score()
	progress["score"] = {
		"current": player.score,
		"turns_remaining": MAX_TURNS - TurnManager.current_turn
	}

	return progress
