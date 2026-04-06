class_name GameTile
extends Node2D
## Represents a single tile on the game map.

# Tile position in grid coordinates
var grid_position: Vector2i = Vector2i.ZERO

# Terrain and features
var terrain_id: String = "grassland"
var feature_id: String = ""
var resource_id: String = ""
var improvement_id: String = ""
var road_level: int = 0  # 0=none, 1=road, 2=railroad
var has_goody_hut: bool = false  # Tribal village (discoverable bonus)

# Ownership (untyped to avoid circular dependency)
var tile_owner = null  # Player
var city_owner = null  # City that works this tile

# Visibility (per player)
var visibility: Dictionary = {}  # player_id -> VisibilityState

# Improvement progress
var improvement_progress: int = 0

# Constants
const TILE_SIZE: int = 64

enum VisibilityState { UNEXPLORED, FOGGED, VISIBLE }

func _init(pos: Vector2i = Vector2i.ZERO) -> void:
	grid_position = pos
	position = GridUtils.grid_to_pixel_corner(grid_position)
func _draw() -> void:
	# Check visibility for human player
	var human_player = GameManager.human_player
	var vis_state = VisibilityState.VISIBLE  # Default to visible if no human player
	if human_player != null:
		vis_state = get_visibility_for_player(human_player.player_id)

	# Don't render unexplored tiles
	if vis_state == VisibilityState.UNEXPLORED:
		draw_rect(Rect2(0, 0, TILE_SIZE, TILE_SIZE), Color.BLACK)
		return

	_draw_terrain()
	_draw_feature()

	# Only show resources, improvements, roads if explored
	if vis_state == VisibilityState.VISIBLE:
		_draw_resource()
		_draw_improvement()
		_draw_road()
		_draw_goody_hut()
		_draw_owner_border()
	else:
		# Fogged - show known improvements but not resources
		_draw_improvement()
		_draw_road()
		_draw_goody_hut()

	# Apply fog overlay for fogged tiles
	if vis_state == VisibilityState.FOGGED:
		draw_rect(Rect2(0, 0, TILE_SIZE, TILE_SIZE), Color(0, 0, 0, 0.5))

func _draw_terrain() -> void:
	var color = DataManager.get_terrain_color(terrain_id)

	# Per-tile brightness variation to break up the flat grid look
	var hash_val = (grid_position.x * 7 + grid_position.y * 13) % 20
	var brightness = 0.95 + float(hash_val) / 200.0  # Range 0.95 to 1.05
	color = Color(
		clampf(color.r * brightness, 0.0, 1.0),
		clampf(color.g * brightness, 0.0, 1.0),
		clampf(color.b * brightness, 0.0, 1.0),
		color.a
	)

	# Draw base terrain rectangle
	draw_rect(Rect2(0, 0, TILE_SIZE, TILE_SIZE), color)

	# Terrain-specific decorations
	match terrain_id:
		"grassland":
			_draw_grassland_details(color)
		"plains":
			_draw_grassland_details(color)  # Similar subtle dots
		"desert":
			_draw_desert_details(color)
		"hills":
			_draw_hills_details(color)
		"mountains":
			_draw_mountain_details()
		"coast":
			_draw_coast_details(color)
		"ocean":
			_draw_ocean_details(color)
		"snow":
			_draw_snow_details()
		"tundra":
			_draw_tundra_details()

	# Soft 1px darkened edges instead of hard grid lines
	var edge_color = Color(
		color.r * 0.8,
		color.g * 0.8,
		color.b * 0.8,
		0.5
	)
	draw_rect(Rect2(0, 0, TILE_SIZE, TILE_SIZE), edge_color, false, 1.0)

func _draw_grassland_details(base_color: Color) -> void:
	# Draw 3-5 small dark green dots at deterministic pseudo-random positions
	var dot_color = Color(base_color.r * 0.7, base_color.g * 0.85, base_color.b * 0.6)
	var seed_val = grid_position.x * 31 + grid_position.y * 17
	var dot_count = 3 + (seed_val % 3)  # 3 to 5
	for i in dot_count:
		var px = 8 + ((seed_val * (i + 1) * 7 + 13) % (TILE_SIZE - 16))
		var py = 8 + ((seed_val * (i + 1) * 11 + 23) % (TILE_SIZE - 16))
		draw_circle(Vector2(px, py), 1.5, dot_color)

func _draw_desert_details(base_color: Color) -> void:
	# Draw 2 subtle wavy horizontal lines in slightly darker tan
	var line_color = Color(base_color.r * 0.9, base_color.g * 0.88, base_color.b * 0.85, 0.5)
	for i in 2:
		var y_base = 18.0 + i * 20.0
		var prev_point = Vector2(0, y_base)
		for seg in range(1, 9):
			var x = seg * 8.0
			var wave_offset = sin(float(seg + grid_position.x * 3 + i * 5)) * 2.5
			var next_point = Vector2(x, y_base + wave_offset)
			draw_line(prev_point, next_point, line_color, 1.0)
			prev_point = next_point

func _draw_hills_details(base_color: Color) -> void:
	# Draw a simple arc/dome shape in darker shade, centered in lower half
	var dome_color = Color(base_color.r * 0.75, base_color.g * 0.75, base_color.b * 0.75)
	var cx = TILE_SIZE / 2.0
	var cy = TILE_SIZE * 0.65
	var arc_points: PackedVector2Array = []
	for j in range(0, 13):
		var angle = PI + float(j) / 12.0 * PI  # PI to 2*PI (bottom half of circle)
		arc_points.append(Vector2(cx + cos(angle) * 20.0, cy + sin(angle) * 12.0))
	# Close the bottom
	arc_points.append(arc_points[0])
	for j in range(0, arc_points.size() - 1):
		draw_line(arc_points[j], arc_points[j + 1], dome_color, 2.0)

func _draw_mountain_details() -> void:
	# Main mountain triangle (dark gray)
	var peak = Vector2(TILE_SIZE / 2.0, 10.0)
	var left = Vector2(8.0, TILE_SIZE - 8.0)
	var right = Vector2(TILE_SIZE - 8.0, TILE_SIZE - 8.0)
	draw_colored_polygon(PackedVector2Array([peak, left, right]), Color(0.35, 0.35, 0.35))
	# Snow cap (small white triangle on top)
	var snow_left = Vector2(TILE_SIZE / 2.0 - 8.0, 22.0)
	var snow_right = Vector2(TILE_SIZE / 2.0 + 8.0, 22.0)
	draw_colored_polygon(PackedVector2Array([peak, snow_left, snow_right]), Color(0.95, 0.95, 0.98))

func _draw_coast_details(base_color: Color) -> void:
	# Draw 2-3 thin wavy horizontal lines in slightly lighter blue
	var line_color = Color(
		minf(base_color.r + 0.12, 1.0),
		minf(base_color.g + 0.12, 1.0),
		minf(base_color.b + 0.12, 1.0),
		0.6
	)
	var wave_count = 2 + (grid_position.x + grid_position.y) % 2  # 2 or 3
	for i in wave_count:
		var y_base = 14.0 + i * 16.0
		var prev_point = Vector2(0, y_base)
		for seg in range(1, 9):
			var x = seg * 8.0
			var wave_offset = sin(float(seg + grid_position.x * 2 + i * 4)) * 3.0
			var next_point = Vector2(x, y_base + wave_offset)
			draw_line(prev_point, next_point, line_color, 1.0)
			prev_point = next_point

func _draw_ocean_details(base_color: Color) -> void:
	# Draw 1-2 wavy lines in darker blue
	var line_color = Color(base_color.r * 0.8, base_color.g * 0.8, base_color.b * 1.1, 0.5)
	var wave_count = 1 + (grid_position.x * 3 + grid_position.y) % 2  # 1 or 2
	for i in wave_count:
		var y_base = 20.0 + i * 18.0
		var prev_point = Vector2(0, y_base)
		for seg in range(1, 9):
			var x = seg * 8.0
			var wave_offset = sin(float(seg + grid_position.y * 2 + i * 3)) * 3.5
			var next_point = Vector2(x, y_base + wave_offset)
			draw_line(prev_point, next_point, line_color, 1.0)
			prev_point = next_point

func _draw_snow_details() -> void:
	# Scattered white dots (snowflakes)
	var seed_val = grid_position.x * 23 + grid_position.y * 41
	var dot_count = 4 + (seed_val % 3)  # 4 to 6
	for i in dot_count:
		var px = 6 + ((seed_val * (i + 1) * 13 + 7) % (TILE_SIZE - 12))
		var py = 6 + ((seed_val * (i + 1) * 19 + 11) % (TILE_SIZE - 12))
		draw_circle(Vector2(px, py), 1.0, Color(1.0, 1.0, 1.0, 0.7))

func _draw_tundra_details() -> void:
	# Scattered white dots (sparse snowflakes) on tundra
	var seed_val = grid_position.x * 29 + grid_position.y * 37
	var dot_count = 2 + (seed_val % 3)  # 2 to 4
	for i in dot_count:
		var px = 8 + ((seed_val * (i + 1) * 11 + 3) % (TILE_SIZE - 16))
		var py = 8 + ((seed_val * (i + 1) * 17 + 9) % (TILE_SIZE - 16))
		draw_circle(Vector2(px, py), 1.0, Color(1.0, 1.0, 1.0, 0.5))

func _draw_feature() -> void:
	if feature_id == "":
		return

	var feature = DataManager.get_feature(feature_id)
	if feature.is_empty():
		return

	match feature_id:
		"forest":
			_draw_feature_forest()
		"jungle":
			_draw_feature_jungle()
		"flood_plains":
			_draw_feature_flood_plains()
		"oasis":
			_draw_feature_oasis()
		"ice":
			_draw_feature_ice()
		_:
			# Fallback: draw the symbol for any unknown features
			var symbol = feature.get("symbol", "?")
			var color = Color(feature.get("color", "#228B22"))
			var font = ThemeDB.fallback_font
			var font_size = 20
			var text_size = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
			var text_pos = Vector2(TILE_SIZE / 2 - text_size.x / 2, TILE_SIZE / 2 + text_size.y / 4)
			draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_feature_forest() -> void:
	# 2-3 small green triangles (pointed up) at slightly offset positions
	var tree_color = Color(0.13, 0.55, 0.13)
	var seed_val = grid_position.x * 11 + grid_position.y * 23
	var tree_count = 2 + (seed_val % 2)  # 2 or 3

	# Predefined base positions for trees (center-ish of tile)
	var base_positions = [
		Vector2(TILE_SIZE * 0.3, TILE_SIZE * 0.55),
		Vector2(TILE_SIZE * 0.6, TILE_SIZE * 0.45),
		Vector2(TILE_SIZE * 0.45, TILE_SIZE * 0.7),
	]

	for i in tree_count:
		var bx = base_positions[i].x + float((seed_val * (i + 1)) % 7) - 3.0
		var by = base_positions[i].y + float((seed_val * (i + 2)) % 5) - 2.0
		# Triangle: base ~8px, height ~12px
		var top = Vector2(bx, by - 12.0)
		var bl = Vector2(bx - 4.0, by)
		var br = Vector2(bx + 4.0, by)
		draw_colored_polygon(PackedVector2Array([top, bl, br]), tree_color)

func _draw_feature_jungle() -> void:
	# 3-4 shorter, wider triangles in very dark green, packed tighter
	var jungle_color = Color(0.0, 0.4, 0.0)
	var seed_val = grid_position.x * 13 + grid_position.y * 19
	var tree_count = 3 + (seed_val % 2)  # 3 or 4

	var base_positions = [
		Vector2(TILE_SIZE * 0.25, TILE_SIZE * 0.5),
		Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.4),
		Vector2(TILE_SIZE * 0.7, TILE_SIZE * 0.55),
		Vector2(TILE_SIZE * 0.4, TILE_SIZE * 0.7),
	]

	for i in tree_count:
		var bx = base_positions[i].x + float((seed_val * (i + 1)) % 5) - 2.0
		var by = base_positions[i].y + float((seed_val * (i + 2)) % 5) - 2.0
		# Shorter, wider triangles: base ~10px, height ~9px
		var top = Vector2(bx, by - 9.0)
		var bl = Vector2(bx - 5.0, by)
		var br = Vector2(bx + 5.0, by)
		draw_colored_polygon(PackedVector2Array([top, bl, br]), jungle_color)

func _draw_feature_flood_plains() -> void:
	# 3 thin horizontal wavy blue lines across the tile
	var line_color = Color(0.2, 0.5, 0.9, 0.6)
	for i in 3:
		var y_base = 16.0 + i * 14.0
		var prev_point = Vector2(4.0, y_base)
		for seg in range(1, 8):
			var x = 4.0 + seg * 8.0
			var wave_offset = sin(float(seg + grid_position.x * 5 + i * 3)) * 2.0
			var next_point = Vector2(x, y_base + wave_offset)
			draw_line(prev_point, next_point, line_color, 1.0)
			prev_point = next_point

func _draw_feature_oasis() -> void:
	# Small filled blue circle for water, green circle outline for vegetation
	var center = Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	draw_circle(center, 6.0, Color(0.1, 0.5, 0.9))  # Blue water
	# Green vegetation ring (draw as an unfilled circle via arc)
	var ring_color = Color(0.2, 0.7, 0.2)
	var point_count = 24
	for j in point_count:
		var angle_a = float(j) / float(point_count) * TAU
		var angle_b = float(j + 1) / float(point_count) * TAU
		var pa = center + Vector2(cos(angle_a), sin(angle_a)) * 8.0
		var pb = center + Vector2(cos(angle_b), sin(angle_b)) * 8.0
		draw_line(pa, pb, ring_color, 1.5)

func _draw_feature_ice() -> void:
	# Angular white shapes: 2-3 short diagonal white lines crossing each other
	var ice_color = Color(0.9, 0.95, 1.0, 0.85)
	var seed_val = grid_position.x * 17 + grid_position.y * 29
	var group_count = 2 + (seed_val % 2)  # 2 or 3

	var base_positions = [
		Vector2(TILE_SIZE * 0.3, TILE_SIZE * 0.35),
		Vector2(TILE_SIZE * 0.65, TILE_SIZE * 0.55),
		Vector2(TILE_SIZE * 0.45, TILE_SIZE * 0.7),
	]

	for i in group_count:
		var cx = base_positions[i].x + float((seed_val * (i + 1)) % 7) - 3.0
		var cy = base_positions[i].y + float((seed_val * (i + 2)) % 5) - 2.0
		# Draw crossing diagonal lines
		draw_line(Vector2(cx - 5, cy - 4), Vector2(cx + 5, cy + 4), ice_color, 1.5)
		draw_line(Vector2(cx - 4, cy + 5), Vector2(cx + 4, cy - 5), ice_color, 1.5)

func _draw_resource() -> void:
	if resource_id == "":
		return

	# Check if resource is revealed to human player
	var human_player = GameManager.human_player
	if human_player != null and not is_resource_visible_to_player(human_player):
		return

	var resource = DataManager.get_resource(resource_id)
	if resource.is_empty():
		return

	var symbol = resource.get("symbol", "?")

	# Draw resource symbol in bottom right
	var font = ThemeDB.fallback_font
	var font_size = 14
	var text_pos = Vector2(TILE_SIZE - 18, TILE_SIZE - 4)
	draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

func _draw_improvement() -> void:
	if improvement_id == "":
		return

	var improvement = DataManager.get_improvement(improvement_id)
	if improvement.is_empty():
		return

	var symbol = improvement.get("symbol", "?")
	var color = Color(improvement.get("color", "#FFFFFF"))

	# Draw improvement symbol in top left
	var font = ThemeDB.fallback_font
	var font_size = 14
	var text_pos = Vector2(4, 16)
	draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_road() -> void:
	if road_level == 0:
		return

	var road_color = Color("#A9A9A9") if road_level == 1 else Color("#4B4B4B")

	# Draw simple cross pattern for road
	var center = Vector2(TILE_SIZE / 2, TILE_SIZE / 2)
	var half = TILE_SIZE / 2

	draw_line(Vector2(0, center.y), Vector2(TILE_SIZE, center.y), road_color, 3.0)
	draw_line(Vector2(center.x, 0), Vector2(center.x, TILE_SIZE), road_color, 3.0)

func _draw_goody_hut() -> void:
	if not has_goody_hut:
		return

	# Draw tribal village symbol (hut icon)
	var symbol = "🏠"
	var color = Color("#8B4513")  # Saddle brown

	var font = ThemeDB.fallback_font
	var font_size = 20
	var text_size = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(TILE_SIZE / 2 - text_size.x / 2, TILE_SIZE / 2 + text_size.y / 4)
	draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_owner_border() -> void:
	if tile_owner == null:
		return

	var border_color = tile_owner.color
	border_color.a = 1.0  # Fully opaque border lines

	var grid = GameManager.hex_grid
	if grid == null:
		return

	# Check 4 cardinal directions and draw border lines where we meet unowned territory
	# North edge
	var north_pos = GridUtils.wrap_position(grid_position + Vector2i(0, -1), grid.width, grid.height)
	var north_tile = grid.get_tile(north_pos)
	if north_tile == null or north_tile.tile_owner != tile_owner:
		draw_line(Vector2(0, 0), Vector2(TILE_SIZE, 0), border_color, 3.0)

	# East edge
	var east_pos = GridUtils.wrap_position(grid_position + Vector2i(1, 0), grid.width, grid.height)
	var east_tile = grid.get_tile(east_pos)
	if east_tile == null or east_tile.tile_owner != tile_owner:
		draw_line(Vector2(TILE_SIZE, 0), Vector2(TILE_SIZE, TILE_SIZE), border_color, 3.0)

	# South edge
	var south_pos = GridUtils.wrap_position(grid_position + Vector2i(0, 1), grid.width, grid.height)
	var south_tile = grid.get_tile(south_pos)
	if south_tile == null or south_tile.tile_owner != tile_owner:
		draw_line(Vector2(TILE_SIZE, TILE_SIZE), Vector2(0, TILE_SIZE), border_color, 3.0)

	# West edge
	var west_pos = GridUtils.wrap_position(grid_position + Vector2i(-1, 0), grid.width, grid.height)
	var west_tile = grid.get_tile(west_pos)
	if west_tile == null or west_tile.tile_owner != tile_owner:
		draw_line(Vector2(0, TILE_SIZE), Vector2(0, 0), border_color, 3.0)

func update_visuals() -> void:
	queue_redraw()

## Copy visual data from another tile (used for wrap display)
func copy_from(other: GameTile) -> void:
	terrain_id = other.terrain_id
	feature_id = other.feature_id
	resource_id = other.resource_id
	improvement_id = other.improvement_id
	road_level = other.road_level
	tile_owner = other.tile_owner
	visibility = other.visibility.duplicate()
	queue_redraw()

# Terrain and feature queries
func get_total_movement_cost() -> int:
	var base_cost = DataManager.get_terrain_movement_cost(terrain_id)
	if feature_id != "":
		base_cost += DataManager.get_feature_movement_cost(feature_id)
	if road_level >= 1:
		base_cost = 1  # Roads make movement cost 1
	if road_level >= 2:
		base_cost = 0  # Railroads are essentially free
	return max(base_cost, 1)

func is_passable() -> bool:
	if not DataManager.is_terrain_passable(terrain_id):
		return false
	if feature_id != "":
		var feature = DataManager.get_feature(feature_id)
		if feature.get("impassable", false):
			return false
	return true

func is_water() -> bool:
	return terrain_id in ["coast", "ocean"]

func is_coast() -> bool:
	return terrain_id == "coast"

func is_ocean() -> bool:
	return terrain_id == "ocean"

func is_hills() -> bool:
	return terrain_id == "hills"

func is_mountains() -> bool:
	return terrain_id == "mountains"

func has_fresh_water() -> bool:
	# Would need to check for adjacent rivers/lakes
	# Simplified: check if adjacent to coast or has oasis
	return feature_id == "oasis"

func get_defense_bonus() -> float:
	var bonus = DataManager.get_terrain_defense_bonus(terrain_id)
	if feature_id != "":
		bonus += DataManager.get_feature_defense_bonus(feature_id)
	if improvement_id == "fort":
		var improvement = DataManager.get_improvement(improvement_id)
		bonus += improvement.get("defense_bonus", 0.0)
	return bonus

# Yield calculations
func get_yields(for_player = null) -> Dictionary:
	var yields = DataManager.get_terrain_yields(terrain_id).duplicate()

	# Add feature yields
	if feature_id != "":
		var feature_yields = DataManager.get_feature_yields(feature_id)
		for key in feature_yields:
			yields[key] = yields.get(key, 0) + feature_yields[key]

	# Add resource yields (only if improved AND visible to player)
	if resource_id != "" and _is_resource_improved():
		var resource_visible = true
		if for_player != null:
			resource_visible = is_resource_visible_to_player(for_player)
		elif tile_owner != null:
			resource_visible = is_resource_visible_to_player(tile_owner)
		if resource_visible:
			var resource_yields = DataManager.get_resource_yields(resource_id)
			for key in resource_yields:
				yields[key] = yields.get(key, 0) + resource_yields[key]

	# Add improvement yields
	if improvement_id != "":
		var improvement_yields = DataManager.get_improvement_yields(improvement_id)
		for key in improvement_yields:
			yields[key] = yields.get(key, 0) + improvement_yields[key]

	return yields

func _is_resource_improved() -> bool:
	if resource_id == "":
		return false
	var resource = DataManager.get_resource(resource_id)
	var required_improvement = resource.get("improvement", "")
	return improvement_id == required_improvement

func get_food() -> int:
	return get_yields().get("food", 0)

func get_production() -> int:
	return get_yields().get("production", 0)

func get_commerce() -> int:
	return get_yields().get("commerce", 0)

# Visibility
func set_visibility_for_player(player_id: int, state: VisibilityState) -> void:
	visibility[player_id] = state
	update_visuals()

func get_visibility_for_player(player_id: int) -> VisibilityState:
	return visibility.get(player_id, VisibilityState.UNEXPLORED)

func is_visible_to(player_id: int) -> bool:
	return get_visibility_for_player(player_id) == VisibilityState.VISIBLE

func is_explored_by(player_id: int) -> bool:
	return get_visibility_for_player(player_id) != VisibilityState.UNEXPLORED

## Check if the resource on this tile is visible to a player (has required tech)
func is_resource_visible_to_player(player) -> bool:
	if resource_id == "":
		return false
	var resource = DataManager.get_resource(resource_id)
	if resource.is_empty():
		return false
	var revealed_by = resource.get("revealed_by", "")
	if revealed_by == "":
		return true  # No tech required, always visible
	return player.has_tech(revealed_by)

# Improvement building
func can_build_improvement(improvement_type: String, builder_owner) -> bool:
	var improvement = DataManager.get_improvement(improvement_type)
	if improvement.is_empty():
		return false

	# Check tech requirement
	var required_tech = improvement.get("required_tech", "")
	if required_tech != "" and not builder_owner.has_tech(required_tech):
		return false

	# Check if terrain is valid
	var valid_terrains = improvement.get("valid_terrains", [])
	var terrain_valid = valid_terrains.is_empty() or terrain_id in valid_terrains

	# Special case: mines can be built on any terrain with mineable resources
	if improvement_type == "mine" and not terrain_valid:
		var mineable_resources = ["iron", "copper", "gems", "silver", "gold_resource", "coal", "uranium"]
		if resource_id in mineable_resources and is_resource_visible_to_player(builder_owner):
			terrain_valid = true

	if not terrain_valid:
		return false

	# Check resource requirement
	var required_resources = improvement.get("requires_resource", [])
	if not required_resources.is_empty():
		if resource_id == "" or resource_id not in required_resources:
			return false
		# Also check if resource is visible to builder
		if not is_resource_visible_to_player(builder_owner):
			return false

	# Check if requires existing improvement
	var requires_improvement = improvement.get("requires_improvement", "")
	if requires_improvement != "" and improvement_id != requires_improvement:
		return false

	# Check fresh water requirement
	var requires_fresh_water = improvement.get("requires_fresh_water_on", [])
	if terrain_id in requires_fresh_water and not has_fresh_water():
		return false

	return true

func start_improvement(improvement_type: String) -> void:
	improvement_id = improvement_type
	improvement_progress = 0

func complete_improvement() -> void:
	update_visuals()

# Serialization
func to_dict() -> Dictionary:
	return {
		"grid_position": {"x": grid_position.x, "y": grid_position.y},
		"terrain_id": terrain_id,
		"feature_id": feature_id,
		"resource_id": resource_id,
		"improvement_id": improvement_id,
		"road_level": road_level,
		"has_goody_hut": has_goody_hut,
		"owner_id": tile_owner.player_id if tile_owner else -1,
		"visibility": visibility,
	}

func from_dict(data: Dictionary) -> void:
	grid_position = Vector2i(data.grid_position.x, data.grid_position.y)
	terrain_id = data.get("terrain_id", "grassland")
	feature_id = data.get("feature_id", "")
	resource_id = data.get("resource_id", "")
	improvement_id = data.get("improvement_id", "")
	road_level = data.get("road_level", 0)
	has_goody_hut = data.get("has_goody_hut", false)
	visibility = data.get("visibility", {})
	position = GridUtils.grid_to_pixel_corner(grid_position)
	update_visuals()
