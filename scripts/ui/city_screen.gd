class_name CityScreen
extends Control
## City management screen showing production, buildings, and yields.

var current_city = null  # City (untyped to avoid load-order issues)

# UI References - will be created dynamically
var panel: Panel
var city_name_label: Label
var population_label: Label
var yields_label: Label
var production_list: VBoxContainer
var production_scroll: ScrollContainer
var production_progress_label: Label
var change_production_btn: Button
var building_list: Label
var close_button: Button

# Colors
const BG_COLOR = Color(0.1, 0.1, 0.15, 1.0)
const HEADER_COLOR = Color(0.2, 0.2, 0.3)
const BUTTON_COLOR = Color(0.3, 0.3, 0.4)

func _ready() -> void:
	_create_ui()
	EventBus.show_city_screen.connect(_on_show_city_screen)
	EventBus.hide_city_screen.connect(_on_close_pressed)
	hide()

func _create_ui() -> void:
	# Main panel - sized and positioned over the city
	panel = Panel.new()
	panel.name = "Panel"
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(700, 550)
	add_child(panel)

	# Close button (top right)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.position = Vector2(panel.size.x - 40, 10)
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close_pressed)
	panel.add_child(close_button)

	# City name header
	city_name_label = Label.new()
	city_name_label.name = "CityName"
	city_name_label.position = Vector2(20, 15)
	city_name_label.add_theme_font_size_override("font_size", 24)
	panel.add_child(city_name_label)

	# Population
	population_label = Label.new()
	population_label.name = "Population"
	population_label.position = Vector2(20, 50)
	population_label.add_theme_font_size_override("font_size", 16)
	panel.add_child(population_label)

	# Yields section
	var yields_header = Label.new()
	yields_header.text = "City Yields"
	yields_header.position = Vector2(20, 85)
	yields_header.add_theme_font_size_override("font_size", 18)
	panel.add_child(yields_header)

	yields_label = Label.new()
	yields_label.name = "Yields"
	yields_label.position = Vector2(20, 115)
	yields_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(yields_label)

	# Current production
	var production_header = Label.new()
	production_header.text = "Current Production"
	production_header.position = Vector2(20, 230)
	production_header.add_theme_font_size_override("font_size", 18)
	panel.add_child(production_header)

	production_progress_label = Label.new()
	production_progress_label.name = "ProductionProgress"
	production_progress_label.position = Vector2(20, 260)
	production_progress_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(production_progress_label)

	# Change production button
	change_production_btn = Button.new()
	change_production_btn.name = "ChangeProductionBtn"
	change_production_btn.text = "Change Production"
	change_production_btn.position = Vector2(20, 310)
	change_production_btn.custom_minimum_size = Vector2(150, 30)
	change_production_btn.pressed.connect(_toggle_production_list)
	panel.add_child(change_production_btn)

	# Production options (scrollable, initially hidden)
	production_scroll = ScrollContainer.new()
	production_scroll.name = "ProductionScroll"
	production_scroll.position = Vector2(20, 350)
	production_scroll.custom_minimum_size = Vector2(350, 180)
	production_scroll.visible = false
	panel.add_child(production_scroll)

	production_list = VBoxContainer.new()
	production_list.name = "ProductionList"
	production_scroll.add_child(production_list)

	# Buildings section (right side)
	var buildings_header = Label.new()
	buildings_header.text = "Buildings"
	buildings_header.position = Vector2(400, 85)
	buildings_header.add_theme_font_size_override("font_size", 18)
	panel.add_child(buildings_header)

	building_list = Label.new()
	building_list.name = "BuildingList"
	building_list.position = Vector2(400, 115)
	building_list.add_theme_font_size_override("font_size", 14)
	panel.add_child(building_list)

func _on_show_city_screen(city) -> void:
	current_city = city
	_update_display()
	_position_over_city()
	show()

func _position_over_city() -> void:
	if current_city == null:
		# Center on screen below top menu
		var viewport_size = get_viewport_rect().size
		panel.position = Vector2(
			(viewport_size.x - panel.size.x) / 2,
			50  # Below top menu
		)
		return

	# Get the city's world position and convert to screen position
	var camera = get_viewport().get_camera_2d()
	if camera:
		var city_world_pos = GridUtils.grid_to_pixel(current_city.grid_position)
		var viewport_size = get_viewport_rect().size
		var canvas_transform = get_viewport().get_canvas_transform()
		var screen_pos = canvas_transform * city_world_pos

		# Position the panel centered horizontally on the city, below it vertically
		var panel_x = screen_pos.x - panel.size.x / 2
		var panel_y = screen_pos.y - panel.size.y / 2

		# Clamp to keep within screen bounds, respecting top menu (40px)
		panel_x = clamp(panel_x, 10, viewport_size.x - panel.size.x - 10)
		panel_y = clamp(panel_y, 50, viewport_size.y - panel.size.y - 10)

		panel.position = Vector2(panel_x, panel_y)
	else:
		# Fallback: center on screen
		var viewport_size = get_viewport_rect().size
		panel.position = Vector2(
			(viewport_size.x - panel.size.x) / 2,
			50
		)

func _update_display() -> void:
	if current_city == null:
		return

	# Update close button position based on panel size
	close_button.position = Vector2(panel.size.x - 50, 10)

	# City name and population
	city_name_label.text = current_city.city_name
	population_label.text = "Population: %d" % current_city.population

	# Update yields
	_update_yields()

	# Update production
	_update_production_progress()
	# Only update production list if it's visible
	if production_scroll.visible:
		_update_production_list()

	# Update buildings
	_update_building_list()

func _update_yields() -> void:
	current_city.calculate_yields()

	var text = ""
	text += "Food: %d" % current_city.food_yield
	if current_city.food_surplus >= 0:
		text += " (+%d surplus)" % current_city.food_surplus
	else:
		text += " (%d deficit)" % current_city.food_surplus
	text += "\n"

	# Food to growth
	var food_needed = current_city.food_needed_for_growth()
	var turns_to_grow = "Never"
	if current_city.food_surplus > 0:
		var remaining = food_needed - current_city.food_stockpile
		turns_to_grow = str(ceili(remaining / float(current_city.food_surplus)))
	text += "Growth: %d/%d (%s turns)\n" % [int(current_city.food_stockpile), food_needed, turns_to_grow]

	text += "\nProduction: %d\n" % current_city.production_yield
	text += "Commerce: %d\n" % current_city.commerce_yield
	text += "Science: %d\n" % current_city.science_yield
	text += "Culture: %d\n" % current_city.culture_yield
	text += "\nHappiness: %d / %d\n" % [current_city.happiness, current_city.unhappiness]
	text += "Health: %d / %d" % [current_city.health, current_city.unhealthiness]

	yields_label.text = text

func _update_production_progress() -> void:
	if current_city.current_production == "":
		production_progress_label.text = "Nothing being built\nSelect something to produce below"
		return

	var cost = current_city.get_production_cost()
	var progress = current_city.production_progress
	var remaining = cost - progress
	var turns_left = ceili(remaining / max(current_city.production_yield, 1))

	# Get name
	var item_name = current_city.current_production
	var unit_data = DataManager.get_unit(current_city.current_production)
	if not unit_data.is_empty():
		item_name = unit_data.get("name", item_name)
	else:
		var building_data = DataManager.get_building(current_city.current_production)
		if not building_data.is_empty():
			item_name = building_data.get("name", item_name)

	production_progress_label.text = "Building: %s\nProgress: %d/%d (%d turns remaining)" % [
		item_name, progress, cost, turns_left
	]

func _toggle_production_list() -> void:
	production_scroll.visible = not production_scroll.visible
	if production_scroll.visible:
		change_production_btn.text = "Hide Build Menu"
		_update_production_list()
	else:
		change_production_btn.text = "Change Production"

func _update_production_list() -> void:
	# Clear existing
	for child in production_list.get_children():
		child.queue_free()

	# Section: Units (excluding great people)
	var units_header = Label.new()
	units_header.text = "--- Units ---"
	units_header.add_theme_font_size_override("font_size", 14)
	production_list.add_child(units_header)

	for unit_id in DataManager.units:
		if current_city.can_build_unit(unit_id):
			var unit_data = DataManager.get_unit(unit_id)
			# Skip great people
			if unit_data.get("unit_class", "") == "great_person":
				continue
			var btn = Button.new()
			var cost = int(DataManager.get_unit_cost(unit_id) * GameManager.get_speed_multiplier())
			var turns = ceili(cost / max(current_city.production_yield, 1))
			btn.text = "%s (%d, %d turns)" % [unit_data.get("name", unit_id), cost, turns]
			btn.pressed.connect(_on_production_selected.bind(unit_id))
			btn.custom_minimum_size = Vector2(320, 30)
			production_list.add_child(btn)

	# Section: Buildings
	var buildings_header = Label.new()
	buildings_header.text = "--- Buildings ---"
	buildings_header.add_theme_font_size_override("font_size", 14)
	production_list.add_child(buildings_header)

	for building_id in DataManager.buildings:
		if current_city.can_build_building(building_id):
			var building_data = DataManager.get_building(building_id)
			var btn = Button.new()
			var cost = int(DataManager.get_building_cost(building_id) * GameManager.get_speed_multiplier())
			var turns = ceili(cost / max(current_city.production_yield, 1))
			btn.text = "%s (%d, %d turns)" % [building_data.get("name", building_id), cost, turns]
			btn.pressed.connect(_on_production_selected.bind(building_id))
			btn.custom_minimum_size = Vector2(320, 30)
			production_list.add_child(btn)

func _on_production_selected(item_id: String) -> void:
	current_city.set_production(item_id)
	# Close the build menu after selection
	production_scroll.visible = false
	change_production_btn.text = "Change Production"
	_update_display()

func _update_building_list() -> void:
	if current_city.buildings.is_empty():
		building_list.text = "(No buildings yet)"
		return

	var text = ""
	for building_id in current_city.buildings:
		var building = DataManager.get_building(building_id)
		text += "- %s\n" % building.get("name", building_id)

		# Show effects
		var effects = building.get("effects", {})
		for key in effects:
			if effects[key] != 0:
				text += "    %s: %s\n" % [key.replace("_", " ").capitalize(), str(effects[key])]

	building_list.text = text

func _on_close_pressed() -> void:
	hide()
	current_city = null

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
