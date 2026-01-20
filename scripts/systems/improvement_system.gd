extends Node
## Handles worker improvements on tiles.

const UnitClass = preload("res://scripts/entities/unit.gd")

# Build times in turns
const BUILD_TIMES = {
	"farm": 5,
	"mine": 6,
	"road": 3,
	"railroad": 3,
	"cottage": 4,
	"lumber_mill": 5,
	"workshop": 5,
	"windmill": 5,
	"watermill": 5,
	"plantation": 5,
	"camp": 5,
	"pasture": 4,
	"quarry": 6,
	"well": 5,
	"winery": 5,
	"fort": 6
}

## Check if a worker can build a specific improvement on a tile
func can_build(worker, tile, improvement_id: String) -> bool:
	if not worker.can_build_improvements():
		return false

	if tile == null:
		return false

	# Can't build same improvement that's already there
	if tile.improvement_id == improvement_id:
		return false

	# Get improvement data
	var improvement = DataManager.get_improvement(improvement_id)
	if improvement.is_empty():
		return false

	# Check valid terrains
	var valid_terrains = improvement.get("valid_terrains", [])
	if not valid_terrains.is_empty():
		var terrain_valid = tile.terrain_id in valid_terrains
		var feature_valid = tile.feature_id != "" and tile.feature_id in valid_terrains
		if not terrain_valid and not feature_valid:
			return false

	# Check tech requirement
	var required_tech = improvement.get("required_tech", "")
	if required_tech != "" and worker.player_owner != null:
		if not worker.player_owner.has_tech(required_tech):
			return false

	# Check resource requirements (some improvements only work with certain resources)
	var requires_resource = improvement.get("requires_resource", [])
	if not requires_resource.is_empty():
		if tile.resource_id == "" or tile.resource_id not in requires_resource:
			return false

	# Check fresh water requirement
	var requires_fresh_water = improvement.get("requires_fresh_water_on", [])
	if tile.terrain_id in requires_fresh_water and not tile.has_fresh_water():
		return false

	# Can't build on water (except specific naval improvements)
	if tile.is_water() and improvement_id not in ["fishing_boats"]:
		return false

	return true

## Check if a worker can build a road
func can_build_road(worker, tile) -> bool:
	if not worker.can_build_improvements():
		return false

	if tile == null:
		return false

	# Can't build road on water
	if tile.is_water():
		return false

	# Already has road
	if tile.road_level >= 1:
		return false

	return true

## Check if a worker can build a railroad
func can_build_railroad(worker, tile) -> bool:
	if not worker.can_build_improvements():
		return false

	if tile == null:
		return false

	# Needs road first
	if tile.road_level < 1:
		return false

	# Already has railroad
	if tile.road_level >= 2:
		return false

	# Check tech requirement (usually railroad tech)
	if worker.player_owner != null and not worker.player_owner.has_tech("railroad"):
		return false

	return true

## Start building an improvement
func start_build(worker, improvement_id: String) -> void:
	worker.current_order = UnitClass.UnitOrder.BUILD
	worker.order_target_improvement = improvement_id
	worker.build_progress = 0
	worker.movement_remaining = 0
	worker.has_acted = true
	EventBus.unit_order_changed.emit(worker, worker.current_order)
	worker.update_visual()

## Start building a road
func start_build_road(worker) -> void:
	worker.current_order = UnitClass.UnitOrder.BUILD
	worker.order_target_improvement = "road"
	worker.build_progress = 0
	worker.movement_remaining = 0
	worker.has_acted = true
	EventBus.unit_order_changed.emit(worker, worker.current_order)
	worker.update_visual()

## Start building a railroad
func start_build_railroad(worker) -> void:
	worker.current_order = UnitClass.UnitOrder.BUILD
	worker.order_target_improvement = "railroad"
	worker.build_progress = 0
	worker.movement_remaining = 0
	worker.has_acted = true
	EventBus.unit_order_changed.emit(worker, worker.current_order)
	worker.update_visual()

## Process build progress at start of turn
## Returns true if build completed
func process_build(worker) -> bool:
	if worker.current_order != UnitClass.UnitOrder.BUILD:
		return false

	if worker.order_target_improvement == "":
		return false

	worker.build_progress += 1
	var time_needed = BUILD_TIMES.get(worker.order_target_improvement, 5)

	# Apply speed bonus from traits/techs if available
	# (simplified - would check worker's owner for bonuses)

	if worker.build_progress >= time_needed:
		_complete_build(worker)
		return true

	return false

func _complete_build(worker) -> void:
	var tile = GameManager.hex_grid.get_tile(worker.grid_position) if GameManager.hex_grid else null
	if tile == null:
		_clear_build_order(worker)
		return

	var improvement_id = worker.order_target_improvement

	# Handle road/railroad separately
	if improvement_id == "road":
		tile.road_level = 1
	elif improvement_id == "railroad":
		tile.road_level = 2
	else:
		# Check if we need to remove feature first (e.g., chopping forest)
		var improvement = DataManager.get_improvement(improvement_id)
		var removes_feature = improvement.get("removes_feature", [])
		if tile.feature_id in removes_feature:
			tile.feature_id = ""

		tile.improvement_id = improvement_id

	tile.update_visuals()
	EventBus.tile_improved.emit(worker.grid_position, improvement_id)

	_clear_build_order(worker)

func _clear_build_order(worker) -> void:
	worker.current_order = UnitClass.UnitOrder.NONE
	worker.order_target_improvement = ""
	worker.build_progress = 0
	worker.update_visual()

## Cancel build order
func cancel_build(worker) -> void:
	_clear_build_order(worker)

## Get list of available improvements for a worker at a tile
func get_available_improvements(worker, tile) -> Array:
	var available = []

	if tile == null or not worker.can_build_improvements():
		return available

	# Check each known improvement
	for imp_id in BUILD_TIMES.keys():
		if imp_id == "road" or imp_id == "railroad":
			continue  # Handle separately
		if can_build(worker, tile, imp_id):
			available.append(imp_id)

	return available

## Get build time for an improvement
func get_build_time(improvement_id: String) -> int:
	return BUILD_TIMES.get(improvement_id, 5)

## Get remaining turns for current build
func get_remaining_turns(worker) -> int:
	if worker.current_order != UnitClass.UnitOrder.BUILD:
		return 0

	var time_needed = BUILD_TIMES.get(worker.order_target_improvement, 5)
	return max(0, time_needed - worker.build_progress)
