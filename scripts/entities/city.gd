class_name City
extends Node2D
## Represents a city on the map.

const UnitClass = preload("res://scripts/entities/unit.gd")

# Identity
var city_name: String = "City"
var player_owner = null  # Player (untyped to avoid circular dependency)

# Position
var grid_position: Vector2i = Vector2i.ZERO

# Population
var population: int = 1
var food_stockpile: float = 0.0

# Production
var current_production: String = ""
var production_progress: int = 0
var production_queue: Array[String] = []

# Buildings
var buildings: Array[String] = []

# Territory
var territory: Array[Vector2i] = []  # Tiles owned by this city
var worked_tiles: Array[Vector2i] = []  # Tiles being worked

# Yields (calculated)
var food_yield: int = 0
var production_yield: int = 0
var commerce_yield: int = 0
var science_yield: int = 0
var culture_yield: int = 0
var food_surplus: int = 0

# Culture
var culture: int = 0
var culture_level: int = 1

# Religion
var religions: Array[String] = []
var holy_city_of: String = ""

# Health and Happiness
var happiness: int = 0
var unhappiness: int = 0
var health: int = 0
var unhealthiness: int = 0

# Available resources
var available_resources: Array[String] = []

# Defense
var defense_strength: float = 0.0
var defense_damage: float = 0.0

# Visual
const TILE_SIZE: int = 64
var is_selected: bool = false

# Culture thresholds for expansion
const CULTURE_THRESHOLDS = [0, 10, 100, 500, 5000, 50000]

signal city_selected()
signal production_changed(item: String)

func _init(pos: Vector2i = Vector2i.ZERO, name: String = "City") -> void:
	grid_position = pos
	city_name = name
	position = GridUtils.grid_to_pixel(grid_position)
	_initialize_territory()

func _ready() -> void:
	calculate_yields()
	update_visual()

func _draw() -> void:
	# City background circle
	var bg_color = player_owner.color if player_owner else Color.GRAY
	draw_circle(Vector2.ZERO, 28, bg_color)

	# Border
	if is_selected:
		draw_arc(Vector2.ZERO, 30, 0, TAU, 32, Color.WHITE, 3.0)
	else:
		draw_arc(Vector2.ZERO, 28, 0, TAU, 32, Color.BLACK, 2.0)

	# Population number
	var font = ThemeDB.fallback_font
	var font_size = 20
	var pop_text = str(population)
	var text_size = font.get_string_size(pop_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(-text_size.x / 2, text_size.y / 4)
	draw_string(font, text_pos, pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# City name below
	var name_size = 12
	var name_text_size = font.get_string_size(city_name, HORIZONTAL_ALIGNMENT_CENTER, -1, name_size)
	var name_pos = Vector2(-name_text_size.x / 2, 40)
	draw_string(font, name_pos, city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color.WHITE)

	# Production icon if producing
	if current_production != "":
		var prod_symbol = "⚙"
		draw_string(font, Vector2(-30, -10), prod_symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.YELLOW)

	# Religion icons
	var religion_x = 20
	for rel in religions:
		var rel_data = DataManager.get_religion(rel)
		var symbol = rel_data.get("symbol", "?")
		draw_string(font, Vector2(religion_x, -20), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		religion_x += 12

func update_visual() -> void:
	queue_redraw()

func _initialize_territory() -> void:
	# Start with just the city tile and immediate neighbors
	territory = [grid_position]
	worked_tiles = [grid_position]

	# Add adjacent tiles
	var neighbors = GridUtils.get_neighbors(grid_position)
	for neighbor in neighbors:
		if _can_claim_tile(neighbor):
			territory.append(neighbor)

func _can_claim_tile(pos: Vector2i) -> bool:
	if GameManager.hex_grid == null:
		return true  # Allow during initialization

	var tile = GameManager.hex_grid.get_tile(pos)
	if tile == null:
		return false
	if tile.tile_owner != null and tile.tile_owner != player_owner:
		return false
	return true

# Yield calculation
func calculate_yields() -> void:
	food_yield = 0
	production_yield = 0
	commerce_yield = 0

	# Base yield from city center
	food_yield += 2
	production_yield += 1
	commerce_yield += 1

	# Yields from worked tiles
	for tile_pos in worked_tiles:
		var tile = _get_tile(tile_pos)
		if tile != null:
			var yields = tile.get_yields()
			food_yield += yields.get("food", 0)
			production_yield += yields.get("production", 0)
			commerce_yield += yields.get("commerce", 0)

	# Building modifiers
	var food_percent = 0.0
	var prod_percent = 0.0
	var commerce_percent = 0.0

	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		food_percent += effects.get("food_percent", 0.0)
		prod_percent += effects.get("production_percent", 0.0)
		commerce_percent += effects.get("gold_percent", 0.0)

	food_yield = int(food_yield * (1.0 + food_percent))
	production_yield = int(production_yield * (1.0 + prod_percent))
	commerce_yield = int(commerce_yield * (1.0 + commerce_percent))

	# Calculate science and culture
	_calculate_science()
	_calculate_culture()

	# Calculate food surplus
	var food_consumed = population * 2
	food_surplus = food_yield - food_consumed

	# Calculate happiness and health
	_calculate_happiness()
	_calculate_health()

func _calculate_science() -> void:
	# Base science from commerce
	var science_rate = 0.5  # 50% of commerce goes to science by default
	science_yield = int(commerce_yield * science_rate)

	# Building bonuses
	var science_percent = 0.0
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		science_percent += effects.get("science_percent", 0.0)

	science_yield = int(science_yield * (1.0 + science_percent))

func _calculate_culture() -> void:
	culture_yield = 0

	# Buildings that produce culture
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		culture_yield += effects.get("culture", 0)

	# Religion bonuses
	if player_owner and player_owner.state_religion in religions:
		for building_id in buildings:
			var effects = DataManager.get_building_effects(building_id)
			culture_yield += effects.get("culture_from_religion", 0)

func _calculate_happiness() -> void:
	happiness = 0
	unhappiness = 0

	# Base unhappiness from population
	unhappiness = population

	# Buildings
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		happiness += effects.get("happiness", 0)

	# Resources
	_update_available_resources()
	for resource_id in available_resources:
		var resource = DataManager.get_resource(resource_id)
		if resource.get("type", "") == "luxury":
			happiness += resource.get("happiness", 1)

func _calculate_health() -> void:
	health = 0
	unhealthiness = 0

	# Base health
	health = 2

	# Population causes unhealthiness
	unhealthiness = population / 2

	# Buildings
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		health += effects.get("health", 0)
		unhealthiness += effects.get("unhealthiness", 0)

func _update_available_resources() -> void:
	available_resources.clear()

	for tile_pos in territory:
		var tile = _get_tile(tile_pos)
		if tile != null and tile.resource_id != "":
			# Check if resource is improved
			var resource = DataManager.get_resource(tile.resource_id)
			var required_improvement = resource.get("improvement", "")
			if tile.improvement_id == required_improvement:
				if tile.resource_id not in available_resources:
					available_resources.append(tile.resource_id)

func _get_tile(pos: Vector2i):
	if GameManager.hex_grid == null:
		return null
	return GameManager.hex_grid.get_tile(pos)

# Population
func food_needed_for_growth() -> int:
	return 20 + population * 4

func grow() -> void:
	population += 1
	food_stockpile = 0

	# Keep some food based on buildings
	var food_stored_percent = 0.0
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		food_stored_percent += effects.get("food_stored_on_growth", 0.0)

	food_stockpile = food_needed_for_growth() * food_stored_percent

	# Auto-assign new citizen
	_auto_assign_citizen()

	EventBus.city_grew.emit(self, population)
	calculate_yields()
	update_visual()

func starve() -> void:
	if population > 1:
		population -= 1
		food_stockpile = 0
		EventBus.city_starving.emit(self)
		calculate_yields()
		update_visual()

func _auto_assign_citizen() -> void:
	# Find best unworked tile in territory
	var best_tile: Vector2i = Vector2i(-1, -1)
	var best_value = -1

	for tile_pos in territory:
		if tile_pos in worked_tiles:
			continue

		var tile = _get_tile(tile_pos)
		if tile == null:
			continue

		var yields = tile.get_yields()
		var value = yields.get("food", 0) * 3 + yields.get("production", 0) * 2 + yields.get("commerce", 0)

		if value > best_value:
			best_value = value
			best_tile = tile_pos

	if best_tile.x >= 0:
		worked_tiles.append(best_tile)

# Production
func set_production(item: String) -> void:
	current_production = item
	production_progress = 0
	production_changed.emit(item)
	update_visual()

func get_production_cost() -> int:
	# Check if it's a unit or building
	var unit_data = DataManager.get_unit(current_production)
	if not unit_data.is_empty():
		return int(DataManager.get_unit_cost(current_production) * GameManager.get_speed_multiplier())

	var building_data = DataManager.get_building(current_production)
	if not building_data.is_empty():
		return int(DataManager.get_building_cost(current_production) * GameManager.get_speed_multiplier())

	return 0

func complete_production() -> void:
	if current_production == "":
		return

	# Check if unit or building
	var unit_data = DataManager.get_unit(current_production)
	if not unit_data.is_empty():
		_produce_unit(current_production)
	else:
		_produce_building(current_production)

	EventBus.city_production_completed.emit(self, current_production)

	# Move to next item in queue or clear
	production_progress = 0
	if not production_queue.is_empty():
		current_production = production_queue.pop_front()
	else:
		current_production = ""

	update_visual()

func _produce_unit(unit_type: String) -> void:
	var unit = UnitClass.new(unit_type, grid_position)
	player_owner.add_unit(unit)

	# Add to scene
	if GameManager.game_world:
		GameManager.game_world.add_child(unit)

	# Apply free experience from buildings
	var free_xp = 0
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		free_xp += effects.get("free_experience", 0)

	unit.experience = free_xp

	EventBus.unit_created.emit(unit)

func _produce_building(building_type: String) -> void:
	if building_type not in buildings:
		buildings.append(building_type)
		EventBus.city_building_constructed.emit(self, building_type)
		calculate_yields()

func has_building(building_id: String) -> bool:
	return building_id in buildings

func can_build_unit(unit_id: String) -> bool:
	if player_owner == null:
		return false
	return player_owner.can_build_unit(unit_id)

func can_build_building(building_id: String) -> bool:
	if player_owner == null:
		return false

	# Already have it?
	if building_id in buildings:
		return false

	# Check requirements
	var building = DataManager.get_building(building_id)

	# Required building
	var requires = building.get("requires_building", "")
	if requires != "" and requires not in buildings:
		return false

	# Exclusive buildings
	var exclusive_with = building.get("exclusive_with", [])
	for exclusive in exclusive_with:
		if exclusive in buildings:
			return false

	# Location requirements
	if building.get("requires_coast", false):
		if not _is_coastal():
			return false

	if building.get("requires_river", false):
		# Simplified - would need river data
		pass

	return player_owner.can_build_building(building_id)

func _is_coastal() -> bool:
	var neighbors = GridUtils.get_neighbors(grid_position)
	for neighbor in neighbors:
		var tile = _get_tile(neighbor)
		if tile != null and tile.is_water():
			return true
	return false

func has_resource(resource_id: String) -> bool:
	return resource_id in available_resources

# Culture and borders
func check_border_expansion() -> void:
	# Check if we've reached next culture level
	while culture_level < CULTURE_THRESHOLDS.size() and culture >= CULTURE_THRESHOLDS[culture_level]:
		culture_level += 1
		_expand_borders()
		EventBus.city_borders_expanded.emit(self)

func _expand_borders() -> void:
	# Add tiles at the next ring
	var range_val = culture_level + 1
	var new_tiles = GridUtils.get_tiles_at_range(grid_position, range_val)

	for tile_pos in new_tiles:
		if tile_pos not in territory and _can_claim_tile(tile_pos):
			territory.append(tile_pos)
			var tile = _get_tile(tile_pos)
			if tile != null:
				tile.tile_owner = player_owner
				tile.city_owner = self
				tile.update_visuals()

# Defense
func get_defense_strength() -> float:
	var base = 0.0

	# Garrison units
	var garrison = GameManager.get_units_at(grid_position)
	for unit in garrison:
		if unit.player_owner == player_owner:
			var unit_strength = unit.get_combat_strength(false, _get_tile(grid_position))
			base = max(base, unit_strength)

	# Building defense bonuses
	var defense_mult = 1.0
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		defense_mult += effects.get("defense", 0.0)

	return base * defense_mult

# Selection
func select() -> void:
	is_selected = true
	update_visual()
	city_selected.emit()
	EventBus.city_selected.emit(self)

func deselect() -> void:
	is_selected = false
	update_visual()
	EventBus.city_deselected.emit(self)

# Serialization
func to_dict() -> Dictionary:
	return {
		"city_name": city_name,
		"owner_id": player_owner.player_id if player_owner else -1,
		"grid_position": {"x": grid_position.x, "y": grid_position.y},
		"population": population,
		"food_stockpile": food_stockpile,
		"current_production": current_production,
		"production_progress": production_progress,
		"production_queue": production_queue,
		"buildings": buildings,
		"territory": territory.map(func(v): return {"x": v.x, "y": v.y}),
		"worked_tiles": worked_tiles.map(func(v): return {"x": v.x, "y": v.y}),
		"culture": culture,
		"culture_level": culture_level,
		"religions": religions,
		"holy_city_of": holy_city_of,
	}

func from_dict(data: Dictionary) -> void:
	city_name = data.get("city_name", "City")
	grid_position = Vector2i(data.grid_position.x, data.grid_position.y)
	population = data.get("population", 1)
	food_stockpile = data.get("food_stockpile", 0.0)
	current_production = data.get("current_production", "")
	production_progress = data.get("production_progress", 0)
	production_queue.assign(data.get("production_queue", []))
	buildings.assign(data.get("buildings", []))

	territory.clear()
	for t in data.get("territory", []):
		territory.append(Vector2i(t.x, t.y))

	worked_tiles.clear()
	for t in data.get("worked_tiles", []):
		worked_tiles.append(Vector2i(t.x, t.y))

	culture = data.get("culture", 0)
	culture_level = data.get("culture_level", 1)
	religions.assign(data.get("religions", []))
	holy_city_of = data.get("holy_city_of", "")

	position = GridUtils.grid_to_pixel(grid_position)
	calculate_yields()
	update_visual()
