extends "res://addons/gut/test.gd"
## Verifies the source-based river generation produces sensible rivers:
##   - Generates a real map via GameGrid
##   - Counts tiles with river edges
##   - Checks every river segment eventually reaches water (no orphaned land-locked rivers)
##   - Confirms rivers only use cardinal edges (no diagonals)
##
## In the vertex-based river model, a river is a graph of *segments* between tile corners
## (vertices). Two segments are connected if they share a corner. To verify "rivers reach
## water" we reconstruct the vertex graph from per-tile river_edges, then BFS from any
## water-adjacent vertex and check that every segment endpoint is reachable.

const GameGridClass = preload("res://scripts/map/game_grid.gd")

func _make_grid(map_type: String, w: int, h: int) -> GameGridClass:
	# Stash and override map_type so the grid uses the requested preset.
	var saved_type = GameManager.map_type
	GameManager.map_type = map_type
	var grid: GameGridClass = GameGridClass.new()
	add_child_autofree(grid)
	grid.generate_map(w, h)
	GameManager.map_type = saved_type
	return grid

func _river_tile_positions(grid) -> Array:
	var result: Array = []
	for pos in grid.tiles.keys():
		var tile = grid.tiles[pos]
		if not tile.river_edges.is_empty():
			result.append(pos)
	return result

## Convert a (tile, edge) into the two vertices at the segment's endpoints.
## Vertex (vx, vy) is the top-left corner of tile (vx, vy); vy ∈ [0, height], vx wraps.
func _segment_endpoints(grid, tx: int, ty: int, edge: int) -> Array:
	var w = grid.width
	match edge:
		0:  # N — top edge from (tx, ty) to (tx+1, ty)
			return [Vector2i(tx, ty), Vector2i((tx + 1) % w, ty)]
		2:  # E — right edge from (tx+1, ty) to (tx+1, ty+1)
			return [Vector2i((tx + 1) % w, ty), Vector2i((tx + 1) % w, ty + 1)]
		4:  # S — bottom edge from (tx, ty+1) to (tx+1, ty+1)
			return [Vector2i(tx, ty + 1), Vector2i((tx + 1) % w, ty + 1)]
		6:  # W — left edge from (tx, ty) to (tx, ty+1)
			return [Vector2i(tx, ty), Vector2i(tx, ty + 1)]
		_:
			return []

## Is this vertex adjacent to water? A vertex (vx, vy) is shared by up to 4 tiles:
## (vx-1, vy-1), (vx, vy-1), (vx-1, vy), (vx, vy). Any water tile makes the vertex water-adjacent.
func _vertex_at_water(grid, v: Vector2i) -> bool:
	var w = grid.width
	var h = grid.height
	for off in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		var tx = (v.x + off.x + w) % w
		var ty = v.y + off.y
		if ty < 0 or ty >= h:
			continue
		var t = grid.tiles.get(Vector2i(tx, ty))
		if t != null and t.is_water():
			return true
	return false

func _river_tiles_reach_water(grid) -> bool:
	# Build the river segment graph in vertex space.
	# vertices: every vertex that is an endpoint of any river segment
	# adjacency: two vertices are adjacent if connected by at least one segment
	var vertices: Dictionary = {}      # Vector2i -> true
	var adj: Dictionary = {}           # Vector2i -> Array[Vector2i]
	for pos in grid.tiles.keys():
		var tile = grid.tiles[pos]
		if tile.river_edges.is_empty():
			continue
		for edge in tile.river_edges:
			var pair = _segment_endpoints(grid, pos.x, pos.y, edge)
			if pair.is_empty():
				continue
			var a: Vector2i = pair[0]
			var b: Vector2i = pair[1]
			vertices[a] = true
			vertices[b] = true
			adj[a] = adj.get(a, []) + [b]
			adj[b] = adj.get(b, []) + [a]

	if vertices.is_empty():
		return true  # No rivers to check.

	# Seed BFS from every water-adjacent vertex (these are river mouths).
	var reached: Dictionary = {}
	var queue: Array = []
	for v in vertices.keys():
		if _vertex_at_water(grid, v):
			reached[v] = true
			queue.append(v)

	while not queue.is_empty():
		var v: Vector2i = queue.pop_front()
		for n in adj.get(v, []):
			if reached.has(n):
				continue
			reached[n] = true
			queue.append(n)

	return reached.size() == vertices.size()

func _all_rivers_are_cardinal(grid) -> bool:
	for pos in grid.tiles.keys():
		var tile = grid.tiles[pos]
		for edge in tile.river_edges:
			if edge != 0 and edge != 2 and edge != 4 and edge != 6:
				return false
	return true

func test_continents_map_generates_rivers():
	var grid = _make_grid("continents", 60, 40)
	var river_positions = _river_tile_positions(grid)
	# Should produce a non-trivial number of river tiles on a map this size.
	assert_gt(river_positions.size(), 5, "continents map should produce >5 river tiles, got %d" % river_positions.size())

func test_continents_rivers_reach_water():
	var grid = _make_grid("continents", 60, 40)
	assert_true(_river_tiles_reach_water(grid),
		"every river tile should chain to water")

func test_continents_rivers_are_cardinal_only():
	var grid = _make_grid("continents", 60, 40)
	assert_true(_all_rivers_are_cardinal(grid),
		"river edges must be cardinal (N/E/S/W)")

func test_pangaea_rivers_reach_water():
	var grid = _make_grid("pangaea", 60, 40)
	assert_true(_river_tiles_reach_water(grid))
	assert_true(_all_rivers_are_cardinal(grid))

func test_archipelago_rivers_reach_water():
	var grid = _make_grid("archipelago", 60, 40)
	# Archipelago may legitimately have very few rivers (small islands), so we don't
	# assert a minimum count — just that any rivers that exist are well-formed.
	assert_true(_river_tiles_reach_water(grid))
	assert_true(_all_rivers_are_cardinal(grid))
