class_name GameGrid
extends Node2D
## Manages the entire game map grid.

# Map dimensions
var width: int = 80
var height: int = 50
var wrap_x: bool = true
var wrap_y: bool = false

# Tile storage
var tiles: Dictionary = {}  # Vector2i -> GameTile

# Wrap visual copies (for cylindrical display)
var left_wrap_container: Node2D
var right_wrap_container: Node2D
var wrap_tiles_left: Dictionary = {}  # Vector2i -> GameTile (visual copies)
var wrap_tiles_right: Dictionary = {}  # Vector2i -> GameTile (visual copies)

# Map generation settings
var sea_level: float = 0.4
var mountain_threshold: float = 0.85
var hill_threshold: float = 0.7
var forest_chance: float = 0.3
var jungle_latitude: float = 0.2  # Latitude band for jungle

# Noise generators for terrain
var elevation_noise: FastNoiseLite
var moisture_noise: FastNoiseLite
var temperature_noise: FastNoiseLite

signal map_generated()
signal tile_clicked(tile)

func _ready() -> void:
	_setup_noise()

func _setup_noise() -> void:
	elevation_noise = FastNoiseLite.new()
	elevation_noise.seed = randi()
	elevation_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	elevation_noise.frequency = 0.02
	elevation_noise.fractal_octaves = 4

	moisture_noise = FastNoiseLite.new()
	moisture_noise.seed = randi()
	moisture_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	moisture_noise.frequency = 0.03
	moisture_noise.fractal_octaves = 3

	temperature_noise = FastNoiseLite.new()
	temperature_noise.seed = randi()
	temperature_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	temperature_noise.frequency = 0.01
	temperature_noise.fractal_octaves = 2

func generate_map(w: int = 80, h: int = 50) -> void:
	width = w
	height = h

	# Clear existing tiles
	for tile in tiles.values():
		tile.queue_free()
	tiles.clear()

	# Regenerate noise seeds
	elevation_noise.seed = randi()
	moisture_noise.seed = randi()
	temperature_noise.seed = randi()

	# Generate all tiles
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			var tile = _create_tile(pos)
			tiles[pos] = tile
			add_child(tile)

	# Post-process: add features, resources
	_add_features()
	_add_resources()

	# Ensure starting locations have good terrain
	_prepare_starting_locations()

	# Create visual wrap copies for cylindrical display
	# Note: Temporarily disabled for debugging - uncomment when working
	#if wrap_x:
	#	_create_wrap_visuals()

	map_generated.emit()

func _create_tile(pos: Vector2i) -> GameTile:
	var tile = GameTile.new(pos)

	# Get noise values
	var elevation = _get_elevation(pos)
	var moisture = _get_moisture(pos)
	var temperature = _get_temperature(pos)

	# Determine terrain type based on elevation and climate
	tile.terrain_id = _determine_terrain(pos, elevation, moisture, temperature)

	return tile

func _get_elevation(pos: Vector2i) -> float:
	var value = elevation_noise.get_noise_2d(pos.x, pos.y)
	# Normalize to 0-1
	value = (value + 1.0) / 2.0

	# Make edges lower (for ocean borders if not wrapping)
	if not wrap_x:
		var edge_dist_x = min(pos.x, width - 1 - pos.x) / float(width / 4)
		value *= min(edge_dist_x, 1.0)

	# Poles are lower (more ice/ocean)
	var latitude = abs(pos.y - height / 2.0) / (height / 2.0)
	if latitude > 0.8:
		value *= 0.5

	return value

func _get_moisture(pos: Vector2i) -> float:
	var value = moisture_noise.get_noise_2d(pos.x, pos.y)
	return (value + 1.0) / 2.0

func _get_temperature(pos: Vector2i) -> float:
	# Base temperature on latitude
	var latitude = abs(pos.y - height / 2.0) / (height / 2.0)
	var base_temp = 1.0 - latitude

	# Add noise variation
	var noise_val = temperature_noise.get_noise_2d(pos.x, pos.y)
	base_temp += noise_val * 0.2

	return clamp(base_temp, 0.0, 1.0)

func _determine_terrain(pos: Vector2i, elevation: float, moisture: float, temperature: float) -> String:
	# Deep water
	if elevation < sea_level * 0.6:
		return "ocean"

	# Shallow water
	if elevation < sea_level:
		return "coast"

	# Mountains
	if elevation > mountain_threshold:
		return "mountains"

	# Hills
	if elevation > hill_threshold:
		return "hills"

	# Land terrain based on climate
	if temperature < 0.15:
		return "snow"
	elif temperature < 0.3:
		return "tundra"
	elif temperature > 0.7 and moisture < 0.3:
		return "desert"
	elif moisture > 0.5:
		return "grassland"
	else:
		return "plains"

func _add_features() -> void:
	for pos in tiles:
		var tile = tiles[pos]

		# Skip water and mountains
		if tile.is_water() or tile.is_mountains():
			continue

		var moisture = _get_moisture(pos)
		var temperature = _get_temperature(pos)

		# Jungle in hot, wet areas
		if temperature > 0.7 and moisture > 0.6:
			if randf() < 0.6:
				tile.feature_id = "jungle"
				continue

		# Forest in temperate, moist areas
		if temperature > 0.3 and temperature < 0.8 and moisture > 0.4:
			if randf() < forest_chance:
				tile.feature_id = "forest"
				continue

		# Flood plains along desert rivers (simplified - random in desert)
		if tile.terrain_id == "desert" and randf() < 0.1:
			tile.feature_id = "flood_plains"
			continue

		# Oasis in desert
		if tile.terrain_id == "desert" and randf() < 0.03:
			tile.feature_id = "oasis"

func _add_resources() -> void:
	var all_resources = DataManager.resources

	for pos in tiles:
		var tile = tiles[pos]

		# Random chance for resource
		if randf() > 0.15:
			continue

		# Find valid resources for this terrain
		var valid_resources = []
		for resource_id in all_resources:
			var resource = all_resources[resource_id]
			var valid_terrains = resource.get("valid_terrains", [])

			# Check terrain
			if tile.terrain_id in valid_terrains:
				valid_resources.append(resource_id)
			# Check feature
			elif tile.feature_id in valid_terrains:
				valid_resources.append(resource_id)

		if not valid_resources.is_empty():
			tile.resource_id = valid_resources[randi() % valid_resources.size()]

func _prepare_starting_locations() -> void:
	# Find good starting spots for players
	# Will be used when placing initial settlers
	pass

## Create visual copies of tiles at the left and right edges for cylindrical wrapping
func _create_wrap_visuals() -> void:
	# Clear existing wrap visuals
	if left_wrap_container:
		left_wrap_container.queue_free()
	if right_wrap_container:
		right_wrap_container.queue_free()
	wrap_tiles_left.clear()
	wrap_tiles_right.clear()

	# Create containers for wrap visuals
	left_wrap_container = Node2D.new()
	left_wrap_container.name = "LeftWrapContainer"
	left_wrap_container.position.x = -width * GridUtils.TILE_SIZE
	add_child(left_wrap_container)

	right_wrap_container = Node2D.new()
	right_wrap_container.name = "RightWrapContainer"
	right_wrap_container.position.x = width * GridUtils.TILE_SIZE
	add_child(right_wrap_container)

	# Create copies of all tiles for both sides
	for pos in tiles:
		var original_tile = tiles[pos]

		# Left wrap copy
		var left_tile = GameTile.new(pos)
		left_tile.copy_from(original_tile)
		wrap_tiles_left[pos] = left_tile
		left_wrap_container.add_child(left_tile)

		# Right wrap copy
		var right_tile = GameTile.new(pos)
		right_tile.copy_from(original_tile)
		wrap_tiles_right[pos] = right_tile
		right_wrap_container.add_child(right_tile)

## Update the wrap tile visuals to match the main tiles
func update_wrap_visuals() -> void:
	if not wrap_x:
		return

	for pos in tiles:
		var original_tile = tiles[pos]

		if pos in wrap_tiles_left:
			wrap_tiles_left[pos].copy_from(original_tile)
		if pos in wrap_tiles_right:
			wrap_tiles_right[pos].copy_from(original_tile)

# Tile access
func get_tile(pos: Vector2i) -> GameTile:
	var wrapped_pos = _wrap_position(pos)
	return tiles.get(wrapped_pos, null)

func _wrap_position(pos: Vector2i) -> Vector2i:
	var result = pos
	if wrap_x:
		result.x = posmod(pos.x, width)
	else:
		result.x = clamp(pos.x, 0, width - 1)

	if wrap_y:
		result.y = posmod(pos.y, height)
	else:
		result.y = clamp(pos.y, 0, height - 1)

	return result

func is_valid_position(pos: Vector2i) -> bool:
	if wrap_x and wrap_y:
		return true
	if wrap_x:
		return pos.y >= 0 and pos.y < height
	if wrap_y:
		return pos.x >= 0 and pos.x < width
	return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func get_neighbors(pos: Vector2i) -> Array:
	var neighbors: Array = []
	var neighbor_positions = GridUtils.get_neighbors(pos)

	for npos in neighbor_positions:
		if is_valid_position(npos):
			var tile = get_tile(npos)
			if tile != null:
				neighbors.append(tile)

	return neighbors

func get_tiles_in_range(center: Vector2i, range_val: int) -> Array:
	var result: Array = []
	var positions = GridUtils.get_tiles_in_range(center, range_val)

	for pos in positions:
		if is_valid_position(pos):
			var tile = get_tile(pos)
			if tile != null:
				result.append(tile)

	return result

# Find suitable starting location
func find_starting_location(avoid_positions: Array[Vector2i], min_distance: int = 10) -> Vector2i:
	var attempts = 0
	var max_attempts = 1000

	while attempts < max_attempts:
		var x = randi() % width
		var y = randi() % (height - 10) + 5  # Avoid poles

		var pos = Vector2i(x, y)
		var tile = get_tile(pos)

		if tile == null:
			attempts += 1
			continue

		# Must be passable land
		if not tile.is_passable() or tile.is_water():
			attempts += 1
			continue

		# Check distance from other starts
		var too_close = false
		for avoid_pos in avoid_positions:
			if GridUtils.chebyshev_distance(pos, avoid_pos) < min_distance:
				too_close = true
				break

		if too_close:
			attempts += 1
			continue

		# Check for nearby good terrain
		var good_tiles = 0
		var nearby = get_tiles_in_range(pos, 2)
		for nearby_tile in nearby:
			if nearby_tile.is_passable() and not nearby_tile.is_water():
				if nearby_tile.get_food() >= 2:
					good_tiles += 1

		if good_tiles < 3:
			attempts += 1
			continue

		return pos

	# Fallback: return center of map
	return Vector2i(width / 2, height / 2)

# Input handling
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = get_local_mouse_position()
			var grid_pos = GridUtils.pixel_to_grid(local_pos)
			var tile = get_tile(grid_pos)
			if tile != null:
				tile_clicked.emit(tile)

# Update all tiles (for visibility changes, etc.)
func update_all_tiles() -> void:
	for tile in tiles.values():
		tile.update_visuals()
	# Also update wrap visuals
	update_wrap_visuals()

# Serialization
func to_dict() -> Dictionary:
	var tiles_data = {}
	for pos in tiles:
		tiles_data[str(pos.x) + "," + str(pos.y)] = tiles[pos].to_dict()

	return {
		"width": width,
		"height": height,
		"wrap_x": wrap_x,
		"wrap_y": wrap_y,
		"tiles": tiles_data,
	}

func from_dict(data: Dictionary) -> void:
	width = data.get("width", 80)
	height = data.get("height", 50)
	wrap_x = data.get("wrap_x", true)
	wrap_y = data.get("wrap_y", false)

	# Clear existing
	for tile in tiles.values():
		tile.queue_free()
	tiles.clear()

	# Clear wrap visuals
	if left_wrap_container:
		left_wrap_container.queue_free()
		left_wrap_container = null
	if right_wrap_container:
		right_wrap_container.queue_free()
		right_wrap_container = null
	wrap_tiles_left.clear()
	wrap_tiles_right.clear()

	# Load tiles
	var tiles_data = data.get("tiles", {})
	for key in tiles_data:
		var parts = key.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		var tile = GameTile.new(pos)
		tile.from_dict(tiles_data[key])
		tiles[pos] = tile
		add_child(tile)

	# Recreate wrap visuals
	if wrap_x:
		_create_wrap_visuals()
