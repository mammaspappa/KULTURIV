class_name WatchGameScreen
extends Control
## Screen for configuring spectator/watch game options.

signal back_pressed
signal start_game(settings: Dictionary)

var panel: PanelContainer

# Option controls
var map_size_option: OptionButton
var num_players_spin: SpinBox
var difficulty_option: OptionButton
var speed_option: OptionButton
var map_type_option: OptionButton
var ai_aggro_option: OptionButton

const BG_COLOR = Color(0.08, 0.08, 0.12, 1.0)
const PANEL_COLOR = Color(0.12, 0.12, 0.18, 1.0)

const MAP_SIZES = {
	"Duel": {"width": 40, "height": 24},
	"Tiny": {"width": 52, "height": 32},
	"Small": {"width": 64, "height": 40},
	"Standard": {"width": 84, "height": 52},
	"Large": {"width": 104, "height": 64},
	"Huge": {"width": 128, "height": 80}
}

const MAP_TYPES = ["Fractal", "Pangaea", "Continents", "Archipelago"]
const MAP_TYPE_IDS = ["fractal", "pangaea", "continents", "archipelago"]

const DIFFICULTIES = ["Settler", "Chieftain", "Warlord", "Noble", "Prince", "Monarch", "Emperor", "Immortal", "Deity"]
const SPEEDS = ["Quick", "Normal", "Epic", "Marathon"]

func _ready() -> void:
	_build_ui()
	hide()

func _build_ui() -> void:
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BG_COLOR
	add_child(bg)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(550, 480)
	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = Color(0.5, 0.4, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Watch Game"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Spectate an AI-only game"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)

	# Options grid
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 15)
	vbox.add_child(grid)

	# Number of Civilizations
	_add_label(grid, "Civilizations:")
	num_players_spin = SpinBox.new()
	num_players_spin.min_value = 2
	num_players_spin.max_value = 18
	num_players_spin.value = 6
	num_players_spin.custom_minimum_size = Vector2(200, 30)
	grid.add_child(num_players_spin)

	# Map Size
	_add_label(grid, "Map Size:")
	map_size_option = OptionButton.new()
	map_size_option.custom_minimum_size = Vector2(200, 30)
	for size_name in MAP_SIZES.keys():
		var sz = MAP_SIZES[size_name]
		map_size_option.add_item("%s (%dx%d)" % [size_name, sz.width, sz.height])
	map_size_option.selected = 2  # Small
	grid.add_child(map_size_option)

	# Map Type
	_add_label(grid, "Map Type:")
	map_type_option = OptionButton.new()
	map_type_option.custom_minimum_size = Vector2(200, 30)
	for t in MAP_TYPES:
		map_type_option.add_item(t)
	map_type_option.selected = 0
	grid.add_child(map_type_option)

	# AI Behavior
	_add_label(grid, "AI Behavior:")
	ai_aggro_option = OptionButton.new()
	ai_aggro_option.custom_minimum_size = Vector2(200, 30)
	ai_aggro_option.add_item("Peaceful")
	ai_aggro_option.add_item("Normal")
	ai_aggro_option.add_item("Aggressive")
	ai_aggro_option.add_item("Random")
	ai_aggro_option.selected = 1
	grid.add_child(ai_aggro_option)

	# Difficulty
	_add_label(grid, "Difficulty:")
	difficulty_option = OptionButton.new()
	difficulty_option.custom_minimum_size = Vector2(200, 30)
	for d in DIFFICULTIES:
		difficulty_option.add_item(d)
	difficulty_option.selected = 4  # Prince
	grid.add_child(difficulty_option)

	# Game Speed
	_add_label(grid, "Game Speed:")
	speed_option = OptionButton.new()
	speed_option.custom_minimum_size = Vector2(200, 30)
	for s in SPEEDS:
		speed_option.add_item(s)
	speed_option.selected = 0  # Quick
	grid.add_child(speed_option)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)

	# Buttons
	var button_box = HBoxContainer.new()
	button_box.add_theme_constant_override("separation", 20)
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_box)

	var back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(150, 45)
	back_button.pressed.connect(_on_back_pressed)
	button_box.add_child(back_button)

	var watch_button = Button.new()
	watch_button.text = "Watch Game"
	watch_button.custom_minimum_size = Vector2(150, 45)
	watch_button.pressed.connect(_on_watch_pressed)
	button_box.add_child(watch_button)

func _add_label(parent: Node, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)

func show_screen() -> void:
	show()

func _on_watch_pressed() -> void:
	var map_size_keys = MAP_SIZES.keys()
	var selected_size = map_size_keys[map_size_option.selected]
	var sz = MAP_SIZES[selected_size]

	var settings = {
		"map_width": sz.width,
		"map_height": sz.height,
		"map_type": MAP_TYPE_IDS[map_type_option.selected],
		"num_players": int(num_players_spin.value),
		"difficulty": difficulty_option.selected,
		"game_speed": speed_option.selected,
		"ai_aggressiveness": ["peaceful", "normal", "aggressive", "random"][ai_aggro_option.selected],
		"spectator": true,
	}
	start_game.emit(settings)

func _on_back_pressed() -> void:
	hide()
	back_pressed.emit()
