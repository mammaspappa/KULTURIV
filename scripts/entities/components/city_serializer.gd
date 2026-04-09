class_name CitySerializer
extends RefCounted
## City save/load marshalling, extracted from city.gd as part of Phase 5.
##
## The serialized shape is intentionally flat to keep the v2 save schema stable.

static func to_dict(city) -> Dictionary:
	return {
		"city_name": city.city_name,
		"owner_id": city.player_owner.player_id if city.player_owner else -1,
		"grid_position": {"x": city.grid_position.x, "y": city.grid_position.y},
		"population": city.population,
		"food_stockpile": city.food_stockpile,
		"current_production": city.current_production,
		"production_progress": city.production_progress,
		"production_queue": city.production_queue,
		"buildings": city.buildings,
		"territory": city.territory.map(func(v): return {"x": v.x, "y": v.y}),
		"worked_tiles": city.worked_tiles.map(func(v): return {"x": v.x, "y": v.y}),
		"culture": city.culture,
		"culture_level": city.culture_level,
		"religions": city.religions,
		"holy_city_of": city.holy_city_of,
		"specialists": city.specialists,
		"city_focus": city.city_focus,
		"locked_tiles": city.locked_tiles.map(func(v): return {"x": v.x, "y": v.y}),
		"original_owner_id": city.original_owner_id,
		"founder_civ_id": city.founder_civ_id,
		"resistance_turns": city.resistance_turns,
	}

static func from_dict(city, data: Dictionary) -> void:
	city.city_name = data.get("city_name", "City")
	city.grid_position = Vector2i(data.grid_position.x, data.grid_position.y)
	city.population = data.get("population", 1)
	city.food_stockpile = data.get("food_stockpile", 0.0)
	city.current_production = data.get("current_production", "")
	city.production_progress = data.get("production_progress", 0)
	city.production_queue.assign(data.get("production_queue", []))
	city.buildings.assign(data.get("buildings", []))

	city.territory.clear()
	for t in data.get("territory", []):
		city.territory.append(Vector2i(t.x, t.y))

	city.worked_tiles.clear()
	for t in data.get("worked_tiles", []):
		city.worked_tiles.append(Vector2i(t.x, t.y))

	city.culture = data.get("culture", 0)
	city.culture_level = data.get("culture_level", 1)
	city.religions.assign(data.get("religions", []))
	city.holy_city_of = data.get("holy_city_of", "")
	city.specialists = data.get("specialists", {})
	city.city_focus = data.get("city_focus", "")
	city.original_owner_id = data.get("original_owner_id", -1)
	city.founder_civ_id = data.get("founder_civ_id", "")
	city.resistance_turns = data.get("resistance_turns", 0)
	city.locked_tiles.clear()
	for t in data.get("locked_tiles", []):
		city.locked_tiles.append(Vector2i(t.x, t.y))

	city.position = GridUtils.grid_to_pixel(city.grid_position)
	city.calculate_yields()
	city.update_visual()
