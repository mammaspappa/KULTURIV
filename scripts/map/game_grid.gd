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

	# Apply map type settings
	var map_type = GameManager.map_type if GameManager else "fractal"
	if map_type == "archipelago":
		elevation_noise.frequency = 0.04
		sea_level = 0.55  # base 0.4 + 0.15
	else:
		elevation_noise.frequency = 0.02
		sea_level = 0.4

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

	# Add tribal villages (goody huts)
	_add_goody_huts()

	# Ensure starting locations have good terrain
	_prepare_starting_locations()

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

	# Apply map type modifier
	value = _apply_map_type_modifier(pos.x, pos.y, value)

	return value

func _apply_map_type_modifier(x: int, y: int, base_elevation: float) -> float:
	var map_type = GameManager.map_type if GameManager else "fractal"

	if map_type == "pangaea":
		# Radial bias: tiles near center get boosted, edges get reduced
		var center_x = width / 2.0
		var center_y = height / 2.0
		var dist_x = abs(x - center_x) / center_x
		var dist_y = abs(y - center_y) / center_y
		var dist = sqrt(dist_x * dist_x + dist_y * dist_y) / sqrt(2.0)  # Normalize to [0, 1]
		var bias = 0.3 * (1.0 - dist * 1.5)
		return clamp(base_elevation + bias, 0.0, 1.0)

	elif map_type == "continents":
		# Three elevation hotspots with Gaussian falloff
		var hotspots = [
			Vector2(width * 0.25, height * 0.5),
			Vector2(width * 0.6, height * 0.3),
			Vector2(width * 0.75, height * 0.7),
		]
		var sigma = width * 0.15
		var best_bias = 0.0
		for hotspot in hotspots:
			var dx = x - hotspot.x
			var dy = y - hotspot.y
			var dist_sq = dx * dx + dy * dy
			var falloff = 0.25 * exp(-dist_sq / (sigma * sigma))
			if falloff > best_bias:
				best_bias = falloff
		return clamp(base_elevation + best_bias, 0.0, 1.0)

	elif map_type == "archipelago":
		# No additional elevation modifier -- the higher frequency and sea_level
		# are already set in generate_map() to create many small islands
		return base_elevation

	# Fractal (default): no modification
	return base_elevation

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

	# Separate resources by type for controlled distribution
	var strategic_resources = []
	var luxury_resources = []
	var bonus_resources = []

	for resource_id in all_resources:
		var resource = all_resources[resource_id]
		match resource.get("type", ""):
			"strategic":
				strategic_resources.append(resource_id)
			"luxury":
				luxury_resources.append(resource_id)
			_:
				bonus_resources.append(resource_id)

	var total_land = 0
	for pos in tiles:
		if not tiles[pos].is_water():
			total_land += 1

	# Strategic resources: limited quantity, terrain-specific
	var strategic_count = max(4, total_land / 80)  # ~1 per 80 land tiles
	for resource_id in strategic_resources:
		var resource = all_resources[resource_id]
		var valid_terrains = resource.get("valid_terrains", [])
		var placed = 0
		var target = strategic_count / strategic_resources.size() + 1
		var attempts = 0
		while placed < target and attempts < 500:
			attempts += 1
			var pos = tiles.keys()[randi() % tiles.size()]
			var tile = tiles[pos]
			if tile.resource_id != "" or tile.is_water():
				continue
			if tile.terrain_id in valid_terrains or tile.feature_id in valid_terrains:
				tile.resource_id = resource_id
				placed += 1

	# Luxury resources: clustered (2-3 of same type near each other)
	var luxury_count = max(6, total_land / 60)  # ~1 per 60 land tiles
	for resource_id in luxury_resources:
		var resource = all_resources[resource_id]
		var valid_terrains = resource.get("valid_terrains", [])
		var placed = 0
		var target = max(2, luxury_count / luxury_resources.size())
		var cluster_center = Vector2i(-1, -1)
		var attempts = 0
		while placed < target and attempts < 500:
			attempts += 1
			var pos = tiles.keys()[randi() % tiles.size()]
			var tile = tiles[pos]
			if tile.resource_id != "" or tile.is_water():
				continue
			if tile.terrain_id in valid_terrains or tile.feature_id in valid_terrains:
				# Cluster: after first placement, prefer nearby tiles
				if cluster_center != Vector2i(-1, -1) and placed > 0:
					if GridUtils.chebyshev_distance(pos, cluster_center) > 5:
						continue
				tile.resource_id = resource_id
				if cluster_center == Vector2i(-1, -1):
					cluster_center = pos
				placed += 1

	# Bonus resources: more generous, 10% of valid land tiles
	for pos in tiles:
		var tile = tiles[pos]
		if tile.resource_id != "" or tile.is_water():
			continue
		if randf() > 0.10:
			continue
		var valid = []
		for resource_id in bonus_resources:
			var resource = all_resources[resource_id]
			var valid_terrains = resource.get("valid_terrains", [])
			if tile.terrain_id in valid_terrains or tile.feature_id in valid_terrains:
				valid.append(resource_id)
		if not valid.is_empty():
			tile.resource_id = valid[randi() % valid.size()]

func _prepare_starting_locations() -> void:
	# Find good starting spots for players
	# Will be used when placing initial settlers
	pass

func _add_goody_huts() -> void:
	# Place tribal villages (goody huts) on the map
	var density = 0.02  # 2% of valid tiles
	var placed = 0

	for pos in tiles:
		var tile = tiles[pos]

		# Only on land, non-mountain, unowned tiles
		if tile.is_water() or tile.terrain_id == "mountains":
			continue

		# Random chance based on density
		if randf() < density:
			# Don't place too close to map edges (starting positions)
			if pos.y > 5 and pos.y < height - 5:
				tile.has_goody_hut = true
				placed += 1

	print("[MapGen] Placed %d goody huts" % placed)

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

# Find suitable starting location — scores candidates for best placement
func find_starting_location(avoid_positions: Array[Vector2i], min_distance: int = -1) -> Vector2i:
	# Scale minimum distance with map size
	if min_distance < 0:
		min_distance = max(8, int(sqrt(width * height) / 4))

	var best_pos = Vector2i(width / 2, height / 2)
	var best_score = -999.0
	var attempts = 0
	var max_attempts = 2000

	while attempts < max_attempts:
		var x = randi() % width
		var y = randi() % (height - 10) + 5  # Avoid poles

		var pos = Vector2i(x, y)
		var tile = get_tile(pos)
		attempts += 1

		if tile == null or not tile.is_passable() or tile.is_water():
			continue

		# Check distance from other starts
		var too_close = false
		for avoid_pos in avoid_positions:
			if GridUtils.chebyshev_distance(pos, avoid_pos) < min_distance:
				too_close = true
				break
		if too_close:
			continue

		# Score this location
		var score = 0.0
		var nearby = get_tiles_in_range(pos, 2)
		var food_tiles = 0
		var prod_tiles = 0
		var has_fresh_water = false
		var has_resource = false

		for nearby_tile in nearby:
			if nearby_tile == null or not nearby_tile.is_passable():
				continue
			if nearby_tile.is_water():
				has_fresh_water = true  # Coastal access
				continue
			var yields = nearby_tile.get_yields()
			if yields.get("food", 0) >= 2:
				food_tiles += 1
			if yields.get("production", 0) >= 1:
				prod_tiles += 1
			if nearby_tile.resource_id != "":
				has_resource = true

		# Need minimum food
		if food_tiles < 3:
			continue

		score += food_tiles * 3.0
		score += prod_tiles * 2.0
		if has_fresh_water:
			score += 5.0
		if has_resource:
			score += 4.0

		# Check range 3 for strategic/luxury resources
		var extended = get_tiles_in_range(pos, 3)
		for ext_tile in extended:
			if ext_tile != null and ext_tile.resource_id != "":
				var res = DataManager.get_resource(ext_tile.resource_id)
				if res.get("type", "") == "strategic":
					score += 3.0
				elif res.get("type", "") == "luxury":
					score += 2.0

		if score > best_score:
			best_score = score
			best_pos = pos

	return best_pos

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

	# Load tiles
	var tiles_data = data.get("tiles", {})
	for key in tiles_data:
		var parts = key.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		var tile = GameTile.new(pos)
		tile.from_dict(tiles_data[key])
		tiles[pos] = tile
		add_child(tile)
