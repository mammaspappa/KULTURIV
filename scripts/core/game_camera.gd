class_name GameCamera
extends Camera2D
## Camera controller for the game world with panning and zooming.

# Movement settings
@export var pan_speed: float = 800.0
@export var edge_pan_margin: int = 50
@export var edge_pan_enabled: bool = true

# Zoom settings
@export var min_zoom: float = 0.25  # Will be calculated based on map size
@export var max_zoom: float = 2.0
@export var zoom_speed: float = 0.1
@export var zoom_smooth: float = 10.0

# Bounds (will be set based on map size)
var map_bounds: Rect2 = Rect2(0, 0, 10000, 10000)
var wrap_x: bool = true  # Whether map wraps horizontally

# Internal state
var target_zoom: float = 1.0
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_start_camera_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	target_zoom = zoom.x

	# Connect to game events
	EventBus.game_started.connect(_on_game_started)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.city_selected.connect(_on_city_selected)

func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_edge_pan(delta)
	_smooth_zoom(delta)
	_clamp_position()

func _unhandled_input(event: InputEvent) -> void:
	# Zoom with mouse wheel
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_in()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_out()
		# Middle mouse drag for panning
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_dragging = true
				drag_start_pos = event.position
				drag_start_camera_pos = position
			else:
				is_dragging = false

	# Mouse drag panning
	if event is InputEventMouseMotion and is_dragging:
		var drag_delta = (drag_start_pos - event.position) / zoom.x
		position = drag_start_camera_pos + drag_delta

func _handle_keyboard_pan(delta: float) -> void:
	var pan_direction = Vector2.ZERO

	if Input.is_action_pressed("camera_pan_up"):
		pan_direction.y -= 1
	if Input.is_action_pressed("camera_pan_down"):
		pan_direction.y += 1
	if Input.is_action_pressed("camera_pan_left"):
		pan_direction.x -= 1
	if Input.is_action_pressed("camera_pan_right"):
		pan_direction.x += 1

	if pan_direction != Vector2.ZERO:
		pan_direction = pan_direction.normalized()
		position += pan_direction * pan_speed * delta / zoom.x

func _handle_edge_pan(delta: float) -> void:
	if not edge_pan_enabled:
		return

	var viewport_size = get_viewport_rect().size
	var mouse_pos = get_viewport().get_mouse_position()
	var pan_direction = Vector2.ZERO

	# Check edges
	if mouse_pos.x < edge_pan_margin:
		pan_direction.x = -1
	elif mouse_pos.x > viewport_size.x - edge_pan_margin:
		pan_direction.x = 1

	if mouse_pos.y < edge_pan_margin:
		pan_direction.y = -1
	elif mouse_pos.y > viewport_size.y - edge_pan_margin:
		pan_direction.y = 1

	if pan_direction != Vector2.ZERO:
		pan_direction = pan_direction.normalized()
		position += pan_direction * pan_speed * delta / zoom.x

func _zoom_in() -> void:
	target_zoom = min(target_zoom + zoom_speed, max_zoom)

func _zoom_out() -> void:
	target_zoom = max(target_zoom - zoom_speed, min_zoom)

func _smooth_zoom(delta: float) -> void:
	var new_zoom = lerp(zoom.x, target_zoom, zoom_smooth * delta)
	zoom = Vector2(new_zoom, new_zoom)

func _clamp_position() -> void:
	var margin = 200 / zoom.x

	if wrap_x:
		# For wrapping maps, wrap the camera position instead of clamping X
		var map_width = map_bounds.size.x
		if position.x < 0:
			position.x += map_width
		elif position.x > map_width:
			position.x -= map_width
	else:
		# No wrap - clamp X position
		position.x = clamp(position.x, map_bounds.position.x - margin, map_bounds.end.x + margin)

	# Y is always clamped (no vertical wrap)
	position.y = clamp(position.y, map_bounds.position.y - margin, map_bounds.end.y + margin)

## Set map bounds based on grid size and calculate zoom limits
func set_map_bounds(width: int, height: int, tile_size: int = 64) -> void:
	map_bounds = Rect2(0, 0, width * tile_size, height * tile_size)

	# Get wrap setting from game grid if available
	if GameManager.hex_grid:
		wrap_x = GameManager.hex_grid.wrap_x

	# Calculate min_zoom so that 60% of the map fills the screen width
	# Deferred to ensure viewport is ready
	call_deferred("_calculate_min_zoom")

func _calculate_min_zoom() -> void:
	print("[DEBUG] _calculate_min_zoom called, map_bounds: %s" % map_bounds)
	if map_bounds.size.x <= 0:
		print("[DEBUG] map_bounds.size.x <= 0, returning early")
		return

	var viewport_size = get_viewport_rect().size
	print("[DEBUG] viewport_size: %s" % viewport_size)
	if viewport_size.x > 0:
		# At zoom Z, viewport shows viewport_width / Z pixels
		# We want: viewport_width / Z = map_width * 0.6
		# So: Z = viewport_width / (map_width * 0.6)
		var map_sixty_percent = map_bounds.size.x * 0.6
		var calculated_min = viewport_size.x / map_sixty_percent
		# Ensure min_zoom is reasonable (between 0.1 and 1.0)
		min_zoom = clamp(calculated_min, 0.1, 1.0)
		# Clamp target zoom if it's now below the new minimum
		target_zoom = max(target_zoom, min_zoom)
		print("[DEBUG] min_zoom set to: %f, target_zoom: %f" % [min_zoom, target_zoom])

## Center camera on a position
func center_on(world_pos: Vector2) -> void:
	position = world_pos

## Center camera on a grid position
func center_on_grid(grid_pos: Vector2i) -> void:
	center_on(GridUtils.grid_to_pixel(grid_pos))

## Smoothly move to position
func move_to(target_pos: Vector2, duration: float = 0.3) -> void:
	var tween = create_tween()
	tween.tween_property(self, "position", target_pos, duration).set_ease(Tween.EASE_OUT)

## Smoothly move to grid position
func move_to_grid(grid_pos: Vector2i, duration: float = 0.3) -> void:
	move_to(GridUtils.grid_to_pixel(grid_pos), duration)

# Event handlers
func _on_game_started() -> void:
	if GameManager.game_grid:
		set_map_bounds(GameManager.game_grid.width, GameManager.game_grid.height)

func _on_unit_selected(unit: Unit) -> void:
	if unit != null:
		move_to_grid(unit.grid_position)

func _on_city_selected(city: City) -> void:
	if city != null:
		move_to_grid(city.grid_position)

func _notification(what: int) -> void:
	# Recalculate zoom limits when viewport size changes
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		_calculate_min_zoom()
