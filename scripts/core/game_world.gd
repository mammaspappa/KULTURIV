class_name GameWorld
extends Node2D
## Main game world manager. Handles the game grid, units, cities, and player interaction.

const PathfindingClass = preload("res://scripts/map/pathfinding.gd")

# Child nodes (initialized in _ready, either from scene tree or created dynamically)
var grid_layer: Node2D = null
var entity_layer: Node2D = null
var ui_layer: CanvasLayer = null

# References
var game_grid = null  # GameGrid (untyped to avoid load-order issues)

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
	# Use existing child nodes from scene, or create dynamically
	if has_node("GridLayer"):
		grid_layer = $GridLayer
	else:
		grid_layer = Node2D.new()
		grid_layer.name = "GridLayer"
		add_child(grid_layer)

	if has_node("EntityLayer"):
		entity_layer = $EntityLayer
	else:
		entity_layer = Node2D.new()
		entity_layer.name = "EntityLayer"
		add_child(entity_layer)

	if has_node("UILayer"):
		ui_layer = $UILayer
	else:
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
		# Debug shortcuts (Alt + key)
		if event.alt_pressed:
			match event.keycode:
				KEY_W:
					_debug_spawn_unit("worker")
					get_viewport().set_input_as_handled()
					return
				KEY_S:
					_debug_spawn_unit("settler")
					get_viewport().set_input_as_handled()
					return

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
				# Build: found city for settlers, build improvements for workers
				if selected_unit:
					if selected_unit.can_found_city():
						found_city(selected_unit)
					elif selected_unit.can_build_improvements():
						_show_build_menu()
			KEY_F5:
				# Quick save
				SaveSystem.quicksave()
			KEY_F9:
				# Quick load
				SaveSystem.quickload()
			KEY_ESCAPE:
				# Deselect
				_deselect_all()
			# Numpad movement (8-directional)
			KEY_KP_8:
				_move_unit_in_direction(GridUtils.Direction.N)
			KEY_KP_9:
				_move_unit_in_direction(GridUtils.Direction.NE)
			KEY_KP_6:
				_move_unit_in_direction(GridUtils.Direction.E)
			KEY_KP_3:
				_move_unit_in_direction(GridUtils.Direction.SE)
			KEY_KP_2:
				_move_unit_in_direction(GridUtils.Direction.S)
			KEY_KP_1:
				_move_unit_in_direction(GridUtils.Direction.SW)
			KEY_KP_4:
				_move_unit_in_direction(GridUtils.Direction.W)
			KEY_KP_7:
				_move_unit_in_direction(GridUtils.Direction.NW)
			KEY_KP_5:
				# Skip turn / center on unit
				if selected_unit:
					selected_unit.skip_turn()

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

	# Connect grid signals
	game_grid.tile_clicked.connect(_on_tile_clicked)

	# Place starting units for players
	_place_starting_units()

	# Start the game
	TurnManager.start_game()

	# Note: Camera centering is handled by game.gd (the 3D camera)

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
	var raycast = GameManager.get_meta("input_raycast") if GameManager.has_meta("input_raycast") else null
	if raycast == null:
		return
	var grid_pos = raycast.screen_to_grid(screen_pos)
	if grid_pos == Vector2i(-1, -1):
		return

	# Check for unit at click position
	var clicked_unit = _get_unit_at_screen_pos(grid_pos)
	var clicked_city = GameManager.get_city_at(grid_pos)

	# If clicking on own unit, select it
	if clicked_unit and clicked_unit.player_owner == GameManager.human_player:
		_select_unit(clicked_unit)
		return

	# If clicking on own city, select it
	if clicked_city and clicked_city.player_owner == GameManager.human_player:
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
	var raycast = GameManager.get_meta("input_raycast") if GameManager.has_meta("input_raycast") else null
	if raycast == null:
		return
	var grid_pos = raycast.screen_to_grid(screen_pos)
	if grid_pos == Vector2i(-1, -1):
		return

	# If unit selected, try to move or attack
	if selected_unit:
		var target_unit = _get_unit_at_screen_pos(grid_pos)

		# Attack enemy
		if target_unit and target_unit.player_owner != selected_unit.player_owner:
			if selected_unit.can_attack(target_unit):
				_attack_unit(selected_unit, target_unit)
				return

		# Move to position
		if selected_unit.can_move():
			# Don't move to current position
			if grid_pos == selected_unit.grid_position:
				return

			var grid = game_grid if game_grid != null else GameManager.hex_grid
			if grid == null:
				return

			# Always use pathfinding for movement - simpler and more reliable
			var pathfinder = PathfindingClass.new(grid, selected_unit)
			var path = pathfinder.find_path_with_movement(selected_unit.grid_position, grid_pos, selected_unit.movement_remaining)
			if not path.is_empty():
				selected_unit.move_along_path(path)
				_update_reachable_tiles()

				# If destination not reached, set GOTO order for multi-turn movement
				if selected_unit.grid_position != grid_pos:
					selected_unit.current_order = selected_unit.UnitOrder.GOTO
					selected_unit.order_target = grid_pos
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

	# Find path using valid grid reference
	var grid = game_grid if game_grid != null else GameManager.hex_grid
	if grid == null:
		return

	var pathfinder = PathfindingClass.new(grid, selected_unit)
	var path = pathfinder.find_path_with_movement(selected_unit.grid_position, target, selected_unit.movement_remaining)

	if not path.is_empty():
		selected_unit.move_along_path(path)

func _attack_unit(attacker: Unit, defender: Unit) -> void:
	# Emit attack event
	EventBus.unit_attacked.emit(attacker, defender)

	var defender_pos = defender.grid_position
	var defender_owner = defender.player_owner

	# Resolve combat using CombatSystem
	var result = CombatSystem.resolve_combat(attacker, defender)

	# Check for city capture after combat (attacker won and defender died)
	if result.get("attacker_won", false) and is_instance_valid(attacker) and attacker.health > 0:
		_check_city_capture(attacker, defender_pos, defender_owner)

	# Update movement overlay after combat
	_update_reachable_tiles()

## Move selected unit in a direction (for numpad/keyboard movement)
func _move_unit_in_direction(direction: int) -> void:
	if selected_unit == null or not selected_unit.can_move():
		return

	var target_pos = GridUtils.get_neighbor(selected_unit.grid_position, direction)

	# Wrap position if map wraps
	if game_grid:
		target_pos = GridUtils.wrap_position(target_pos, game_grid.width, game_grid.height)

	# Check for enemy unit to attack
	var target_unit = GameManager.get_unit_at(target_pos)
	if target_unit and target_unit.player_owner != selected_unit.player_owner:
		if selected_unit.can_attack(target_unit):
			_attack_unit(selected_unit, target_unit)
		return

	# Try to move directly to adjacent tile
	if selected_unit.can_move_to(target_pos):
		selected_unit.move_to(target_pos)
		_update_reachable_tiles()

func _update_reachable_tiles() -> void:
	_clear_movement_overlay()
	reachable_tiles.clear()

	if not selected_unit or not selected_unit.can_move():
		return

	# Make sure we have a valid grid
	var grid = game_grid if game_grid != null else GameManager.hex_grid
	if grid == null:
		return

	var pathfinder = PathfindingClass.new(grid, selected_unit)
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
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Allow clicks to pass through
	indicator.add_child(rect)

	return indicator

func _clear_movement_overlay() -> void:
	for child in movement_overlay.get_children():
		child.queue_free()

func _update_path_preview() -> void:
	_clear_path_preview()

	if not selected_unit:
		return

	var raycast = GameManager.get_meta("input_raycast") if GameManager.has_meta("input_raycast") else null
	if raycast == null:
		return

	var mouse_pos = get_tree().root.get_mouse_position()
	var target_pos = raycast.screen_to_grid(mouse_pos)
	if target_pos == Vector2i(-1, -1):
		return

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
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Allow clicks to pass through
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
	if unit.player_owner == GameManager.human_player:
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

	# Fallback auto-build (proper UI is in game_ui.gd _update_worker_actions)
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
	var owner = settler.player_owner

	# Get city name
	var civ_data = DataManager.get_civ(owner.civilization_id)
	var city_names = civ_data.get("city_names", ["City"])
	var city_count = owner.cities.size()
	var city_name = city_names[city_count % city_names.size()]

	# Create city
	var city = City.new(pos, city_name)
	city.original_owner_id = owner.player_id
	city.founder_civ_id = owner.civilization_id
	owner.add_city(city)
	entity_layer.add_child(city)

	# First city for non-barbarians gets a free palace (becomes capital)
	if city_count == 0 and owner.civilization_id != "barbarian":
		city.buildings.append("palace")
		city.calculate_yields()

	# Set tile ownership
	for tile_pos in city.territory:
		var tile = game_grid.get_tile(tile_pos)
		if tile:
			tile.tile_owner = owner
			tile.city_owner = city
			tile.update_visuals()

	# City tile gets a road automatically
	var city_tile = game_grid.get_tile(pos)
	if city_tile and city_tile.road_level < 1:
		city_tile.road_level = 1
		city_tile.update_visuals()

	# Reveal visibility around the new city
	VisibilitySystem.reveal_for_city(city)

	# Remove settler
	settler.die()

	EventBus.city_founded.emit(city, settler)
	return city

## Check if a city should be captured after combat victory
func _check_city_capture(attacker: Unit, defender_pos: Vector2i, defender_owner) -> void:
	var city = GameManager.get_city_at(defender_pos)
	if city == null or city.player_owner != defender_owner:
		return

	# Check if there are still enemy defenders on the tile
	var remaining_defenders = GameManager.get_units_at(defender_pos)
	for unit in remaining_defenders:
		if unit.player_owner == defender_owner and unit.get_strength() > 0:
			return  # Still has defenders

	# Move attacker onto the city tile
	if attacker.grid_position != defender_pos:
		attacker.grid_position = defender_pos
		attacker.position = GridUtils.grid_to_pixel(defender_pos)

	# For human player, show capture dialog
	if attacker.player_owner.is_human:
		_show_capture_dialog(city, attacker.player_owner)
	else:
		# AI decision
		_ai_capture_decision(city, attacker.player_owner)

## Show capture dialog for human player
func _show_capture_dialog(city, new_owner) -> void:
	var old_owner = city.player_owner
	var dialog = AcceptDialog.new()
	dialog.title = "City Captured!"
	dialog.dialog_text = "%s has been captured!\nPopulation: %d" % [city.city_name, city.population]

	# Remove default OK button
	dialog.get_ok_button().hide()

	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER

	var keep_btn = Button.new()
	keep_btn.text = "Keep"
	keep_btn.pressed.connect(func():
		capture_city(city, new_owner)
		dialog.queue_free()
	)
	hbox.add_child(keep_btn)

	if city.can_be_razed():
		var raze_btn = Button.new()
		raze_btn.text = "Raze"
		raze_btn.pressed.connect(func():
			raze_city(city)
			dialog.queue_free()
		)
		hbox.add_child(raze_btn)

	# Check if can liberate (original owner is different from capturer and still exists)
	if city.original_owner_id != new_owner.player_id and city.original_owner_id != -1:
		var original = GameManager.get_player(city.original_owner_id)
		if original != null and original != city.player_owner:
			var liberate_btn = Button.new()
			liberate_btn.text = "Liberate"
			liberate_btn.pressed.connect(func():
				liberate_city(city, new_owner)
				dialog.queue_free()
			)
			hbox.add_child(liberate_btn)

	dialog.add_child(hbox)
	dialog.min_size = Vector2(300, 150)

	# Add to UI layer
	if ui_layer:
		ui_layer.add_child(dialog)
	else:
		add_child(dialog)
	dialog.popup_centered()

## AI decides what to do with a captured city (BTS personality-driven)
func _ai_capture_decision(city, new_owner) -> void:
	# AI always keeps capitals and holy cities
	if not city.can_be_razed():
		capture_city(city, new_owner)
		return

	# Check if can liberate for diplomatic bonus
	if city.original_owner_id != new_owner.player_id and city.original_owner_id != -1:
		var original = GameManager.get_player(city.original_owner_id)
		if original != null and original != city.player_owner:
			var leader = DataManager.get_leader(new_owner.leader_id)
			var peace_weight = leader.get("base_peace_weight", 5)
			# Peaceful leaders liberate more often for diplomacy bonus
			if peace_weight >= 7 and not GameManager.is_at_war(new_owner, original):
				liberate_city(city, new_owner)
				return

	# BTS raze decision uses leader personality
	var leader = DataManager.get_leader(new_owner.leader_id)
	var raze_prob = leader.get("raze_city_prob", 20)

	# Apply AI aggressiveness modifier
	match GameManager.ai_aggressiveness:
		"peaceful":
			raze_prob = int(raze_prob * 0.5)
		"aggressive":
			raze_prob = int(raze_prob * 1.5)
		"random":
			raze_prob = int(raze_prob * randf_range(0.5, 1.5))

	# Distance from capital increases raze chance
	var capital_pos = Vector2i.ZERO
	for c in new_owner.cities:
		if c.is_capital():
			capital_pos = c.grid_position
			break
	var distance = GridUtils.chebyshev_distance(city.grid_position, capital_pos)
	if distance > 12:
		raze_prob += 15
	elif distance > 8:
		raze_prob += 5

	# Having many cities increases raze chance (maintenance pressure)
	var own_cities = new_owner.cities.size()
	if own_cities > 6:
		raze_prob += 10

	# Small cities are more likely to be razed
	if city.population <= 2:
		raze_prob += 10
	elif city.population >= 6:
		raze_prob -= 15

	# Cities close to own territory are kept
	for c in new_owner.cities:
		if GridUtils.chebyshev_distance(city.grid_position, c.grid_position) <= 4:
			raze_prob -= 20
			break

	raze_prob = clampi(raze_prob, 0, 100)
	if randi() % 100 < raze_prob:
		raze_city(city)
	else:
		capture_city(city, new_owner)

## Capture a city (transfer ownership)
func capture_city(city, new_owner) -> void:
	var old_owner = city.player_owner
	city.transfer_to(new_owner)
	EventBus.city_captured.emit(city, old_owner, new_owner)
	EventBus.notification_added.emit("%s has captured %s!" % [new_owner.player_name, city.city_name])

## Raze (destroy) a captured city
func raze_city(city) -> void:
	var owner = city.player_owner
	var city_name = city.city_name

	# Remove from owner
	if owner:
		owner.cities.erase(city)

	# Clear territory ownership
	for tile_pos in city.territory:
		var tile = game_grid.get_tile(tile_pos) if game_grid else null
		if tile:
			tile.tile_owner = null
			tile.city_owner = null
			tile.update_visuals()

	# Remove from scene
	EventBus.city_destroyed.emit(city)
	EventBus.notification_added.emit("%s has been razed!" % city_name)
	city.queue_free()

	# Check if owner is now eliminated
	if owner and owner.is_eliminated():
		EventBus.player_eliminated.emit(owner)

## Liberate a city (return to original owner)
func liberate_city(city, liberator) -> void:
	var original_owner = GameManager.get_player(city.original_owner_id)
	if original_owner == null:
		# Can't liberate if original owner doesn't exist, just keep it
		capture_city(city, liberator)
		return

	# Transfer to original owner
	city.transfer_to(original_owner)
	city.resistance_turns = 0  # No resistance when liberated

	# Diplomatic bonus for liberating
	DiplomacySystem.add_memory(original_owner.player_id, liberator.player_id, DiplomacySystem.MemoryType.LIBERATED_CITY)

	EventBus.city_captured.emit(city, liberator, original_owner)
	EventBus.notification_added.emit("%s has been liberated!" % city.city_name)

## Debug: Spawn a unit at the human player's capital
func _debug_spawn_unit(unit_type: String) -> void:
	var player = GameManager.human_player
	if player == null:
		return

	# Find capital (first city or city with palace)
	var capital = null
	for city in player.cities:
		if city.has_building("palace"):
			capital = city
			break
	if capital == null and player.cities.size() > 0:
		capital = player.cities[0]

	if capital == null:
		return

	# Find an empty tile near the capital
	var spawn_pos = capital.grid_position
	var unit_at_pos = GameManager.get_unit_at(spawn_pos)
	if unit_at_pos != null:
		# Find adjacent empty tile
		var neighbors = GridUtils.get_neighbors(spawn_pos)
		for neighbor in neighbors:
			var tile = game_grid.get_tile(neighbor) if game_grid else null
			if tile and tile.is_passable() and not tile.is_water():
				if GameManager.get_unit_at(neighbor) == null:
					spawn_pos = neighbor
					break

	var unit = spawn_unit(unit_type, spawn_pos, player)
	if unit:
		_select_unit(unit)
