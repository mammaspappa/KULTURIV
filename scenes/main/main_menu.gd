extends Control
## Main menu screen for the game.

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var load_game_button: Button = $VBoxContainer/LoadGameButton
@onready var options_button: Button = $VBoxContainer/OptionsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton

func _ready() -> void:
	# Connect button signals
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _on_new_game_pressed() -> void:
	# For now, start a quick game with default settings
	var settings = {
		"map_width": 40,
		"map_height": 25,
		"num_players": 2,
		"human_civ": "rome",
		"human_leader": "julius_caesar",
		"player_name": "Player",
		"difficulty": 4,
		"game_speed": 1,
	}

	# Initialize game manager
	GameManager.start_new_game(settings)

	# Change to game scene
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")

func _on_load_game_pressed() -> void:
	# TODO: Implement load game
	print("Load game not yet implemented")

func _on_options_pressed() -> void:
	# TODO: Implement options menu
	print("Options not yet implemented")

func _on_quit_pressed() -> void:
	get_tree().quit()
