class_name GameWorld
extends Node2D
## Main game world manager. Handles the game grid, units, cities, and player interaction.

const PathfindingClass = preload("res://scripts/map/pathfinding.gd")

# Child nodes
@onready var grid_layer: Node2D = $GridLayer
@onready var entity_layer: Node2D = $EntityLayer
@onready var ui_layer: CanvasLayer = $UILayer

# References
var game_grid = null  # GameGrid (untyped to avoid load-order issues)
var game_camera: GameCamera = null

# Selection state
var selected_unit = null  # Unit (untyped to avoid load-order issues)
var selected_city = null  # City (untyped to avoid load-order issues)
var current_path: Array[Vector2i] = []
var reachable_tiles: Array[Vector2i] = []

# Path preview node
var path_preview: Node2D = null

# Movement indicator
var movement_overlay: Node2D = null

func _ready() -> void:
	# Create layers if not in scene
	if not has_node("GridLayer"):
		grid_layer = Node2D.new()
		grid_layer.name = "GridLayer"
		add_child(grid_layer)

	if not has_node("EntityLayer"):
		entity_layer = Node2D.new()
		entity_layer.name = "EntityLayer"
		add_child(entity_layer)

	if not has_node("UILayer"):
		ui_layer = CanvasLayer.new()
		ui_layer.name = "UILayer"
		add_child(ui_layer)

	# Create path preview
	path_preview = Node2D.new()
	path_preview.name = "PathPreview"
	add_child(path_preview)

	# Create movement overlay
	movement_overlay = Node2D.new()
	movement_overlay.name = "MovementOverlay"
	add_child(movement_overlay)

	# Register with GameManager
	GameManager.game_world = self

	# Connect signals
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.unit_deselected.connect(_on_unit_deselected)
	EventBus.city_selected.connect(_on_city_selected)
	EventBus.city_deselected.connect(_on_city_deselected)
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.unit_moved.connect(_on_unit_moved)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(event.position)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(event.position)

	# Keyboard shortcuts
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				if selected_unit:
					selected_unit.skip_turn()
			KEY_F:
				if selected_unit:
					selected_unit.fortify()
			KEY_ENTER, KEY_KP_ENTER:
				TurnManager.end_turn()
			KEY_T:
				EventBus.show_tech_tree.emit()
			KEY_B:
				# Build improvement menu for workers
				if selected_unit and selected_unit.can_build_improvements():
					_show_build_menu()
			KEY_C:
				# Found city with settler
				if selected_unit and selected_unit.can_found_city():
					found_city(selected_unit)
			KEY_F5:
				# Quick save
				SaveSystem.quicksave()
			KEY_F9:
				# Quick load
				SaveSystem.quickload()
			KEY_ESCAPE:
				# Deselect
				_deselect_all()

func _process(_delta: float) -> void:
	# Update path preview on mouse move
	if selected_unit and selected_unit.can_move():
		_update_path_preview()

## Initialize the game world with generated map
func initialize_game(settings: Dictionary) -> void:
	# Create grid
	game_grid = GameGrid.new()
	grid_layer.add_child(game_grid)
	GameManager.game_grid = game_grid

	# Generate map
	var map_width = settings.get("map_width", 40)
	var map_height = settings.get("map_height", 25)
	game_grid.generate_map(map_width, map_height)

	# Create camera
	game_camera = GameCamera.new()
	game_camera.set_map_bounds(map_width, map_height)
	add_child(game_camera)

	# Connect grid signals
	game_grid.tile_clicked.connect(_on_tile_clicked)

	# Place starting units for players
	_place_starting_units()

	# Start the game
	TurnManager.start_game()

	# Center camera on human player's starting location
	if GameManager.human_player and GameManager.human_player.units.size() > 0:
		var start_unit = GameManager.human_player.units[0]
		game_camera.center_on_grid(start_unit.grid_position)

func _place_starting_units() -> void:
	var start_positions: Array[Vector2i] = []

	for player in GameManager.players:
		# Find starting location
		var start_pos = game_grid.find_starting_location(start_positions)
		start_positions.append(start_pos)

		# Create settler
		var settler = Unit.new("settler", start_pos)
		player.add_unit(settler)
		entity_layer.add_child(settler)
		settler._update_visibility()

		# Create warrior
		var warrior_pos = _find_adjacent_land(start_pos)
		var warrior = Unit.new("warrior", warrior_pos)
		player.add_unit(warrior)
		entity_layer.add_child(warrior)
		warrior._update_visibility()

func _find_adjacent_land(pos: Vector2i) -> Vector2i:
	var neighbors = GridUtils.get_neighbors(pos)
	for neighbor in neighbors:
		var tile = game_grid.get_tile(neighbor)
		if tile and tile.is_passable() and not tile.is_water():
			if GameManager.get_unit_at(neighbor) == null:
				return neighbor
	return pos  # Fallback to same position

func _handle_left_click(screen_pos: Vector2) -> void:
	var world_pos = game_camera.get_global_mouse_position() if game_camera else get_global_mouse_position()
	var grid_pos = GridUtils.pixel_to_grid(world_pos)

	# Check for unit at click position
	var clicked_unit = _get_unit_at_screen_pos(grid_pos)
	var clicked_city = GameManager.get_city_at(grid_pos)

	# If clicking on own unit, select it
	if clicked_unit and clicked_unit.owner == GameManager.human_player:
		_select_unit(clicked_unit)
		return

	# If clicking on own city, select it
	if clicked_city and clicked_city.owner == GameManager.human_player:
		_select_city(clicked_city)
		return

	# If unit is selected and clicking on valid move target
	if selected_unit and selected_unit.can_move():
		if grid_pos in reachable_tiles:
			_move_selected_unit(grid_pos)
			return

	# Deselect if clicking elsewhere
	_deselect_all()

func _handle_right_click(screen_pos: Vector2) -> void:
	var world_pos = game_camera.get_global_mouse_position() if game_camera else get_global_mouse_position()
	var grid_pos = GridUtils.pixel_to_grid(world_pos)

	# If unit selected, try to move or attack
	if selected_unit:
		var target_unit = _get_unit_at_screen_pos(grid_pos)

		# Attack enemy
		if target_unit and target_unit.owner != selected_unit.owner:
			if selected_unit.can_attack(target_unit):
				_attack_unit(selected_unit, target_unit)
				return

		# Move to position
		if selected_unit.can_move() and grid_pos in reachable_tiles:
			_move_selected_unit(grid_pos)
			return

func _get_unit_at_screen_pos(grid_pos: Vector2i) -> Unit:
	# Check for friendly unit first
	var units = GameManager.get_units_at(grid_pos)
	if not units.is_empty():
		return units[0]
	return null

func _select_unit(unit: Unit) -> void:
	_deselect_all()
	selected_unit = unit
	unit.select()
	_update_reachable_tiles()

func _select_city(city: City) -> void:
	_deselect_all()
	selected_city = city
	city.select()
	EventBus.show_city_screen.emit(city)

func _deselect_all() -> void:
	if selected_unit:
		selected_unit.deselect()
		selected_unit = null
	if selected_city:
		selected_city.deselect()
		selected_city = null
	_clear_path_preview()
	_clear_movement_overlay()

func _move_selected_unit(target: Vector2i) -> void:
	if not selected_unit:
		return

	# Find path
	var pathfinder = PathfindingClass.new(game_grid, selected_unit)
	var path = pathfinder.find_path_with_movement(selected_unit.grid_position, target, selected_unit.movement_remaining)

	if not path.is_empty():
		selected_unit.move_along_path(path)

func _attack_unit(attacker: Unit, defender: Unit) -> void:
	# Emit attack event
	EventBus.unit_attacked.emit(attacker, defender)

	# Resolve combat using CombatSystem
	var result = CombatSystem.resolve_combat(attacker, defender)

	# Update movement overlay after combat
	_update_reachable_tiles()

func _update_reachable_tiles() -> void:
	_clear_movement_overlay()
	reachable_tiles.clear()

	if not selected_unit or not selected_unit.can_move():
		return

	var pathfinder = PathfindingClass.new(game_grid, selected_unit)
	reachable_tiles = pathfinder.get_reachable_tiles(selected_unit.grid_position, selected_unit.movement_remaining)

	_draw_movement_overlay()

func _draw_movement_overlay() -> void:
	movement_overlay.queue_redraw()

	# Create indicator for each reachable tile
	for tile_pos in reachable_tiles:
		var indicator = _create_tile_indicator(tile_pos, Color(0, 0.5, 1, 0.3))
		movement_overlay.add_child(indicator)

func _create_tile_indicator(grid_pos: Vector2i, color: Color) -> Node2D:
	var indicator = Node2D.new()
	indicator.position = GridUtils.grid_to_pixel_corner(grid_pos)

	# Create colored rect
	var rect = ColorRect.new()
	rect.color = color
	rect.size = Vector2(GridUtils.TILE_SIZE, GridUtils.TILE_SIZE)
	indicator.add_child(rect)

	return indicator

func _clear_movement_overlay() -> void:
	for child in movement_overlay.get_children():
		child.queue_free()

func _update_path_preview() -> void:
	_clear_path_preview()

	if not selected_unit or not game_camera:
		return

	var world_pos = game_camera.get_global_mouse_position()
	var target_pos = GridUtils.pixel_to_grid(world_pos)

	if target_pos not in reachable_tiles:
		return

	# Find path to mouse position
	var pathfinder = PathfindingClass.new(game_grid, selected_unit)
	current_path = pathfinder.find_path_with_movement(selected_unit.grid_position, target_pos, selected_unit.movement_remaining)

	# Draw path
	for i in range(current_path.size()):
		var pos = current_path[i]
		var indicator = _create_path_indicator(pos, i)
		path_preview.add_child(indicator)

func _create_path_indicator(grid_pos: Vector2i, index: int) -> Node2D:
	var indicator = Node2D.new()
	indicator.position = GridUtils.grid_to_pixel(grid_pos)

	# Draw circle
	var circle = Node2D.new()
	circle.set_script(load("res://scripts/ui/path_circle.gd") if FileAccess.file_exists("res://scripts/ui/path_circle.gd") else null)

	# Fallback: use ColorRect
	var rect = ColorRect.new()
	rect.color = Color(1, 1, 0, 0.5)
	rect.size = Vector2(16, 16)
	rect.position = Vector2(-8, -8)
	indicator.add_child(rect)

	return indicator

func _clear_path_preview() -> void:
	current_path.clear()
	for child in path_preview.get_children():
		child.queue_free()

func _on_tile_clicked(tile: GameTile) -> void:
	# Handle tile click (already processed in _handle_left_click)
	pass

func _on_unit_selected(unit: Unit) -> void:
	if unit.owner == GameManager.human_player:
		_update_reachable_tiles()

func _on_unit_deselected(_unit: Unit) -> void:
	_clear_path_preview()
	_clear_movement_overlay()

func _on_city_selected(_city: City) -> void:
	pass

func _on_city_deselected(_city: City) -> void:
	pass

func _on_turn_started(_turn: int, player: Player) -> void:
	if player == GameManager.human_player:
		# Update UI, select first unit with movement, etc.
		_update_reachable_tiles()

func _on_unit_moved(_unit: Unit, _from: Vector2i, _to: Vector2i) -> void:
	_update_reachable_tiles()

## Spawn a unit at position
func spawn_unit(unit_type: String, pos: Vector2i, owner: Player) -> Unit:
	var unit = Unit.new(unit_type, pos)
	owner.add_unit(unit)
	entity_layer.add_child(unit)
	unit._update_visibility()
	EventBus.unit_created.emit(unit)
	return unit

## Show build menu for workers
func _show_build_menu() -> void:
	if selected_unit == null or not selected_unit.can_build_improvements():
		return

	var tile = game_grid.get_tile(selected_unit.grid_position) if game_grid else null
	if tile == null:
		return

	# Get available improvements
	var available = ImprovementSystem.get_available_improvements(selected_unit, tile)
	var can_road = ImprovementSystem.can_build_road(selected_unit, tile)
	var can_railroad = ImprovementSystem.can_build_railroad(selected_unit, tile)

	# For now, just build the first available or road
	# TODO: Create proper build menu UI
	if can_road:
		ImprovementSystem.start_build_road(selected_unit)
	elif can_railroad:
		ImprovementSystem.start_build_railroad(selected_unit)
	elif not available.is_empty():
		ImprovementSystem.start_build(selected_unit, available[0])

## Found a city at position
func found_city(settler: Unit) -> City:
	if not settler.can_found_city():
		return null

	var pos = settler.grid_position
	var owner = settler.owner

	# Get city name
	var civ_data = DataManager.get_civ(owner.civilization_id)
	var city_names = civ_data.get("city_names", ["City"])
	var city_count = owner.cities.size()
	var city_name = city_names[city_count % city_names.size()]

	# Create city
	var city = City.new(pos, city_name)
	owner.add_city(city)
	entity_layer.add_child(city)

	# Set tile ownership
	for tile_pos in city.territory:
		var tile = game_grid.get_tile(tile_pos)
		if tile:
			tile.owner = owner
			tile.city_owner = city
			tile.update_visuals()

	# Remove settler
	settler.die()

	EventBus.city_founded.emit(city, settler)
	return city
