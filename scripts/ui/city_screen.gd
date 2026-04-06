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
var building_scroll: ScrollContainer
var building_list: Label
var close_button: Button

# City focus & specialist UI
var focus_dropdown: OptionButton
var specialist_container: VBoxContainer

# Colors
const BG_COLOR = Color(0.1, 0.1, 0.15, 1.0)
const HEADER_COLOR = Color(0.2, 0.2, 0.3)
const BUTTON_COLOR = Color(0.3, 0.3, 0.4)

func _ready() -> void:
	# Allow clicks to pass through to top menu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_ui()
	EventBus.show_city_screen.connect(_on_show_city_screen)
	EventBus.hide_city_screen.connect(_on_close_pressed)
	EventBus.close_all_popups.connect(_on_close_pressed)
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

	# City Focus dropdown
	var focus_label = Label.new()
	focus_label.text = "City Focus:"
	focus_label.position = Vector2(200, 50)
	focus_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(focus_label)

	focus_dropdown = OptionButton.new()
	focus_dropdown.position = Vector2(290, 47)
	focus_dropdown.custom_minimum_size = Vector2(120, 28)
	focus_dropdown.add_item("Balanced", 0)
	focus_dropdown.add_item("Food", 1)
	focus_dropdown.add_item("Production", 2)
	focus_dropdown.add_item("Commerce", 3)
	focus_dropdown.add_item("Science", 4)
	focus_dropdown.add_item("Culture", 5)
	focus_dropdown.item_selected.connect(_on_focus_changed)
	panel.add_child(focus_dropdown)

	# Specialist section (below yields)
	var spec_header = Label.new()
	spec_header.text = "Specialists"
	spec_header.position = Vector2(200, 85)
	spec_header.add_theme_font_size_override("font_size", 18)
	panel.add_child(spec_header)

	specialist_container = VBoxContainer.new()
	specialist_container.position = Vector2(200, 115)
	specialist_container.custom_minimum_size = Vector2(180, 100)
	specialist_container.add_theme_constant_override("separation", 2)
	panel.add_child(specialist_container)

	# Buildings section (right side) with scroll container
	var buildings_header = Label.new()
	buildings_header.text = "Buildings"
	buildings_header.position = Vector2(400, 85)
	buildings_header.add_theme_font_size_override("font_size", 18)
	panel.add_child(buildings_header)

	building_scroll = ScrollContainer.new()
	building_scroll.name = "BuildingScroll"
	building_scroll.position = Vector2(400, 115)
	building_scroll.custom_minimum_size = Vector2(280, 420)
	panel.add_child(building_scroll)

	building_list = Label.new()
	building_list.name = "BuildingList"
	building_list.add_theme_font_size_override("font_size", 14)
	building_scroll.add_child(building_list)

func _on_show_city_screen(city) -> void:
	# Close all other popups first
	EventBus.close_all_popups.emit()
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

	# Update focus dropdown
	_update_focus_dropdown()

	# Update specialists
	_update_specialist_ui()

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
	text += "Health: %d / %d\n" % [current_city.health, current_city.unhealthiness]

	# Great People points
	var gp_progress = current_city.get_meta("gp_progress") if current_city.has_meta("gp_progress") else 0
	var gp_points_per_turn = 0
	var gp_breakdown = current_city.get_great_people_points()
	for gp_type in gp_breakdown:
		gp_points_per_turn += gp_breakdown[gp_type]
	# Add settled GP bonus
	if current_city.has_meta("settled_great_people"):
		gp_points_per_turn += current_city.get_meta("settled_great_people").size() * 2

	var threshold = 100 + (GreatPeopleSystem.great_people_born.get(current_city.player_owner.player_id, 0) * 50) if current_city.player_owner else 100
	if gp_points_per_turn > 0:
		var turns_to_gp = ceili((threshold - gp_progress) / float(gp_points_per_turn))
		text += "\nGreat Person: %d/%d (+%d/turn, %d turns)" % [gp_progress, threshold, gp_points_per_turn, turns_to_gp]
	else:
		text += "\nGreat Person: %d/%d" % [gp_progress, threshold]

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

	# Categorize buildings
	var regular_buildings = []
	var national_wonders = []
	var world_wonders = []

	for building_id in current_city.buildings:
		var building = DataManager.get_building(building_id)
		var wonder_type = building.get("wonder_type", "")
		if wonder_type == "world":
			world_wonders.append(building_id)
		elif wonder_type == "national":
			national_wonders.append(building_id)
		else:
			regular_buildings.append(building_id)

	var text = ""

	# World Wonders section
	if not world_wonders.is_empty():
		text += "=== WORLD WONDERS ===\n"
		for building_id in world_wonders:
			text += _format_building_entry(building_id)
		text += "\n"

	# National Wonders section
	if not national_wonders.is_empty():
		text += "=== NATIONAL WONDERS ===\n"
		for building_id in national_wonders:
			text += _format_building_entry(building_id)
		text += "\n"

	# Regular Buildings section
	if not regular_buildings.is_empty():
		text += "=== BUILDINGS ===\n"
		for building_id in regular_buildings:
			text += _format_building_entry(building_id)

	building_list.text = text

func _format_building_entry(building_id: String) -> String:
	var building = DataManager.get_building(building_id)
	var text = "- %s\n" % building.get("name", building_id)

	# Show effects
	var effects = building.get("effects", {})
	for key in effects:
		if effects[key] != 0:
			text += "    %s: %s\n" % [key.replace("_", " ").capitalize(), str(effects[key])]

	return text

func _update_focus_dropdown() -> void:
	if focus_dropdown == null or current_city == null:
		return
	var focus_map = {"": 0, "food": 1, "production": 2, "commerce": 3, "science": 4, "culture": 5}
	focus_dropdown.selected = focus_map.get(current_city.city_focus, 0)

func _on_focus_changed(index: int) -> void:
	if current_city == null:
		return
	var focuses = ["", "food", "production", "commerce", "science", "culture"]
	if index < focuses.size():
		current_city.set_city_focus(focuses[index])
		_update_display()

func _update_specialist_ui() -> void:
	if specialist_container == null or current_city == null:
		return

	for child in specialist_container.get_children():
		child.queue_free()

	var available_pop = current_city.get_available_population()
	var pop_label = Label.new()
	pop_label.text = "Available: %d" % available_pop
	pop_label.add_theme_font_size_override("font_size", 12)
	specialist_container.add_child(pop_label)

	var spec_types = ["citizen", "priest", "artist", "merchant", "engineer", "scientist", "spy"]
	for spec_id in spec_types:
		var slots = current_city.get_specialist_slots(spec_id)
		if slots <= 0:
			continue

		var current = current_city.get_specialist_count(spec_id)
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)

		var name_label = Label.new()
		name_label.text = DataManager.get_specialist_name(spec_id)
		name_label.custom_minimum_size = Vector2(70, 0)
		name_label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(name_label)

		var minus_btn = Button.new()
		minus_btn.text = "-"
		minus_btn.custom_minimum_size = Vector2(25, 25)
		minus_btn.disabled = current <= 0
		minus_btn.pressed.connect(_on_specialist_minus.bind(spec_id))
		hbox.add_child(minus_btn)

		var count_label = Label.new()
		count_label.text = "%d/%d" % [current, slots]
		count_label.custom_minimum_size = Vector2(35, 0)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(count_label)

		var plus_btn = Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(25, 25)
		plus_btn.disabled = current >= slots or available_pop <= 0
		plus_btn.pressed.connect(_on_specialist_plus.bind(spec_id))
		hbox.add_child(plus_btn)

		specialist_container.add_child(hbox)

func _on_specialist_plus(spec_id: String) -> void:
	if current_city == null or not current_city.can_add_specialist(spec_id):
		return
	current_city.add_specialist(spec_id)
	current_city.calculate_yields()
	_update_display()

func _on_specialist_minus(spec_id: String) -> void:
	if current_city == null or current_city.get_specialist_count(spec_id) <= 0:
		return
	current_city.remove_specialist(spec_id)
	current_city.calculate_yields()
	_update_display()

func _on_close_pressed() -> void:
	hide()
	current_city = null

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
