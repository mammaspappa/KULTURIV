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

# AI position history — for detecting oscillation and stuck units.
# Length is configurable via tunables/units.json (units.position_history_length).
var _position_history: Array[Vector2i] = []
var _stuck_turns: int = 0  # Consecutive turns at same position

func _max_history() -> int:
	return int(DataManager.get_tunable("units.position_history_length", 6))

## Record position at end of AI turn. Call after AI processes this unit.
func record_position() -> void:
	_position_history.append(grid_position)
	if _position_history.size() > _max_history():
		_position_history.pop_front()
	# Track stuck turns
	if _position_history.size() >= 2 and _position_history[-1] == _position_history[-2]:
		_stuck_turns += 1
	else:
		_stuck_turns = 0

## Detect if unit is oscillating between 2-3 positions.
## Requires a clear A-B-A-B pattern (4 turns of strict swapping) — workers
## legitimately revisit tiles for chained improvements so a one-off A-B-A
## is NOT enough. The strict guard in ai_controller relies on this firing
## only when the unit is genuinely stuck in a loop.
func is_oscillating() -> bool:
	var h = _position_history
	var n = h.size()
	if n < 4:
		return false
	# Strict A-B-A-B pattern (4 turns, alternating exactly 2 positions)
	if h[n-1] == h[n-3] and h[n-2] == h[n-4] and h[n-1] != h[n-2]:
		return true
	# A-B-C-A-B-C pattern (3-position cycle)
	if n >= 6 and h[n-1] == h[n-4] and h[n-2] == h[n-5] and h[n-3] == h[n-6]:
		return true
	return false

## Pick a random non-recent neighbor tile to break oscillation.
## Returns Vector2i(-1,-1) if no valid escape exists.
func pick_anti_oscillation_target() -> Vector2i:
	var grid = GameManager.hex_grid if GameManager else null
	if grid == null:
		return Vector2i(-1, -1)
	var recent = {}
	for p in _position_history:
		recent[p] = true
	var neighbors = GridUtils.get_neighbors(grid_position)
	neighbors.shuffle()
	# First pass: find a passable neighbor we haven't been to
	for n_pos in neighbors:
		if recent.has(n_pos):
			continue
		var tile = grid.get_tile(n_pos)
		if tile == null or not tile.is_passable():
			continue
		if tile.is_water() and get_unit_class() != "naval":
			continue
		if not tile.is_water() and get_unit_class() == "naval":
			continue
		return n_pos
	# Second pass: any passable neighbor (even recent), as long as it's not
	# the position we were on last turn
	var last = _position_history[-1] if _position_history.size() >= 1 else grid_position
	for n_pos in neighbors:
		if n_pos == last:
			continue
		var tile = grid.get_tile(n_pos)
		if tile == null or not tile.is_passable():
			continue
		if tile.is_water() and get_unit_class() != "naval":
			continue
		if not tile.is_water() and get_unit_class() == "naval":
			continue
		return n_pos
	return Vector2i(-1, -1)

## Check if unit has been stuck (same position) for N turns
func is_stuck(turns: int = 3) -> bool:
	return _stuck_turns >= turns

## Get set of recently visited positions (for avoidance)
func get_recent_positions() -> Array[Vector2i]:
	return _position_history.duplicate()

# Transport/Cargo
var cargo: Array = []  # Units being transported
var transport: Node2D = null  # Reference to transport unit if loaded

# Promotions
var promotions: Array[String] = []

# Great General attachment. Bonuses are configured in tunables/units.json (units.great_general.*).
var attached_great_general: Node2D = null  # Reference to attached Great General unit

func _great_general_combat_bonus() -> float:
	return float(DataManager.get_tunable("units.great_general.combat_bonus", 0.20))

func _great_general_xp_bonus() -> float:
	return float(DataManager.get_tunable("units.great_general.xp_bonus", 0.50))

# Visual
const TILE_SIZE: int = 64
var is_selected: bool = false

# Unit icon texture cache (loaded once, shared by all units)
static var _unit_textures_loaded: bool = false
static var unit_textures: Dictionary = {}

static func _load_unit_textures() -> void:
	if _unit_textures_loaded:
		return
	_unit_textures_loaded = true
	var dir = DirAccess.open("res://assets/units/")
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".png"):
			var uid = file_name.replace(".png", "")
			var path = "res://assets/units/%s" % file_name
			if ResourceLoader.exists(path):
				unit_textures[uid] = load(path)
		file_name = dir.get_next()

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
	_load_unit_textures()

func _ready() -> void:
	update_visual()

func _draw() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var unit_data = DataManager.get_unit(unit_id)
	var symbol = unit_data.get("symbol", "?")
	var unit_class = unit_data.get("unit_class", "melee")

	# Background circle color based on owner
	var bg_color = player_owner.color if player_owner else Color.GRAY
	draw_circle(Vector2.ZERO, 24, bg_color)

	# Border for selection
	if is_selected:
		draw_arc(Vector2.ZERO, 26, 0, TAU, 32, Color.WHITE, 3.0)

	# Unit icon
	_draw_unit_icon(Vector2.ZERO, unit_class, symbol)

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
	var font = ThemeDB.fallback_font
	if is_fortified:
		var shield_pos = Vector2(15, -15)
		draw_string(font, shield_pos, "⛨", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.CYAN)

	# Great General attachment indicator
	if attached_great_general != null:
		var general_pos = Vector2(-20, -15)
		draw_string(font, general_pos, "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.GOLD)

	# Movement points indicator
	if movement_remaining > 0:
		var move_text = str(int(movement_remaining))
		draw_string(font, Vector2(15, 20), move_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _draw_unit_icon(center: Vector2, unit_class: String, symbol: String) -> void:
	# Try to draw texture icon if available
	if unit_id in unit_textures:
		var tex = unit_textures[unit_id]
		var icon_size = 32.0
		var draw_pos = center - Vector2(icon_size / 2, icon_size / 2)
		draw_texture_rect(tex, Rect2(draw_pos, Vector2(icon_size, icon_size)), false)
		return

	# Fallback: procedural geometric drawing
	var col = Color.WHITE
	var lw = 2.0  # line width

	match unit_class:
		"melee":
			# Sword: vertical blade + crossguard + grip
			draw_rect(Rect2(center.x - 1, center.y - 10, 2, 16), col)  # blade
			draw_rect(Rect2(center.x - 4, center.y + 2, 8, 2), col)   # crossguard
			draw_rect(Rect2(center.x - 1, center.y + 6, 2, 5), col)   # grip
			# Pommel dot
			draw_circle(center + Vector2(0, 12), 1.5, col)

		"archery":
			# Bow: curved arc + string line
			draw_arc(center + Vector2(-3, 0), 10, -PI / 3, PI / 3, 16, col, lw)
			# String (straight line from arc endpoints)
			var string_top = center + Vector2(-3, 0) + Vector2(10 * cos(-PI / 3), 10 * sin(-PI / 3))
			var string_bot = center + Vector2(-3, 0) + Vector2(10 * cos(PI / 3), 10 * sin(PI / 3))
			draw_line(string_top, string_bot, col, lw)
			# Arrow
			draw_line(center + Vector2(-8, 0), center + Vector2(8, 0), col, lw)
			# Arrowhead
			draw_line(center + Vector2(8, 0), center + Vector2(5, -3), col, lw)
			draw_line(center + Vector2(8, 0), center + Vector2(5, 3), col, lw)

		"mounted":
			# Chevron / inverted V (horseshoe shape)
			draw_line(center + Vector2(-8, 8), center + Vector2(0, -8), col, lw)
			draw_line(center + Vector2(0, -8), center + Vector2(8, 8), col, lw)
			# Second inner chevron for emphasis
			draw_line(center + Vector2(-5, 5), center + Vector2(0, -3), col, lw)
			draw_line(center + Vector2(0, -3), center + Vector2(5, 5), col, lw)

		"gunpowder":
			# Musket: long diagonal barrel + angled stock
			draw_line(center + Vector2(-10, 6), center + Vector2(8, -8), col, lw)  # barrel
			draw_line(center + Vector2(-10, 6), center + Vector2(-6, 12), col, lw)  # stock
			# Trigger guard
			draw_line(center + Vector2(-4, 4), center + Vector2(-3, 7), col, 1.5)

		"armor":
			# Tank: body rectangle + turret + barrel
			draw_rect(Rect2(center.x - 10, center.y - 2, 20, 10), col, false, lw)  # body
			draw_rect(Rect2(center.x - 5, center.y - 7, 10, 6), col, false, lw)    # turret
			draw_line(center + Vector2(5, -5), center + Vector2(14, -5), col, lw)   # barrel
			# Treads (bottom lines)
			draw_line(center + Vector2(-10, 9), center + Vector2(10, 9), col, lw)

		"siege":
			# Wheel + barrel/arm
			draw_arc(center + Vector2(-3, 3), 7, 0, TAU, 20, col, lw)  # wheel
			# Spokes
			draw_line(center + Vector2(-3, 3), center + Vector2(-3, -4), col, 1.0)
			draw_line(center + Vector2(-3, 3), center + Vector2(4, 3), col, 1.0)
			# Barrel pointing up-right
			draw_line(center + Vector2(2, -1), center + Vector2(12, -10), col, lw)

		"naval":
			# Hull (filled half-oval polygon)
			var hull_points = PackedVector2Array()
			hull_points.append(center + Vector2(-12, 0))
			for i in range(9):
				var angle = PI + (PI * i / 8.0)
				hull_points.append(center + Vector2(cos(angle) * 12, sin(angle) * 6 + 3))
			hull_points.append(center + Vector2(12, 0))
			draw_colored_polygon(hull_points, col)
			# Mast
			draw_line(center + Vector2(0, 0), center + Vector2(0, -12), col, lw)
			# Sail (small triangle)
			var sail = PackedVector2Array([
				center + Vector2(0, -11),
				center + Vector2(8, -6),
				center + Vector2(0, -3)
			])
			draw_colored_polygon(sail, col)

		"recon":
			# Eye shape: two arcs forming almond shape + center dot
			# Upper arc (curved up)
			draw_arc(center + Vector2(0, 8), 12, -1.1, -PI + 1.1, 16, col, lw)
			# Lower arc (curved down)
			draw_arc(center + Vector2(0, -8), 12, 1.1, PI - 1.1, 16, col, lw)
			# Pupil
			draw_circle(center, 3, col)

		"civilian":
			_draw_civilian_icon(center, col, lw)

		_:
			# Fallback: draw the text symbol
			var font = ThemeDB.fallback_font
			var font_size = 24
			var text_size = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos = center + Vector2(-text_size.x / 2, text_size.y / 4)
			draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_civilian_icon(center: Vector2, col: Color, lw: float) -> void:
	match unit_id:
		"settler":
			# House: rectangle base + triangle roof
			draw_rect(Rect2(center.x - 7, center.y - 2, 14, 10), col, false, lw)
			var roof = PackedVector2Array([
				center + Vector2(-9, -2),
				center + Vector2(0, -11),
				center + Vector2(9, -2)
			])
			draw_polyline(roof, col, lw)
			# Door
			draw_rect(Rect2(center.x - 2, center.y + 3, 4, 5), col, false, lw)

		"worker":
			# Crossed tools: X shape with thicker ends
			draw_line(center + Vector2(-8, -8), center + Vector2(8, 8), col, lw)
			draw_line(center + Vector2(8, -8), center + Vector2(-8, 8), col, lw)
			# Thicker ends (tool heads)
			draw_circle(center + Vector2(-8, -8), 2.5, col)
			draw_circle(center + Vector2(8, -8), 2.5, col)
			draw_circle(center + Vector2(-8, 8), 2.5, col)
			draw_circle(center + Vector2(8, 8), 2.5, col)

		"missionary", "inquisitor":
			# Cross shape
			draw_rect(Rect2(center.x - 2, center.y - 11, 4, 20), col)  # vertical bar
			draw_rect(Rect2(center.x - 7, center.y - 6, 14, 4), col)   # horizontal bar

		"spy":
			# Target/eye: circle with crosshairs
			draw_arc(center, 7, 0, TAU, 20, col, lw)
			draw_line(center + Vector2(-10, 0), center + Vector2(10, 0), col, 1.5)
			draw_line(center + Vector2(0, -10), center + Vector2(0, 10), col, 1.5)
			draw_circle(center, 2.5, col)

		_:
			# Fallback: draw the text symbol
			var font = ThemeDB.fallback_font
			var font_size = 24
			var symbol = DataManager.get_unit(unit_id).get("symbol", "?")
			var text_size = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos = center + Vector2(-text_size.x / 2, text_size.y / 4)
			draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


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
	is_moving = false  # Reset animation state (tweens may not complete in headless)
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

	# Check for enemy units (non-warring civs can share tiles per Civ4 BTS rules)
	var units_at_target = GameManager.get_units_at(target)
	for other_unit in units_at_target:
		if other_unit.player_owner != player_owner and other_unit.player_owner != null:
			if player_owner != null and player_owner.is_at_war_with(other_unit.player_owner.player_id):
				return false  # Enemy unit blocks movement - must attack instead

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

	# Own territory
	if tile.tile_owner == player_owner:
		return true

	# Need open borders or war to enter foreign territory
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

	# Normalize target on wrapping axes — otherwise raw negative coordinates
	# accumulate forever and break pathfinding (each non-normalized position
	# looks unique to A*'s closed set, blowing up the search space).
	target = grid._wrap_position(target)

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
## Combat math has been extracted to UnitCombatHelper. This method remains as a thin
## façade so existing call sites (`unit.get_combat_strength(...)`) continue to work.
func get_combat_strength(is_attacking: bool, target_tile = null, defender = null) -> float:
	return UnitCombatHelper.get_combat_strength(self, is_attacking, target_tile, defender)

func _direction_to_edge(dx: int, dy: int) -> int:
	return UnitCombatHelper.direction_to_edge(dx, dy)

func get_first_strikes() -> int:
	return UnitCombatHelper.get_first_strikes(self)

func get_withdraw_chance() -> float:
	return UnitCombatHelper.get_withdraw_chance(self)

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

## Whether this unit is being consumed (e.g., settler founding city), not killed in combat
var _consumed: bool = false

func consume() -> void:
	"""Remove unit without emitting unit_destroyed (used for settlers founding cities, etc.)."""
	_consumed = true
	die()

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

	if not _consumed:
		EventBus.unit_destroyed.emit(self)
	if player_owner:
		player_owner.remove_unit(self)
	queue_free()

# Experience and promotions
func gain_experience(amount: int) -> void:
	var xp_amount = amount
	# Great General attachment gives bonus XP
	if attached_great_general != null:
		xp_amount = int(amount * (1.0 + _great_general_xp_bonus()))
	experience += xp_amount
	_check_level_up()

func _check_level_up() -> void:
	var xp_needed = _xp_for_next_level()
	while experience >= xp_needed:
		level += 1
		xp_needed = _xp_for_next_level()

func _xp_for_next_level() -> int:
	# Civ4 BTS XP thresholds: 2, 5, 10, 17, 26, 37...
	return level * level + 1

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

# Unit upgrades
func get_upgrade_target() -> String:
	var unit_data = DataManager.get_unit(unit_id)
	return unit_data.get("upgrades_to", "")

func can_upgrade() -> bool:
	var target = get_upgrade_target()
	if target == "":
		return false
	if player_owner == null:
		return false
	# Must be in a friendly city
	var city = GameManager.get_city_at(grid_position)
	if city == null or city.player_owner != player_owner:
		return false
	# Must have the tech for the target unit
	var target_data = DataManager.get_unit(target)
	var required_tech = target_data.get("required_tech", "")
	if required_tech != "" and not player_owner.has_tech(required_tech):
		return false
	# Must afford it
	if player_owner.gold < get_upgrade_cost():
		return false
	return true

func get_upgrade_cost() -> int:
	var target = get_upgrade_target()
	if target == "":
		return 0
	var current_cost = DataManager.get_unit_cost(unit_id)
	var target_cost = DataManager.get_unit_cost(target)
	return int(max(15, (target_cost - current_cost) * 1.5))

func upgrade() -> bool:
	if not can_upgrade():
		return false
	var target = get_upgrade_target()
	var cost = get_upgrade_cost()
	player_owner.gold -= cost
	# Keep experience, promotions, health
	unit_id = target
	# Refresh movement
	movement_remaining = 0
	has_acted = true
	EventBus.notification_added.emit("Unit upgraded to %s" % DataManager.get_unit(target).get("name", target))
	update_visual()
	queue_redraw()
	return true

# Unit disbanding
func disband() -> void:
	if player_owner == null:
		return
	var refund = DataManager.get_unit_cost(unit_id) / 2
	player_owner.gold += refund
	EventBus.notification_added.emit("Unit disbanded for %d gold" % refund)
	die()

# Paradrop ability
func can_paradrop() -> bool:
	if has_acted or movement_remaining <= 0:
		return false
	var abilities = DataManager.get_unit(unit_id).get("abilities", [])
	return "paradrop" in abilities

func get_paradrop_range() -> int:
	return DataManager.get_unit(unit_id).get("paradrop_range", 5)

func paradrop(target: Vector2i) -> bool:
	if not can_paradrop():
		return false

	# Check range from any friendly city
	var in_range = false
	for city in player_owner.cities:
		if GridUtils.chebyshev_distance(city.grid_position, target) <= get_paradrop_range():
			in_range = true
			break

	if not in_range:
		return false

	# Target must be passable land with no enemy unit
	var tile = GameManager.hex_grid.get_tile(target) if GameManager.hex_grid else null
	if tile == null or tile.is_water() or not tile.is_passable():
		return false
	if GameManager.get_unit_at(target) != null:
		return false

	# Execute paradrop
	var from_pos = grid_position
	grid_position = target
	position = GridUtils.grid_to_pixel(target)
	movement_remaining = 0
	has_acted = true
	update_visual()
	EventBus.unit_moved.emit(self, from_pos, target)
	return true

# Airlift ability
func can_be_airlifted() -> bool:
	if has_acted or movement_remaining <= 0:
		return false
	var unit_data = DataManager.get_unit(unit_id)
	if unit_data.get("unit_class", "") in ["air", "naval"]:
		return false  # Only land units
	# Must be in a city with airport
	var city = GameManager.get_city_at(grid_position)
	if city == null or city.player_owner != player_owner:
		return false
	if "airport" not in city.buildings:
		return false
	return true

func airlift_to(target_city) -> bool:
	if not can_be_airlifted():
		return false
	if target_city == null or target_city.player_owner != player_owner:
		return false
	if "airport" not in target_city.buildings:
		return false
	if target_city.grid_position == grid_position:
		return false

	var from_pos = grid_position
	grid_position = target_city.grid_position
	position = GridUtils.grid_to_pixel(grid_position)
	movement_remaining = 0
	has_acted = true
	update_visual()
	EventBus.unit_moved.emit(self, from_pos, grid_position)
	EventBus.notification_added.emit("Unit airlifted to %s" % target_city.city_name)
	return true

# Great General attachment
func can_attach_great_general(general) -> bool:
	if general == null or general == self:
		return false
	# General must be a Great General unit type
	var general_data = DataManager.get_unit(general.unit_id)
	if general_data.get("great_person_type", "") != "great_general":
		return false
	# Must be same owner
	if general.player_owner != player_owner:
		return false
	# This unit must be military (not civilian)
	var unit_data = DataManager.get_unit(unit_id)
	var unit_class = unit_data.get("unit_class", "")
	if unit_class in ["civilian", "work_boat"]:
		return false
	# This unit must not already have a general attached
	if attached_great_general != null:
		return false
	# General must be at same position or adjacent
	var distance = GridUtils.chebyshev_distance(grid_position, general.grid_position)
	if distance > 1:
		return false
	return true

func attach_great_general(general) -> bool:
	if not can_attach_great_general(general):
		return false

	attached_great_general = general
	# The general unit is consumed when attached
	general.visible = false
	if general.player_owner:
		general.player_owner.remove_unit(general)
	general.queue_free()

	update_visual()
	return true

func detach_great_general() -> void:
	# Great Generals cannot be detached once attached (they're consumed)
	# This function exists for edge cases or if future design changes
	attached_great_general = null
	update_visual()

func has_attached_great_general() -> bool:
	return attached_great_general != null

# Orders
func fortify() -> void:
	current_order = UnitOrder.FORTIFY
	is_fortified = true
	movement_remaining = 0
	has_acted = true
	EventBus.unit_order_changed.emit(self, current_order)
	update_visual()
	EventBus.unit_action_completed.emit(self)

func sleep() -> void:
	current_order = UnitOrder.SLEEP
	is_sleeping = true
	movement_remaining = 0
	has_acted = true
	EventBus.unit_order_changed.emit(self, current_order)
	update_visual()
	EventBus.unit_action_completed.emit(self)

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
	EventBus.unit_action_completed.emit(self)

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
## Save / load delegated to UnitSerializer (Phase 5 extraction).
## Wrapper methods preserve the public API (`unit.to_dict()` / `unit.from_dict(data)`).
func to_dict() -> Dictionary:
	return UnitSerializer.to_dict(self)

func from_dict(data: Dictionary) -> void:
	UnitSerializer.from_dict(self, data)
