extends Node
## Handles special wonder effects that trigger on construction or affect gameplay globally.
## Passive yield effects (culture, gold, science %) are already handled by City.calculate_yields().

func _ready() -> void:
	EventBus.city_building_constructed.connect(_on_building_constructed)

func _on_building_constructed(city, building_id: String) -> void:
	var building = DataManager.get_building(building_id)
	if building.is_empty():
		return

	var wonder_type = building.get("wonder_type", "")
	if wonder_type == "":
		return

	var effects = building.get("effects", {})
	var player = city.player_owner
	if player == null:
		return

	# Emit wonder_built signal
	EventBus.wonder_built.emit(building_id, player.player_id, wonder_type)

	# One-time effects on construction
	_apply_free_tech(player, effects)
	_apply_golden_age(player, effects)
	_apply_population_all_cities(player, effects)
	_apply_free_building_all_cities(player, effects)
	_apply_free_experience_all_units(player, effects)

## Oracle, Oxford University: grant a free tech
func _apply_free_tech(player, effects: Dictionary) -> void:
	if not effects.get("free_tech", false):
		return

	# For human player: auto-research cheapest available tech
	# (ideally we'd open tech tree for selection, but this is simpler and works for both)
	var best_tech = ""
	var best_cost = INF
	for tech_id in DataManager.techs:
		if player.can_research(tech_id):
			var cost = DataManager.get_tech_cost(tech_id)
			if cost < best_cost:
				best_cost = cost
				best_tech = tech_id

	if best_tech != "":
		player.researched_techs.append(best_tech)
		EventBus.research_completed.emit(player, best_tech)
		EventBus.notification_added.emit("Free technology discovered: %s" % DataManager.get_tech(best_tech).get("name", best_tech))

## The Internet: grant techs known by at least 2 civs
func apply_free_tech_known_by_two(player) -> void:
	var granted = []
	for tech_id in DataManager.techs:
		if tech_id in player.researched_techs:
			continue
		var count = 0
		for other in GameManager.players:
			if other != player and tech_id in other.researched_techs:
				count += 1
		if count >= 2:
			granted.append(tech_id)

	for tech_id in granted:
		player.researched_techs.append(tech_id)
		EventBus.research_completed.emit(player, tech_id)

	if not granted.is_empty():
		EventBus.notification_added.emit("The Internet grants %d technologies!" % granted.size())

## Taj Mahal: start a golden age
func _apply_golden_age(player, effects: Dictionary) -> void:
	if not effects.get("golden_age", false):
		return
	player.start_golden_age()
	EventBus.notification_added.emit("A Golden Age has begun!")

## Hanging Gardens: +1 population in all cities
func _apply_population_all_cities(player, effects: Dictionary) -> void:
	var pop_bonus = effects.get("population_all_cities", 0)
	if pop_bonus <= 0:
		return

	for city in player.cities:
		for i in pop_bonus:
			city.grow()
	EventBus.notification_added.emit("+%d population in all cities!" % pop_bonus)

## Stonehenge (free_monument_all_cities), Eiffel Tower (free_broadcast_tower_all_cities)
func _apply_free_building_all_cities(player, effects: Dictionary) -> void:
	if effects.get("free_monument_all_cities", false):
		_grant_building_all_cities(player, "monument")
	if effects.get("free_broadcast_tower_all_cities", false):
		_grant_building_all_cities(player, "broadcast_tower")

func _grant_building_all_cities(player, building_id: String) -> void:
	var count = 0
	for city in player.cities:
		if building_id not in city.buildings:
			city.buildings.append(building_id)
			city.calculate_yields()
			count += 1
	if count > 0:
		var building = DataManager.get_building(building_id)
		var name = building.get("name", building_id.replace("_", " ").capitalize())
		EventBus.notification_added.emit("Free %s in %d cities!" % [name, count])

## Pentagon: +2 free XP to all existing units
func _apply_free_experience_all_units(player, effects: Dictionary) -> void:
	var xp = effects.get("free_experience_all_units", 0)
	if xp <= 0:
		return

	for unit in player.units:
		unit.experience += xp
	EventBus.notification_added.emit("+%d XP for all military units!" % xp)

## Check if any player has a wonder with a specific effect (for per-turn/passive checks)
func player_has_wonder_effect(player, effect_key: String):
	for city in player.cities:
		for building_id in city.buildings:
			var building = DataManager.get_building(building_id)
			if building.get("wonder_type", "") != "":
				var effects = building.get("effects", {})
				if effects.has(effect_key):
					return effects[effect_key]
	return null

## Get free specialist slots from wonders (Statue of Liberty: +1 free specialist in all cities)
func get_wonder_free_specialist_slots(player) -> int:
	var slots = 0
	for city in player.cities:
		for building_id in city.buildings:
			var effects = DataManager.get_building_effects(building_id)
			slots += effects.get("free_specialist_all_cities", 0)
	# Return the max from any single wonder (not sum across cities)
	var max_slots = 0
	for building_id in _get_player_wonders(player):
		var effects = DataManager.get_building_effects(building_id)
		max_slots += effects.get("free_specialist_all_cities", 0)
	return max_slots

## Get all wonders owned by a player
func _get_player_wonders(player) -> Array:
	var wonders = []
	for city in player.cities:
		for building_id in city.buildings:
			var building = DataManager.get_building(building_id)
			if building.get("wonder_type", "") != "":
				wonders.append(building_id)
	return wonders

## Get extra naval movement from wonders (Great Lighthouse)
func get_wonder_naval_bonus(player) -> int:
	var bonus = 0
	for building_id in _get_player_wonders(player):
		var effects = DataManager.get_building_effects(building_id)
		bonus += effects.get("naval_movement", 0)
	return bonus

## Get defense bonus from wonders for all cities (Chichen Itza)
func get_wonder_defense_bonus(player) -> float:
	var bonus = 0.0
	for building_id in _get_player_wonders(player):
		var effects = DataManager.get_building_effects(building_id)
		bonus += effects.get("defense_all_cities", 0.0)
	return bonus

## Get happiness bonus from wonders for all cities (Notre Dame)
func get_wonder_happiness_bonus(player) -> int:
	var bonus = 0
	for building_id in _get_player_wonders(player):
		var effects = DataManager.get_building_effects(building_id)
		bonus += effects.get("happiness_all_cities", 0)
	return bonus

## Check if player has no_unhappiness wonder in a city (Globe Theatre)
func city_has_no_unhappiness(city) -> bool:
	for building_id in city.buildings:
		var effects = DataManager.get_building_effects(building_id)
		if effects.get("no_unhappiness", false):
			return true
	return false

## Get war weariness reduction from wonders (Mt. Rushmore)
func get_war_weariness_reduction(player) -> float:
	var reduction = 0.0
	for building_id in _get_player_wonders(player):
		var effects = DataManager.get_building_effects(building_id)
		reduction += effects.get("war_weariness_reduction", 0.0)
	return reduction
