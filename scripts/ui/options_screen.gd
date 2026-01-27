class_name OptionsScreen
extends Control
## Screen for game options and settings.

signal back_pressed

var panel: PanelContainer
var title_label: Label

# Audio options
var master_volume_slider: HSlider
var music_volume_slider: HSlider
var sfx_volume_slider: HSlider

# Graphics options
var fullscreen_check: CheckBox
var vsync_check: CheckBox

# Gameplay options
var edge_pan_check: CheckBox
var auto_end_turn_check: CheckBox

var apply_button: Button
var back_button: Button

const BG_COLOR = Color(0.08, 0.08, 0.12, 1.0)
const PANEL_COLOR = Color(0.12, 0.12, 0.18, 1.0)

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
	panel.custom_minimum_size = Vector2(500, 500)
	var style = StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = Color(0.3, 0.3, 0.4)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)

	# Title
	title_label = Label.new()
	title_label.text = "Options"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Audio section
	_add_section_header(vbox, "Audio")
	var audio_grid = _create_grid()
	vbox.add_child(audio_grid)

	_add_label(audio_grid, "Master Volume:")
	master_volume_slider = _create_slider()
	audio_grid.add_child(master_volume_slider)

	_add_label(audio_grid, "Music Volume:")
	music_volume_slider = _create_slider()
	audio_grid.add_child(music_volume_slider)

	_add_label(audio_grid, "SFX Volume:")
	sfx_volume_slider = _create_slider()
	audio_grid.add_child(sfx_volume_slider)

	# Graphics section
	_add_section_header(vbox, "Graphics")
	var graphics_grid = _create_grid()
	vbox.add_child(graphics_grid)

	_add_label(graphics_grid, "Fullscreen:")
	fullscreen_check = CheckBox.new()
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	graphics_grid.add_child(fullscreen_check)

	_add_label(graphics_grid, "V-Sync:")
	vsync_check = CheckBox.new()
	vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED
	graphics_grid.add_child(vsync_check)

	# Gameplay section
	_add_section_header(vbox, "Gameplay")
	var gameplay_grid = _create_grid()
	vbox.add_child(gameplay_grid)

	_add_label(gameplay_grid, "Edge Panning:")
	edge_pan_check = CheckBox.new()
	edge_pan_check.button_pressed = true
	gameplay_grid.add_child(edge_pan_check)

	_add_label(gameplay_grid, "Auto End Turn:")
	auto_end_turn_check = CheckBox.new()
	auto_end_turn_check.button_pressed = false
	gameplay_grid.add_child(auto_end_turn_check)

	# Spacer
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Buttons
	var button_box = HBoxContainer.new()
	button_box.add_theme_constant_override("separation", 20)
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_box)

	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(120, 40)
	back_button.pressed.connect(_on_back_pressed)
	button_box.add_child(back_button)

	apply_button = Button.new()
	apply_button.text = "Apply"
	apply_button.custom_minimum_size = Vector2(120, 40)
	apply_button.pressed.connect(_on_apply_pressed)
	button_box.add_child(apply_button)

func _add_section_header(parent: Node, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	parent.add_child(label)

func _create_grid() -> GridContainer:
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	return grid

func _add_label(parent: Node, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	parent.add_child(label)

func _create_slider() -> HSlider:
	var slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = 100
	slider.step = 5
	slider.custom_minimum_size = Vector2(200, 20)
	return slider

func show_screen() -> void:
	_load_settings()
	show()

func _load_settings() -> void:
	# Load current settings
	fullscreen_check.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	vsync_check.button_pressed = DisplayServer.window_get_vsync_mode() != DisplayServer.VSYNC_DISABLED

	# Load audio settings from AudioServer
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		var db = AudioServer.get_bus_volume_db(master_idx)
		master_volume_slider.value = db_to_linear(db) * 100

func _on_apply_pressed() -> void:
	# Apply graphics settings
	if fullscreen_check.button_pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	if vsync_check.button_pressed:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	# Apply audio settings
	var master_idx = AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		var linear = master_volume_slider.value / 100.0
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(linear))

	# Store gameplay settings in GameManager if available
	if GameManager:
		GameManager.edge_pan_enabled = edge_pan_check.button_pressed
		GameManager.auto_end_turn = auto_end_turn_check.button_pressed

func _on_back_pressed() -> void:
	hide()
	back_pressed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_back_pressed()
			get_viewport().set_input_as_handled()
