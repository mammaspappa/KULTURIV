class_name VictoryScreen
extends Control
## Victory screen shown when a player wins.

var winner = null  # Player (untyped to avoid load-order issues)
var victory_type: String = ""

# UI elements
var panel: Panel
var title_label: Label
var message_label: Label
var stats_label: Label
var main_menu_button: Button
var continue_button: Button

const BG_COLOR = Color(0.05, 0.05, 0.1, 1.0)

func _ready() -> void:
	_create_ui()
	EventBus.victory_achieved.connect(_on_victory_achieved)
	EventBus.game_over.connect(_on_game_over)
	hide()

func _create_ui() -> void:
	# Main panel
	panel = Panel.new()
	panel.name = "Panel"
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_width_left = 4
	style.border_width_right = 4
	style.border_width_top = 4
	style.border_width_bottom = 4
	style.border_color = Color.GOLD
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.2
	panel.anchor_right = 0.8
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_top = 50  # Below the 40px top menu
	panel.offset_bottom = -50
	add_child(panel)

	# Title
	title_label = Label.new()
	title_label.name = "Title"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", Color.GOLD)
	title_label.position = Vector2(0, 30)
	title_label.size = Vector2(600, 60)  # Will be updated in show
	panel.add_child(title_label)

	# Victory message
	message_label = Label.new()
	message_label.name = "Message"
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 24)
	message_label.position = Vector2(20, 110)
	message_label.size = Vector2(560, 100)
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(message_label)

	# Stats
	stats_label = Label.new()
	stats_label.name = "Stats"
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.position = Vector2(50, 220)
	stats_label.size = Vector2(500, 200)
	panel.add_child(stats_label)

	# Buttons container
	var button_container = HBoxContainer.new()
	button_container.name = "Buttons"
	button_container.position = Vector2(150, 450)
	button_container.add_theme_constant_override("separation", 50)
	panel.add_child(button_container)

	# Continue button
	continue_button = Button.new()
	continue_button.text = "Continue Playing"
	continue_button.custom_minimum_size = Vector2(150, 50)
	continue_button.pressed.connect(_on_continue_pressed)
	button_container.add_child(continue_button)

	# Main menu button
	main_menu_button = Button.new()
	main_menu_button.text = "Main Menu"
	main_menu_button.custom_minimum_size = Vector2(150, 50)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	button_container.add_child(main_menu_button)

func _on_victory_achieved(player, type: String) -> void:
	winner = player
	victory_type = type
	_show_victory_screen()

func _on_game_over(player, type: String) -> void:
	winner = player
	victory_type = type
	_show_victory_screen()

func _show_victory_screen() -> void:
	_update_display()
	show()

func _update_display() -> void:
	if winner == null:
		return

	# Update panel size references
	var panel_width = panel.size.x
	title_label.size.x = panel_width - 40
	message_label.size.x = panel_width - 80

	# Determine if player won or lost
	var player_won = (winner == GameManager.human_player)

	# Title
	if player_won:
		title_label.text = "VICTORY!"
		title_label.add_theme_color_override("font_color", Color.GOLD)
	else:
		title_label.text = "DEFEAT"
		title_label.add_theme_color_override("font_color", Color.RED)

	# Victory message
	var victory_name = _get_victory_name(victory_type)
	var civ_name = DataManager.get_civ(winner.civilization_id).get("name", "Unknown")

	if player_won:
		message_label.text = "Congratulations! You have achieved a %s Victory!\n\nYour civilization will be remembered throughout history." % victory_name
	else:
		message_label.text = "The %s has achieved a %s Victory.\n\nYour civilization has been overshadowed." % [civ_name, victory_name]

	# Stats
	var stats_text = "Final Statistics\n"
	stats_text += "───────────────────\n\n"

	for player in GameManager.players:
		player.calculate_score()
		var p_civ_name = DataManager.get_civ(player.civilization_id).get("name", "Unknown")
		var marker = " <-- Winner" if player == winner else ""
		stats_text += "%s: %d points%s\n" % [p_civ_name, player.score, marker]
		stats_text += "  Cities: %d, Population: %d\n" % [player.cities.size(), player.get_total_population()]
		stats_text += "  Technologies: %d\n\n" % player.researched_techs.size()

	stats_text += "\nGame completed in %d turns (%s)" % [TurnManager.current_turn, TurnManager.get_year_string()]

	stats_label.text = stats_text

func _get_victory_name(type: String) -> String:
	match type:
		"conquest":
			return "Conquest"
		"domination":
			return "Domination"
		"cultural":
			return "Cultural"
		"space":
			return "Space Race"
		"score":
			return "Score"
		_:
			return type.capitalize()

func _on_continue_pressed() -> void:
	hide()

func _on_main_menu_pressed() -> void:
	# Go back to main menu
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_continue_pressed()
			get_viewport().set_input_as_handled()
