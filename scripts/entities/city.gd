class_name City
extends Node2D
## Represents a city on the map.

const UnitClass = preload("res://scripts/entities/unit.gd")
const GameTileClass = preload("res://scripts/map/game_tile.gd")

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

# Specialists
var specialists: Dictionary = {}  # specialist_id -> count
var free_specialists: int = 0  # Free specialists from civics

# Yields (calculated)
var food_yield: int = 0
var production_yield: int = 0
var commerce_yield: int = 0
var science_yield: int = 0
var culture_yield: int = 0
var gold_yield: int = 0  # Gold from commerce (based on science rate)
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
	# Check if this city should be visible to the human player
	var human_player = GameManager.human_player
	if human_player != null and player_owner != human_player:
		# Enemy city - only show if on a tile explored by human player
		var tile = GameManager.hex_grid.get_tile(grid_position) if GameManager.hex_grid else null
		if tile != null:
			var vis_state = tile.get_visibility_for_player(human_player.player_id)
			# Cities remain visible once explored (they don't disappear in fog)
			visible = (vis_state != GameTileClass.VisibilityState.UNEXPLORED)
		else:
			visible = false
	else:
		# Own city or no human player - always visible
		visible = true

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

	# Specialist yields
	var spec_yields = get_specialist_yields()
	food_yield += spec_yields.get("food", 0)
	production_yield += spec_yields.get("production", 0)
	commerce_yield += spec_yields.get("commerce", 0)

	# Building flat bonuses and percentage modifiers
	var food_percent = 0.0
	var prod_percent = 0.0
	var commerce_percent = 0.0

	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		# Flat bonuses from buildings (e.g., Palace gives +8 commerce)
		food_yield += effects.get("food", 0)
		production_yield += effects.get("production", 0)
		commerce_yield += effects.get("commerce", 0)
		# Percentage modifiers
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
	# Get science rate from player (percentage of commerce going to science)
	var rate = 1.0  # Default 100%
	if player_owner != null:
		rate = player_owner.science_rate

	# Base science from commerce (based on player's science slider)
	science_yield = int(commerce_yield * rate)

	# Specialist science bonus
	var spec_commerces = get_specialist_commerces()
	science_yield += spec_commerces.get("research", 0)

	# Building bonuses
	var science_percent = 0.0
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		science_percent += effects.get("science_percent", 0.0)

	science_yield = int(science_yield * (1.0 + science_percent))

	# Gold from remaining commerce (commerce not going to science)
	# This follows Civ4 mechanics where commerce is split between science and gold
	var gold_from_commerce = int(commerce_yield * (1.0 - rate))
	# Add gold from buildings
	var gold_bonus = 0
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		gold_bonus += effects.get("gold", 0)
	# Store in a city property for reference (gold_yield)
	gold_yield = gold_from_commerce + gold_bonus

func _calculate_culture() -> void:
	culture_yield = 0

	# Buildings that produce culture
	var culture_percent = 0.0
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		culture_yield += effects.get("culture", 0)
		culture_percent += effects.get("culture_percent", 0.0)

	# Specialist culture bonus
	var spec_commerces = get_specialist_commerces()
	culture_yield += spec_commerces.get("culture", 0)

	# Religion bonuses
	if player_owner and player_owner.state_religion in religions:
		for building_id in buildings:
			var effects = DataManager.get_building_effects(building_id)
			culture_yield += effects.get("culture_from_religion", 0)

	# Apply percentage modifier (e.g., Broadcast Tower gives +50% culture)
	culture_yield = int(culture_yield * (1.0 + culture_percent))

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

# Specialist management
func get_specialist_count(specialist_id: String) -> int:
	return specialists.get(specialist_id, 0)

func get_total_specialists() -> int:
	var total = 0
	for spec_id in specialists:
		total += specialists[spec_id]
	return total

func get_available_population() -> int:
	# Population minus worked tiles minus specialists
	return population - worked_tiles.size() - get_total_specialists() + 1  # +1 for city center

func get_specialist_slots(specialist_id: String) -> int:
	var slots = 0

	# Slots from buildings
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		var building_slots = effects.get("specialist_slots", {})
		slots += building_slots.get(specialist_id, 0)

	# Unlimited slots from civics (Caste System)
	if player_owner:
		var civic_effects = CivicsSystem.get_civic_effects(player_owner)
		if civic_effects.get("unlimited_" + specialist_id + "_slots", false):
			return 99

	# Free specialists from civics (Mercantilism, Free Religion)
	if player_owner:
		var free_spec = CivicsSystem.get_free_specialists_per_city(player_owner)
		if free_spec > 0:
			# Free specialists can be any type
			slots += free_spec

	return slots

func can_add_specialist(specialist_id: String) -> bool:
	if get_available_population() <= 0:
		return false

	var current = get_specialist_count(specialist_id)
	var max_slots = get_specialist_slots(specialist_id)

	return current < max_slots

func add_specialist(specialist_id: String) -> bool:
	if not can_add_specialist(specialist_id):
		return false

	specialists[specialist_id] = specialists.get(specialist_id, 0) + 1
	calculate_yields()
	return true

func remove_specialist(specialist_id: String) -> bool:
	if specialists.get(specialist_id, 0) <= 0:
		return false

	specialists[specialist_id] -= 1
	if specialists[specialist_id] <= 0:
		specialists.erase(specialist_id)

	calculate_yields()
	return true

func get_specialist_yields() -> Dictionary:
	var total_yields = {"food": 0, "production": 0, "commerce": 0}

	for specialist_id in specialists:
		var count = specialists[specialist_id]
		var spec_yields = DataManager.get_specialist_yields(specialist_id)

		for yield_key in spec_yields:
			total_yields[yield_key] = total_yields.get(yield_key, 0) + spec_yields[yield_key] * count

	return total_yields

func get_specialist_commerces() -> Dictionary:
	var total_commerces = {"gold": 0, "research": 0, "culture": 0, "espionage": 0}

	for specialist_id in specialists:
		var count = specialists[specialist_id]
		var spec_commerces = DataManager.get_specialist_commerces(specialist_id)

		for commerce_key in spec_commerces:
			total_commerces[commerce_key] = total_commerces.get(commerce_key, 0) + spec_commerces[commerce_key] * count

	# Apply civic bonuses (Representation: +3 research per specialist)
	if player_owner:
		var civic_effects = CivicsSystem.get_civic_effects(player_owner)
		var specialist_research_bonus = civic_effects.get("specialist_commerce_bonus", 0)
		if specialist_research_bonus > 0:
			total_commerces["research"] += get_total_specialists() * specialist_research_bonus

	return total_commerces

func get_great_people_points() -> Dictionary:
	var gp_points = {}

	for specialist_id in specialists:
		var count = specialists[specialist_id]
		var gp_type = DataManager.get_specialist_gp_type(specialist_id)
		var gp_amount = DataManager.get_specialist_gp_points(specialist_id)

		if gp_type != "" and gp_amount > 0:
			gp_points[gp_type] = gp_points.get(gp_type, 0) + gp_amount * count

	# Buildings that generate GP points
	for building_id in buildings:
		var effects = DataManager.get_building_effects(building_id)
		var building_gp = effects.get("great_person_points", 0)
		var building_gp_type = effects.get("great_person_type", "")

		if building_gp > 0 and building_gp_type != "":
			gp_points[building_gp_type] = gp_points.get(building_gp_type, 0) + building_gp

	return gp_points

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
		"specialists": specialists,
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
	specialists = data.get("specialists", {})

	position = GridUtils.grid_to_pixel(grid_position)
	calculate_yields()
	update_visual()
