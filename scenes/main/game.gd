extends Node2D
## Main game scene that sets up the game world.

@onready var game_world: GameWorld = $GameWorld
@onready var game_ui: Control = $GameUI

func _ready() -> void:
	# Initialize the game with current settings
	var settings = {
		"map_width": GameManager.map_width,
		"map_height": GameManager.map_height,
	}

	game_world.initialize_game(settings)

	# Connect UI signals
	_setup_ui()

func _setup_ui() -> void:
	# Connect UI events
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.city_selected.connect(_on_city_selected)

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
