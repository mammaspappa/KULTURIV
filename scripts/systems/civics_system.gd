extends Node
## Handles civic management and effects for all players.

# Civic categories
const CIVIC_CATEGORIES = ["government", "legal", "labor", "economy", "religion"]

# Upkeep costs per level
const UPKEEP_COSTS = {
	"none": 0,
	"low": 1,
	"medium": 2,
	"high": 3
}

# Anarchy turns when changing civics
const BASE_ANARCHY_TURNS = 1

func _ready() -> void:
	# Connect to turn events
	EventBus.all_turns_completed.connect(_on_turn_completed)

## Get the default civics for a new player
func get_default_civics() -> Dictionary:
	return {
		"government": "despotism",
		"legal": "barbarism",
		"labor": "tribalism",
		"economy": "decentralization",
		"religion": "paganism"
	}

## Check if a player can adopt a civic
func can_adopt_civic(player, civic_id: String) -> bool:
	if player == null:
		return false

	var civic = DataManager.get_civic(civic_id)
	if civic.is_empty():
		return false

	# Check tech requirement
	var required_tech = civic.get("required_tech", "")
	if required_tech != "" and not player.has_tech(required_tech):
		return false

	# Check if already using this civic
	var category = civic.get("category", "")
	if player.civics.get(category, "") == civic_id:
		return false

	return true

## Get available civics for a player in a category
func get_available_civics(player, category: String) -> Array:
	var available = []

	if player == null or category not in CIVIC_CATEGORIES:
		return available

	var all_civics = DataManager.civics
	for civic_id in all_civics:
		if civic_id.begins_with("_"):
			continue  # Skip metadata

		var civic = all_civics[civic_id]
		if civic.get("category", "") != category:
			continue

		var required_tech = civic.get("required_tech", "")
		if required_tech == "" or player.has_tech(required_tech):
			available.append(civic_id)

	return available

## Change a player's civic (triggers anarchy)
func change_civic(player, civic_id: String) -> bool:
	if player == null:
		return false

	if not can_adopt_civic(player, civic_id):
		return false

	var civic = DataManager.get_civic(civic_id)
	var category = civic.get("category", "")

	if category == "":
		return false

	var old_civic = player.civics.get(category, "")

	# Apply anarchy if changing
	if old_civic != "" and old_civic != civic_id:
		var anarchy_turns = _calculate_anarchy_turns(player)
		if anarchy_turns > 0:
			_start_anarchy(player, anarchy_turns)

	# Update civic
	player.civics[category] = civic_id

	# Emit signal
	EventBus.civic_changed.emit(player, category, civic_id)

	return true

## Change multiple civics at once (single anarchy period)
func change_civics(player, new_civics: Dictionary) -> bool:
	if player == null:
		return false

	var changes_made = false
	var needs_anarchy = false

	# Validate all changes first
	for category in new_civics:
		var civic_id = new_civics[category]
		if not can_adopt_civic(player, civic_id):
			continue

		var old_civic = player.civics.get(category, "")
		if old_civic != civic_id:
			needs_anarchy = true
			changes_made = true

	if not changes_made:
		return false

	# Apply anarchy once for all changes
	if needs_anarchy:
		var anarchy_turns = _calculate_anarchy_turns(player)
		if anarchy_turns > 0:
			_start_anarchy(player, anarchy_turns)

	# Apply all changes
	for category in new_civics:
		var civic_id = new_civics[category]
		if can_adopt_civic(player, civic_id):
			player.civics[category] = civic_id
			EventBus.civic_changed.emit(player, category, civic_id)

	return true

## Calculate anarchy turns for civic change
func _calculate_anarchy_turns(player) -> int:
	var base_turns = BASE_ANARCHY_TURNS

	# Spiritual trait reduces anarchy
	if player.has_trait("spiritual"):
		return 0

	# Some wonders might reduce anarchy
	# TODO: Add wonder effects

	return base_turns

## Start anarchy period for a player
func _start_anarchy(player, turns: int) -> void:
	if player == null:
		return

	player.anarchy_turns = turns
	EventBus.anarchy_started.emit(player, turns)

## Process anarchy each turn
func _process_anarchy(player) -> void:
	if player == null or player.anarchy_turns <= 0:
		return

	player.anarchy_turns -= 1

	if player.anarchy_turns <= 0:
		EventBus.anarchy_ended.emit(player)

## Get total civic upkeep for a player
func get_civic_upkeep(player) -> int:
	if player == null:
		return 0

	var total_upkeep = 0

	for category in player.civics:
		var civic_id = player.civics[category]
		var civic = DataManager.get_civic(civic_id)
		var upkeep_level = civic.get("upkeep", "none")
		total_upkeep += UPKEEP_COSTS.get(upkeep_level, 0)

	# Scale by number of cities
	total_upkeep *= player.cities.size()

	return total_upkeep

## Get all civic effects for a player (aggregated)
func get_civic_effects(player) -> Dictionary:
	var effects = {}

	if player == null:
		return effects

	for category in player.civics:
		var civic_id = player.civics[category]
		var civic = DataManager.get_civic(civic_id)
		var civic_effects = civic.get("effects", {})

		for effect_key in civic_effects:
			var effect_value = civic_effects[effect_key]

			# Aggregate numeric effects
			if effect_value is int or effect_value is float:
				effects[effect_key] = effects.get(effect_key, 0) + effect_value
			# Boolean effects are OR'd together
			elif effect_value is bool:
				if effect_value:
					effects[effect_key] = true
			else:
				effects[effect_key] = effect_value

	return effects

## Check if player has a specific civic effect
func has_civic_effect(player, effect_key: String) -> bool:
	var effects = get_civic_effects(player)
	return effects.get(effect_key, false) == true

## Get numeric civic effect value
func get_civic_effect_value(player, effect_key: String, default_value = 0):
	var effects = get_civic_effects(player)
	return effects.get(effect_key, default_value)

## Apply civic effects to city yields
func apply_civic_effects_to_city(player, city, yields: Dictionary) -> Dictionary:
	var modified_yields = yields.duplicate()
	var effects = get_civic_effects(player)

	# Capital bonuses (Bureaucracy)
	if city == player.cities[0] if not player.cities.is_empty() else null:
		var capital_prod_mod = effects.get("capital_production_modifier", 0)
		var capital_comm_mod = effects.get("capital_commerce_modifier", 0)

		if capital_prod_mod > 0:
			modified_yields["production"] = int(modified_yields.get("production", 0) * (1.0 + capital_prod_mod / 100.0))
		if capital_comm_mod > 0:
			modified_yields["commerce"] = int(modified_yields.get("commerce", 0) * (1.0 + capital_comm_mod / 100.0))

	# Culture modifier (Free Speech)
	var culture_mod = effects.get("culture_modifier", 0)
	if culture_mod > 0:
		modified_yields["culture"] = int(modified_yields.get("culture", 0) * (1.0 + culture_mod / 100.0))

	return modified_yields

## Get happiness bonus from civics for a city
func get_civic_happiness(player, city) -> int:
	var happiness = 0
	var effects = get_civic_effects(player)

	# Happiness per military unit (Hereditary Rule)
	var happy_per_mil = effects.get("happy_per_military_unit", 0)
	if happy_per_mil > 0:
		var military_units = _count_military_units_in_city(player, city)
		happiness += military_units * happy_per_mil

	# Largest city happiness (Representation)
	var largest_city_bonus = effects.get("largest_city_happiness", 0)
	if largest_city_bonus > 0:
		if _is_among_largest_cities(player, city, 5):
			happiness += largest_city_bonus

	# Happiness per religion (Free Religion)
	var happy_per_religion = effects.get("happiness_per_religion", 0)
	if happy_per_religion > 0:
		happiness += city.religions.size() * happy_per_religion

	return happiness

## Get unhappiness from civics (like Emancipation anger)
func get_civic_unhappiness(player, city) -> int:
	var unhappiness = 0

	# Emancipation anger: if you don't run Emancipation but other civs do
	unhappiness += _get_emancipation_anger(player, city)

	return unhappiness

## Calculate Emancipation anger
## If other known civs run Emancipation and this player doesn't,
## this player gets unhappiness in their cities
func _get_emancipation_anger(player, _city) -> int:
	if player == null or GameManager == null:
		return 0

	# Check if this player runs Emancipation
	if player.civics.get("labor", "") == "emancipation":
		return 0  # No anger if we have Emancipation

	# Check if any known civ runs Emancipation
	var emancipation_count = 0
	for other_player in GameManager.players:
		if other_player.player_id == player.player_id:
			continue
		if not player.met_players.has(other_player.player_id):
			continue
		if other_player.civics.get("labor", "") == "emancipation":
			emancipation_count += 1

	# +2 unhappiness for each known civ with Emancipation, max +6
	return min(emancipation_count * 2, 6)

## Get health bonus from civics for a city
func get_civic_health(player, _city) -> int:
	var health = 0
	var effects = get_civic_effects(player)

	# Health per city (Environmentalism)
	health += effects.get("health_per_city", 0)

	return health

## Get worker speed modifier from civics
func get_worker_speed_modifier(player) -> float:
	var effects = get_civic_effects(player)
	return effects.get("worker_speed_modifier", 0) / 100.0

## Get military production modifier from civics
func get_military_production_modifier(player) -> float:
	var effects = get_civic_effects(player)
	return effects.get("military_production_modifier", 0) / 100.0

## Check if player can hurry production with gold
func can_hurry_with_gold(player) -> bool:
	return has_civic_effect(player, "can_hurry_with_gold")

## Check if player can hurry production with population
func can_hurry_with_population(player) -> bool:
	return has_civic_effect(player, "can_hurry_with_population")

## Get free experience for new units
func get_free_unit_experience(player) -> int:
	var effects = get_civic_effects(player)
	return effects.get("free_unit_experience", 0)

## Get free specialists per city
func get_free_specialists_per_city(player) -> int:
	var effects = get_civic_effects(player)
	return effects.get("free_specialist_per_city", 0)

## Check if foreign trade is disabled
func is_foreign_trade_disabled(player) -> bool:
	return has_civic_effect(player, "no_foreign_trade")

## Check if corporations are disabled
func are_corporations_disabled(player) -> bool:
	return has_civic_effect(player, "no_corporations")

## Check if player requires state religion for civic
func requires_state_religion(player) -> bool:
	return has_civic_effect(player, "requires_state_religion")

## Check if non-state religions can spread
func can_non_state_religions_spread(player) -> bool:
	return not has_civic_effect(player, "no_non_state_religion_spread")

## Helper: Count military units in a city
func _count_military_units_in_city(player, city) -> int:
	var count = 0
	for unit in player.units:
		if unit.grid_position == city.grid_position:
			var unit_data = DataManager.get_unit(unit.unit_id)
			if unit_data.get("strength", 0) > 0:
				count += 1
	return count

## Helper: Check if city is among largest N cities
func _is_among_largest_cities(player, city, n: int) -> bool:
	if player.cities.size() <= n:
		return true

	# Sort cities by population
	var cities_by_pop = player.cities.duplicate()
	cities_by_pop.sort_custom(func(a, b): return a.population > b.population)

	for i in range(min(n, cities_by_pop.size())):
		if cities_by_pop[i] == city:
			return true

	return false

func _on_turn_completed(_turn: int) -> void:
	# Process anarchy for all players
	for player in GameManager.players:
		_process_anarchy(player)
