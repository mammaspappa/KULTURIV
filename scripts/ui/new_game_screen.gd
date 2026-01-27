class_name NewGameScreen
extends Control
## Screen for configuring new game options.

signal back_pressed
signal start_game(settings: Dictionary)

var panel: PanelContainer
var title_label: Label

# Option controls
var map_size_option: OptionButton
var num_players_spin: SpinBox
var difficulty_option: OptionButton
var speed_option: OptionButton
var civ_option: OptionButton
var leader_option: OptionButton
var player_name_edit: LineEdit

var start_button: Button
var back_button: Button

const BG_COLOR = Color(0.08, 0.08, 0.12, 1.0)
const PANEL_COLOR = Color(0.12, 0.12, 0.18, 1.0)

const MAP_SIZES = {
	"Duel": {"width": 24, "height": 16},
	"Tiny": {"width": 32, "height": 20},
	"Small": {"width": 40, "height": 25},
	"Standard": {"width": 52, "height": 32},
	"Large": {"width": 64, "height": 40},
	"Huge": {"width": 80, "height": 50}
}

const DIFFICULTIES = ["Settler", "Chieftain", "Warlord", "Noble", "Prince", "Monarch", "Emperor", "Immortal", "Deity"]
const SPEEDS = ["Quick", "Normal", "Epic", "Marathon"]

func _ready() -> void:
	_build_ui()
	hide()

func _build_ui() -> void:
	# Full screen background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	add_child(bg)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main panel
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 550)
	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = Color(0.3, 0.3, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	# Title
	title_label = Label.new()
	title_label.text = "New Game"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Options grid
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 15)
	vbox.add_child(grid)

	# Player Name
	_add_label(grid, "Player Name:")
	player_name_edit = LineEdit.new()
	player_name_edit.text = "Player"
	player_name_edit.custom_minimum_size = Vector2(200, 30)
	grid.add_child(player_name_edit)

	# Civilization
	_add_label(grid, "Civilization:")
	civ_option = OptionButton.new()
	civ_option.custom_minimum_size = Vector2(200, 30)
	civ_option.item_selected.connect(_on_civ_selected)
	grid.add_child(civ_option)

	# Leader
	_add_label(grid, "Leader:")
	leader_option = OptionButton.new()
	leader_option.custom_minimum_size = Vector2(200, 30)
	grid.add_child(leader_option)

	# Map Size
	_add_label(grid, "Map Size:")
	map_size_option = OptionButton.new()
	map_size_option.custom_minimum_size = Vector2(200, 30)
	for size_name in MAP_SIZES.keys():
		var size = MAP_SIZES[size_name]
		map_size_option.add_item("%s (%dx%d)" % [size_name, size.width, size.height])
	map_size_option.selected = 2  # Small as default
	grid.add_child(map_size_option)

	# Number of Players
	_add_label(grid, "Opponents:")
	num_players_spin = SpinBox.new()
	num_players_spin.min_value = 1
	num_players_spin.max_value = 7
	num_players_spin.value = 3
	num_players_spin.custom_minimum_size = Vector2(200, 30)
	grid.add_child(num_players_spin)

	# Difficulty
	_add_label(grid, "Difficulty:")
	difficulty_option = OptionButton.new()
	difficulty_option.custom_minimum_size = Vector2(200, 30)
	for i in range(DIFFICULTIES.size()):
		difficulty_option.add_item(DIFFICULTIES[i])
	difficulty_option.selected = 4  # Prince as default
	grid.add_child(difficulty_option)

	# Game Speed
	_add_label(grid, "Game Speed:")
	speed_option = OptionButton.new()
	speed_option.custom_minimum_size = Vector2(200, 30)
	for i in range(SPEEDS.size()):
		speed_option.add_item(SPEEDS[i])
	speed_option.selected = 1  # Normal as default
	grid.add_child(speed_option)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Buttons
	var button_box = HBoxContainer.new()
	button_box.add_theme_constant_override("separation", 20)
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_box)

	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(150, 45)
	back_button.pressed.connect(_on_back_pressed)
	button_box.add_child(back_button)

	start_button = Button.new()
	start_button.text = "Start Game"
	start_button.custom_minimum_size = Vector2(150, 45)
	start_button.pressed.connect(_on_start_pressed)
	button_box.add_child(start_button)

func _add_label(parent: Node, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)

func show_screen() -> void:
	_populate_civs()
	show()

func _populate_civs() -> void:
	civ_option.clear()
	leader_option.clear()

	var civs = DataManager.get_all_civs()
	for civ_id in civs:
		var civ_data = DataManager.get_civ(civ_id)
		civ_option.add_item(civ_data.get("name", civ_id.capitalize()))
		civ_option.set_item_metadata(civ_option.item_count - 1, civ_id)

	if civ_option.item_count > 0:
		civ_option.selected = 0
		_on_civ_selected(0)

func _on_civ_selected(index: int) -> void:
	leader_option.clear()

	var civ_id = civ_option.get_item_metadata(index)
	if civ_id == null:
		return

	var civ_data = DataManager.get_civ(civ_id)
	var leaders = civ_data.get("leaders", [])

	for leader_id in leaders:
		var leader_data = DataManager.get_leader(leader_id)
		var leader_name = leader_data.get("name", leader_id.replace("_", " ").capitalize())
		leader_option.add_item(leader_name)
		leader_option.set_item_metadata(leader_option.item_count - 1, leader_id)

	if leader_option.item_count > 0:
		leader_option.selected = 0

func _on_start_pressed() -> void:
	var map_size_keys = MAP_SIZES.keys()
	var selected_size = map_size_keys[map_size_option.selected]
	var size = MAP_SIZES[selected_size]

	var civ_id = civ_option.get_item_metadata(civ_option.selected)
	var leader_id = leader_option.get_item_metadata(leader_option.selected)

	var settings = {
		"map_width": size.width,
		"map_height": size.height,
		"num_players": int(num_players_spin.value) + 1,  # +1 for human player
		"human_civ": civ_id if civ_id else "rome",
		"human_leader": leader_id if leader_id else "julius_caesar",
		"player_name": player_name_edit.text if player_name_edit.text != "" else "Player",
		"difficulty": difficulty_option.selected,
		"game_speed": speed_option.selected,
	}

	start_game.emit(settings)

func _on_back_pressed() -> void:
	hide()
	back_pressed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_back_pressed()
			get_viewport().set_input_as_handled()
