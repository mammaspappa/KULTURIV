extends Control
## Main menu screen for the game.

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var new_game_button: Button = $VBoxContainer/NewGameButton
@onready var load_game_button: Button = $VBoxContainer/LoadGameButton
@onready var options_button: Button = $VBoxContainer/OptionsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var main_buttons: VBoxContainer = $VBoxContainer

var new_game_screen: Control
var load_game_screen: Control
var options_screen: Control

func _ready() -> void:
	# Connect button signals
	new_game_button.pressed.connect(_on_new_game_pressed)
	load_game_button.pressed.connect(_on_load_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	# Create sub-screens
	_create_screens()

func _create_screens() -> void:
	# New Game Screen
	var NewGameScreenClass = load("res://scripts/ui/new_game_screen.gd")
	if NewGameScreenClass:
		new_game_screen = Control.new()
		new_game_screen.set_script(NewGameScreenClass)
		new_game_screen.name = "NewGameScreen"
		new_game_screen.back_pressed.connect(_on_subscreen_back)
		new_game_screen.start_game.connect(_on_start_game)
		add_child(new_game_screen)

	# Load Game Screen
	var LoadGameScreenClass = load("res://scripts/ui/load_game_screen.gd")
	if LoadGameScreenClass:
		load_game_screen = Control.new()
		load_game_screen.set_script(LoadGameScreenClass)
		load_game_screen.name = "LoadGameScreen"
		load_game_screen.back_pressed.connect(_on_subscreen_back)
		add_child(load_game_screen)

	# Options Screen
	var OptionsScreenClass = load("res://scripts/ui/options_screen.gd")
	if OptionsScreenClass:
		options_screen = Control.new()
		options_screen.set_script(OptionsScreenClass)
		options_screen.name = "OptionsScreen"
		options_screen.back_pressed.connect(_on_subscreen_back)
		add_child(options_screen)

func _on_new_game_pressed() -> void:
	if new_game_screen:
		main_buttons.hide()
		new_game_screen.show_screen()

func _on_load_game_pressed() -> void:
	if load_game_screen:
		main_buttons.hide()
		load_game_screen.show_screen()

func _on_options_pressed() -> void:
	if options_screen:
		main_buttons.hide()
		options_screen.show_screen()
	else:
		print("Options not yet implemented")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _on_subscreen_back() -> void:
	main_buttons.show()

func _on_start_game(settings: Dictionary) -> void:
	# Initialize game manager
	GameManager.start_new_game(settings)

	# Change to game scene
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")
