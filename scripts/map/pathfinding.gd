class_name Pathfinding
extends RefCounted
## A* pathfinding for units on the game grid.

const GameTileClass = preload("res://scripts/map/game_tile.gd")

var grid  # GameGrid (untyped to avoid load-order issues)
var unit  # Unit (untyped to avoid load-order issues)

# Path result
var path: Array[Vector2i] = []
var total_cost: float = 0.0

func _init(game_grid, path_unit = null) -> void:
	grid = game_grid
	unit = path_unit

## Find path from start to goal using A*
func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	path.clear()
	total_cost = 0.0

	if grid == null:
		return path

	# Wrap positions for consistent handling
	var wrapped_start = _wrap_grid_position(start)
	var wrapped_goal = _wrap_grid_position(goal)

	if wrapped_start == wrapped_goal:
		return path

	# Check if goal is reachable
	var goal_tile = grid.get_tile(wrapped_goal)
	if goal_tile == null or not _is_tile_passable(goal_tile):
		return path

	# A* algorithm
	var open_set = PriorityQueue.new()
	var came_from: Dictionary = {}
	var g_score: Dictionary = {}
	var f_score: Dictionary = {}

	g_score[wrapped_start] = 0.0
	f_score[wrapped_start] = _heuristic(wrapped_start, wrapped_goal)
	open_set.push(wrapped_start, f_score[wrapped_start])

	var closed_set: Dictionary = {}

	while not open_set.is_empty():
		var current = open_set.pop()

		if current == wrapped_goal:
			# Reconstruct path
			path = _reconstruct_path(came_from, current)
			total_cost = g_score[current]
			return path

		closed_set[current] = true

		# Check neighbors
		var neighbors = GridUtils.get_neighbors(current)
		for neighbor in neighbors:
			# Wrap neighbor for consistent coordinates
			var wrapped_neighbor = _wrap_grid_position(neighbor)

			if wrapped_neighbor in closed_set:
				continue

			if not grid.is_valid_position(wrapped_neighbor):
				continue

			var neighbor_tile = grid.get_tile(wrapped_neighbor)
			if neighbor_tile == null or not _is_tile_passable(neighbor_tile):
				continue

			var move_cost = _get_movement_cost(neighbor_tile)
			var tentative_g = g_score.get(current, INF) + move_cost

			if tentative_g < g_score.get(wrapped_neighbor, INF):
				came_from[wrapped_neighbor] = current
				g_score[wrapped_neighbor] = tentative_g
				f_score[wrapped_neighbor] = tentative_g + _heuristic(wrapped_neighbor, wrapped_goal)

				if not open_set.contains(wrapped_neighbor):
					open_set.push(wrapped_neighbor, f_score[wrapped_neighbor])

	# No path found
	return path

## Find path considering movement points
func find_path_with_movement(start: Vector2i, goal: Vector2i, movement_points: float) -> Array[Vector2i]:
	# Wrap positions for consistent handling
	var wrapped_start = _wrap_grid_position(start)
	var wrapped_goal = _wrap_grid_position(goal)

	var full_path = find_path(wrapped_start, wrapped_goal)

	if full_path.is_empty():
		return full_path

	# Trim path to what we can actually move
	var reachable_path: Array[Vector2i] = []
	var remaining_movement = movement_points

	for pos in full_path:
		var tile = grid.get_tile(pos)
		if tile == null:
			break

		var cost = _get_movement_cost(tile)
		if remaining_movement >= cost or reachable_path.is_empty():
			reachable_path.append(pos)
			remaining_movement -= cost
			if remaining_movement <= 0:
				break
		else:
			break

	return reachable_path

## Get all tiles reachable within movement points
func get_reachable_tiles(start: Vector2i, movement_points: float) -> Array[Vector2i]:
	var reachable: Array[Vector2i] = []

	if grid == null:
		return reachable

	# Dijkstra's algorithm to find all reachable tiles
	var distances: Dictionary = {}
	var visited: Dictionary = {}
	var queue = PriorityQueue.new()

	# Wrap start position for consistent storage
	var wrapped_start = _wrap_grid_position(start)
	distances[wrapped_start] = 0.0
	queue.push(wrapped_start, 0.0)

	while not queue.is_empty():
		var current = queue.pop()

		if current in visited:
			continue
		visited[current] = true

		var current_dist = distances.get(current, INF)
		if current_dist <= movement_points and current != wrapped_start:
			reachable.append(current)

		var neighbors = GridUtils.get_neighbors(current)
		for neighbor in neighbors:
			# Wrap neighbor position for consistent coordinate handling
			var wrapped_neighbor = _wrap_grid_position(neighbor)

			if wrapped_neighbor in visited:
				continue

			if not grid.is_valid_position(wrapped_neighbor):
				continue

			var neighbor_tile = grid.get_tile(wrapped_neighbor)
			if neighbor_tile == null or not _is_tile_passable(neighbor_tile):
				continue

			var move_cost = _get_movement_cost(neighbor_tile)
			var new_dist = current_dist + move_cost

			# Allow moving into tiles even if we don't have full movement
			# (as long as we have any movement left)
			if new_dist <= movement_points or (current_dist < movement_points and current_dist + 1 <= movement_points + 1):
				if new_dist < distances.get(wrapped_neighbor, INF):
					distances[wrapped_neighbor] = new_dist
					queue.push(wrapped_neighbor, new_dist)

	return reachable

## Wrap grid position for consistent coordinate storage
func _wrap_grid_position(pos: Vector2i) -> Vector2i:
	if grid == null:
		return pos
	var result = pos
	if grid.wrap_x:
		result.x = posmod(pos.x, grid.width)
	if grid.wrap_y:
		result.y = posmod(pos.y, grid.height)
	return result

## Get the cost to reach a specific tile
func get_path_cost(start: Vector2i, goal: Vector2i) -> float:
	find_path(start, goal)
	return total_cost

## Check if tile is passable for this unit
func _is_tile_passable(tile) -> bool:
	if not tile.is_passable():
		return false

	# Check water traversal
	if tile.is_water():
		if unit != null:
			return unit.get_unit_class() == "naval"
		return false

	# Check for enemy units blocking
	if unit != null:
		var blocking_unit = GameManager.get_unit_at(tile.grid_position)
		if blocking_unit != null and blocking_unit.player_owner != unit.player_owner:
			return false

	return true

## Get movement cost for a tile
func _get_movement_cost(tile) -> float:
	var base_cost = float(tile.get_total_movement_cost())

	# Unit-specific modifiers
	if unit != null:
		# Ignore terrain cost ability
		if "ignore_terrain_cost" in unit.get_abilities():
			return 1.0

		# Promotion effects for terrain
		for promo in unit.promotions:
			var effects = DataManager.get_promotion_effects(promo)
			if tile.feature_id == "forest" and effects.get("forest_double_movement", false):
				base_cost = 1.0
			if tile.terrain_id == "hills" and effects.get("hills_double_movement", false):
				base_cost = 1.0

	return base_cost

## Heuristic function (Chebyshev distance for 8-directional movement, accounting for wrap)
func _heuristic(from: Vector2i, to: Vector2i) -> float:
	var dx = abs(to.x - from.x)
	var dy = abs(to.y - from.y)

	# Account for X wrapping
	if grid != null and grid.wrap_x:
		var wrap_dx = grid.width - dx
		dx = min(dx, wrap_dx)

	# Account for Y wrapping
	if grid != null and grid.wrap_y:
		var wrap_dy = grid.height - dy
		dy = min(dy, wrap_dy)

	return float(max(dx, dy))

## Reconstruct path from came_from map
func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = [current]
	while current in came_from:
		current = came_from[current]
		result.push_front(current)
	# Remove start position
	if result.size() > 0:
		result.remove_at(0)
	return result


## Simple priority queue implementation
class PriorityQueue:
	var heap: Array = []
	var positions: Dictionary = {}

	func push(item: Vector2i, priority: float) -> void:
		heap.append({"item": item, "priority": priority})
		positions[item] = heap.size() - 1
		_sift_up(heap.size() - 1)

	func pop() -> Vector2i:
		if heap.is_empty():
			return Vector2i.ZERO

		var result = heap[0].item
		positions.erase(result)

		if heap.size() > 1:
			heap[0] = heap.pop_back()
			positions[heap[0].item] = 0
			_sift_down(0)
		else:
			heap.pop_back()

		return result

	func is_empty() -> bool:
		return heap.is_empty()

	func contains(item: Vector2i) -> bool:
		return item in positions

	func _sift_up(idx: int) -> void:
		while idx > 0:
			var parent = (idx - 1) / 2
			if heap[idx].priority < heap[parent].priority:
				_swap(idx, parent)
				idx = parent
			else:
				break

	func _sift_down(idx: int) -> void:
		var size = heap.size()
		while true:
			var smallest = idx
			var left = 2 * idx + 1
			var right = 2 * idx + 2

			if left < size and heap[left].priority < heap[smallest].priority:
				smallest = left
			if right < size and heap[right].priority < heap[smallest].priority:
				smallest = right

			if smallest != idx:
				_swap(idx, smallest)
				idx = smallest
			else:
				break

	func _swap(i: int, j: int) -> void:
		var temp = heap[i]
		heap[i] = heap[j]
		heap[j] = temp
		positions[heap[i].item] = i
		positions[heap[j].item] = j
