class_name LoadGameScreen
extends Control
## Screen for selecting and loading saved games.

signal back_pressed
signal game_loaded

var panel: PanelContainer
var title_label: Label
var save_list: ItemList
var info_label: RichTextLabel
var load_button: Button
var delete_button: Button
var back_button: Button

var save_files: Array = []
var selected_index: int = -1

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
	panel.custom_minimum_size = Vector2(700, 500)
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
	title_label.text = "Load Game"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	# Content container
	var content = HBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(content)

	# Save list
	save_list = ItemList.new()
	save_list.custom_minimum_size = Vector2(350, 0)
	save_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save_list.item_selected.connect(_on_save_selected)
	save_list.item_activated.connect(_on_save_activated)
	content.add_child(save_list)

	# Info panel
	var info_container = VBoxContainer.new()
	info_container.custom_minimum_size = Vector2(280, 0)
	info_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(info_container)

	var info_title = Label.new()
	info_title.text = "Save Details"
	info_title.add_theme_font_size_override("font_size", 18)
	info_container.add_child(info_title)

	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_label.text = "[i]Select a save file[/i]"
	info_container.add_child(info_label)

	# Buttons
	var button_box = HBoxContainer.new()
	button_box.add_theme_constant_override("separation", 10)
	button_box.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_box)

	back_button = Button.new()
	back_button.text = "Back"
	back_button.custom_minimum_size = Vector2(120, 40)
	back_button.pressed.connect(_on_back_pressed)
	button_box.add_child(back_button)

	delete_button = Button.new()
	delete_button.text = "Delete"
	delete_button.custom_minimum_size = Vector2(120, 40)
	delete_button.disabled = true
	delete_button.pressed.connect(_on_delete_pressed)
	button_box.add_child(delete_button)

	load_button = Button.new()
	load_button.text = "Load"
	load_button.custom_minimum_size = Vector2(120, 40)
	load_button.disabled = true
	load_button.pressed.connect(_on_load_pressed)
	button_box.add_child(load_button)

func show_screen() -> void:
	_refresh_save_list()
	show()

func _refresh_save_list() -> void:
	save_list.clear()
	save_files = SaveSystem.get_save_files()
	selected_index = -1
	load_button.disabled = true
	delete_button.disabled = true
	info_label.text = "[i]Select a save file[/i]"

	if save_files.is_empty():
		save_list.add_item("No saved games found")
		save_list.set_item_disabled(0, true)
		return

	for save_info in save_files:
		var filename = save_info.filename
		var display_name = filename.replace(".json", "")

		# Format special saves nicely
		if filename == "autosave.json":
			display_name = "Autosave"
		elif filename == "quicksave.json":
			display_name = "Quicksave"

		# Add modification date
		var modified = save_info.modified
		var datetime = Time.get_datetime_dict_from_unix_time(modified)
		var date_str = "%04d-%02d-%02d %02d:%02d" % [
			datetime.year, datetime.month, datetime.day,
			datetime.hour, datetime.minute
		]
		display_name += " (" + date_str + ")"

		save_list.add_item(display_name)

func _on_save_selected(index: int) -> void:
	if index < 0 or index >= save_files.size():
		return

	selected_index = index
	load_button.disabled = false
	delete_button.disabled = false

	# Load save file metadata
	var save_info = save_files[index]
	_show_save_info(save_info)

func _show_save_info(save_info: Dictionary) -> void:
	var full_path = save_info.path
	var file = FileAccess.open(full_path, FileAccess.READ)
	if file == null:
		info_label.text = "[color=red]Error reading save file[/color]"
		return

	var json_string = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(json_string) != OK:
		info_label.text = "[color=red]Error parsing save file[/color]"
		return

	var data = json.data
	var text = ""

	# Version
	text += "[b]Version:[/b] %s\n" % data.get("version", "Unknown")

	# Save time
	text += "[b]Saved:[/b] %s\n" % data.get("save_time", "Unknown")

	# Turn and year
	var turn = data.get("turn", 0)
	var year = data.get("year", -4000)
	var year_str = str(abs(year)) + (" BC" if year < 0 else " AD")
	text += "[b]Turn:[/b] %d (%s)\n" % [turn, year_str]

	# Map size
	var settings = data.get("settings", {})
	text += "[b]Map:[/b] %dx%d\n" % [
		settings.get("map_width", 0),
		settings.get("map_height", 0)
	]

	# Difficulty
	var diff_names = ["Settler", "Chieftain", "Warlord", "Noble", "Prince", "Monarch", "Emperor", "Immortal", "Deity"]
	var diff = settings.get("difficulty", 4)
	text += "[b]Difficulty:[/b] %s\n" % diff_names[clampi(diff, 0, 8)]

	# Players
	var players = data.get("players", [])
	text += "[b]Players:[/b] %d\n" % players.size()

	# Human player info
	for p in players:
		if p.get("is_human", false):
			text += "\n[b]Your Civilization:[/b]\n"
			text += "  %s\n" % p.get("civ_id", "Unknown").capitalize()
			text += "  Leader: %s\n" % p.get("leader_id", "Unknown").replace("_", " ").capitalize()
			var cities = p.get("city_ids", [])
			var units = p.get("unit_ids", [])
			text += "  Cities: %d, Units: %d\n" % [cities.size(), units.size()]
			break

	info_label.text = text

func _on_save_activated(index: int) -> void:
	# Double-click to load
	_on_load_pressed()

func _on_load_pressed() -> void:
	if selected_index < 0 or selected_index >= save_files.size():
		return

	var save_info = save_files[selected_index]
	var success = SaveSystem.load_game(save_info.filename)

	if success:
		game_loaded.emit()
		# Change to game scene
		get_tree().change_scene_to_file("res://scenes/main/game.tscn")
	else:
		info_label.text = "[color=red]Failed to load save file![/color]"

func _on_delete_pressed() -> void:
	if selected_index < 0 or selected_index >= save_files.size():
		return

	var save_info = save_files[selected_index]
	SaveSystem.delete_save(save_info.filename)
	_refresh_save_list()

func _on_back_pressed() -> void:
	hide()
	back_pressed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_back_pressed()
			get_viewport().set_input_as_handled()
