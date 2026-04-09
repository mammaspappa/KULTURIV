class_name GameGrid
extends Node2D
## Manages the entire game map grid.
## Uses a 7-stage geologically realistic generation pipeline:
## 1. Tectonic plates  2. Elevation  3. Climate/wind  4. Terrain
## 5. Watershed rivers  6. Features  7. Resources

# Map dimensions
var width: int = 80
var height: int = 50
var wrap_x: bool = true
var wrap_y: bool = false

# Tile storage
var tiles: Dictionary = {}  # Vector2i -> GameTile

# Generation thresholds (initialized from tunables/mapgen.json at generate time;
# the inline defaults match the historic hardcoded values).
var _sea_level: float = 0.4
var _mountain_threshold: float = 0.82
var _hill_threshold: float = 0.68

func _refresh_thresholds_from_tunables() -> void:
	_sea_level = float(DataManager.get_tunable("mapgen.thresholds.sea_level", 0.4))
	_mountain_threshold = float(DataManager.get_tunable("mapgen.thresholds.mountain", 0.82))
	_hill_threshold = float(DataManager.get_tunable("mapgen.thresholds.hill", 0.68))

# Intermediate buffers (allocated during generation, freed after)
var _plate_map: PackedInt32Array
var _plate_count: int = 0
var _plate_is_continental: Array[bool] = []
var _plate_drift: Array[Vector2] = []
var _plate_growth_weight: Array[int] = []
var _elevation_map: PackedFloat32Array
var _temperature_map: PackedFloat32Array
var _moisture_map: PackedFloat32Array
var _flow_direction: PackedInt32Array
var _flow_accumulation: PackedFloat32Array
var _ocean_distance: PackedInt32Array
var _boundary_type: PackedInt32Array  # 0=none, 1=convergent, 2=divergent, 3=transform

# Direction lookup tables
const DIR_DX = [0, 1, 1, 1, 0, -1, -1, -1]
const DIR_DY = [-1, -1, 0, 1, 1, 1, 0, -1]

# Noise for perturbation
var _noise: FastNoiseLite

signal map_generated()
signal tile_clicked(tile)

func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_octaves = 3

# =============================================================================
# PUBLIC API (unchanged)
# =============================================================================

func generate_map(w: int = 80, h: int = 50) -> void:
	width = w
	height = h

	# Clear existing tiles
	for tile in tiles.values():
		tile.queue_free()
	tiles.clear()

	_noise.seed = randi()
	var map_type = GameManager.map_type if GameManager else "fractal"
	_refresh_thresholds_from_tunables()

	_allocate_buffers()

	# Stage 1: Tectonic plates
	_generate_plates(map_type)

	# Stage 2: Elevation from plates
	_generate_elevation(map_type)

	# Stage 3: Climate
	_generate_temperature()
	_generate_moisture()

	# Stage 4: Create tiles with terrain
	_create_all_tiles()
	_apply_coast_detection()
	_apply_terrain_transitions()

	# Stage 5: Rivers (watershed)
	_compute_flow_directions()
	_fill_sinks()
	_create_lakes()
	_compute_flow_accumulation()
	_extract_rivers()

	# Stage 6: Features
	_add_features()

	# Stage 7: Resources (existing logic)
	_add_resources()

	# Post-processing
	_add_goody_huts()
	_assign_continents()
	_prepare_starting_locations()

	_free_buffers()
	map_generated.emit()

# =============================================================================
# BUFFER MANAGEMENT
# =============================================================================

func _allocate_buffers() -> void:
	var total = width * height
	_plate_map = PackedInt32Array()
	_plate_map.resize(total)
	_plate_map.fill(-1)
	_elevation_map = PackedFloat32Array()
	_elevation_map.resize(total)
	_elevation_map.fill(0.0)
	_temperature_map = PackedFloat32Array()
	_temperature_map.resize(total)
	_moisture_map = PackedFloat32Array()
	_moisture_map.resize(total)
	_flow_direction = PackedInt32Array()
	_flow_direction.resize(total)
	_flow_direction.fill(-1)
	_flow_accumulation = PackedFloat32Array()
	_flow_accumulation.resize(total)
	_ocean_distance = PackedInt32Array()
	_ocean_distance.resize(total)
	_ocean_distance.fill(999)
	_boundary_type = PackedInt32Array()
	_boundary_type.resize(total)
	_boundary_type.fill(0)

func _free_buffers() -> void:
	_plate_map = PackedInt32Array()
	_elevation_map = PackedFloat32Array()
	_temperature_map = PackedFloat32Array()
	_moisture_map = PackedFloat32Array()
	_flow_direction = PackedInt32Array()
	_flow_accumulation = PackedFloat32Array()
	_ocean_distance = PackedInt32Array()
	_boundary_type = PackedInt32Array()
	_plate_is_continental.clear()
	_plate_drift.clear()
	_plate_growth_weight.clear()

func _idx(x: int, y: int) -> int:
	return y * width + x

func _wrap_x(x: int) -> int:
	return posmod(x, width) if wrap_x else clampi(x, 0, width - 1)

# =============================================================================
# STAGE 1: TECTONIC PLATES
# =============================================================================

func _generate_plates(map_type: String) -> void:
	# Plate counts and growth weights are looked up in tunables (mapgen.plates.<map_type>).
	# An unrecognized map_type falls back to the "fractal" entry.
	var preset: Dictionary = DataManager.get_tunable("mapgen.plates." + map_type, {}) as Dictionary
	if preset.is_empty():
		preset = DataManager.get_tunable("mapgen.plates.fractal", {}) as Dictionary

	var continental_count: int = randi_range(
		int(preset.get("continental_count_min", 4)),
		int(preset.get("continental_count_max", 7))
	)
	var oceanic_count: int = randi_range(
		int(preset.get("oceanic_count_min", 5)),
		int(preset.get("oceanic_count_max", 8))
	)
	var continental_weight_range := Vector2i(
		int(preset.get("continental_weight_min", 3)),
		int(preset.get("continental_weight_max", 6))
	)
	var oceanic_weight_range := Vector2i(
		int(preset.get("oceanic_weight_min", 3)),
		int(preset.get("oceanic_weight_max", 5))
	)

	_plate_count = continental_count + oceanic_count
	_plate_is_continental.resize(_plate_count)
	_plate_drift.resize(_plate_count)
	_plate_growth_weight.resize(_plate_count)

	# Sow seeds
	_sow_plate_seeds(map_type, continental_count, oceanic_count,
		continental_weight_range, oceanic_weight_range)

	# Grow plates via weighted BFS flood fill
	_fill_plates()

	# Assign drift vectors
	_assign_plate_drift(map_type)

	# Classify boundaries
	_classify_boundaries()

func _sow_plate_seeds(map_type: String, cont_count: int, ocean_count: int,
		cont_weight: Vector2i, ocean_weight: Vector2i) -> void:
	var seeds: Array[Vector2i] = []
	var min_spacing = max(width, height) / (_plate_count + 2)
	var y_margin = max(3, height / 8)

	# Place continental plate seeds
	for i in range(cont_count):
		_plate_is_continental[i] = true
		_plate_growth_weight[i] = randi_range(cont_weight.x, cont_weight.y)
		var pos = _find_plate_seed(seeds, min_spacing, map_type, true, y_margin)
		seeds.append(pos)
		_plate_map[_idx(pos.x, pos.y)] = i

	# Place oceanic plate seeds
	for i in range(ocean_count):
		var pid = cont_count + i
		_plate_is_continental[pid] = false
		_plate_growth_weight[pid] = randi_range(ocean_weight.x, ocean_weight.y)
		var pos = _find_plate_seed(seeds, min_spacing / 2, map_type, false, 0)
		seeds.append(pos)
		_plate_map[_idx(pos.x, pos.y)] = pid

func _find_plate_seed(existing: Array[Vector2i], min_dist: int,
		map_type: String, is_continental: bool, y_margin: int) -> Vector2i:
	for _attempt in range(500):
		var x: int
		var y: int
		if is_continental and map_type == "pangaea":
			# Cluster near center
			x = randi_range(width / 4, width * 3 / 4)
			y = randi_range(height / 4, height * 3 / 4)
		elif is_continental:
			x = randi_range(0, width - 1)
			y = randi_range(y_margin, height - 1 - y_margin)
		else:
			x = randi_range(0, width - 1)
			y = randi_range(0, height - 1)

		var pos = Vector2i(x, y)
		var ok = true
		for s in existing:
			var dx = abs(pos.x - s.x)
			if wrap_x:
				dx = mini(dx, width - dx)
			var dy = abs(pos.y - s.y)
			if max(dx, dy) < min_dist:
				ok = false
				break
		if ok:
			return pos

	# Fallback: random position
	return Vector2i(randi_range(0, width - 1), randi_range(0, height - 1))

func _fill_plates() -> void:
	# BFS-style weighted flood fill (per BTS fillPlates)
	for _iteration in range(width + height):
		var any_unassigned = false
		for y in range(height):
			for x in range(width):
				var idx = _idx(x, y)
				if _plate_map[idx] != -1:
					continue
				any_unassigned = true
				# Check 4 cardinal neighbors
				for dir in [0, 2, 4, 6]:  # N, E, S, W
					var nx = _wrap_x(x + DIR_DX[dir])
					var ny = y + DIR_DY[dir]
					if ny < 0 or ny >= height:
						continue
					var n_plate = _plate_map[_idx(nx, ny)]
					if n_plate >= 0:
						if randi() % 10 < _plate_growth_weight[n_plate]:
							_plate_map[idx] = n_plate
							break
		if not any_unassigned:
			break

	# Force-assign remaining tiles to nearest plate
	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			if _plate_map[idx] == -1:
				_plate_map[idx] = _nearest_plate(x, y)

func _nearest_plate(x: int, y: int) -> int:
	var best_plate = 0
	var best_dist = 999999
	for cy in range(height):
		for cx in range(width):
			var cidx = _idx(cx, cy)
			if _plate_map[cidx] >= 0:
				var dx = abs(x - cx)
				if wrap_x:
					dx = mini(dx, width - dx)
				var dy = abs(y - cy)
				var d = dx + dy
				if d < best_dist:
					best_dist = d
					best_plate = _plate_map[cidx]
				if d <= 1:
					return best_plate
	return best_plate

func _assign_plate_drift(map_type: String) -> void:
	for i in range(_plate_count):
		_plate_drift[i] = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

func _classify_boundaries() -> void:
	var convergence_threshold = 0.5
	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			var my_plate = _plate_map[idx]
			var max_convergence = 0.0
			var is_boundary = false

			for dir in range(8):
				var nx = _wrap_x(x + DIR_DX[dir])
				var ny = y + DIR_DY[dir]
				if ny < 0 or ny >= height:
					continue
				var n_plate = _plate_map[_idx(nx, ny)]
				if n_plate == my_plate:
					continue

				is_boundary = true
				var boundary_normal = Vector2(DIR_DX[dir], DIR_DY[dir]).normalized()
				var relative_vel = _plate_drift[n_plate] - _plate_drift[my_plate]
				var convergence = relative_vel.dot(boundary_normal)
				if abs(convergence) > abs(max_convergence):
					max_convergence = convergence

			if is_boundary:
				if max_convergence > convergence_threshold:
					_boundary_type[idx] = 1  # Convergent
				elif max_convergence < -convergence_threshold:
					_boundary_type[idx] = 2  # Divergent
				else:
					_boundary_type[idx] = 3  # Transform

# =============================================================================
# STAGE 2: ELEVATION
# =============================================================================

func _generate_elevation(map_type: String) -> void:
	# Base elevation from plate type
	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			if _plate_is_continental[_plate_map[idx]]:
				_elevation_map[idx] = 0.50 + randf() * 0.12
			else:
				_elevation_map[idx] = 0.12 + randf() * 0.10

	# Apply plate boundary effects
	_apply_boundary_elevation()

	# Foothills gradient from mountains
	_apply_foothills()

	# Noise perturbation for natural irregularity
	_noise.frequency = 0.03
	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			_elevation_map[idx] += _noise.get_noise_2d(x, y) * 0.08

	# Polar depression
	for y in range(height):
		var latitude = abs(float(y) - height / 2.0) / (height / 2.0)
		if latitude > 0.85:
			var factor = 0.2 + 0.8 * ((1.0 - latitude) / 0.15)
			for x in range(width):
				_elevation_map[_idx(x, y)] *= factor

	# Erosion smoothing
	_apply_erosion(3)

	# Determine sea level from target water percentage
	var target_water: float
	match map_type:
		"pangaea": target_water = 0.32
		"continents": target_water = 0.58
		"archipelago": target_water = 0.68
		_: target_water = 0.52

	_determine_sea_level(target_water)

	# Clamp
	for i in range(width * height):
		_elevation_map[i] = clampf(_elevation_map[i], 0.0, 1.0)

func _apply_boundary_elevation() -> void:
	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			var btype = _boundary_type[idx]
			if btype == 0:
				continue

			var my_plate = _plate_map[idx]
			var my_continental = _plate_is_continental[my_plate]

			# Check if neighbor across boundary is continental
			var neighbor_continental = false
			for dir in range(8):
				var nx = _wrap_x(x + DIR_DX[dir])
				var ny = y + DIR_DY[dir]
				if ny < 0 or ny >= height:
					continue
				var n_plate = _plate_map[_idx(nx, ny)]
				if n_plate != my_plate:
					neighbor_continental = _plate_is_continental[n_plate]
					break

			match btype:
				1:  # Convergent
					if my_continental and neighbor_continental:
						# Continental collision → major mountain range
						_elevation_map[idx] = 0.85 + randf() * 0.15
					elif my_continental:
						# Subduction: continental side gets coastal mountains
						_elevation_map[idx] = 0.75 + randf() * 0.15
					elif neighbor_continental:
						# Oceanic side of subduction: trench
						_elevation_map[idx] = 0.05 + randf() * 0.08
					else:
						# Oceanic-oceanic: island arc
						_elevation_map[idx] = 0.50 + randf() * 0.25
				2:  # Divergent
					if my_continental:
						# Rift valley
						_elevation_map[idx] = 0.32 + randf() * 0.10
					else:
						# Mid-ocean ridge
						_elevation_map[idx] = 0.22 + randf() * 0.10
				3:  # Transform
					_elevation_map[idx] += randf() * 0.12

func _apply_foothills() -> void:
	# BFS outward from mountain boundary tiles, decay elevation bonus
	var mountain_tiles: Array[int] = []
	for i in range(width * height):
		if _boundary_type[i] == 1 and _elevation_map[i] > 0.75:
			mountain_tiles.append(i)

	var visited = PackedInt32Array()
	visited.resize(width * height)
	visited.fill(0)
	var queue: Array = []

	for idx in mountain_tiles:
		visited[idx] = 1
		queue.append({"idx": idx, "dist": 0, "bonus": _elevation_map[idx] - 0.50})

	while not queue.is_empty():
		var item = queue.pop_front()
		var cx = item.idx % width
		var cy = item.idx / width
		var dist = item.dist
		var bonus = item.bonus

		if dist >= 5:
			continue

		for dir in [0, 2, 4, 6]:  # Cardinal only for BFS
			var nx = _wrap_x(cx + DIR_DX[dir])
			var ny = cy + DIR_DY[dir]
			if ny < 0 or ny >= height:
				continue
			var nidx = _idx(nx, ny)
			if visited[nidx] == 1:
				continue
			visited[nidx] = 1
			var decayed = bonus * 0.45
			if decayed > 0.02:
				_elevation_map[nidx] = maxf(_elevation_map[nidx], _elevation_map[nidx] + decayed)
				queue.append({"idx": nidx, "dist": dist + 1, "bonus": decayed})

func _apply_erosion(passes: int) -> void:
	for _pass in range(passes):
		var new_elev = _elevation_map.duplicate()
		for y in range(height):
			for x in range(width):
				var idx = _idx(x, y)
				var total = _elevation_map[idx] * 4.0
				var count = 4.0
				for dir in [0, 2, 4, 6]:
					var nx = _wrap_x(x + DIR_DX[dir])
					var ny = y + DIR_DY[dir]
					if ny >= 0 and ny < height:
						total += _elevation_map[_idx(nx, ny)]
						count += 1.0
				new_elev[idx] = total / count
		_elevation_map = new_elev

func _determine_sea_level(target_water_pct: float) -> void:
	# Sort elevations and pick the percentile
	var sorted_elev: Array[float] = []
	for i in range(width * height):
		sorted_elev.append(_elevation_map[i])
	sorted_elev.sort()
	var index = clampi(int(target_water_pct * sorted_elev.size()), 0, sorted_elev.size() - 1)
	_sea_level = sorted_elev[index]

	# Set mountain/hill thresholds relative to land range
	var land_range = 1.0 - _sea_level
	_mountain_threshold = _sea_level + land_range * 0.82
	_hill_threshold = _sea_level + land_range * 0.62

# =============================================================================
# STAGE 3: CLIMATE & WIND
# =============================================================================

func _generate_temperature() -> void:
	# First compute ocean distance for maritime moderation
	_compute_ocean_distance()

	for y in range(height):
		var latitude = abs(float(y) - height / 2.0) / (height / 2.0)
		for x in range(width):
			var idx = _idx(x, y)
			var temp = 1.0 - latitude  # Equator hot, poles cold

			# Altitude cooling
			if _elevation_map[idx] > _sea_level:
				var alt_factor = (_elevation_map[idx] - _sea_level) / (1.0 - _sea_level)
				temp -= alt_factor * 0.3

			# Maritime moderation (coastal = moderate, inland = extreme)
			var ocean_dist = _ocean_distance[idx]
			if ocean_dist < 999 and _elevation_map[idx] >= _sea_level:
				var coastal_factor = 1.0 - clampf(float(ocean_dist) / 10.0, 0.0, 1.0)
				temp = lerpf(temp, 0.5, coastal_factor * 0.18)

			# Subtle noise variation
			temp += _noise.get_noise_2d(x * 1.5, y * 1.5) * 0.06

			_temperature_map[idx] = clampf(temp, 0.0, 1.0)

func _compute_ocean_distance() -> void:
	# Multi-source BFS from all ocean tiles
	var queue: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			if _elevation_map[_idx(x, y)] < _sea_level:
				_ocean_distance[_idx(x, y)] = 0
				queue.append(Vector2i(x, y))

	var head = 0
	while head < queue.size():
		var pos = queue[head]
		head += 1
		var cur_dist = _ocean_distance[_idx(pos.x, pos.y)]
		if cur_dist >= 15:
			continue
		for dir in [0, 2, 4, 6]:
			var nx = _wrap_x(pos.x + DIR_DX[dir])
			var ny = pos.y + DIR_DY[dir]
			if ny < 0 or ny >= height:
				continue
			var nidx = _idx(nx, ny)
			if cur_dist + 1 < _ocean_distance[nidx]:
				_ocean_distance[nidx] = cur_dist + 1
				queue.append(Vector2i(nx, ny))

func _generate_moisture() -> void:
	# Wind-driven moisture simulation (Coriolis effect)
	# Ocean tiles generate moisture; wind carries it inland
	var max_wind_force = max(8, width / 8)

	for y in range(height):
		for x in range(width):
			if _elevation_map[_idx(x, y)] >= _sea_level:
				continue
			# This is an ocean tile — blow moisture in wind direction
			var latitude = abs(float(y) - height / 2.0) / (height / 2.0) * 90.0
			var is_southern = y > height / 2
			var wind_dir = _get_wind_direction(latitude, is_southern)
			var moisture_load = 5.0 + max_wind_force
			_blow_moisture(x, y, wind_dir.x, wind_dir.y, moisture_load, max_wind_force)

	# Normalize moisture to [0, 1]
	var max_moisture = 0.001
	for i in range(width * height):
		if _moisture_map[i] > max_moisture:
			max_moisture = _moisture_map[i]
	for i in range(width * height):
		_moisture_map[i] = clampf(_moisture_map[i] / max_moisture, 0.0, 1.0)

	# Add subtle noise to break up uniform bands
	_noise.frequency = 0.025
	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			_moisture_map[idx] = clampf(
				_moisture_map[idx] + _noise.get_noise_2d(x + 500.0, y + 500.0) * 0.1,
				0.0, 1.0)

func _get_wind_direction(latitude_deg: float, is_southern: bool) -> Vector2i:
	# Coriolis wind bands
	var hx: int
	var vy: int
	if latitude_deg > 60:
		hx = 1   # Polar easterlies (blow westward, source from east = +x)
		vy = -1 if is_southern else 1  # Toward equator
	elif latitude_deg > 30:
		hx = -1  # Westerlies (blow eastward, source from west = -x)
		vy = 1 if is_southern else -1  # Toward poles
	else:
		hx = 1   # Trade winds (blow westward)
		vy = -1 if is_southern else 1  # Toward equator
	return Vector2i(hx, vy)

func _blow_moisture(start_x: int, start_y: int, dx: int, dy: int,
		moisture_load: float, max_steps: int) -> void:
	var x = start_x
	var y = start_y
	var load = moisture_load

	for _step in range(max_steps):
		x = _wrap_x(x + dx)
		y = y + dy
		if y < 0 or y >= height:
			return
		var idx = _idx(x, y)

		# Deposit moisture
		_moisture_map[idx] += load * 0.3

		# Terrain reduces moisture
		if _elevation_map[idx] >= _sea_level:
			if _elevation_map[idx] > _mountain_threshold:
				# Mountains block ALL remaining moisture (rain shadow!)
				_moisture_map[idx] += load * 0.7  # Dump moisture on windward side
				return
			elif _elevation_map[idx] > _hill_threshold:
				load -= 5.0  # Hills cause heavy rainfall
			else:
				load -= 1.0  # Flat land: gradual loss
		else:
			# Passing over water: replenish slightly
			load += 1.0

		if load <= 0:
			return

	# Also blow a minor perpendicular component
	var perp_x = start_x
	var perp_y = start_y
	var perp_load = moisture_load * 0.3
	for _step in range(max_steps / 3):
		perp_x = _wrap_x(perp_x + dx)
		perp_y = perp_y  # Only horizontal spread
		if perp_y < 0 or perp_y >= height:
			return
		var pidx = _idx(perp_x, perp_y)
		_moisture_map[pidx] += perp_load * 0.15
		perp_load -= 0.5
		if perp_load <= 0:
			return

# =============================================================================
# STAGE 4: TERRAIN ASSIGNMENT
# =============================================================================

func _create_all_tiles() -> void:
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			var idx = _idx(x, y)
			var tile = GameTile.new(pos)
			var elev = _elevation_map[idx]
			var temp = _temperature_map[idx]
			var moist = _moisture_map[idx]

			if elev < _sea_level:
				tile.terrain_id = "ocean"  # Coast detection comes later
			elif elev > _mountain_threshold:
				tile.terrain_id = "mountains"
			elif elev > _hill_threshold:
				tile.terrain_id = "hills"
			else:
				tile.terrain_id = _assign_biome(temp, moist)

			tiles[pos] = tile
			add_child(tile)

func _assign_biome(temp: float, moist: float) -> String:
	# Whittaker-diagram inspired classification
	if temp < 0.12:
		return "snow"
	if temp < 0.22:
		return "snow" if moist < 0.3 else "tundra"
	if temp < 0.35:
		return "tundra"
	# Temperate to tropical
	if moist < 0.18:
		return "desert" if temp > 0.50 else "plains"
	if moist < 0.35:
		return "desert" if temp > 0.65 else "plains"
	if moist < 0.55:
		return "grassland" if temp > 0.45 else "plains"
	return "grassland"

func _apply_coast_detection() -> void:
	for y in range(height):
		for x in range(width):
			var tile = tiles[Vector2i(x, y)]
			if tile.terrain_id != "ocean":
				continue
			# Check if adjacent to land
			for dir in range(8):
				var nx = _wrap_x(x + DIR_DX[dir])
				var ny = y + DIR_DY[dir]
				if ny < 0 or ny >= height:
					continue
				var n_tile = tiles.get(Vector2i(nx, ny))
				if n_tile != null and not n_tile.is_water():
					tile.terrain_id = "coast"
					break

func _apply_terrain_transitions() -> void:
	# Desert-to-grassland buffer: insert plains transition
	var to_plains: Array[Vector2i] = []
	for y in range(height):
		for x in range(width):
			var tile = tiles[Vector2i(x, y)]
			if tile.terrain_id != "grassland":
				continue
			for dir in range(8):
				var nx = _wrap_x(x + DIR_DX[dir])
				var ny = y + DIR_DY[dir]
				if ny < 0 or ny >= height:
					continue
				var n_tile = tiles.get(Vector2i(nx, ny))
				if n_tile != null and n_tile.terrain_id == "desert":
					to_plains.append(Vector2i(x, y))
					break

	for pos in to_plains:
		tiles[pos].terrain_id = "plains"

# =============================================================================
# STAGE 5: WATERSHED RIVERS
# =============================================================================

func _compute_flow_directions() -> void:
	# Rivers flow along tile borders (cardinal directions only: N, E, S, W)
	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			if _elevation_map[idx] < _sea_level:
				_flow_direction[idx] = -1
				continue
			var best_dir = -1
			var best_drop = 0.0
			for dir in [0, 2, 4, 6]:  # Cardinal only: N, E, S, W
				var nx = _wrap_x(x + DIR_DX[dir])
				var ny = y + DIR_DY[dir]
				if ny < 0 or ny >= height:
					continue
				var drop = _elevation_map[idx] - _elevation_map[_idx(nx, ny)]
				if drop > best_drop:
					best_drop = drop
					best_dir = dir
			_flow_direction[idx] = best_dir

func _fill_sinks() -> void:
	# Find land tiles with no downhill neighbor (sinks) and raise them
	# Only fill small sinks (<6 tiles); large ones become lakes
	var changed = true
	var max_passes = 10
	var pass_num = 0
	while changed and pass_num < max_passes:
		changed = false
		pass_num += 1
		for y in range(height):
			for x in range(width):
				var idx = _idx(x, y)
				if _elevation_map[idx] < _sea_level:
					continue
				if _flow_direction[idx] >= 0:
					continue
				# This is a sink — find lowest neighbor that has an outlet
				var lowest_rim = 999.0
				for dir in range(8):
					var nx = _wrap_x(x + DIR_DX[dir])
					var ny = y + DIR_DY[dir]
					if ny < 0 or ny >= height:
						continue
					var n_elev = _elevation_map[_idx(nx, ny)]
					if n_elev < lowest_rim:
						lowest_rim = n_elev
				# Raise sink to just above rim
				if lowest_rim < 999.0 and lowest_rim >= _elevation_map[idx]:
					_elevation_map[idx] = lowest_rim + 0.001
					changed = true

		# Recompute flow directions for affected tiles
		if changed:
			_compute_flow_directions()

func _create_lakes() -> void:
	# Find remaining sinks (large depressions) and convert to lakes
	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			if _elevation_map[idx] < _sea_level:
				continue
			if _flow_direction[idx] >= 0:
				continue
			# This tile is still a sink — flood fill to find the depression
			var depression: Array[Vector2i] = []
			var visited: Dictionary = {}
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			visited[Vector2i(x, y)] = true
			while not queue.is_empty():
				var pos = queue.pop_front()
				var pidx = _idx(pos.x, pos.y)
				if _flow_direction[pidx] >= 0:
					continue  # Has outlet, not part of sink
				if _elevation_map[pidx] < _sea_level:
					continue
				depression.append(pos)
				for dir in range(8):
					var nx = _wrap_x(pos.x + DIR_DX[dir])
					var ny = pos.y + DIR_DY[dir]
					if ny < 0 or ny >= height:
						continue
					var npos = Vector2i(nx, ny)
					if npos not in visited:
						visited[npos] = true
						if _flow_direction[_idx(nx, ny)] < 0 and _elevation_map[_idx(nx, ny)] >= _sea_level:
							queue.append(npos)

			if depression.size() >= 3:
				# Convert to lake (coast tiles)
				for pos in depression:
					var pidx = _idx(pos.x, pos.y)
					_elevation_map[pidx] = _sea_level - 0.05
					if tiles.has(pos):
						tiles[pos].terrain_id = "coast"

func _compute_flow_accumulation() -> void:
	# Sort land tiles by elevation descending
	var land_tiles: Array[int] = []
	for i in range(width * height):
		if _elevation_map[i] >= _sea_level:
			land_tiles.append(i)

	land_tiles.sort_custom(func(a, b): return _elevation_map[a] > _elevation_map[b])

	# Initialize accumulation
	for i in range(width * height):
		if _elevation_map[i] >= _sea_level:
			_flow_accumulation[i] = 1.0 + _moisture_map[i]

	# Propagate downstream
	for idx in land_tiles:
		var dir = _flow_direction[idx]
		if dir < 0:
			continue
		var x = idx % width
		var y = idx / width
		var nx = _wrap_x(x + DIR_DX[dir])
		var ny = y + DIR_DY[dir]
		if ny >= 0 and ny < height:
			_flow_accumulation[_idx(nx, ny)] += _flow_accumulation[idx]

func _extract_rivers() -> void:
	var river_threshold = maxf(12.0, float(width * height) / 500.0)

	for y in range(height):
		for x in range(width):
			var idx = _idx(x, y)
			if _flow_accumulation[idx] < river_threshold:
				continue
			if _elevation_map[idx] < _sea_level:
				continue

			var tile = tiles[Vector2i(x, y)]

			# Outgoing edge
			var out_dir = _flow_direction[idx]
			if out_dir >= 0 and out_dir not in tile.river_edges:
				tile.river_edges.append(out_dir)

			# Incoming edges from river neighbors (cardinal only)
			for dir in [0, 2, 4, 6]:
				var nx = _wrap_x(x + DIR_DX[dir])
				var ny = y + DIR_DY[dir]
				if ny < 0 or ny >= height:
					continue
				var nidx = _idx(nx, ny)
				if _flow_accumulation[nidx] < river_threshold:
					continue
				# Check if neighbor flows INTO this tile
				var n_dir = _flow_direction[nidx]
				var opposite = (dir + 4) % 8
				if n_dir == opposite:
					if dir not in tile.river_edges:
						tile.river_edges.append(dir)

# =============================================================================
# STAGE 6: FEATURES
# =============================================================================

func _add_features() -> void:
	for y in range(height):
		for x in range(width):
			var pos = Vector2i(x, y)
			var tile = tiles[pos]
			var idx = _idx(x, y)
			var temp = _temperature_map[idx]
			var moist = _moisture_map[idx]

			if tile.is_water():
				# Ice on polar ocean/coast
				if temp < 0.15 and tile.terrain_id in ["coast", "ocean"]:
					if randf() < 0.8:
						tile.feature_id = "ice"
				continue

			if tile.is_mountains():
				continue

			# Jungle: tropical + very wet
			if temp > 0.7 and moist > 0.55:
				if tile.terrain_id in ["grassland", "plains"]:
					if randf() < 0.65:
						tile.feature_id = "jungle"
						continue

			# Forest: temperate + moist
			if temp > 0.3 and temp < 0.75 and moist > 0.35:
				if tile.terrain_id in ["grassland", "plains", "tundra", "hills"]:
					if randf() < 0.35:
						tile.feature_id = "forest"
						continue

			# Flood plains: desert with rivers
			if tile.terrain_id == "desert" and not tile.river_edges.is_empty():
				tile.feature_id = "flood_plains"
				continue

			# Oasis: desert without rivers, chance scales with moisture
			if tile.terrain_id == "desert" and tile.river_edges.is_empty():
				if randf() < 0.02 + moist * 0.03:
					tile.feature_id = "oasis"

# =============================================================================
# STAGE 7: RESOURCES (unchanged from original)
# =============================================================================

func _add_resources() -> void:
	var all_resources = DataManager.resources
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

	# Strategic resources
	var strategic_count = max(4, total_land / 80)
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

	# Luxury resources (clustered)
	var luxury_count = max(6, total_land / 60)
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
				if cluster_center != Vector2i(-1, -1) and placed > 0:
					if GridUtils.chebyshev_distance(pos, cluster_center) > 5:
						continue
				tile.resource_id = resource_id
				if cluster_center == Vector2i(-1, -1):
					cluster_center = pos
				placed += 1

	# Bonus resources
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

# =============================================================================
# POST-PROCESSING (unchanged from original)
# =============================================================================

func _prepare_starting_locations() -> void:
	pass

func _add_goody_huts() -> void:
	var density = 0.02
	var placed = 0
	for pos in tiles:
		var tile = tiles[pos]
		if tile.is_water() or tile.terrain_id == "mountains":
			continue
		if randf() < density:
			if pos.y > 5 and pos.y < height - 5:
				tile.has_goody_hut = true
				placed += 1
	print("[MapGen] Placed %d goody huts" % placed)

func _assign_continents() -> void:
	var next_id = 0
	var visited: Dictionary = {}
	for pos in tiles:
		if pos in visited:
			continue
		var tile = tiles[pos]
		if tile.is_water():
			tile.continent_id = -1
			visited[pos] = true
			continue
		var queue: Array[Vector2i] = [pos]
		visited[pos] = true
		while not queue.is_empty():
			var current = queue.pop_front()
			tiles[current].continent_id = next_id
			for n_pos in GridUtils.get_neighbors(current):
				if n_pos in visited:
					continue
				var wrapped = _wrap_position(n_pos)
				if wrapped not in tiles:
					continue
				if wrapped in visited:
					continue
				var n_tile = tiles[wrapped]
				if n_tile.is_water():
					continue
				visited[wrapped] = true
				queue.append(wrapped)
		next_id += 1

# =============================================================================
# TILE ACCESS & UTILITIES (unchanged from original)
# =============================================================================

func get_tile(pos: Vector2i) -> GameTile:
	# Reject out-of-bounds queries on non-wrapping axes. Returning the clamped
	# edge tile here would let units "step" off the edge — can_move_to() relies
	# on get_tile() returning null to refuse the move.
	if not wrap_x and (pos.x < 0 or pos.x >= width):
		return null
	if not wrap_y and (pos.y < 0 or pos.y >= height):
		return null
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

func find_all_starting_locations(num_players: int) -> Array[Vector2i]:
	var map_tiles = float(width * height)
	var tiles_per_player = map_tiles / max(num_players, 1)
	var ideal_spacing = max(8, int(sqrt(tiles_per_player) * 0.7))
	var min_quality = max(8.0, 20.0 - num_players * 1.0 - (2000.0 / max(map_tiles, 100.0)) * 5.0)

	var candidates: Array = []
	var y_margin = max(2, height / 10)
	for x in range(width):
		for y in range(y_margin, height - y_margin):
			var pos = Vector2i(x, y)
			var score = _score_start_location(pos)
			if score >= min_quality:
				candidates.append({"pos": pos, "score": score})

	candidates.sort_custom(func(a, b): return a.score > b.score)

	var selected: Array[Vector2i] = []
	var current_spacing = ideal_spacing

	while current_spacing >= 4:
		selected.clear()
		for candidate in candidates:
			var pos: Vector2i = candidate.pos
			var too_close = false
			for existing in selected:
				if GridUtils.chebyshev_distance(pos, existing) < current_spacing:
					too_close = true
					break
			if not too_close:
				selected.append(pos)
				if selected.size() >= num_players:
					break
		if selected.size() >= num_players:
			break
		current_spacing -= 2

	if selected.size() < num_players:
		return []

	var result: Array[Vector2i] = []
	for i in range(num_players):
		result.append(selected[i])

	for i in range(result.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var tmp = result[i]
		result[i] = result[j]
		result[j] = tmp

	return result

func _score_start_location(pos: Vector2i) -> float:
	var tile = get_tile(pos)
	if tile == null or not tile.is_passable() or tile.is_water():
		return 0.0

	var score = 0.0
	var nearby = get_tiles_in_range(pos, 2)
	var food_tiles = 0
	var prod_tiles = 0
	var commerce_tiles = 0
	var has_fresh_water = false
	var has_coast = false
	var resource_count = 0

	for nearby_tile in nearby:
		if nearby_tile == null or not nearby_tile.is_passable():
			continue
		if nearby_tile.is_water():
			has_coast = true
			continue
		var yields = nearby_tile.get_yields()
		var food = yields.get("food", 0)
		var prod = yields.get("production", 0)
		var comm = yields.get("commerce", 0)
		if food >= 2:
			food_tiles += 1
		if prod >= 1:
			prod_tiles += 1
		if comm >= 1:
			commerce_tiles += 1
		if nearby_tile.resource_id != "":
			resource_count += 1
		if nearby_tile.has_fresh_water():
			has_fresh_water = true

	if food_tiles < 2:
		return 0.0

	score += food_tiles * 3.0
	score += prod_tiles * 2.5
	score += commerce_tiles * 1.5
	score += resource_count * 3.0
	if has_fresh_water:
		score += 6.0
	if has_coast:
		score += 3.0

	var extended = get_tiles_in_range(pos, 3)
	for ext_tile in extended:
		if ext_tile != null and ext_tile.resource_id != "":
			var res = DataManager.get_resource(ext_tile.resource_id)
			var res_type = res.get("type", "")
			if res_type == "strategic":
				score += 2.0
			elif res_type == "luxury":
				score += 1.5

	return score

func find_starting_location(avoid_positions: Array[Vector2i], min_distance: int = -1) -> Vector2i:
	if min_distance < 0:
		min_distance = max(8, int(sqrt(width * height) / 4))

	var best_pos = Vector2i(-1, -1)
	var best_score = -1.0
	var y_margin = max(2, height / 10)

	for x in range(width):
		for y in range(y_margin, height - y_margin):
			var pos = Vector2i(x, y)
			var score = _score_start_location(pos)
			if score <= best_score:
				continue
			var too_close = false
			for avoid_pos in avoid_positions:
				if GridUtils.chebyshev_distance(pos, avoid_pos) < min_distance:
					too_close = true
					break
			if not too_close:
				best_score = score
				best_pos = pos

	if best_pos == Vector2i(-1, -1):
		for x in range(width):
			for y in range(y_margin, height - y_margin):
				var pos = Vector2i(x, y)
				var score = _score_start_location(pos)
				if score > best_score:
					var ok = true
					for avoid_pos in avoid_positions:
						if GridUtils.chebyshev_distance(pos, avoid_pos) < 4:
							ok = false
							break
					if ok:
						best_score = score
						best_pos = pos

	return best_pos

# =============================================================================
# INPUT & SERIALIZATION (unchanged from original)
# =============================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos = get_local_mouse_position()
			var grid_pos = GridUtils.pixel_to_grid(local_pos)
			var tile = get_tile(grid_pos)
			if tile != null:
				tile_clicked.emit(tile)

func update_all_tiles() -> void:
	for tile in tiles.values():
		tile.update_visuals()

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

	for tile in tiles.values():
		tile.queue_free()
	tiles.clear()

	var tiles_data = data.get("tiles", {})
	for key in tiles_data:
		var parts = key.split(",")
		var pos = Vector2i(int(parts[0]), int(parts[1]))
		var tile = GameTile.new(pos)
		tile.from_dict(tiles_data[key])
		tiles[pos] = tile
		add_child(tile)
