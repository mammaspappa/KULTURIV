class_name Unit
extends Node2D
## Represents a single unit on the map.

const GameTileClass = preload("res://scripts/map/game_tile.gd")

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
enum UnitOrder { NONE, FORTIFY, SLEEP, SENTRY, HEAL, EXPLORE, BUILD, GOTO }
var current_order: UnitOrder = UnitOrder.NONE
var order_target: Vector2i = Vector2i.ZERO
var order_target_improvement: String = ""
var build_progress: int = 0

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

	return true

func _can_enter_water() -> bool:
	var unit_class = get_unit_class()
	return unit_class == "naval"

func move_to(target: Vector2i) -> bool:
	if not can_move_to(target):
		return false

	var grid = GameManager.hex_grid
	var tile = grid.get_tile(target)
	var move_cost = tile.get_total_movement_cost()

	# Check if we have enough movement
	if movement_remaining < move_cost and movement_remaining < 1:
		return false

	var old_pos = grid_position
	grid_position = target

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

# Special abilities
func can_found_city() -> bool:
	return "found_city" in get_abilities()

func can_build_improvements() -> bool:
	return "build_improvements" in get_abilities()

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
