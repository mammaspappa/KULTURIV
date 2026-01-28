class_name Unit
extends Node2D
## Represents a single unit on the map.

const GameTileClass = preload("res://scripts/map/game_tile.gd")
const PathfindingClass = preload("res://scripts/map/pathfinding.gd")

# Identity
var unit_id: String = "warrior"
var player_owner = null  # Player (untyped to avoid circular dependency)

# Position
var grid_position: Vector2i = Vector2i.ZERO

# Stats
var health: float = 100.0
var max_health: float = 100.0
var experience: int = 0
var level: int = 1

# Movement
var movement_remaining: float = 0.0
var has_acted: bool = false

# State
var is_fortified: bool = false
var fortify_bonus: float = 0.0  # Accumulates up to 0.25
var is_sleeping: bool = false

# Orders
enum UnitOrder { NONE, FORTIFY, SLEEP, SENTRY, HEAL, EXPLORE, BUILD, GOTO, AUTOMATE }
var current_order: UnitOrder = UnitOrder.NONE
var order_target: Vector2i = Vector2i.ZERO
var order_target_improvement: String = ""
var build_progress: int = 0

# Transport/Cargo
var cargo: Array = []  # Units being transported
var transport: Node2D = null  # Reference to transport unit if loaded

# Promotions
var promotions: Array[String] = []

# Visual
const TILE_SIZE: int = 64
var is_selected: bool = false

# Movement animation
var is_moving: bool = false
var movement_tween: Tween = null

signal movement_completed()
signal unit_selected(unit)
signal unit_attacked(target)

func _init(type: String = "warrior", pos: Vector2i = Vector2i.ZERO) -> void:
	unit_id = type
	grid_position = pos
	position = GridUtils.grid_to_pixel(grid_position)
	refresh_movement()

func _ready() -> void:
	update_visual()

func _draw() -> void:
	var unit_data = DataManager.get_unit(unit_id)
	var symbol = unit_data.get("symbol", "?")
	var unit_class = unit_data.get("unit_class", "melee")

	# Background circle color based on owner
	var bg_color = player_owner.color if player_owner else Color.GRAY
	draw_circle(Vector2.ZERO, 24, bg_color)

	# Border for selection
	if is_selected:
		draw_arc(Vector2.ZERO, 26, 0, TAU, 32, Color.WHITE, 3.0)

	# Unit symbol
	var font = ThemeDB.fallback_font
	var font_size = 24
	var text_size = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(-text_size.x / 2, text_size.y / 4)
	draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# Health bar
	if health < max_health:
		var bar_width = 40
		var bar_height = 4
		var bar_y = -30
		var health_percent = health / max_health

		# Background
		draw_rect(Rect2(-bar_width/2, bar_y, bar_width, bar_height), Color.DARK_RED)
		# Health
		var health_color = Color.GREEN if health_percent > 0.5 else (Color.YELLOW if health_percent > 0.25 else Color.RED)
		draw_rect(Rect2(-bar_width/2, bar_y, bar_width * health_percent, bar_height), health_color)

	# Fortification indicator
	if is_fortified:
		var shield_pos = Vector2(15, -15)
		draw_string(font, shield_pos, "⛨", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.CYAN)

	# Movement points indicator
	if movement_remaining > 0:
		var move_text = str(int(movement_remaining))
		draw_string(font, Vector2(15, 20), move_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func update_visual() -> void:
	# Check if this unit should be visible to the human player
	var human_player = GameManager.human_player
	if human_player != null and player_owner != human_player:
		# Enemy unit - only show if on a tile visible to human player
		var tile = GameManager.hex_grid.get_tile(grid_position) if GameManager.hex_grid else null
		if tile != null:
			var vis_state = tile.get_visibility_for_player(human_player.player_id)
			visible = (vis_state == GameTileClass.VisibilityState.VISIBLE)
		else:
			visible = false
	else:
		# Own unit or no human player - always visible
		visible = true

	queue_redraw()

# Stats from data
func get_strength() -> float:
	var base = DataManager.get_unit_strength(unit_id)
	# Apply promotions
	for promo in promotions:
		var effects = DataManager.get_promotion_effects(promo)
		base *= (1.0 + effects.get("strength_bonus", 0.0))
	return base

func get_base_movement() -> int:
	return DataManager.get_unit_movement(unit_id)

func get_unit_class() -> String:
	var unit_data = DataManager.get_unit(unit_id)
	return unit_data.get("unit_class", "melee")

func get_abilities() -> Array:
	return DataManager.get_unit_abilities(unit_id)

# Movement
func refresh_movement() -> void:
	movement_remaining = get_base_movement()
	has_acted = false
	update_visual()

func can_move() -> bool:
	return movement_remaining > 0 and not is_moving

func can_move_to(target: Vector2i) -> bool:
	if not can_move():
		return false

	var grid = GameManager.hex_grid
	if grid == null:
		return false

	var tile = grid.get_tile(target)
	if tile == null:
		return false

	if not tile.is_passable():
		return false

	# Check if water and we can't swim
	if tile.is_water() and not _can_enter_water():
		return false

	# Check for enemy units
	var other_unit = GameManager.get_unit_at(target)
	if other_unit != null and other_unit.player_owner != player_owner:
		# Can attack instead
		return false

	# Check border permissions
	if not can_enter_tile(tile):
		return false

	return true

## Check if this unit can enter a tile based on border ownership
func can_enter_tile(tile) -> bool:
	if player_owner == null:
		return true

	# No owner = neutral territory, anyone can enter
	if tile.tile_owner == null:
		return true

	# Check if we have permission to enter this player's borders
	return player_owner.can_enter_borders_of(tile.tile_owner.player_id)

func _can_enter_water() -> bool:
	var unit_class = get_unit_class()
	return unit_class == "naval"

func move_to(target: Vector2i) -> bool:
	if not can_move_to(target):
		return false

	var grid = GameManager.hex_grid
	var tile = grid.get_tile(target)
	var source_tile = grid.get_tile(grid_position)
	var move_cost = _get_movement_cost_to(source_tile, tile)

	# Check if we have enough movement
	if movement_remaining < move_cost and movement_remaining < 1:
		return false

	var old_pos = grid_position
	grid_position = target

	# Move cargo along with transport
	for cargo_unit in cargo:
		cargo_unit.grid_position = target

	# Animate movement
	_animate_move_to(target)

	# Deduct movement
	movement_remaining = max(0, movement_remaining - move_cost)

	# Unfog tiles
	_update_visibility()

	EventBus.unit_moved.emit(self, old_pos, target)

	if movement_remaining <= 0:
		EventBus.unit_movement_finished.emit(self)

	update_visual()
	return true

func _animate_move_to(target: Vector2i) -> void:
	is_moving = true
	var target_pos = GridUtils.grid_to_pixel(target)

	if movement_tween:
		movement_tween.kill()

	movement_tween = create_tween()
	movement_tween.tween_property(self, "position", target_pos, 0.2)
	movement_tween.tween_callback(_on_movement_animation_done)

func _on_movement_animation_done() -> void:
	is_moving = false
	movement_completed.emit()

func move_along_path(path: Array[Vector2i]) -> void:
	if path.is_empty():
		return

	# Move one tile at a time
	var next_pos = path[0]
	if move_to(next_pos):
		path.remove_at(0)
		if not path.is_empty() and can_move():
			# Continue moving after animation
			await movement_completed
			move_along_path(path)

## Calculate movement cost considering road-to-road movement
func _get_movement_cost_to(source_tile, dest_tile) -> float:
	if dest_tile == null:
		return 1.0

	var base_cost = float(dest_tile.get_total_movement_cost())

	# Road-to-road movement costs 1/3 movement point
	if source_tile != null and source_tile.road_level >= 1 and dest_tile.road_level >= 1:
		# Both tiles have roads - reduced movement cost
		if dest_tile.road_level >= 2 and source_tile.road_level >= 2:
			# Railroad-to-railroad is essentially free
			base_cost = 0.1
		else:
			# Road-to-road costs 1/3 movement point
			base_cost = 1.0 / 3.0

	# Unit-specific modifiers
	if "ignore_terrain_cost" in get_abilities():
		return 1.0

	# Promotion effects for terrain
	for promo in promotions:
		var effects = DataManager.get_promotion_effects(promo)
		if dest_tile.feature_id == "forest" and effects.get("forest_double_movement", false):
			base_cost = 1.0
		if dest_tile.terrain_id == "hills" and effects.get("hills_double_movement", false):
			base_cost = 1.0

	return base_cost

func teleport_to(target: Vector2i) -> void:
	grid_position = target
	position = GridUtils.grid_to_pixel(target)
	_update_visibility()
	update_visual()

# Visibility
func get_visibility_range() -> int:
	# Get base sight range from unit data (default 1)
	var unit_data = DataManager.get_unit(unit_id)
	var base_range = unit_data.get("sight_range", 1)

	# Promotions can increase this
	for promo in promotions:
		var effects = DataManager.get_promotion_effects(promo)
		base_range += effects.get("visibility_range_increase", 0)

	# Hills provide +1 visibility
	if player_owner != null and GameManager.hex_grid != null:
		var tile = GameManager.hex_grid.get_tile(grid_position)
		if tile != null and tile.is_hills():
			base_range += 1

	return base_range

func _update_visibility() -> void:
	if player_owner == null:
		return

	# Use VisibilitySystem to reveal tiles
	VisibilitySystem.reveal_for_unit(self)

	# Check for first contact with other players
	var vis_range = get_visibility_range()
	var visible_tiles = GridUtils.get_tiles_in_range(grid_position, vis_range)
	visible_tiles.append(grid_position)

	for tile_pos in visible_tiles:
		_check_first_contact_at(tile_pos)

func _check_first_contact_at(tile_pos: Vector2i) -> void:
	if player_owner == null:
		return

	# Check for units at this position
	var units_at_pos = GameManager.get_units_at(tile_pos)
	for other_unit in units_at_pos:
		if other_unit.player_owner != null and other_unit.player_owner != player_owner:
			var other_player = other_unit.player_owner
			if other_player.player_id not in player_owner.met_players:
				# First contact
				player_owner.met_players.append(other_player.player_id)
				other_player.met_players.append(player_owner.player_id)
				EventBus.first_contact.emit(player_owner, other_player)

	# Check for cities at this position
	var city = GameManager.get_city_at(tile_pos)
	if city != null and city.player_owner != null and city.player_owner != player_owner:
		var other_player = city.player_owner
		if other_player.player_id not in player_owner.met_players:
			# First contact
			player_owner.met_players.append(other_player.player_id)
			other_player.met_players.append(player_owner.player_id)
			EventBus.first_contact.emit(player_owner, other_player)

# Combat
func get_combat_strength(is_attacking: bool, target_tile = null, defender = null) -> float:
	var strength = get_strength()

	# Health penalty
	strength *= (health / max_health)

	# Fortification bonus (defense only)
	if not is_attacking and is_fortified:
		strength *= (1.0 + fortify_bonus)

	# Terrain defense bonus
	if not is_attacking and target_tile != null:
		strength *= (1.0 + target_tile.get_defense_bonus())

	# Promotion bonuses vs specific unit types
	if defender != null:
		var defender_class = defender.get_unit_class()
		for promo in promotions:
			var effects = DataManager.get_promotion_effects(promo)
			var bonus_key = "bonus_vs_" + defender_class
			strength *= (1.0 + effects.get(bonus_key, 0.0))

	# Unit type bonuses
	var unit_data = DataManager.get_unit(unit_id)
	if defender != null:
		var defender_class = defender.get_unit_class()
		var bonus_vs = unit_data.get("bonus_vs", {})
		if defender_class in bonus_vs:
			strength *= (1.0 + bonus_vs[defender_class])

	return strength

func get_first_strikes() -> int:
	var base = DataManager.get_unit(unit_id).get("first_strikes", 0)
	for promo in promotions:
		var effects = DataManager.get_promotion_effects(promo)
		base += effects.get("first_strikes", 0)
	return base

func get_withdraw_chance() -> float:
	var base = DataManager.get_unit(unit_id).get("withdraw_chance", 0.0)
	for promo in promotions:
		var effects = DataManager.get_promotion_effects(promo)
		base += effects.get("withdraw_increase", 0.0)
	return min(base, 0.9)  # Cap at 90%

func can_attack(target) -> bool:
	if has_acted:
		return false
	if target.player_owner == player_owner:
		return false
	if get_strength() <= 0:
		return false
	if not GridUtils.are_adjacent(grid_position, target.grid_position):
		return false

	# Check if we can enter the defender's tile (border permissions)
	# Must be at war or have permission to cross their borders to attack
	if player_owner != null and target.player_owner != null:
		var defender_tile = GameManager.hex_grid.get_tile(target.grid_position) if GameManager.hex_grid else null
		if defender_tile != null and defender_tile.tile_owner != null:
			# If target is in their own territory, check if we can enter
			if defender_tile.tile_owner == target.player_owner:
				if not player_owner.can_enter_borders_of(target.player_owner.player_id):
					return false

	return true

func take_damage(amount: float) -> void:
	health = max(0, health - amount)
	update_visual()

	if health <= 0:
		die()

func heal(amount: int) -> void:
	health = min(max_health, health + amount)
	EventBus.unit_healed.emit(self, amount)
	update_visual()

func die() -> void:
	# Destroy cargo when transport dies
	for cargo_unit in cargo:
		cargo_unit.transport = null
		cargo_unit.die()
	cargo.clear()

	# If loaded in a transport, remove from cargo
	if transport != null:
		transport.cargo.erase(self)
		transport = null

	EventBus.unit_destroyed.emit(self)
	if player_owner:
		player_owner.remove_unit(self)
	queue_free()

# Experience and promotions
func gain_experience(amount: int) -> void:
	experience += amount
	_check_level_up()

func _check_level_up() -> void:
	var xp_needed = _xp_for_next_level()
	while experience >= xp_needed:
		level += 1
		xp_needed = _xp_for_next_level()

func _xp_for_next_level() -> int:
	# 2, 5, 10, 17, 26, 37, 50...
	return level * (level + 1)

func can_promote() -> bool:
	return experience >= _xp_for_next_level() and _get_available_promotions().size() > 0

func _get_available_promotions() -> Array:
	var available = []
	var all_promotions = DataManager.promotions
	var unit_class = get_unit_class()

	for promo_id in all_promotions:
		if promo_id in promotions:
			continue

		var promo = all_promotions[promo_id]

		# Check unit class
		var valid_classes = promo.get("valid_unit_classes", [])
		if not valid_classes.is_empty() and unit_class not in valid_classes:
			continue

		# Check prerequisites
		var prereqs = promo.get("prerequisites", [])
		var has_prereqs = true
		for prereq in prereqs:
			if prereq not in promotions:
				has_prereqs = false
				break

		if has_prereqs:
			available.append(promo_id)

	return available

func add_promotion(promo_id: String) -> void:
	if promo_id not in promotions:
		promotions.append(promo_id)
		EventBus.unit_promoted.emit(self, promo_id)
		update_visual()

# Orders
func fortify() -> void:
	current_order = UnitOrder.FORTIFY
	is_fortified = true
	movement_remaining = 0
	has_acted = true
	EventBus.unit_order_changed.emit(self, current_order)
	update_visual()

func sleep() -> void:
	current_order = UnitOrder.SLEEP
	is_sleeping = true
	movement_remaining = 0
	has_acted = true
	EventBus.unit_order_changed.emit(self, current_order)
	update_visual()

func wake() -> void:
	current_order = UnitOrder.NONE
	is_sleeping = false
	is_fortified = false
	fortify_bonus = 0.0
	update_visual()

func skip_turn() -> void:
	movement_remaining = 0
	has_acted = true
	update_visual()

func automate() -> void:
	if not can_build_improvements():
		return
	current_order = UnitOrder.AUTOMATE
	EventBus.unit_order_changed.emit(self, current_order)
	# Process automation immediately if we have movement
	if movement_remaining > 0:
		process_automation()
	update_visual()

func stop_automation() -> void:
	if current_order == UnitOrder.AUTOMATE:
		current_order = UnitOrder.NONE
		EventBus.unit_order_changed.emit(self, current_order)
		update_visual()

func process_automation() -> void:
	if current_order != UnitOrder.AUTOMATE or not can_build_improvements():
		return
	if movement_remaining <= 0 or has_acted:
		return

	# If currently building, continue
	if order_target_improvement != "" and build_progress > 0:
		return

	var tile = GameManager.hex_grid.get_tile(grid_position) if GameManager.hex_grid else null
	if tile == null:
		return

	# Find best improvement for current tile or move to a better tile
	var best_improvement = _find_best_improvement(tile)
	if best_improvement != "":
		# Build this improvement
		if best_improvement == "road":
			ImprovementSystem.start_build_road(self)
		elif best_improvement == "railroad":
			ImprovementSystem.start_build_railroad(self)
		else:
			ImprovementSystem.start_build(self, best_improvement)
		return

	# Current tile doesn't need improvement, find a tile that does
	var target_tile = _find_tile_needing_improvement()
	if target_tile != null and target_tile.grid_position != grid_position:
		# Move toward the target tile
		var pathfinder = PathfindingClass.new(GameManager.hex_grid, self)
		var path = pathfinder.find_path(grid_position, target_tile.grid_position)
		if path.size() > 1:
			move_along_path(path)

func _find_best_improvement(tile) -> String:
	if tile == null or player_owner == null:
		return ""

	# Check what can be built on this tile
	var can_road = ImprovementSystem.can_build_road(self, tile)
	var can_railroad = ImprovementSystem.can_build_railroad(self, tile)
	var available = ImprovementSystem.get_available_improvements(self, tile)

	# Priority: Resources first, then terrain-appropriate improvements, then roads
	var resource = tile.resource
	if resource != "":
		var resource_data = DataManager.get_resource(resource)
		var required_imp = resource_data.get("improvement", "")
		if required_imp != "" and required_imp in available:
			return required_imp

	# Check if tile is in our territory and worked
	if tile.city_owner == null or tile.city_owner.player_owner != player_owner:
		return ""  # Don't improve tiles we don't own

	# Terrain-based improvements
	var terrain = tile.terrain_type
	var feature = tile.feature

	# Remove forest/jungle for farms/mines in appropriate cases
	if feature == "forest" and "lumber_mill" in available:
		return "lumber_mill"
	if feature == "jungle" and "farm" in available:
		return "farm"  # Clears jungle for farm

	# Hills get mines
	if terrain == "hills" and "mine" in available:
		return "mine"

	# Grassland/plains get farms for food, cottages for commerce
	if terrain in ["grassland", "plains", "flood_plains"]:
		# Prefer farms near city center for food, cottages farther out
		if tile.city_owner:
			var dist = GridUtils.chebyshev_distance(tile.grid_position, tile.city_owner.grid_position)
			if dist <= 2 and "farm" in available:
				return "farm"
			elif "cottage" in available:
				return "cottage"
			elif "farm" in available:
				return "farm"

	# Build roads to connect cities
	if can_road and tile.improvement != "road" and tile.improvement != "railroad":
		# Check if this tile should have a road (on path between cities)
		if _should_have_road(tile):
			return "road"

	# Upgrade roads to railroads
	if can_railroad and tile.improvement == "road":
		return "railroad"

	return ""

func _should_have_road(tile) -> bool:
	if player_owner == null or player_owner.cities.size() < 2:
		return false

	# Simple heuristic: build roads in our territory
	if tile.tile_owner == player_owner:
		# Check if adjacent to a road or city
		var neighbors = GridUtils.get_neighbors(tile.grid_position)
		for neighbor_pos in neighbors:
			var neighbor = GameManager.hex_grid.get_tile(neighbor_pos) if GameManager.hex_grid else null
			if neighbor:
				if neighbor.improvement == "road" or neighbor.improvement == "railroad":
					return true
				# Check if neighbor has a city
				var city = GameManager.get_city_at(neighbor_pos)
				if city and city.player_owner == player_owner:
					return true
	return false

func _find_tile_needing_improvement():
	if player_owner == null:
		return null

	var best_tile = null
	var best_score = -1
	var best_distance = INF

	# Search tiles in player's territory
	for city in player_owner.cities:
		for tile_pos in city.territory:
			var tile = GameManager.hex_grid.get_tile(tile_pos) if GameManager.hex_grid else null
			if tile == null:
				continue

			# Skip tiles with workers already
			var has_worker = false
			for unit in player_owner.units:
				if unit != self and unit.grid_position == tile_pos and unit.can_build_improvements():
					has_worker = true
					break
			if has_worker:
				continue

			var improvement = _find_best_improvement(tile)
			if improvement != "":
				var score = _score_improvement(tile, improvement)
				var dist = GridUtils.chebyshev_distance(grid_position, tile_pos)
				if score > best_score or (score == best_score and dist < best_distance):
					best_score = score
					best_distance = dist
					best_tile = tile

	return best_tile

func _score_improvement(tile, improvement: String) -> int:
	var score = 10  # Base score

	# Resources are highest priority
	if tile.resource != "":
		score += 50

	# Closer to city is better
	if tile.city_owner:
		var dist = GridUtils.chebyshev_distance(tile.grid_position, tile.city_owner.grid_position)
		score += max(0, 10 - dist * 2)

	# Food improvements near small cities
	if improvement == "farm" and tile.city_owner and tile.city_owner.population < 6:
		score += 20

	return score

# =============================================================================
# EXPLORER AUTOMATION
# =============================================================================

func can_automate_explore() -> bool:
	var unit_class = get_unit_class()
	return unit_class in ["recon", "naval"] or "ignore_terrain_cost" in get_abilities()

func automate_explore() -> void:
	if not can_automate_explore():
		return
	current_order = UnitOrder.EXPLORE
	EventBus.unit_order_changed.emit(self, current_order)
	# Process exploration immediately if we have movement
	if movement_remaining > 0:
		process_explore_automation()
	update_visual()

func stop_explore_automation() -> void:
	if current_order == UnitOrder.EXPLORE:
		current_order = UnitOrder.NONE
		EventBus.unit_order_changed.emit(self, current_order)
		update_visual()

func process_explore_automation() -> void:
	if current_order != UnitOrder.EXPLORE:
		return
	if movement_remaining <= 0 or has_acted:
		return
	if GameManager.hex_grid == null or player_owner == null:
		return

	# Find the best unexplored tile to move to
	var target_pos = _find_best_explore_target()
	if target_pos == Vector2i(-1, -1):
		# No unexplored tiles reachable - stop exploring
		stop_explore_automation()
		return

	# Move toward target
	var pathfinder = PathfindingClass.new(GameManager.hex_grid, self)
	var path = pathfinder.find_path_with_movement(grid_position, target_pos, movement_remaining)
	if path.size() > 0:
		move_along_path(path)

func _find_best_explore_target() -> Vector2i:
	var best_tile = Vector2i(-1, -1)
	var best_score = -INF
	var sight_range = get_sight_range()

	# Search for tiles that would reveal the most fog
	var search_radius = 15  # How far to search for explore targets
	var center = grid_position

	for dx in range(-search_radius, search_radius + 1):
		for dy in range(-search_radius, search_radius + 1):
			var check_pos = Vector2i(center.x + dx, center.y + dy)

			# Wrap X coordinate for cylindrical map
			if GameManager.hex_grid:
				check_pos.x = posmod(check_pos.x, GameManager.hex_grid.width)

			if not GameManager.hex_grid.is_valid_position(check_pos):
				continue

			var tile = GameManager.hex_grid.get_tile(check_pos)
			if tile == null:
				continue

			# Skip impassable tiles
			if not tile.is_passable():
				continue

			# Skip water for land units
			if tile.is_water() and get_unit_class() != "naval":
				continue

			# Skip land for naval units (unless coastal)
			if not tile.is_water() and get_unit_class() == "naval":
				continue

			# Score this tile based on fog it would reveal
			var score = _score_explore_tile(check_pos, sight_range)
			var distance = GridUtils.chebyshev_distance(grid_position, check_pos)

			# Prefer closer tiles with high reveal potential
			score -= distance * 0.5

			if score > best_score:
				best_score = score
				best_tile = check_pos

	return best_tile

func _score_explore_tile(tile_pos: Vector2i, sight_range: int) -> float:
	var score = 0.0

	if player_owner == null or GameManager.hex_grid == null:
		return score

	# Count fog tiles that would be revealed from this position
	var tiles_to_check = GridUtils.get_tiles_in_range(tile_pos, sight_range)
	tiles_to_check.append(tile_pos)

	for check_pos in tiles_to_check:
		if not GameManager.hex_grid.is_valid_position(check_pos):
			continue

		var tile = GameManager.hex_grid.get_tile(check_pos)
		if tile == null:
			continue

		# Check visibility status for this player
		var visibility = tile.get_visibility(player_owner.player_id)
		if visibility == 0:  # HIDDEN - fog of war
			score += 2.0
		elif visibility == 1:  # REVEALED - seen before but not currently visible
			score += 0.5

	# Bonus for goody huts / ancient ruins
	var center_tile = GameManager.hex_grid.get_tile(tile_pos)
	if center_tile and center_tile.get_meta("goody_hut", false):
		score += 20.0

	return score

func get_sight_range() -> int:
	var unit_data = DataManager.get_unit(unit_id)
	var base_range = unit_data.get("sight_range", 1)

	# Check for promotions that increase sight range
	for promo in promotions:
		var effects = DataManager.get_promotion_effects(promo)
		base_range += effects.get("visibility_range_increase", 0)

	return base_range

# Special abilities
func can_found_city() -> bool:
	return "found_city" in get_abilities()

func can_build_improvements() -> bool:
	return "build_improvements" in get_abilities()

func can_spread_religion() -> bool:
	if "spread_religion" not in get_abilities():
		return false
	# Check if unit has uses remaining
	var unit_data = DataManager.get_unit(unit_id)
	var max_uses = unit_data.get("uses", -1)
	if max_uses > 0:
		var uses_remaining = get_meta("uses_remaining", max_uses)
		if uses_remaining <= 0:
			return false
	# Check if we're in a city
	var city = GameManager.get_city_at(grid_position)
	if city == null:
		return false
	# Check if city already has our religion
	if player_owner == null or player_owner.state_religion == "":
		return false
	if player_owner.state_religion in city.religions:
		return false
	# Check if target city's owner has Theocracy (blocks non-state religion spread)
	if city.player_owner != null:
		if CivicsSystem.has_civic_effect(city.player_owner, "no_non_state_religion_spread"):
			# Can only spread if it matches the city owner's state religion
			if player_owner.state_religion != city.player_owner.state_religion:
				return false
	return true

func spread_religion() -> bool:
	if not can_spread_religion():
		return false
	if player_owner == null or player_owner.state_religion == "":
		return false

	var city = GameManager.get_city_at(grid_position)
	if city == null:
		return false

	# Spread the state religion
	ReligionSystem.spread_religion(city, player_owner.state_religion)

	# Consume a use
	var unit_data = DataManager.get_unit(unit_id)
	var max_uses = unit_data.get("uses", -1)
	if max_uses > 0:
		var uses_remaining = get_meta("uses_remaining", max_uses)
		uses_remaining -= 1
		set_meta("uses_remaining", uses_remaining)
		if uses_remaining <= 0:
			die()  # Unit is consumed after all uses

	has_acted = true
	movement_remaining = 0
	return true

# Transport functions
func is_transport() -> bool:
	var unit_data = DataManager.get_unit(unit_id)
	return unit_data.get("transport_capacity", 0) > 0

func get_transport_capacity() -> int:
	var unit_data = DataManager.get_unit(unit_id)
	return unit_data.get("transport_capacity", 0)

func is_loaded() -> bool:
	return transport != null

func can_load_unit(unit) -> bool:
	if unit == null or unit == self:
		return false
	# Must be a transport
	if not is_transport():
		return false
	# Unit must be at same position
	if unit.grid_position != grid_position:
		return false
	# Unit must be owned by same player
	if unit.player_owner != player_owner:
		return false
	# Unit must not be a naval/air unit (only land units can load)
	var unit_data = DataManager.get_unit(unit.unit_id)
	var unit_class = unit_data.get("unit_class", "")
	if unit_class in ["naval", "air"]:
		return false
	# Unit must not already be loaded
	if unit.is_loaded():
		return false
	# Must have space
	if cargo.size() >= get_transport_capacity():
		return false
	return true

func load_unit(unit) -> bool:
	if not can_load_unit(unit):
		return false

	cargo.append(unit)
	unit.transport = self
	unit.visible = false  # Hide loaded unit
	EventBus.unit_loaded.emit(unit, self)
	return true

func can_unload_unit(unit) -> bool:
	if unit == null or unit not in cargo:
		return false
	# Must be at a valid land tile for the unit
	var tile = GameManager.hex_grid.get_tile(grid_position) if GameManager.hex_grid else null
	if tile == null:
		return false
	# Check if unit can be on this terrain
	var terrain = tile.terrain_type
	# Naval transport must be in coast/ocean adjacent to land
	if terrain in ["coast", "ocean"]:
		# Check for adjacent land tile to unload to
		var neighbors = GridUtils.get_neighbors(grid_position)
		for neighbor_pos in neighbors:
			var neighbor_tile = GameManager.hex_grid.get_tile(neighbor_pos) if GameManager.hex_grid else null
			if neighbor_tile and neighbor_tile.terrain_type not in ["coast", "ocean"]:
				return true
		return false
	return true

func unload_unit(unit, target_pos: Vector2i = Vector2i(-1, -1)) -> bool:
	if unit not in cargo:
		return false

	# Find a valid position to unload
	if target_pos == Vector2i(-1, -1):
		target_pos = _find_unload_position()

	if target_pos == Vector2i(-1, -1):
		return false

	cargo.erase(unit)
	unit.transport = null
	unit.grid_position = target_pos
	unit.position = GridUtils.grid_to_pixel(target_pos)
	unit.visible = true
	unit.movement_remaining = 0  # Unloading uses all movement
	unit.has_acted = true
	EventBus.unit_unloaded.emit(unit, self)
	return true

func unload_all() -> int:
	var unloaded = 0
	var units_to_unload = cargo.duplicate()
	for unit in units_to_unload:
		if unload_unit(unit):
			unloaded += 1
	return unloaded

func _find_unload_position() -> Vector2i:
	var tile = GameManager.hex_grid.get_tile(grid_position) if GameManager.hex_grid else null
	if tile == null:
		return Vector2i(-1, -1)

	# If transport is on land (somehow), unload here
	if tile.terrain_type not in ["coast", "ocean"]:
		return grid_position

	# Find adjacent land tile
	var neighbors = GridUtils.get_neighbors(grid_position)
	for neighbor_pos in neighbors:
		var neighbor_tile = GameManager.hex_grid.get_tile(neighbor_pos) if GameManager.hex_grid else null
		if neighbor_tile and neighbor_tile.terrain_type not in ["coast", "ocean", "mountains"]:
			# Check for enemy units
			var enemy_there = false
			for player in GameManager.players:
				if player != player_owner and player_owner.is_at_war_with(player.player_id):
					for enemy_unit in player.units:
						if enemy_unit.grid_position == neighbor_pos:
							enemy_there = true
							break
				if enemy_there:
					break
			if not enemy_there:
				return neighbor_pos

	return Vector2i(-1, -1)

# Selection
func select() -> void:
	is_selected = true
	wake()  # Wake up if sleeping
	update_visual()
	unit_selected.emit(self)
	EventBus.unit_selected.emit(self)

func deselect() -> void:
	is_selected = false
	update_visual()
	EventBus.unit_deselected.emit(self)

# Serialization
func to_dict() -> Dictionary:
	return {
		"unit_id": unit_id,
		"owner_id": player_owner.player_id if player_owner else -1,
		"grid_position": {"x": grid_position.x, "y": grid_position.y},
		"health": health,
		"experience": experience,
		"level": level,
		"movement_remaining": movement_remaining,
		"is_fortified": is_fortified,
		"fortify_bonus": fortify_bonus,
		"promotions": promotions,
		"current_order": current_order,
		"order_target_improvement": order_target_improvement,
		"build_progress": build_progress,
	}

func from_dict(data: Dictionary) -> void:
	unit_id = data.get("unit_id", "warrior")
	grid_position = Vector2i(data.grid_position.x, data.grid_position.y)
	health = data.get("health", 100.0)
	experience = data.get("experience", 0)
	level = data.get("level", 1)
	movement_remaining = data.get("movement_remaining", 0.0)
	is_fortified = data.get("is_fortified", false)
	fortify_bonus = data.get("fortify_bonus", 0.0)
	promotions.assign(data.get("promotions", []))
	current_order = data.get("current_order", UnitOrder.NONE)
	order_target_improvement = data.get("order_target_improvement", "")
	build_progress = data.get("build_progress", 0)
	position = GridUtils.grid_to_pixel(grid_position)
	update_visual()
