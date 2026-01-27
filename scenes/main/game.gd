extends Node2D
## Main game scene that sets up the game world.

@onready var game_world: GameWorld = $GameWorld
@onready var game_ui: Control = $ScreenUILayer/GameUI
@onready var screen_ui_layer: CanvasLayer = $ScreenUILayer

# UI Screen instances
var event_popup: Control
var espionage_screen: Control
var spaceship_screen: Control
var voting_screen: Control

func _ready() -> void:
	# Initialize the game with current settings
	var settings = {
		"map_width": GameManager.map_width,
		"map_height": GameManager.map_height,
	}

	game_world.initialize_game(settings)

	# Connect UI signals
	_setup_ui()

	# Setup additional UI screens
	_setup_ui_screens()

func _setup_ui() -> void:
	# Connect UI events
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.city_selected.connect(_on_city_selected)

func _setup_ui_screens() -> void:
	# Load and add Event Popup to ScreenUILayer (so it doesn't scale with zoom)
	var EventPopupScript = load("res://scripts/ui/event_popup.gd")
	if EventPopupScript:
		event_popup = Control.new()
		event_popup.set_script(EventPopupScript)
		event_popup.name = "EventPopup"
		screen_ui_layer.add_child(event_popup)

	# Load and add Espionage Screen to ScreenUILayer
	var EspionageScreenScript = load("res://scripts/ui/espionage_screen.gd")
	if EspionageScreenScript:
		espionage_screen = Control.new()
		espionage_screen.set_script(EspionageScreenScript)
		espionage_screen.name = "EspionageScreen"
		screen_ui_layer.add_child(espionage_screen)

	# Load and add Spaceship Screen to ScreenUILayer
	var SpaceshipScreenScript = load("res://scripts/ui/spaceship_screen.gd")
	if SpaceshipScreenScript:
		spaceship_screen = Control.new()
		spaceship_screen.set_script(SpaceshipScreenScript)
		spaceship_screen.name = "SpaceshipScreen"
		screen_ui_layer.add_child(spaceship_screen)

	# Load and add Voting Screen to ScreenUILayer
	var VotingScreenScript = load("res://scripts/ui/voting_screen.gd")
	if VotingScreenScript:
		voting_screen = Control.new()
		voting_screen.set_script(VotingScreenScript)
		voting_screen.name = "VotingScreen"
		screen_ui_layer.add_child(voting_screen)

func _on_turn_started(turn: int, player: Player) -> void:
	if player == GameManager.human_player:
		_update_ui()

func _on_unit_selected(unit: Unit) -> void:
	_update_unit_panel(unit)

func _on_city_selected(city: City) -> void:
	_update_city_panel(city)

func _update_ui() -> void:
	# Update turn display, resources, etc.
	pass

func _update_unit_panel(unit: Unit) -> void:
	# Update unit info panel
	pass

func _update_city_panel(city: City) -> void:
	# Update city info panel
	pass
