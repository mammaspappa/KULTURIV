extends Node3D
## Main game scene that sets up the 3D cylinder map.
## Renders all 2D content (tiles, units, cities) into a SubViewport,
## then maps that viewport's texture onto a 3D cylinder mesh.

const CylinderMapClass = preload("res://scripts/core/cylinder_map.gd")
const InputRaycastClass = preload("res://scripts/core/input_raycast.gd")
const GameCamera3DClass = preload("res://scripts/core/game_camera_3d.gd")

@onready var map_viewport: SubViewport = $MapViewport
@onready var game_world: GameWorld = $MapViewport/GameWorld
@onready var screen_ui_layer: CanvasLayer = $ScreenUILayer
@onready var game_ui: Control = $ScreenUILayer/GameUI

# 3D scene objects (created at runtime)
var cylinder_map = null  # CylinderMap
var game_camera_3d = null  # GameCamera3D
var input_raycast = null  # InputRaycast
var world_env: WorldEnvironment

# UI Screen instances
var event_popup: Control
var espionage_screen: Control
var spaceship_screen: Control
var voting_screen: Control
var religion_screen: Control

func _ready() -> void:
	var settings = {
		"map_width": GameManager.map_width,
		"map_height": GameManager.map_height,
	}

	var map_width: int = settings.get("map_width", 80)
	var map_height: int = settings.get("map_height", 50)
	var tile_size: int = GridUtils.TILE_SIZE

	# Configure SubViewport to render the full 2D map
	map_viewport.size = Vector2i(map_width * tile_size, map_height * tile_size)
	map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	map_viewport.handle_input_locally = false
	map_viewport.transparent_bg = false

	# Add a static Camera2D inside the SubViewport so the full map is rendered
	var viewport_camera = Camera2D.new()
	viewport_camera.name = "ViewportCamera"
	viewport_camera.position = Vector2(
		float(map_width * tile_size) / 2.0,
		float(map_height * tile_size) / 2.0)
	viewport_camera.zoom = Vector2(1.0, 1.0)
	viewport_camera.enabled = true
	map_viewport.add_child(viewport_camera)

	# Initialize game world (generates map, places units, starts game)
	game_world.initialize_game(settings)
	print("[Game] Map initialized: %dx%d tiles" % [map_width, map_height])

	# Create the 3D cylinder mesh
	cylinder_map = CylinderMapClass.new()
	cylinder_map.name = "CylinderMap"
	add_child(cylinder_map)
	# Must call setup after adding to tree so viewport texture is available
	cylinder_map.setup(map_width, map_height, map_viewport)
	print("[Game] Cylinder: radius=%.2f, height=%.2f" % [cylinder_map.cylinder_radius, cylinder_map.cylinder_height])

	# Create orbital 3D camera
	game_camera_3d = GameCamera3DClass.new()
	game_camera_3d.name = "GameCamera3D"
	add_child(game_camera_3d)
	game_camera_3d.setup(
		cylinder_map.cylinder_radius,
		cylinder_map.cylinder_height,
		map_width, map_height)
	game_camera_3d.current = true

	# Create input raycast converter
	input_raycast = InputRaycastClass.new(game_camera_3d, cylinder_map)

	# Store references in GameManager for other scripts to access
	GameManager.set_meta("input_raycast", input_raycast)
	GameManager.set_meta("camera_3d", game_camera_3d)

	# Create WorldEnvironment for proper lighting
	world_env = WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.05, 0.1)  # Dark blue-black
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 1.0
	world_env.environment = env
	add_child(world_env)

	# Connect UI signals
	_setup_ui()

	# Setup additional UI screens
	_setup_ui_screens()

	# Center camera
	if GameManager.spectator_mode:
		# Spectator: center on map middle
		game_camera_3d.center_on_grid(Vector2i(map_width / 2, map_height / 2))
		game_camera_3d.orbit_angle = game_camera_3d.target_orbit_angle
		game_camera_3d.orbit_elevation = game_camera_3d.target_orbit_elevation
		_build_spectator_ui()
	elif GameManager.human_player and GameManager.human_player.units.size() > 0:
		var start_unit = GameManager.human_player.units[0]
		game_camera_3d.center_on_grid(start_unit.grid_position)
		# Snap immediately (no interpolation on first frame)
		game_camera_3d.orbit_angle = game_camera_3d.target_orbit_angle
		game_camera_3d.orbit_elevation = game_camera_3d.target_orbit_elevation

	print("[Game] 3D cylinder map setup complete")

var spectator_speed_label: Label = null

func _build_spectator_ui() -> void:
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 10
	panel.offset_top = 50
	screen_ui_layer.add_child(panel)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	panel.add_child(hbox)

	var title = Label.new()
	title.text = "SPECTATOR"
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	hbox.add_child(title)

	var sep = VSeparator.new()
	hbox.add_child(sep)

	# Speed buttons
	var speeds = {"Pause": 0.0, "Slow": 1.0, "Normal": 0.5, "Fast": 0.15, "Max": 0.0}
	# Max uses 0 but we need to distinguish from Pause
	for speed_name in ["Pause", "Slow", "Normal", "Fast", "Max"]:
		var btn = Button.new()
		btn.text = speed_name
		btn.custom_minimum_size = Vector2(60, 30)
		btn.pressed.connect(_on_spectator_speed.bind(speed_name))
		hbox.add_child(btn)

	spectator_speed_label = Label.new()
	spectator_speed_label.text = "Speed: Normal"
	hbox.add_child(spectator_speed_label)

func _on_spectator_speed(speed_name: String) -> void:
	match speed_name:
		"Pause":
			GameManager.spectator_speed = -1.0  # Negative = paused
		"Slow":
			GameManager.spectator_speed = 1.0
		"Normal":
			GameManager.spectator_speed = 0.5
		"Fast":
			GameManager.spectator_speed = 0.15
		"Max":
			GameManager.spectator_speed = 0.0
	if spectator_speed_label:
		spectator_speed_label.text = "Speed: %s" % speed_name

func _unhandled_input(event: InputEvent) -> void:
	# GameWorld is inside the SubViewport, which has handle_input_locally=false,
	# so it never receives input callbacks. Forward input to it from here.
	if game_world:
		game_world._unhandled_input(event)

func _setup_ui() -> void:
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.city_selected.connect(_on_city_selected)

func _setup_ui_screens() -> void:
	var EventPopupScript = load("res://scripts/ui/event_popup.gd")
	if EventPopupScript:
		event_popup = Control.new()
		event_popup.set_script(EventPopupScript)
		event_popup.name = "EventPopup"
		screen_ui_layer.add_child(event_popup)

	var EspionageScreenScript = load("res://scripts/ui/espionage_screen.gd")
	if EspionageScreenScript:
		espionage_screen = Control.new()
		espionage_screen.set_script(EspionageScreenScript)
		espionage_screen.name = "EspionageScreen"
		screen_ui_layer.add_child(espionage_screen)

	var SpaceshipScreenScript = load("res://scripts/ui/spaceship_screen.gd")
	if SpaceshipScreenScript:
		spaceship_screen = Control.new()
		spaceship_screen.set_script(SpaceshipScreenScript)
		spaceship_screen.name = "SpaceshipScreen"
		screen_ui_layer.add_child(spaceship_screen)

	var VotingScreenScript = load("res://scripts/ui/voting_screen.gd")
	if VotingScreenScript:
		voting_screen = Control.new()
		voting_screen.set_script(VotingScreenScript)
		voting_screen.name = "VotingScreen"
		screen_ui_layer.add_child(voting_screen)

	var ReligionScreenScript = load("res://scripts/ui/religion_screen.gd")
	if ReligionScreenScript:
		religion_screen = Control.new()
		religion_screen.set_script(ReligionScreenScript)
		religion_screen.name = "ReligionScreen"
		screen_ui_layer.add_child(religion_screen)

func _on_turn_started(turn: int, player: Player) -> void:
	if player == GameManager.human_player:
		_update_ui()

func _on_unit_selected(unit: Unit) -> void:
	_update_unit_panel(unit)

func _on_city_selected(city: City) -> void:
	_update_city_panel(city)

func _update_ui() -> void:
	pass

func _update_unit_panel(unit: Unit) -> void:
	pass

func _update_city_panel(city: City) -> void:
	pass
