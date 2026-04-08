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

# City focus for citizen assignment: "", "food", "production", "commerce", "science", "culture", "gpp"
var city_focus: String = ""

# Manual tile locks: tiles the player has manually assigned (won't be auto-reassigned)
var locked_tiles: Array[Vector2i] = []

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
var culture_level: int = 0  # Starts at Poor (0), expands at Fledgling (10), Developing (100), etc.

# Religion
var religions: Array[String] = []
var holy_city_of: String = ""

# Health and Happiness
var happiness: int = 0
var unhappiness: int = 0
var health: int = 0
var unhealthiness: int = 0

func get_happiness() -> int:
	return happiness

func get_unhappiness() -> int:
	return unhappiness

func get_health() -> int:
	return health

func get_unhealthiness() -> int:
	return unhealthiness

# Available resources
var available_resources: Array[String] = []

# Defense
var defense_strength: float = 0.0
var defense_damage: float = 0.0

# Resistance (after capture)
var resistance_turns: int = 0
var original_owner_id: int = -1  # Player who founded this city
var founder_civ_id: String = ""  # Civilization that founded this city

# Trade routes
var trade_routes: Array = []  # [{target_name, value, is_foreign}]
var trade_route_income: int = 0

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
	if DisplayServer.get_name() == "headless":
		return
	var font = ThemeDB.fallback_font
	var bg_color = player_owner.color if player_owner else Color.GRAY
	var is_own = player_owner == GameManager.human_player

	# Determine visibility for enemy cities
	var show_details = is_own
	if not is_own and GameManager.human_player != null:
		var tile = GameManager.hex_grid.get_tile(grid_position) if GameManager.hex_grid else null
		if tile != null:
			show_details = tile.is_visible_to(GameManager.human_player.player_id)

	# --- City Bar (above the circle) ---
	var bar_width = 90
	var bar_x = -bar_width / 2
	var bar_y = -72  # Above city circle

	# Name bar background
	var name_bg_color = bg_color
	name_bg_color.a = 0.85
	draw_rect(Rect2(bar_x - 2, bar_y - 2, bar_width + 4, 18), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar_x, bar_y, bar_width, 16), name_bg_color)

	# Population number (left side of bar)
	var pop_text = str(population)
	draw_string(font, Vector2(bar_x + 2, bar_y + 12), pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)

	# City name (centered in bar)
	var name_width = font.get_string_size(city_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var name_x = bar_x + (bar_width - name_width) / 2
	draw_string(font, Vector2(max(name_x, bar_x + 16), bar_y + 12), city_name, HORIZONTAL_ALIGNMENT_LEFT, bar_width - 16, 10, Color.WHITE)

	# Growth progress bar (food)
	var growth_y = bar_y + 17
	var food_needed = food_needed_for_growth()
	var growth_ratio = clampf(food_stockpile / max(food_needed, 1), 0.0, 1.0)
	draw_rect(Rect2(bar_x, growth_y, bar_width, 4), Color(0.15, 0.15, 0.15))
	if growth_ratio > 0:
		draw_rect(Rect2(bar_x, growth_y, bar_width * growth_ratio, 4), Color(0.2, 0.8, 0.2))

	# Production progress bar (only if producing and details visible)
	var prod_y = growth_y + 5
	if current_production != "" and (is_own or show_details):
		var prod_cost = get_production_cost()
		var prod_ratio = clampf(float(production_progress) / max(prod_cost, 1), 0.0, 1.0)
		draw_rect(Rect2(bar_x, prod_y, bar_width, 4), Color(0.15, 0.15, 0.15))
		if prod_ratio > 0:
			draw_rect(Rect2(bar_x, prod_y, bar_width * prod_ratio, 4), Color(0.9, 0.7, 0.1))
		prod_y += 5

	# Culture progress bar (thin)
	var culture_y = prod_y
	var next_threshold = CULTURE_THRESHOLDS[min(culture_level + 1, CULTURE_THRESHOLDS.size() - 1)]
	if next_threshold > 0:
		var culture_ratio = clampf(float(culture) / next_threshold, 0.0, 1.0)
		draw_rect(Rect2(bar_x, culture_y, bar_width, 3), Color(0.1, 0.1, 0.1))
		if culture_ratio > 0:
			draw_rect(Rect2(bar_x, culture_y, bar_width * culture_ratio, 3), Color(0.6, 0.3, 0.8))

	# Religion icons row (below bars)
	var icon_y = culture_y + 5
	if not religions.is_empty():
		var rx = bar_x
		for rel in religions:
			var rel_data = DataManager.get_religion(rel)
			var symbol = rel_data.get("symbol", "?")
			var rel_color = Color.WHITE
			if player_owner and player_owner.state_religion == rel:
				rel_color = Color(1.0, 0.9, 0.4)  # Gold for state religion
			draw_string(font, Vector2(rx, icon_y + 10), symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, rel_color)
			rx += 11

	# Health/Happiness indicators (right side of religion row)
	if is_own:
		var indicator_x = bar_x + bar_width - 16
		if happiness >= unhappiness:
			draw_circle(Vector2(indicator_x, icon_y + 6), 4, Color(0.2, 0.8, 0.2))
		else:
			draw_circle(Vector2(indicator_x, icon_y + 6), 4, Color(0.9, 0.2, 0.2))

	# --- City Circle (center) ---
	draw_circle(Vector2.ZERO, 20, bg_color)
	if is_selected:
		draw_arc(Vector2.ZERO, 22, 0, TAU, 32, Color.WHITE, 3.0)
	else:
		draw_arc(Vector2.ZERO, 20, 0, TAU, 32, Color.BLACK, 1.5)

	# Population number in circle
	var pop_circle_text = str(population)
	var ptsize = font.get_string_size(pop_circle_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	draw_string(font, Vector2(-ptsize.x / 2, ptsize.y / 4), pop_circle_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

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
	# Start with just the city tile and initial culture level 0 territory (3x3)
	territory = [grid_position]
	worked_tiles = [grid_position]

	# Add tiles for culture level 0 (Poor - 3x3 square around city)
	var initial_tiles = GridUtils.get_culture_expansion_tiles(grid_position, 0)
	for tile_pos in initial_tiles:
		if _can_claim_tile(tile_pos):
			territory.append(tile_pos)

func _can_claim_tile(pos: Vector2i) -> bool:
	if GameManager.hex_grid == null:
		return true  # Allow during initialization

	var tile = GameManager.hex_grid.get_tile(pos)
	if tile == null:
		return false

	# Unclaimed tiles can always be claimed
	if tile.tile_owner == null:
		return true

	# Own tiles are fine
	if tile.tile_owner == player_owner:
		return true

	# Rival tiles: can claim if our culture dominates (>2x theirs)
	if player_owner:
		var our_culture = tile.get_culture_for(player_owner.player_id)
		var their_culture = tile.get_culture_for(tile.tile_owner.player_id)
		if our_culture > their_culture * 2:
			return true

	return false

# Yield calculation
## Check if a building is obsolete (tech that makes it stop functioning has been researched)
func _is_building_obsolete(building_id: String) -> bool:
	var building_data = DataManager.get_building(building_id)
	var obsolete_tech = building_data.get("obsolete_tech", "")
	if obsolete_tech != "" and player_owner and obsolete_tech in player_owner.researched_techs:
		return true
	return false

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
		if _is_building_obsolete(building_id):
			continue
		var effects = DataManager.get_building_effects(building_id)
		# Flat bonuses from buildings (e.g., Palace gives +8 commerce)
		food_yield += effects.get("food", 0)
		production_yield += effects.get("production", 0)
		commerce_yield += effects.get("commerce", 0)
		# Percentage modifiers
		food_percent += effects.get("food_percent", 0.0)
		prod_percent += effects.get("production_percent", 0.0)
		commerce_percent += effects.get("commerce_percent", 0.0)

	food_yield = int(food_yield * (1.0 + food_percent))
	production_yield = int(production_yield * (1.0 + prod_percent))
	commerce_yield = int(commerce_yield * (1.0 + commerce_percent))

	# Golden Age bonuses (+1 hammer and +1 commerce per worked tile that already produces it)
	if player_owner != null and player_owner.is_in_golden_age():
		for tile_pos in worked_tiles:
			var tile = _get_tile(tile_pos)
			if tile != null:
				var tile_yields = tile.get_yields()
				if tile_yields.get("production", 0) > 0:
					production_yield += 1
				if tile_yields.get("commerce", 0) > 0:
					commerce_yield += 1

	# BTS Financial trait: +1 commerce on tiles with 2+ commerce
	if player_owner and player_owner.has_trait("financial"):
		for tile_pos in worked_tiles:
			var tile = _get_tile(tile_pos)
			if tile != null and tile.get_yields().get("commerce", 0) >= 2:
				commerce_yield += 1

	# We Love the King Day bonuses
	if is_wltkd_active():
		for tile_pos in worked_tiles:
			var tile = _get_tile(tile_pos)
			if tile != null:
				food_yield += 1
				commerce_yield += 1

	# Whip anger decay
	if has_meta("whip_anger_turns") and get_meta("whip_anger_turns") > 0:
		set_meta("whip_anger_turns", get_meta("whip_anger_turns") - 1)

	# Settled Great People bonuses
	var settled_gp_bonuses = get_settled_gp_bonuses()
	production_yield += settled_gp_bonuses.get("production", 0)
	commerce_yield += settled_gp_bonuses.get("commerce", 0)

	# Calculate trade route income
	_calculate_trade_routes()
	gold_yield += trade_route_income

	# Calculate science and culture
	_calculate_science()
	_calculate_culture()
	# Add culture from commerce slider (calculated in _calculate_science, applied after _calculate_culture)
	culture_yield += get_meta("culture_from_commerce") if has_meta("culture_from_commerce") else 0

	# Add settled GP science/culture/gold bonuses after base calculation
	science_yield += settled_gp_bonuses.get("science", 0)
	culture_yield += settled_gp_bonuses.get("culture", 0)
	gold_yield += settled_gp_bonuses.get("gold", 0)

	# Calculate food surplus
	var food_consumed = population * 2
	food_surplus = food_yield - food_consumed

	# Calculate happiness and health
	_calculate_happiness()
	_calculate_health()

func _calculate_science() -> void:
	# BTS commerce slider: split commerce between science, culture, espionage, and gold
	var sci_rate = 1.0
	var cult_rate = 0.0
	var esp_rate = 0.0
	if player_owner != null:
		sci_rate = player_owner.science_rate
		cult_rate = player_owner.culture_rate
		esp_rate = player_owner.espionage_rate
	# Gold gets the remainder
	var gold_rate = max(0.0, 1.0 - sci_rate - cult_rate - esp_rate)

	# Base science from commerce
	science_yield = int(commerce_yield * sci_rate)

	# Specialist science bonus
	var spec_commerces = get_specialist_commerces()
	science_yield += spec_commerces.get("research", 0)

	# Building science percentage bonuses
	var science_percent = 0.0
	for building_id in buildings:
		if _is_building_obsolete(building_id):
			continue
		var effects = DataManager.get_building_effects(building_id)
		science_percent += effects.get("science_percent", 0.0)

	science_yield = int(science_yield * (1.0 + science_percent))

	# Gold from commerce remainder + building gold percent + flat gold + shrines
	var gold_from_commerce = int(commerce_yield * gold_rate)
	var gold_percent = 0.0
	var gold_bonus = 0
	for building_id in buildings:
		if _is_building_obsolete(building_id):
			continue
		var effects = DataManager.get_building_effects(building_id)
		gold_percent += effects.get("gold_percent", 0.0)
		gold_bonus += effects.get("gold", 0)
	gold_from_commerce = int(gold_from_commerce * (1.0 + gold_percent))
	var shrine_gold = ReligionSystem.get_religious_gold(self)
	gold_yield = gold_from_commerce + gold_bonus + shrine_gold

	# Espionage from commerce slider (stored as meta, processed in turn_manager)
	if esp_rate > 0:
		set_meta("espionage_from_commerce", int(commerce_yield * esp_rate))
	else:
		set_meta("espionage_from_commerce", 0)

	# Culture from commerce is stored temporarily, added after _calculate_culture()
	if cult_rate > 0 and player_owner and player_owner.has_tech("drama"):
		set_meta("culture_from_commerce", int(commerce_yield * cult_rate))
	else:
		set_meta("culture_from_commerce", 0)

func _calculate_culture() -> void:
	culture_yield = 0

	# Buildings that produce culture
	var culture_percent = 0.0
	for building_id in buildings:
		if _is_building_obsolete(building_id):
			continue
		var effects = DataManager.get_building_effects(building_id)
		culture_yield += effects.get("culture", 0)
		culture_percent += effects.get("culture_percent", 0.0)

	# Specialist culture bonus
	var spec_commerces = get_specialist_commerces()
	culture_yield += spec_commerces.get("culture", 0)

	# Religion bonuses
	if player_owner and player_owner.state_religion in religions:
		for building_id in buildings:
			if _is_building_obsolete(building_id):
				continue
			var effects = DataManager.get_building_effects(building_id)
			culture_yield += effects.get("culture_from_religion", 0)

	# Apply percentage modifier (e.g., Broadcast Tower gives +50% culture)
	culture_yield = int(culture_yield * (1.0 + culture_percent))

	# BTS Creative trait: +2 base culture per city
	if player_owner and player_owner.has_trait("creative"):
		culture_yield += 2

## Calculate trade route income (BTS-style passive commerce from city connections)
func _calculate_trade_routes() -> void:
	trade_routes.clear()
	trade_route_income = 0

	if player_owner == null:
		return

	# Determine max trade routes: base 1, +1 per building effect
	var max_routes = 1
	for building_id in buildings:
		if _is_building_obsolete(building_id):
			continue
		var effects = DataManager.get_building_effects(building_id)
		max_routes += effects.get("trade_route_yield", 0)

	# Civic bonuses for trade routes (Free Market: +1)
	if CivicsSystem:
		var civic_effects = CivicsSystem.get_civic_effects(player_owner)
		max_routes += civic_effects.get("extra_trade_routes", 0)

	# Check if foreign trade is blocked (Mercantilism)
	var no_foreign_trade = false
	if CivicsSystem:
		no_foreign_trade = CivicsSystem.has_civic_effect(player_owner, "no_foreign_trade")

	var is_connected_to_capital = self in player_owner.connected_cities

	# Gather candidates with BTS connectivity checks
	var candidates = []

	for other_city in GameManager.get_all_cities():
		if other_city == self:
			continue

		var is_foreign = (other_city.player_owner != player_owner)

		# Foreign routes require open borders and no Mercantilism
		if is_foreign:
			if no_foreign_trade:
				continue
			if not player_owner.has_open_borders_with(other_city.player_owner.player_id):
				continue

		# BTS connectivity check
		if not _can_trade_with(other_city, is_foreign):
			continue

		# BTS trade route value formula
		var route_value = _calculate_route_value(other_city, is_foreign, is_connected_to_capital)

		candidates.append({
			"target_name": other_city.city_name,
			"value": route_value,
			"is_foreign": is_foreign
		})

	# Sort by value descending and take top N
	candidates.sort_custom(func(a, b): return a.value > b.value)
	for i in range(min(max_routes, candidates.size())):
		trade_routes.append(candidates[i])
		trade_route_income += candidates[i].value

## BTS: check if two cities can trade (road/river/coastal connectivity required)
func _can_trade_with(other_city, is_foreign: bool) -> bool:
	if not is_foreign:
		# Domestic: both connected to capital via roads/rivers
		if self in player_owner.connected_cities and other_city in player_owner.connected_cities:
			return true
		# Or both coastal (sea trade)
		if _is_coastal() and other_city._is_coastal():
			return true
		return false
	else:
		# Foreign: this city connected to our capital, other to theirs
		var other_owner = other_city.player_owner
		if other_owner == null:
			return false
		if self in player_owner.connected_cities and other_city in other_owner.connected_cities:
			return true
		# Sea trade: both coastal
		if _is_coastal() and other_city._is_coastal():
			return true
		return false

## BTS trade route value formula
func _calculate_route_value(other_city, is_foreign: bool, connected_to_capital: bool) -> int:
	var base = (population + other_city.population) / 5
	var modifier = 1.0

	# Capital connectivity: +25%
	if connected_to_capital:
		modifier += 0.25

	# Overseas (different continent): +100%
	if _is_overseas(other_city):
		modifier += 1.0

	# Foreign trade: +150% with open borders, +75% without
	if is_foreign:
		if player_owner.has_open_borders_with(other_city.player_owner.player_id):
			modifier += 1.5
		else:
			modifier += 0.75

	# Population modifier: max(0, (pop - 10) * 5%)
	modifier += max(0.0, (population - 10) * 0.05)

	return max(1, int(base * modifier))

## Check if other city is on a different continent
func _is_overseas(other_city) -> bool:
	var grid = GameManager.hex_grid
	if grid == null:
		return false
	var my_tile = grid.get_tile(grid_position)
	var other_tile = grid.get_tile(other_city.grid_position)
	if my_tile == null or other_tile == null:
		return false
	return my_tile.continent_id != other_tile.continent_id and my_tile.continent_id >= 0

func _calculate_happiness() -> void:
	happiness = 0
	unhappiness = 0

	# Base unhappiness from population
	unhappiness = population

	# Buildings
	for building_id in buildings:
		if _is_building_obsolete(building_id):
			continue
		var effects = DataManager.get_building_effects(building_id)
		happiness += effects.get("happiness", 0)

	# Resources
	_update_available_resources()
	for resource_id in available_resources:
		var resource = DataManager.get_resource(resource_id)
		if resource.get("type", "") == "luxury":
			happiness += resource.get("happiness", 1)

	# Religious happiness (holy city bonus, temple/monastery happiness with state religion)
	if ReligionSystem:
		happiness += ReligionSystem.get_religious_happiness(self)

	# Wonder effects
	if WonderSystem and player_owner:
		happiness += WonderSystem.get_wonder_happiness_bonus(player_owner)
		if WonderSystem.city_has_no_unhappiness(self):
			unhappiness = 0

	# BTS Charismatic trait: +1 happiness per city
	if player_owner and player_owner.has_trait("charismatic"):
		happiness += 1

	# War weariness unhappiness
	if player_owner and player_owner.war_weariness > 0:
		var ww_unhappy = player_owner.war_weariness / max(player_owner.cities.size(), 1)
		# Civic modifier
		if CivicsSystem:
			var ww_mod = CivicsSystem.get_civic_effects(player_owner).get("war_weariness_modifier", 0)
			ww_unhappy = int(ww_unhappy * (1.0 + ww_mod / 100.0))
		# Wonder reduction
		if WonderSystem:
			var ww_reduction = WonderSystem.get_war_weariness_reduction(player_owner)
			ww_unhappy = int(ww_unhappy * (1.0 - ww_reduction))
		unhappiness += max(0, ww_unhappy)

	# Draft anger
	unhappiness += get_draft_unhappiness()

	# Whip anger
	if has_meta("whip_anger_turns") and get_meta("whip_anger_turns") > 0:
		unhappiness += 1

func _calculate_health() -> void:
	health = 0
	unhealthiness = 0

	# Base health
	health = 2

	# Population causes unhealthiness
	unhealthiness = population / 2

	# Buildings
	for building_id in buildings:
		if _is_building_obsolete(building_id):
			continue
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
	# Find best unworked tile in territory based on city focus
	var best_tile: Vector2i = Vector2i(-1, -1)
	var best_value = -1.0

	for tile_pos in territory:
		if tile_pos in worked_tiles:
			continue

		var tile = _get_tile(tile_pos)
		if tile == null:
			continue

		var yields = tile.get_yields()
		var value = _score_tile_for_focus(yields)

		if value > best_value:
			best_value = value
			best_tile = tile_pos

	if best_tile.x >= 0:
		worked_tiles.append(best_tile)

func _score_tile_for_focus(yields: Dictionary) -> float:
	var food = yields.get("food", 0)
	var prod = yields.get("production", 0)
	var commerce = yields.get("commerce", 0)
	match city_focus:
		"food":
			return food * 5 + prod * 1 + commerce * 1
		"production":
			return food * 1 + prod * 5 + commerce * 1
		"commerce", "science":
			return food * 1 + prod * 1 + commerce * 5
		"culture":
			return food * 1 + prod * 1 + commerce * 4
		_:
			return food * 3 + prod * 2 + commerce * 1

## Toggle whether a tile is manually worked or unworked
func toggle_tile_work(tile_pos: Vector2i) -> void:
	if tile_pos not in territory or tile_pos == grid_position:
		return

	if tile_pos in worked_tiles:
		# Unwork the tile
		worked_tiles.erase(tile_pos)
		locked_tiles.erase(tile_pos)
	else:
		# Work the tile if we have available population
		if get_available_population() > 0:
			worked_tiles.append(tile_pos)
			if tile_pos not in locked_tiles:
				locked_tiles.append(tile_pos)

	calculate_yields()

## Reassign all non-locked citizens based on city focus
func reassign_citizens() -> void:
	# Remove non-locked tiles
	var new_worked = []
	for tile_pos in worked_tiles:
		if tile_pos in locked_tiles:
			new_worked.append(tile_pos)
	worked_tiles.assign(new_worked)

	# Fill remaining slots
	while get_available_population() > 0:
		var had = worked_tiles.size()
		_auto_assign_citizen()
		if worked_tiles.size() == had:
			break

	calculate_yields()

## Set city focus and reassign citizens
func set_city_focus(focus: String) -> void:
	city_focus = focus
	reassign_citizens()

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

	# Free specialists from wonders (Statue of Liberty)
	if player_owner and WonderSystem:
		slots += WonderSystem.get_wonder_free_specialist_slots(player_owner)

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

## Get yield bonuses from settled Great People
func get_settled_gp_bonuses() -> Dictionary:
	var bonuses = {"production": 0, "commerce": 0, "science": 0, "culture": 0, "gold": 0}
	if not has_meta("settled_great_people"):
		return bonuses

	var settled = get_meta("settled_great_people")
	for gp_type in settled:
		match gp_type:
			"great_prophet":
				bonuses["production"] += 2
				bonuses["gold"] += 5
			"great_artist":
				bonuses["culture"] += 12
			"great_scientist":
				bonuses["science"] += 6
			"great_merchant":
				bonuses["gold"] += 6
				bonuses["commerce"] += 6
			"great_engineer":
				bonuses["production"] += 3
			"great_general":
				bonuses["production"] += 2
	return bonuses

# Production
func set_production(item: String) -> void:
	# No-op if already producing this item — otherwise we'd wipe accumulated progress
	# every turn the AI re-affirms its choice, leaving cities stuck at 0/cost forever.
	if current_production == item:
		return
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
	var unit_data = DataManager.get_unit(unit_type)

	# Civ4 BTS: settlers do NOT consume population (that's a Civ5 mechanic)
	# Food surplus was already redirected to production during building
	var food_cost = unit_data.get("food_cost", 0)
	if food_cost > 0:
		food_stockpile = 0  # Reset food stockpile after settler completes

	var unit = UnitClass.new(unit_type, grid_position)
	player_owner.add_unit(unit)

	# Add to scene
	if GameManager.game_world:
		GameManager.game_world.add_child(unit)

	# Apply free experience from buildings
	var free_xp = 0
	for building_id in buildings:
		if _is_building_obsolete(building_id):
			continue
		var effects = DataManager.get_building_effects(building_id)
		free_xp += effects.get("free_experience", 0)

	# Theocracy civic: +2 XP in cities with state religion
	if CivicsSystem and player_owner and player_owner.state_religion in religions:
		var civic_effects = CivicsSystem.get_civic_effects(player_owner)
		free_xp += civic_effects.get("state_religion_free_experience", 0)

	unit.experience = free_xp

	EventBus.unit_created.emit(unit)

func _produce_building(building_type: String) -> void:
	if building_type not in buildings:
		# Check wonder availability at completion time (race condition guard)
		var building = DataManager.get_building(building_type)
		var wonder_type = building.get("wonder_type", "")
		if wonder_type == "world" and not GameManager.is_world_wonder_available(building_type):
			# Another civ completed this wonder first — refund some production as gold
			if player_owner:
				var cost = building.get("cost", 100)
				player_owner.gold += cost / 2
			return
		if wonder_type == "national" and player_owner and not GameManager.is_national_wonder_available(building_type, player_owner.player_id):
			return

		buildings.append(building_type)

		# Register wonders with GameManager
		if wonder_type == "world" and player_owner != null:
			GameManager.register_world_wonder(building_type, player_owner.player_id)
		elif wonder_type == "national" and player_owner != null:
			GameManager.register_national_wonder(building_type, player_owner.player_id)

		EventBus.city_building_constructed.emit(self, building_type)
		calculate_yields()

func has_building(building_id: String) -> bool:
	return building_id in buildings

func can_build_unit(unit_id: String) -> bool:
	if player_owner == null:
		return false
	# Civ4 BTS: any city can build settlers (food surplus goes to production)
	# No population requirement — city just stops growing during construction
	return player_owner.can_build_unit(unit_id)

func can_build_building(building_id: String) -> bool:
	if player_owner == null:
		return false

	# Already have it?
	if building_id in buildings:
		return false

	# Check requirements
	var building = DataManager.get_building(building_id)

	# Check wonder availability
	var wonder_type = building.get("wonder_type", "")
	if wonder_type == "world":
		if not GameManager.is_world_wonder_available(building_id):
			return false
	elif wonder_type == "national":
		if not GameManager.is_national_wonder_available(building_id, player_owner.player_id):
			return false

	# Required building (singular legacy format)
	var requires = building.get("requires_building", "")
	if requires != "" and requires not in buildings:
		return false

	# Required buildings (BTS array format — all must be present)
	var required_buildings = building.get("required_buildings", [])
	for req_bld in required_buildings:
		if req_bld not in buildings:
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

## Radiate culture to surrounding tiles (BTS-style culture competition)
func radiate_culture() -> void:
	if player_owner == null or GameManager.hex_grid == null:
		return
	if culture_yield <= 0:
		return

	var pid = player_owner.player_id
	var max_radius = min(culture_level + 2, 6)  # Radius based on culture level

	# City tile gets full culture
	var city_tile = GameManager.hex_grid.get_tile(grid_position)
	if city_tile:
		city_tile.add_culture(pid, culture_yield)

	# Radiate outward with diminishing amounts
	for radius in range(1, max_radius + 1):
		var ring_tiles = GridUtils.get_tiles_in_range(grid_position, radius)
		var amount = 0
		match radius:
			1: amount = int(culture_yield * 0.5)
			2: amount = int(culture_yield * 0.25)
			_: amount = int(culture_yield * 0.1)

		if amount <= 0:
			continue

		for tile_pos in ring_tiles:
			# Skip tiles already processed in inner rings
			if GridUtils.chebyshev_distance(grid_position, tile_pos) != radius:
				continue
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile and not tile.is_water():
				tile.add_culture(pid, amount)

func check_border_expansion() -> void:
	# Check if we've reached the next culture level threshold
	# culture_level 0 = Poor (initial 3x3), expands to level 1 at 10 culture
	# culture_level 1 = Fledgling (Fat Cross), expands to level 2 at 100 culture
	# etc.
	while culture_level + 1 < CULTURE_THRESHOLDS.size() and culture >= CULTURE_THRESHOLDS[culture_level + 1]:
		culture_level += 1
		_expand_borders()
		EventBus.city_borders_expanded.emit(self)

func _expand_borders() -> void:
	# Get all tiles that should be in territory for current culture level
	# This uses circular expansion patterns instead of square rings
	var expansion_tiles = GridUtils.get_culture_expansion_tiles(grid_position, culture_level)

	var added_new_tiles = false
	for tile_pos in expansion_tiles:
		if tile_pos not in territory and _can_claim_tile(tile_pos):
			territory.append(tile_pos)
			var tile = _get_tile(tile_pos)
			if tile != null:
				# Remove from rival city territory if culture-flipping
				if tile.city_owner and tile.city_owner != self:
					tile.city_owner.territory.erase(tile_pos)
					if tile_pos in tile.city_owner.worked_tiles:
						tile.city_owner.worked_tiles.erase(tile_pos)
				tile.tile_owner = player_owner
				tile.city_owner = self
				# Seed initial culture for the claiming player
				if player_owner:
					tile.add_culture(player_owner.player_id, 20)
				added_new_tiles = true

	# Redraw ALL territory tiles so old border lines are removed
	# and update visibility based on new cultural borders
	if added_new_tiles:
		for tile_pos in territory:
			var tile = _get_tile(tile_pos)
			if tile != null:
				tile.update_visuals()

		# Update visibility to extend beyond new borders
		VisibilitySystem.reveal_for_city(self)

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

# =============================================================================
# CONSCRIPTION (Draft)
# =============================================================================

## Maximum drafts per turn based on city population
const DRAFT_ANGER_TURNS = 10
const DRAFT_POP_COST = 1
const MAX_DRAFTS_PER_TURN = 3

var drafts_this_turn: int = 0
var draft_anger_turns: int = 0

## Check if conscription is available
func can_conscript() -> bool:
	if player_owner == null:
		return false

	# Need Nationalism tech
	if not player_owner.has_tech("nationalism"):
		return false

	# Need Nationhood civic
	if player_owner.civics.get("legal", "") != "nationhood":
		return false

	# Need minimum population
	if population < 2:
		return false

	# Check draft limit this turn
	if drafts_this_turn >= MAX_DRAFTS_PER_TURN:
		return false

	return true

## Get the unit type that can be drafted
func get_draft_unit() -> String:
	# Draft the best infantry-type unit available
	var draft_units = ["mechanized_infantry", "infantry", "rifleman", "musketman", "pikeman", "spearman", "warrior"]

	for unit_id in draft_units:
		var unit_data = DataManager.get_unit(unit_id)
		if unit_data.is_empty():
			continue

		var required_tech = unit_data.get("required_tech", "")
		if required_tech == "" or player_owner.has_tech(required_tech):
			return unit_id

	return "warrior"  # Fallback

## Perform conscription
func conscript() -> bool:
	if not can_conscript():
		return false

	var draft_unit = get_draft_unit()

	# Reduce population
	population -= DRAFT_POP_COST
	if population < 1:
		population = 1

	# Create the unit
	if GameManager.game_world:
		GameManager.game_world.spawn_unit(draft_unit, grid_position, player_owner)

	# Increase draft anger
	draft_anger_turns = DRAFT_ANGER_TURNS
	drafts_this_turn += 1

	EventBus.city_drafted.emit(self, draft_unit)
	calculate_yields()
	return true

## Get unhappiness from recent drafts
func get_draft_unhappiness() -> int:
	if draft_anger_turns > 0:
		return drafts_this_turn
	return 0

## Reset drafts at turn start
func reset_drafts() -> void:
	drafts_this_turn = 0
	if draft_anger_turns > 0:
		draft_anger_turns -= 1

# Whipping (Slavery civic)
const WHIP_PRODUCTION = 30  # Hammers per population sacrificed
const WHIP_ANGER_TURNS = 10

func can_whip() -> bool:
	if player_owner == null or population <= 1:
		return false
	if current_production == "":
		return false
	# Requires Slavery civic (can_hurry_with_population)
	if not CivicsSystem.has_civic_effect(player_owner, "can_hurry_with_population"):
		return false
	return true

func whip() -> bool:
	if not can_whip():
		return false
	population -= 1
	production_progress += WHIP_PRODUCTION
	set_meta("whip_anger_turns", WHIP_ANGER_TURNS)
	# Check if production completed
	var cost = get_production_cost()
	if production_progress >= cost:
		complete_production()
	calculate_yields()
	EventBus.notification_added.emit("Population whipped in %s!" % city_name)
	return true

# Hurrying with gold (Universal Suffrage civic)
func can_hurry_gold() -> bool:
	if player_owner == null:
		return false
	if current_production == "":
		return false
	if not CivicsSystem.has_civic_effect(player_owner, "can_hurry_with_gold"):
		return false
	return player_owner.gold >= get_hurry_cost()

func get_hurry_cost() -> int:
	var cost = get_production_cost()
	var remaining = cost - production_progress
	return max(1, remaining * 4)  # 4 gold per remaining hammer

func hurry_with_gold() -> bool:
	if not can_hurry_gold():
		return false
	player_owner.gold -= get_hurry_cost()
	production_progress = get_production_cost()
	complete_production()
	calculate_yields()
	EventBus.notification_added.emit("Production rushed in %s!" % city_name)
	return true

# We Love the King Day
func is_wltkd_active() -> bool:
	return happiness - unhappiness >= 3 and population >= 5

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
## Check if this city is the capital (has palace)
func is_capital() -> bool:
	return "palace" in buildings

## Check if this city is a holy city for any religion
func is_holy_city() -> bool:
	return holy_city_of != ""

## Check if this city can be razed (not capital, not holy city)
func can_be_razed() -> bool:
	return not is_capital() and not is_holy_city()

## Transfer city to a new owner (used during capture)
func transfer_to(new_owner) -> void:
	var old_owner = player_owner

	# Remove from old owner
	if old_owner:
		old_owner.cities.erase(self)

	# Add to new owner
	player_owner = new_owner
	if new_owner:
		new_owner.cities.append(self)

	# Set resistance proportional to population
	resistance_turns = max(1, population / 2)

	# Reset production
	current_production = ""
	production_progress = 0
	production_queue.clear()

	# Clear food stockpile
	food_stockpile = 0.0

	# Remove unique buildings from old owner's civ
	if old_owner:
		var old_civ = DataManager.get_civ(old_owner.civilization_id)
		var unique_buildings = old_civ.get("unique_buildings", {})
		for ub in unique_buildings.values():
			if ub in buildings:
				buildings.erase(ub)

	# Update tile ownership
	for tile_pos in territory:
		var tile = GameManager.hex_grid.get_tile(tile_pos) if GameManager.hex_grid else null
		if tile:
			tile.tile_owner = new_owner
			tile.city_owner = self
			tile.update_visuals()

	# Recalculate yields
	calculate_yields()
	update_visual()

	# Check if old owner is now eliminated
	if old_owner and old_owner.is_eliminated():
		EventBus.player_eliminated.emit(old_owner)

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
		"city_focus": city_focus,
		"locked_tiles": locked_tiles.map(func(v): return {"x": v.x, "y": v.y}),
		"original_owner_id": original_owner_id,
		"founder_civ_id": founder_civ_id,
		"resistance_turns": resistance_turns,
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
	city_focus = data.get("city_focus", "")
	original_owner_id = data.get("original_owner_id", -1)
	founder_civ_id = data.get("founder_civ_id", "")
	resistance_turns = data.get("resistance_turns", 0)
	locked_tiles.clear()
	for t in data.get("locked_tiles", []):
		locked_tiles.append(Vector2i(t.x, t.y))

	position = GridUtils.grid_to_pixel(grid_position)
	calculate_yields()
	update_visual()
