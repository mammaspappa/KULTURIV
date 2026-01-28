extends Node
## Handles religion founding, spread, and effects.

# Religion founding techs
const FOUNDING_TECHS = {
	"meditation": "buddhism",
	"polytheism": "hinduism",
	"monotheism": "judaism",
	"theology": "christianity",
	"code_of_laws": "confucianism",
	"philosophy": "taoism",
	"divine_right": "islam"
}

# Spread chance per turn (base)
const BASE_SPREAD_CHANCE = 0.05

# Religion effects
const RELIGION_HAPPINESS_HOLY_CITY = 1
const RELIGION_HAPPINESS_WITH_BUILDING = 1

func _ready() -> void:
	# Connect to research events
	EventBus.research_completed.connect(_on_research_completed)

	# Connect to turn events for natural spread
	EventBus.all_turns_completed.connect(_on_turn_completed)

## Check if a religion can be founded
func can_found_religion(religion_id: String) -> bool:
	# Check if religion already exists
	for player in GameManager.players:
		if player.founded_religion == religion_id:
			return false

	# Check if any city is already holy city for this religion
	for city in GameManager.get_all_cities():
		if city.holy_city_of == religion_id:
			return false

	return true

## Found a religion in a city
func found_religion(city, religion_id: String, founder) -> void:
	if city == null or founder == null:
		return

	if not can_found_religion(religion_id):
		return

	# Set the city as holy city
	city.holy_city_of = religion_id

	# Add religion to city
	if religion_id not in city.religions:
		city.religions.append(religion_id)

	# Mark player as founder
	founder.founded_religion = religion_id

	# Adopt as state religion if none
	if founder.state_religion == "":
		adopt_state_religion(founder, religion_id)

	EventBus.religion_founded.emit(founder, religion_id, city)

## Spread religion to a city
func spread_religion(city, religion_id: String) -> void:
	if city == null:
		return

	if religion_id in city.religions:
		return

	city.religions.append(religion_id)
	EventBus.religion_spread.emit(religion_id, city)

## Remove religion from a city
func remove_religion(city, religion_id: String) -> void:
	if city == null:
		return

	city.religions.erase(religion_id)

## Adopt a state religion
func adopt_state_religion(player, religion_id: String) -> void:
	if player == null:
		return

	player.state_religion = religion_id
	EventBus.state_religion_adopted.emit(player, religion_id)

## Process natural religion spread each turn
func process_spread() -> void:
	for city in GameManager.get_all_cities():
		_try_spread_to_city(city)

func _try_spread_to_city(city) -> void:
	if city == null:
		return

	# Get neighboring cities that have religions this city doesn't
	var neighbors = _get_nearby_cities(city, 5)

	for neighbor in neighbors:
		for religion_id in neighbor.religions:
			if religion_id not in city.religions:
				var chance = _calculate_spread_chance(city, neighbor, religion_id)
				if randf() < chance:
					spread_religion(city, religion_id)

func _get_nearby_cities(city, max_distance: int) -> Array:
	var nearby = []

	for other_city in GameManager.get_all_cities():
		if other_city == city:
			continue

		var distance = GridUtils.chebyshev_distance(city.grid_position, other_city.grid_position)
		if distance <= max_distance:
			nearby.append(other_city)

	return nearby

func _calculate_spread_chance(target_city, source_city, religion_id: String) -> float:
	var chance = BASE_SPREAD_CHANCE

	# Distance modifier (closer = higher chance)
	var distance = GridUtils.chebyshev_distance(target_city.grid_position, source_city.grid_position)
	chance *= 1.0 / max(1, distance)

	# Holy city bonus
	if source_city.holy_city_of == religion_id:
		chance *= 2.0

	# State religion bonus (if source owner has this as state religion)
	if source_city.player_owner and source_city.player_owner.state_religion == religion_id:
		chance *= 1.5

	# Monastery/temple bonus
	if source_city.has_building("monastery") or source_city.has_building("temple"):
		chance *= 1.5

	# Open borders bonus
	if target_city.player_owner and source_city.player_owner:
		if target_city.player_owner.player_id in source_city.player_owner.open_borders_with:
			chance *= 1.5

	return chance

## Get religious bonus for a city
func get_religious_happiness(city) -> int:
	if city == null:
		return 0

	var happiness = 0

	# Holy city bonus
	if city.holy_city_of != "":
		happiness += RELIGION_HAPPINESS_HOLY_CITY

	# State religion with religious buildings
	if city.player_owner and city.player_owner.state_religion != "":
		var state_rel = city.player_owner.state_religion
		if state_rel in city.religions:
			# Check for religious buildings
			for building_id in city.buildings:
				var building = DataManager.get_building(building_id)
				if building.get("religious", false):
					happiness += RELIGION_HAPPINESS_WITH_BUILDING

	return happiness

## Get gold from religious buildings (holy city shrine bonus)
func get_religious_gold(city) -> int:
	if city == null or city.holy_city_of == "":
		return 0

	# Get the shrine building for this religion
	var religion_data = DataManager.get_religion(city.holy_city_of)
	var shrine_building = religion_data.get("shrine", "")
	if shrine_building == "":
		return 0

	# Check if city has the shrine
	if not city.has_building(shrine_building):
		return 0

	# Count cities with this religion
	var count = 0
	for other_city in GameManager.get_all_cities():
		if city.holy_city_of in other_city.religions:
			count += 1

	# Shrine gives 1 gold per city with religion
	return count

func _on_research_completed(player, tech: String) -> void:
	# Check if this tech founds a religion
	if tech in FOUNDING_TECHS:
		var religion_id = FOUNDING_TECHS[tech]

		if can_found_religion(religion_id):
			# Found religion in capital or first city
			var city = null
			if not player.cities.is_empty():
				# Prefer capital (first city usually)
				city = player.cities[0]

			if city:
				found_religion(city, religion_id, player)

func _on_turn_completed(_turn: int) -> void:
	process_spread()
