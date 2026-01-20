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
		_draw_owner_border()
	else:
		# Fogged - show known improvements but not resources
		_draw_improvement()
		_draw_road()

	# Apply fog overlay for fogged tiles
	if vis_state == VisibilityState.FOGGED:
		draw_rect(Rect2(0, 0, TILE_SIZE, TILE_SIZE), Color(0, 0, 0, 0.5))

func _draw_terrain() -> void:
	var color = DataManager.get_terrain_color(terrain_id)
	draw_rect(Rect2(0, 0, TILE_SIZE, TILE_SIZE), color)
	# Draw grid lines
	draw_rect(Rect2(0, 0, TILE_SIZE, TILE_SIZE), Color(0, 0, 0, 0.2), false, 1.0)

func _draw_feature() -> void:
	if feature_id == "":
		return

	var feature = DataManager.get_feature(feature_id)
	if feature.is_empty():
		return

	var symbol = feature.get("symbol", "?")
	var color = Color(feature.get("color", "#228B22"))

	# Draw feature symbol in center
	var font = ThemeDB.fallback_font
	var font_size = 20
	var text_size = font.get_string_size(symbol, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(TILE_SIZE / 2 - text_size.x / 2, TILE_SIZE / 2 + text_size.y / 4)
	draw_string(font, text_pos, symbol, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw_resource() -> void:
	if resource_id == "":
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

func _draw_owner_border() -> void:
	if tile_owner == null:
		return

	# Draw colored border to show ownership
	var border_color = tile_owner.color
	border_color.a = 0.5
	draw_rect(Rect2(0, 0, TILE_SIZE, TILE_SIZE), border_color, false, 2.0)

func update_visuals() -> void:
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
func get_yields() -> Dictionary:
	var yields = DataManager.get_terrain_yields(terrain_id).duplicate()

	# Add feature yields
	if feature_id != "":
		var feature_yields = DataManager.get_feature_yields(feature_id)
		for key in feature_yields:
			yields[key] = yields.get(key, 0) + feature_yields[key]

	# Add resource yields (only if improved)
	if resource_id != "" and _is_resource_improved():
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

# Improvement building
func can_build_improvement(improvement_type: String, builder_owner) -> bool:
	var improvement = DataManager.get_improvement(improvement_type)
	if improvement.is_empty():
		return false

	# Check if terrain is valid
	var valid_terrains = improvement.get("valid_terrains", [])
	if not valid_terrains.is_empty() and terrain_id not in valid_terrains:
		return false

	# Check tech requirement
	var required_tech = improvement.get("required_tech", "")
	if required_tech != "" and not builder_owner.has_tech(required_tech):
		return false

	# Check resource requirement
	var required_resources = improvement.get("requires_resource", [])
	if not required_resources.is_empty():
		if resource_id == "" or resource_id not in required_resources:
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
	visibility = data.get("visibility", {})
	position = GridUtils.grid_to_pixel_corner(grid_position)
	update_visuals()
