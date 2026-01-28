extends Node
## Manages corporations, their spread, and city bonuses.

# Corporation headquarters: corporation_id -> city
var headquarters: Dictionary = {}

# Cities with corporations: city -> [corporation_ids]
var city_corporations: Dictionary = {}

func _ready() -> void:
	# Connect to relevant signals
	EventBus.city_destroyed.connect(_on_city_destroyed)
	EventBus.all_turns_completed.connect(_on_turn_completed)

## Found a new corporation in a city
func found_corporation(corporation_id: String, city, founder) -> bool:
	if corporation_id in headquarters:
		return false  # Corporation already exists

	var corp_data = DataManager.get_corporation(corporation_id)
	if corp_data.is_empty():
		return false

	# Check if player has State Property civic (no corporations allowed)
	if city.player_owner != null and CivicsSystem.has_civic_effect(city.player_owner, "no_corporations"):
		return false

	# Check tech requirement
	var required_tech = corp_data.get("tech_required", "")
	if required_tech != "" and required_tech not in city.player_owner.researched_techs:
		return false

	# Found corporation
	headquarters[corporation_id] = city

	# Add to city
	_add_corporation_to_city(city, corporation_id)

	# Emit signal
	EventBus.corporation_founded.emit(corporation_id, city, founder)

	return true

## Spread corporation to a city using an executive
func spread_corporation(corporation_id: String, city, executive_unit) -> bool:
	if corporation_id not in headquarters:
		return false  # Corporation doesn't exist

	if has_corporation(city, corporation_id):
		return false  # Already has this corporation

	# Check if player has State Property civic (no corporations allowed)
	if city.player_owner != null and CivicsSystem.has_civic_effect(city.player_owner, "no_corporations"):
		return false

	var corp_data = DataManager.get_corporation(corporation_id)

	# Check tech requirement
	var required_tech = corp_data.get("tech_required", "")
	if required_tech != "" and required_tech not in city.player_owner.researched_techs:
		return false

	# Check cost
	var spread_cost = corp_data.get("spread_cost", 100)
	if city.player_owner.gold < spread_cost:
		return false

	# Pay cost
	city.player_owner.gold -= spread_cost

	# Add corporation to city
	_add_corporation_to_city(city, corporation_id)

	# Consume executive unit
	if executive_unit:
		executive_unit.queue_free()

	# Emit signal
	EventBus.corporation_spread.emit(corporation_id, city)

	return true

## Add corporation to a city
func _add_corporation_to_city(city, corporation_id: String) -> void:
	if city not in city_corporations:
		city_corporations[city] = []

	if corporation_id not in city_corporations[city]:
		city_corporations[city].append(corporation_id)

## Remove corporation from a city
func remove_corporation(city, corporation_id: String) -> void:
	if city not in city_corporations:
		return

	city_corporations[city].erase(corporation_id)

	# If this was the headquarters, corporation is destroyed
	if headquarters.get(corporation_id) == city:
		_destroy_corporation(corporation_id)

## Check if city has a corporation
func has_corporation(city, corporation_id: String) -> bool:
	if city not in city_corporations:
		return false
	return corporation_id in city_corporations[city]

## Get all corporations in a city
func get_city_corporations(city) -> Array:
	return city_corporations.get(city, [])

## Get headquarters city for a corporation
func get_headquarters(corporation_id: String):
	return headquarters.get(corporation_id, null)

## Check if player owns corporation headquarters
func player_owns_corporation(player, corporation_id: String) -> bool:
	var hq = headquarters.get(corporation_id)
	return hq != null and hq.player_owner == player

## Calculate corporation bonuses for a city
func calculate_city_bonuses(city) -> Dictionary:
	var bonuses = {
		"food": 0,
		"production": 0,
		"commerce": 0,
		"gold": 0,
		"culture": 0,
		"happiness": 0,
		"health": 0
	}

	if city not in city_corporations:
		return bonuses

	var player = city.player_owner
	if player == null:
		return bonuses

	# Get player's available resources
	var available_resources = player.get_available_resources()
	var imported_resources = TradeSystem.get_imported_resources(player.player_id)
	var all_resources = available_resources.duplicate()
	for res in imported_resources:
		if res not in all_resources:
			all_resources.append(res)

	for corporation_id in city_corporations[city]:
		var corp_data = DataManager.get_corporation(corporation_id)
		if corp_data.is_empty():
			continue

		# Count matching resources
		var resources_consumed = corp_data.get("resources_consumed", [])
		var matching_resources = 0
		for res_id in resources_consumed:
			if res_id in all_resources:
				matching_resources += 1

		# Apply base bonus
		var base_bonus = corp_data.get("base_bonus", {})
		for key in base_bonus:
			if bonuses.has(key):
				bonuses[key] += base_bonus[key]

		# Apply per-resource bonus
		var per_resource = corp_data.get("bonus_per_resource", {})
		for key in per_resource:
			if bonuses.has(key):
				bonuses[key] += per_resource[key] * matching_resources

	return bonuses

## Calculate corporation maintenance for a city
func calculate_city_maintenance(city) -> int:
	var maintenance = 0

	if city not in city_corporations:
		return maintenance

	var player = city.player_owner
	if player == null:
		return maintenance

	# Get player's available resources
	var available_resources = player.get_available_resources()
	var imported_resources = TradeSystem.get_imported_resources(player.player_id)
	var all_resources = available_resources.duplicate()
	for res in imported_resources:
		if res not in all_resources:
			all_resources.append(res)

	for corporation_id in city_corporations[city]:
		var corp_data = DataManager.get_corporation(corporation_id)
		if corp_data.is_empty():
			continue

		# Base maintenance per city
		maintenance += corp_data.get("maintenance_per_city", 0)

		# Additional maintenance per consumed resource
		var resources_consumed = corp_data.get("resources_consumed", [])
		var maint_per_resource = corp_data.get("maintenance_per_resource", 0)
		for res_id in resources_consumed:
			if res_id in all_resources:
				maintenance += maint_per_resource

	return maintenance

## Calculate total corporation maintenance for a player
func calculate_player_maintenance(player) -> int:
	var total = 0
	for city in player.cities:
		total += calculate_city_maintenance(city)
	return total

## Get all cities with a specific corporation
func get_cities_with_corporation(corporation_id: String) -> Array:
	var cities = []
	for city in city_corporations:
		if corporation_id in city_corporations[city]:
			cities.append(city)
	return cities

## Get count of cities with corporation for a player
func get_corporation_city_count(player, corporation_id: String) -> int:
	var count = 0
	for city in player.cities:
		if has_corporation(city, corporation_id):
			count += 1
	return count

## Check if a Great Person can found a specific corporation
func can_found_corporation(gp_type: String, corporation_id: String, player = null) -> bool:
	if corporation_id in headquarters:
		return false  # Already founded

	# Check if player has State Property civic (no corporations allowed)
	if player != null and CivicsSystem.has_civic_effect(player, "no_corporations"):
		return false

	var corp_data = DataManager.get_corporation(corporation_id)
	if corp_data.is_empty():
		return false

	var founder_type = corp_data.get("founded_by", "")
	return founder_type == gp_type

## Get corporations that can be founded by a Great Person type
func get_foundable_corporations(gp_type: String, player) -> Array:
	var foundable = []

	# State Property civic prevents all corporations
	if player != null and CivicsSystem.has_civic_effect(player, "no_corporations"):
		return foundable

	for corporation_id in DataManager.corporations:
		if corporation_id.begins_with("_"):
			continue

		if corporation_id in headquarters:
			continue  # Already founded

		var corp_data = DataManager.get_corporation(corporation_id)
		if corp_data.get("founded_by", "") != gp_type:
			continue

		# Check tech requirement
		var required_tech = corp_data.get("tech_required", "")
		if required_tech != "" and required_tech not in player.researched_techs:
			continue

		foundable.append(corporation_id)

	return foundable

## Check if executive can spread corporation to city
func can_spread_to_city(corporation_id: String, city) -> bool:
	if corporation_id not in headquarters:
		return false

	if has_corporation(city, corporation_id):
		return false

	# Check if player has State Property civic (no corporations allowed)
	if city.player_owner != null and CivicsSystem.has_civic_effect(city.player_owner, "no_corporations"):
		return false

	var corp_data = DataManager.get_corporation(corporation_id)

	# Check tech requirement
	var required_tech = corp_data.get("tech_required", "")
	if required_tech != "" and required_tech not in city.player_owner.researched_techs:
		return false

	# Check cost
	var spread_cost = corp_data.get("spread_cost", 100)
	if city.player_owner.gold < spread_cost:
		return false

	return true

## Destroy a corporation (remove from all cities)
func _destroy_corporation(corporation_id: String) -> void:
	# Remove from all cities
	for city in city_corporations:
		city_corporations[city].erase(corporation_id)

	# Remove headquarters
	headquarters.erase(corporation_id)

	EventBus.corporation_destroyed.emit(corporation_id)

## Handle city destruction
func _on_city_destroyed(city) -> void:
	# Check if any corporations have HQ here
	for corporation_id in headquarters.keys():
		if headquarters[corporation_id] == city:
			# Move HQ to another city with this corporation, or destroy
			var other_cities = get_cities_with_corporation(corporation_id)
			other_cities.erase(city)

			if other_cities.is_empty():
				_destroy_corporation(corporation_id)
			else:
				headquarters[corporation_id] = other_cities[0]
				EventBus.corporation_hq_moved.emit(corporation_id, other_cities[0])

	# Remove city from tracking
	city_corporations.erase(city)

## Process corporations each turn (headquarters income)
func _on_turn_completed(_turn: int) -> void:
	# Headquarters generate income based on corporation spread
	for corporation_id in headquarters:
		var hq_city = headquarters[corporation_id]
		if hq_city == null or hq_city.player_owner == null:
			continue

		var cities = get_cities_with_corporation(corporation_id)
		var foreign_cities = 0
		for city in cities:
			if city.player_owner != hq_city.player_owner:
				foreign_cities += 1

		# HQ owner gets gold per foreign city with corporation
		if foreign_cities > 0:
			hq_city.player_owner.gold += foreign_cities * 2
			# Note: In full implementation, this would be culture/gold added to HQ city

## Serialization
func to_dict() -> Dictionary:
	var hq_data = {}
	for corp_id in headquarters:
		var city = headquarters[corp_id]
		hq_data[corp_id] = {
			"player_id": city.player_owner.player_id,
			"city_name": city.city_name
		}

	var city_data = {}
	for city in city_corporations:
		var key = "%d_%s" % [city.player_owner.player_id, city.city_name]
		city_data[key] = city_corporations[city]

	return {
		"headquarters": hq_data,
		"city_corporations": city_data
	}

func from_dict(data: Dictionary) -> void:
	# Note: This requires cities to be loaded first
	# Full implementation would resolve city references after load
	pass
