extends Node
## Utility class for square grid coordinate math and conversions.

# Tile size in pixels
const TILE_SIZE: int = 64

# Direction constants (8-directional movement)
enum Direction { N, NE, E, SE, S, SW, W, NW }

# Direction vectors for 8-directional movement
const DIRECTION_VECTORS = {
	Direction.N:  Vector2i(0, -1),
	Direction.NE: Vector2i(1, -1),
	Direction.E:  Vector2i(1, 0),
	Direction.SE: Vector2i(1, 1),
	Direction.S:  Vector2i(0, 1),
	Direction.SW: Vector2i(-1, 1),
	Direction.W:  Vector2i(-1, 0),
	Direction.NW: Vector2i(-1, -1),
}

# Cardinal directions only (4-directional)
const CARDINAL_DIRECTIONS = [Direction.N, Direction.E, Direction.S, Direction.W]

# All 8 directions
const ALL_DIRECTIONS = [Direction.N, Direction.NE, Direction.E, Direction.SE,
						Direction.S, Direction.SW, Direction.W, Direction.NW]

## Convert grid coordinates to pixel position (center of tile)
static func grid_to_pixel(grid_pos: Vector2i) -> Vector2:
	return Vector2(
		grid_pos.x * TILE_SIZE + TILE_SIZE / 2.0,
		grid_pos.y * TILE_SIZE + TILE_SIZE / 2.0
	)

## Convert grid coordinates to pixel position (top-left corner)
static func grid_to_pixel_corner(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)

## Convert pixel position to grid coordinates
static func pixel_to_grid(pixel_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(pixel_pos.x / TILE_SIZE)),
		int(floor(pixel_pos.y / TILE_SIZE))
	)

## Get all 8 neighboring tiles
static func get_neighbors(grid_pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dir in ALL_DIRECTIONS:
		neighbors.append(grid_pos + DIRECTION_VECTORS[dir])
	return neighbors

## Get only cardinal (4) neighbors
static func get_cardinal_neighbors(grid_pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	for dir in CARDINAL_DIRECTIONS:
		neighbors.append(grid_pos + DIRECTION_VECTORS[dir])
	return neighbors

## Get neighbor in specific direction
static func get_neighbor(grid_pos: Vector2i, direction: Direction) -> Vector2i:
	return grid_pos + DIRECTION_VECTORS[direction]

## Calculate Manhattan distance (for 4-directional movement)
static func manhattan_distance(from: Vector2i, to: Vector2i) -> int:
	return abs(to.x - from.x) + abs(to.y - from.y)

## Calculate Chebyshev distance (for 8-directional movement)
static func chebyshev_distance(from: Vector2i, to: Vector2i) -> int:
	return max(abs(to.x - from.x), abs(to.y - from.y))

## Calculate Euclidean distance
static func euclidean_distance(from: Vector2i, to: Vector2i) -> float:
	return Vector2(from).distance_to(Vector2(to))

## Get tiles within a certain range (square area)
static func get_tiles_in_range(center: Vector2i, range_val: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(-range_val, range_val + 1):
		for y in range(-range_val, range_val + 1):
			if x == 0 and y == 0:
				continue
			tiles.append(center + Vector2i(x, y))
	return tiles

## Get tiles within Manhattan distance (diamond shape)
static func get_tiles_in_manhattan_range(center: Vector2i, range_val: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(-range_val, range_val + 1):
		for y in range(-range_val, range_val + 1):
			if x == 0 and y == 0:
				continue
			if abs(x) + abs(y) <= range_val:
				tiles.append(center + Vector2i(x, y))
	return tiles

## Get tiles at exact range (ring)
static func get_tiles_at_range(center: Vector2i, range_val: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for x in range(-range_val, range_val + 1):
		for y in range(-range_val, range_val + 1):
			if max(abs(x), abs(y)) == range_val:
				tiles.append(center + Vector2i(x, y))
	return tiles

## Check if position is within map bounds
static func is_valid_position(pos: Vector2i, map_width: int, map_height: int, wrap_x: bool = true) -> bool:
	if wrap_x:
		# X wraps around (cylindrical map)
		if pos.y < 0 or pos.y >= map_height:
			return false
		return true
	else:
		return pos.x >= 0 and pos.x < map_width and pos.y >= 0 and pos.y < map_height

## Wrap coordinates for cylindrical map
static func wrap_position(pos: Vector2i, map_width: int, map_height: int, wrap_x: bool = true) -> Vector2i:
	var result = pos
	if wrap_x:
		result.x = posmod(pos.x, map_width)
	else:
		result.x = clamp(pos.x, 0, map_width - 1)
	result.y = clamp(pos.y, 0, map_height - 1)
	return result

## Get direction from one tile to another
static func get_direction(from: Vector2i, to: Vector2i) -> Direction:
	var diff = to - from
	# Normalize to -1, 0, or 1
	var norm = Vector2i(sign(diff.x), sign(diff.y))

	for dir in DIRECTION_VECTORS:
		if DIRECTION_VECTORS[dir] == norm:
			return dir

	return Direction.N  # Default

## Get opposite direction
static func get_opposite_direction(dir: Direction) -> Direction:
	match dir:
		Direction.N: return Direction.S
		Direction.NE: return Direction.SW
		Direction.E: return Direction.W
		Direction.SE: return Direction.NW
		Direction.S: return Direction.N
		Direction.SW: return Direction.NE
		Direction.W: return Direction.E
		Direction.NW: return Direction.SE
	return Direction.N

## Check if two positions are adjacent
static func are_adjacent(pos1: Vector2i, pos2: Vector2i) -> bool:
	return chebyshev_distance(pos1, pos2) == 1

## Check if two positions are cardinally adjacent (4-directional)
static func are_cardinally_adjacent(pos1: Vector2i, pos2: Vector2i) -> bool:
	return manhattan_distance(pos1, pos2) == 1

## Get line of tiles between two points (Bresenham's line algorithm)
static func get_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)
	var sx = 1 if from.x < to.x else -1
	var sy = 1 if from.y < to.y else -1
	var err = dx - dy

	var x = from.x
	var y = from.y

	while true:
		points.append(Vector2i(x, y))
		if x == to.x and y == to.y:
			break
		var e2 = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

	return points

## Check line of sight between two tiles
static func has_line_of_sight(from: Vector2i, to: Vector2i, blocked_tiles: Array) -> bool:
	var line = get_line(from, to)
	# Skip first and last tile
	for i in range(1, line.size() - 1):
		if line[i] in blocked_tiles:
			return false
	return true

## Get tiles within a circular radius (using Euclidean distance)
## This creates a more rounded shape than the square Chebyshev distance
static func get_tiles_in_circular_range(center: Vector2i, radius: float) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var int_radius = int(ceil(radius))

	for x in range(-int_radius, int_radius + 1):
		for y in range(-int_radius, int_radius + 1):
			if x == 0 and y == 0:
				continue
			# Use Euclidean distance for circular shape
			var dist = sqrt(x * x + y * y)
			if dist <= radius:
				tiles.append(center + Vector2i(x, y))
	return tiles

## Get the "Fat Cross" pattern - the 20 workable tiles around a city
## This is based on Civ4's Big Fat Cross (BFC) adapted for square grid
## Includes all tiles within Euclidean distance of ~2.24 (sqrt(5))
static func get_fat_cross(center: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []

	# All tiles within range 1 (8 tiles)
	for x in range(-1, 2):
		for y in range(-1, 2):
			if x == 0 and y == 0:
				continue
			tiles.append(center + Vector2i(x, y))

	# Cardinal tiles at range 2 (4 tiles) - N, E, S, W
	tiles.append(center + Vector2i(0, -2))  # N
	tiles.append(center + Vector2i(2, 0))   # E
	tiles.append(center + Vector2i(0, 2))   # S
	tiles.append(center + Vector2i(-2, 0))  # W

	# Semi-cardinal tiles at range 2 (8 tiles) - NE, SE, SW, NW directions
	tiles.append(center + Vector2i(1, -2))   # NNE
	tiles.append(center + Vector2i(2, -1))   # ENE
	tiles.append(center + Vector2i(2, 1))    # ESE
	tiles.append(center + Vector2i(1, 2))    # SSE
	tiles.append(center + Vector2i(-1, 2))   # SSW
	tiles.append(center + Vector2i(-2, 1))   # WSW
	tiles.append(center + Vector2i(-2, -1))  # WNW
	tiles.append(center + Vector2i(-1, -2))  # NNW

	return tiles  # Total: 8 + 4 + 8 = 20 tiles

## Get tiles for a specific culture level expansion pattern
## Level 0: 3x3 initial (8 neighbors)
## Level 1: Fat Cross (20 workable tiles)
## Level 2+: Circular expansion at increasing radii
static func get_culture_expansion_tiles(center: Vector2i, culture_level: int) -> Array[Vector2i]:
	match culture_level:
		0:
			# Initial 3x3 square (the 8 neighbors)
			return get_neighbors(center)
		1:
			# Fat Cross pattern (20 tiles)
			return get_fat_cross(center)
		2:
			# 3-tile radius circle
			return get_tiles_in_circular_range(center, 3.0)
		3:
			# 4-tile radius circle
			return get_tiles_in_circular_range(center, 4.0)
		4:
			# 5-tile radius circle
			return get_tiles_in_circular_range(center, 5.0)
		5:
			# 6-tile radius circle (Legendary)
			return get_tiles_in_circular_range(center, 6.0)
		_:
			# Beyond legendary - keep expanding
			return get_tiles_in_circular_range(center, float(culture_level + 1))
