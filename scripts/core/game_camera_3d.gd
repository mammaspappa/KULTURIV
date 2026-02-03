class_name GameCamera3D
extends Camera3D
## Orbital camera controller for the 3D cylinder map.
## Orbits around the cylinder's Y axis with elevation control.

# Orbital state
var orbit_angle: float = 0.0        # Horizontal angle around cylinder (radians)
var orbit_elevation: float = 0.0     # Vertical offset along Y axis
var orbit_distance: float = 30.0     # Distance from cylinder surface

# Smooth targets
var target_orbit_angle: float = 0.0
var target_orbit_elevation: float = 0.0
var target_orbit_distance: float = 30.0

# Map dimensions (set via setup)
var cylinder_radius: float = 1.0
var cylinder_height: float = 1.0
var map_width: int = 80
var map_height: int = 50

# Settings
@export var pan_speed: float = 1.5
@export var edge_pan_margin: int = 50
@export var edge_pan_enabled: bool = true
@export var min_distance: float = 5.0
@export var max_distance: float = 80.0
@export var zoom_speed: float = 2.0
@export var smooth_speed: float = 10.0

# Drag state
var is_dragging: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var drag_start_angle: float = 0.0
var drag_start_elevation: float = 0.0

func setup(cyl_radius: float, cyl_height: float, w: int, h: int) -> void:
	cylinder_radius = cyl_radius
	cylinder_height = cyl_height
	map_width = w
	map_height = h
	min_distance = cylinder_radius * 0.3
	max_distance = cylinder_radius * 6.0
	target_orbit_distance = cylinder_radius * 2.5
	orbit_distance = target_orbit_distance

func _ready() -> void:
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.city_selected.connect(_on_city_selected)

func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	_handle_edge_pan(delta)
	_smooth_camera(delta)
	_apply_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				target_orbit_distance = max(min_distance, target_orbit_distance - zoom_speed)
			MOUSE_BUTTON_WHEEL_DOWN:
				target_orbit_distance = min(max_distance, target_orbit_distance + zoom_speed)
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					is_dragging = true
					drag_start_pos = event.position
					drag_start_angle = target_orbit_angle
					drag_start_elevation = target_orbit_elevation
				else:
					is_dragging = false

	if event is InputEventMouseMotion and is_dragging:
		var d: Vector2 = event.position - drag_start_pos
		target_orbit_angle = drag_start_angle - d.x * 0.003
		target_orbit_elevation = clampf(
			drag_start_elevation + d.y * 0.01,
			-cylinder_height / 2.0, cylinder_height / 2.0)

func _handle_keyboard_pan(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_action_pressed("camera_pan_left"):
		dir.x -= 1.0
	if Input.is_action_pressed("camera_pan_right"):
		dir.x += 1.0
	if Input.is_action_pressed("camera_pan_up"):
		dir.y -= 1.0
	if Input.is_action_pressed("camera_pan_down"):
		dir.y += 1.0

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var spd: float = orbit_distance / (cylinder_radius * 2.0)
		target_orbit_angle += dir.x * pan_speed * spd * delta
		target_orbit_elevation = clampf(
			target_orbit_elevation + dir.y * pan_speed * spd * delta * cylinder_height * 0.3,
			-cylinder_height / 2.0, cylinder_height / 2.0)

func _handle_edge_pan(delta: float) -> void:
	if not edge_pan_enabled:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var mp: Vector2 = get_viewport().get_mouse_position()
	var dir := Vector2.ZERO
	if mp.x < edge_pan_margin:
		dir.x = -1.0
	elif mp.x > vs.x - edge_pan_margin:
		dir.x = 1.0
	if mp.y < edge_pan_margin:
		dir.y = -1.0
	elif mp.y > vs.y - edge_pan_margin:
		dir.y = 1.0

	if dir != Vector2.ZERO:
		dir = dir.normalized()
		var spd: float = orbit_distance / (cylinder_radius * 2.0)
		target_orbit_angle += dir.x * pan_speed * spd * delta
		target_orbit_elevation = clampf(
			target_orbit_elevation + dir.y * pan_speed * spd * delta * cylinder_height * 0.3,
			-cylinder_height / 2.0, cylinder_height / 2.0)

func _smooth_camera(delta: float) -> void:
	var t: float = minf(smooth_speed * delta, 1.0)
	orbit_angle = lerp_angle(orbit_angle, target_orbit_angle, t)
	orbit_elevation = lerpf(orbit_elevation, target_orbit_elevation, t)
	orbit_distance = lerpf(orbit_distance, target_orbit_distance, t)
	# Snap to target when close to prevent endless micro-oscillation
	if absf(angle_difference(orbit_angle, target_orbit_angle)) < 0.0001:
		orbit_angle = target_orbit_angle
	if absf(orbit_elevation - target_orbit_elevation) < 0.0001:
		orbit_elevation = target_orbit_elevation
	if absf(orbit_distance - target_orbit_distance) < 0.001:
		orbit_distance = target_orbit_distance

func _apply_transform() -> void:
	var dist: float = cylinder_radius + orbit_distance
	global_position = Vector3(
		dist * cos(orbit_angle),
		orbit_elevation,
		-dist * sin(orbit_angle))
	look_at(Vector3(0.0, orbit_elevation, 0.0), Vector3.UP)

## Center the camera on a grid position by converting to orbit angle + elevation.
func center_on_grid(grid_pos: Vector2i) -> void:
	target_orbit_angle = (float(grid_pos.x) / float(map_width)) * TAU
	target_orbit_elevation = cylinder_height * (0.5 - float(grid_pos.y) / float(map_height))

## Alias for move_to_grid (instant snap via smooth interpolation).
func move_to_grid(grid_pos: Vector2i, _duration: float = 0.3) -> void:
	center_on_grid(grid_pos)

## Alias matching Camera2D API used by game_ui.gd
func center_on(_world_pos: Vector2) -> void:
	# Convert pixel position to grid and use center_on_grid
	var grid_pos = GridUtils.pixel_to_grid(_world_pos)
	center_on_grid(grid_pos)

## Get the current grid position the camera is looking at (center of view).
func get_view_center_grid() -> Vector2i:
	var grid_x: int = int(fposmod(orbit_angle / TAU, 1.0) * map_width)
	var grid_y: int = int((0.5 - orbit_elevation / cylinder_height) * map_height)
	grid_x = clampi(grid_x, 0, map_width - 1)
	grid_y = clampi(grid_y, 0, map_height - 1)
	return Vector2i(grid_x, grid_y)

## Estimate how many tiles are visible horizontally at current zoom.
func get_visible_tile_width() -> float:
	# Approximate: field of view / angular span per tile
	var angular_span_per_tile: float = TAU / float(map_width)
	var visible_angle: float = 2.0 * atan(tan(deg_to_rad(fov) / 2.0) * get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y)
	# Scale by how close we are (closer = fewer tiles visible)
	var dist: float = cylinder_radius + orbit_distance
	var subtended: float = 2.0 * asin(clampf(cylinder_radius / dist, 0.0, 1.0))
	var effective_angle: float = minf(visible_angle, subtended)
	return effective_angle / angular_span_per_tile

## Estimate how many tiles are visible vertically at current zoom.
func get_visible_tile_height() -> float:
	var dist: float = cylinder_radius + orbit_distance
	var half_fov_rad: float = deg_to_rad(fov) / 2.0
	var visible_world_height: float = 2.0 * dist * tan(half_fov_rad)
	return visible_world_height

func _on_unit_selected(unit) -> void:
	if unit:
		move_to_grid(unit.grid_position)

func _on_city_selected(city) -> void:
	if city:
		move_to_grid(city.grid_position)
