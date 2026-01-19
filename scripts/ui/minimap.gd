class_name Minimap
extends Panel
## Minimap showing the game world overview.

var minimap_image: Image
var minimap_texture: ImageTexture
var texture_rect: TextureRect

# Camera viewport rectangle
var viewport_rect: ColorRect

# Size
var minimap_size = Vector2(200, 160)

func _ready() -> void:
	# Create texture rect for the map
	texture_rect = TextureRect.new()
	texture_rect.name = "MinimapTexture"
	texture_rect.position = Vector2(0, 0)
	texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	add_child(texture_rect)

	# Create viewport indicator
	viewport_rect = ColorRect.new()
	viewport_rect.name = "ViewportRect"
	viewport_rect.color = Color(1, 1, 1, 0.3)
	viewport_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(viewport_rect)

	# Connect signals
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.unit_moved.connect(_on_unit_moved)
	EventBus.city_founded.connect(_on_city_founded)
	EventBus.tile_improved.connect(_on_tile_improved)

	# Initialize after a frame to ensure GameManager is ready
	call_deferred("_setup_minimap")

func _setup_minimap() -> void:
	if GameManager.hex_grid == null:
		return

	var width = GameManager.map_width
	var height = GameManager.map_height

	# Create image
	minimap_image = Image.create(width, height, false, Image.FORMAT_RGBA8)
	minimap_texture = ImageTexture.create_from_image(minimap_image)
	texture_rect.texture = minimap_texture

	# Size the texture rect
	texture_rect.size = minimap_size

	_update_minimap()

func _process(_delta: float) -> void:
	_update_viewport_rect()

func _update_minimap() -> void:
	if minimap_image == null or GameManager.hex_grid == null:
		return

	var player = GameManager.human_player
	var player_id = player.player_id if player else -1

	# Visibility state constants
	const UNEXPLORED = 0
	const FOGGED = 1

	for x in range(GameManager.map_width):
		for y in range(GameManager.map_height):
			var tile = GameManager.hex_grid.get_tile(Vector2i(x, y))
			if tile == null:
				minimap_image.set_pixel(x, y, Color.BLACK)
				continue

			# Check visibility
			var visibility = tile.get_visibility_for_player(player_id) if player_id >= 0 else 2  # VISIBLE

			if visibility == UNEXPLORED:
				minimap_image.set_pixel(x, y, Color.BLACK)
				continue

			# Base terrain color
			var color = DataManager.get_terrain_color(tile.terrain_id)

			# Darken if fogged
			if visibility == FOGGED:
				color = color.darkened(0.5)
			else:
				# Show city
				var city = GameManager.get_city_at(Vector2i(x, y))
				if city != null:
					color = city.player_owner.color if city.player_owner else Color.WHITE

				# Show unit
				var unit = GameManager.get_unit_at(Vector2i(x, y))
				if unit != null:
					color = unit.player_owner.color.lightened(0.3) if unit.player_owner else Color.WHITE

			minimap_image.set_pixel(x, y, color)

	minimap_texture.update(minimap_image)

func _update_viewport_rect() -> void:
	if GameManager.hex_grid == null:
		viewport_rect.visible = false
		return

	var camera = get_viewport().get_camera_2d()
	if camera == null:
		viewport_rect.visible = false
		return

	viewport_rect.visible = true

	# Calculate viewport position on minimap
	var viewport_size = get_viewport().get_visible_rect().size
	var camera_pos = camera.global_position
	var zoom = camera.zoom

	# Convert to grid coordinates
	var top_left_grid = GridUtils.pixel_to_grid(camera_pos - viewport_size / (2.0 * zoom))
	var bottom_right_grid = GridUtils.pixel_to_grid(camera_pos + viewport_size / (2.0 * zoom))

	# Convert to minimap coordinates
	var scale_x = minimap_size.x / GameManager.map_width
	var scale_y = minimap_size.y / GameManager.map_height

	viewport_rect.position = Vector2(top_left_grid.x * scale_x, top_left_grid.y * scale_y)
	viewport_rect.size = Vector2(
		(bottom_right_grid.x - top_left_grid.x) * scale_x,
		(bottom_right_grid.y - top_left_grid.y) * scale_y
	)

	# Clamp size
	viewport_rect.size = viewport_rect.size.clamp(Vector2(10, 10), minimap_size)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_handle_minimap_click(event.position)

func _handle_minimap_click(local_pos: Vector2) -> void:
	if GameManager.hex_grid == null:
		return

	# Convert minimap position to grid position
	var scale_x = float(GameManager.map_width) / minimap_size.x
	var scale_y = float(GameManager.map_height) / minimap_size.y

	var grid_x = int(local_pos.x * scale_x)
	var grid_y = int(local_pos.y * scale_y)

	# Clamp to valid range
	grid_x = clamp(grid_x, 0, GameManager.map_width - 1)
	grid_y = clamp(grid_y, 0, GameManager.map_height - 1)

	# Pan camera to location
	var camera = get_viewport().get_camera_2d()
	if camera and camera is GameCamera:
		camera.center_on_grid(Vector2i(grid_x, grid_y))

func _on_turn_started(_turn: int, _player) -> void:
	call_deferred("_update_minimap")

func _on_unit_moved(_unit, _from: Vector2i, _to: Vector2i) -> void:
	_update_minimap()

func _on_city_founded(_city, _founder) -> void:
	_update_minimap()

func _on_tile_improved(_pos: Vector2i, _improvement: String) -> void:
	_update_minimap()
