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
var building_container: VBoxContainer
var close_button: Button

# City focus & specialist UI
var focus_dropdown: OptionButton
var specialist_container: VBoxContainer

# Tile grid view
var tile_grid: Control = null

# Production queue
var queue_container: VBoxContainer = null

# Culture bar
var culture_bar: ProgressBar = null
var culture_label_display: Label = null

# Building tooltip
var building_tooltip: PanelContainer = null
var building_tooltip_label: Label = null

# Whip/Buy buttons
var whip_button: Button = null
var buy_button: Button = null

# Happiness visualization
var happiness_container: HBoxContainer = null

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
	# Main panel
	panel = Panel.new()
	panel.name = "Panel"
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.set_border_width_all(2)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(960, 650)
	add_child(panel)

	# Root VBox inside panel
	var root_vbox = VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_KEEP_SIZE, 10)
	root_vbox.add_theme_constant_override("separation", 6)
	panel.add_child(root_vbox)

	# === HEADER ROW ===
	var header_row = HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 10)

	city_name_label = Label.new()
	city_name_label.add_theme_font_size_override("font_size", 22)
	city_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(city_name_label)

	population_label = Label.new()
	population_label.add_theme_font_size_override("font_size", 16)
	header_row.add_child(population_label)

	var focus_label = Label.new()
	focus_label.text = "Focus:"
	focus_label.add_theme_font_size_override("font_size", 13)
	header_row.add_child(focus_label)

	focus_dropdown = OptionButton.new()
	focus_dropdown.custom_minimum_size = Vector2(110, 26)
	focus_dropdown.add_item("Balanced", 0)
	focus_dropdown.add_item("Food", 1)
	focus_dropdown.add_item("Production", 2)
	focus_dropdown.add_item("Commerce", 3)
	focus_dropdown.add_item("Science", 4)
	focus_dropdown.add_item("Culture", 5)
	focus_dropdown.item_selected.connect(_on_focus_changed)
	header_row.add_child(focus_dropdown)

	close_button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close_pressed)
	header_row.add_child(close_button)

	root_vbox.add_child(header_row)

	# Happiness row
	happiness_container = HBoxContainer.new()
	happiness_container.add_theme_constant_override("separation", 1)
	happiness_container.custom_minimum_size = Vector2(0, 14)
	root_vbox.add_child(happiness_container)

	# === THREE-COLUMN BODY ===
	var body_hbox = HBoxContainer.new()
	body_hbox.add_theme_constant_override("separation", 12)
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vbox.add_child(body_hbox)

	# --- LEFT COLUMN (yields, tile grid, culture) ---
	var left_col = VBoxContainer.new()
	left_col.custom_minimum_size = Vector2(220, 0)
	left_col.add_theme_constant_override("separation", 4)

	var yields_header = Label.new()
	yields_header.text = "City Yields"
	yields_header.add_theme_font_size_override("font_size", 16)
	left_col.add_child(yields_header)

	yields_label = Label.new()
	yields_label.add_theme_font_size_override("font_size", 12)
	left_col.add_child(yields_label)

	tile_grid = Control.new()
	tile_grid.custom_minimum_size = Vector2(210, 210)
	tile_grid.gui_input.connect(_on_tile_grid_input)
	left_col.add_child(tile_grid)

	culture_label_display = Label.new()
	culture_label_display.add_theme_font_size_override("font_size", 11)
	left_col.add_child(culture_label_display)

	culture_bar = ProgressBar.new()
	culture_bar.custom_minimum_size = Vector2(210, 8)
	culture_bar.show_percentage = false
	left_col.add_child(culture_bar)

	body_hbox.add_child(left_col)

	# --- MIDDLE COLUMN (production, specialists, queue) ---
	var mid_col = VBoxContainer.new()
	mid_col.custom_minimum_size = Vector2(240, 0)
	mid_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid_col.add_theme_constant_override("separation", 4)

	var production_header = Label.new()
	production_header.text = "Production"
	production_header.add_theme_font_size_override("font_size", 16)
	mid_col.add_child(production_header)

	production_progress_label = Label.new()
	production_progress_label.add_theme_font_size_override("font_size", 12)
	mid_col.add_child(production_progress_label)

	var prod_buttons = HBoxContainer.new()
	prod_buttons.add_theme_constant_override("separation", 4)

	change_production_btn = Button.new()
	change_production_btn.text = "Change Production"
	change_production_btn.custom_minimum_size = Vector2(140, 28)
	change_production_btn.pressed.connect(_toggle_production_list)
	prod_buttons.add_child(change_production_btn)

	whip_button = Button.new()
	whip_button.text = "Whip (-1 Pop)"
	whip_button.custom_minimum_size = Vector2(90, 28)
	whip_button.visible = false
	whip_button.pressed.connect(_on_whip_pressed)
	prod_buttons.add_child(whip_button)

	buy_button = Button.new()
	buy_button.text = "Buy"
	buy_button.custom_minimum_size = Vector2(80, 28)
	buy_button.visible = false
	buy_button.pressed.connect(_on_buy_pressed)
	prod_buttons.add_child(buy_button)

	mid_col.add_child(prod_buttons)

	# Production options (scrollable, initially hidden)
	production_scroll = ScrollContainer.new()
	production_scroll.custom_minimum_size = Vector2(230, 160)
	production_scroll.visible = false
	production_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid_col.add_child(production_scroll)

	production_list = VBoxContainer.new()
	production_scroll.add_child(production_list)

	var spec_header = Label.new()
	spec_header.text = "Specialists"
	spec_header.add_theme_font_size_override("font_size", 16)
	mid_col.add_child(spec_header)

	specialist_container = VBoxContainer.new()
	specialist_container.custom_minimum_size = Vector2(0, 60)
	specialist_container.add_theme_constant_override("separation", 2)
	mid_col.add_child(specialist_container)

	var queue_header = Label.new()
	queue_header.text = "Production Queue"
	queue_header.add_theme_font_size_override("font_size", 16)
	mid_col.add_child(queue_header)

	queue_container = VBoxContainer.new()
	queue_container.custom_minimum_size = Vector2(0, 60)
	queue_container.add_theme_constant_override("separation", 2)
	mid_col.add_child(queue_container)

	body_hbox.add_child(mid_col)

	# --- RIGHT COLUMN (buildings) ---
	var right_col = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.add_theme_constant_override("separation", 4)

	var buildings_header = Label.new()
	buildings_header.text = "Buildings"
	buildings_header.add_theme_font_size_override("font_size", 16)
	right_col.add_child(buildings_header)

	building_scroll = ScrollContainer.new()
	building_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(building_scroll)

	building_container = VBoxContainer.new()
	building_container.add_theme_constant_override("separation", 1)
	building_scroll.add_child(building_container)

	body_hbox.add_child(right_col)

	# Building tooltip (floating, outside containers)
	building_tooltip = PanelContainer.new()
	building_tooltip.visible = false
	building_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tt_style = StyleBoxFlat.new()
	tt_style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	tt_style.border_color = Color(0.4, 0.4, 0.5)
	tt_style.set_border_width_all(1)
	tt_style.set_corner_radius_all(4)
	tt_style.set_content_margin_all(8)
	building_tooltip.add_theme_stylebox_override("panel", tt_style)
	building_tooltip_label = Label.new()
	building_tooltip_label.add_theme_font_size_override("font_size", 12)
	building_tooltip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	building_tooltip.add_child(building_tooltip_label)
	panel.add_child(building_tooltip)

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

	# Update buildings (interactive)
	_update_building_list()

	# Update focus dropdown
	_update_focus_dropdown()

	# Update specialists
	_update_specialist_ui()

	# Update tile grid
	_update_tile_grid()

	# Update culture bar
	_update_culture_display()

	# Update happiness visualization
	_update_happiness_display()

	# Update production queue
	_update_production_queue()

	# Update whip/buy buttons
	if whip_button:
		whip_button.visible = current_city.can_whip()
	if buy_button:
		if current_city.can_hurry_gold():
			buy_button.visible = true
			buy_button.text = "Buy (%dg)" % current_city.get_hurry_cost()
		else:
			buy_button.visible = false

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
	# Shift-click adds to queue instead of replacing
	if Input.is_key_pressed(KEY_SHIFT) and current_city.current_production != "":
		if current_city.production_queue.size() < 6:
			current_city.production_queue.append(item_id)
	else:
		current_city.set_production(item_id)
		# Close the build menu after selection
		production_scroll.visible = false
		change_production_btn.text = "Change Production"
	_update_display()

func _update_building_list() -> void:
	if building_container == null:
		return

	for child in building_container.get_children():
		child.queue_free()

	if current_city.buildings.is_empty():
		var empty_label = Label.new()
		empty_label.text = "(No buildings yet)"
		empty_label.add_theme_font_size_override("font_size", 12)
		building_container.add_child(empty_label)
		return

	# Categorize buildings
	var categories = {"world": [], "national": [], "regular": []}
	for building_id in current_city.buildings:
		var building = DataManager.get_building(building_id)
		var wonder_type = building.get("wonder_type", "")
		if wonder_type == "world":
			categories["world"].append(building_id)
		elif wonder_type == "national":
			categories["national"].append(building_id)
		else:
			categories["regular"].append(building_id)

	for cat in [["world", "WORLD WONDERS"], ["national", "NATIONAL WONDERS"], ["regular", "BUILDINGS"]]:
		if categories[cat[0]].is_empty():
			continue
		var header = Label.new()
		header.text = "=== %s ===" % cat[1]
		header.add_theme_font_size_override("font_size", 11)
		header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.5))
		building_container.add_child(header)

		for building_id in categories[cat[0]]:
			var building = DataManager.get_building(building_id)
			var btn = Button.new()
			btn.text = building.get("name", building_id)
			btn.flat = true
			btn.custom_minimum_size = Vector2(0, 22)
			btn.add_theme_font_size_override("font_size", 12)
			btn.mouse_entered.connect(_on_building_hover.bind(building_id, btn))
			btn.mouse_exited.connect(_on_building_unhover)
			building_container.add_child(btn)

func _on_building_hover(building_id: String, btn: Button) -> void:
	if building_tooltip == null or building_tooltip_label == null:
		return
	var building = DataManager.get_building(building_id)
	var effects = building.get("effects", {})
	var text = "[b]%s[/b]\n" % building.get("name", building_id)
	for key in effects:
		if effects[key] != 0:
			var value = effects[key]
			var label = key.replace("_", " ").capitalize()
			if value is float and value < 1.0 and value > -1.0:
				text += "+%d%% %s\n" % [int(value * 100), label]
			else:
				text += "+%s %s\n" % [str(value), label]
	building_tooltip_label.text = text.strip_edges()
	building_tooltip.visible = true
	building_tooltip.position = Vector2(btn.global_position.x - panel.global_position.x - 200, btn.global_position.y - panel.global_position.y)

func _on_building_unhover() -> void:
	if building_tooltip:
		building_tooltip.visible = false

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

func _update_tile_grid() -> void:
	if tile_grid == null or current_city == null:
		return
	tile_grid.queue_redraw()

	# We need to draw the tile grid via a connected draw signal or by overriding
	# Since tile_grid is a plain Control, we connect its draw signal
	if not tile_grid.draw.is_connected(_draw_tile_grid):
		tile_grid.draw.connect(_draw_tile_grid)

func _draw_tile_grid() -> void:
	if current_city == null or GameManager.hex_grid == null:
		return

	var fat_cross = GridUtils.get_fat_cross(current_city.grid_position)
	var all_tiles = [current_city.grid_position]
	all_tiles.append_array(fat_cross)

	var cell_size = 38
	var center_offset = Vector2(105, 105)  # Center of the 210x210 area

	for tile_pos in all_tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile == null:
			continue

		var rel = tile_pos - current_city.grid_position
		var draw_pos = Vector2(rel.x * cell_size, rel.y * cell_size) + center_offset - Vector2(cell_size / 2, cell_size / 2)

		# Background color
		var bg = DataManager.get_terrain_color(tile.terrain_id)
		if tile_pos not in current_city.territory:
			bg = bg.darkened(0.6)

		tile_grid.draw_rect(Rect2(draw_pos, Vector2(cell_size - 2, cell_size - 2)), bg)

		# Border: green if worked, yellow if locked, gray otherwise
		var border_color = Color(0.3, 0.3, 0.3, 0.5)
		if tile_pos in current_city.worked_tiles:
			border_color = Color(0.2, 0.8, 0.2, 0.8)
		if tile_pos in current_city.locked_tiles:
			border_color = Color(0.9, 0.8, 0.2, 0.8)

		tile_grid.draw_rect(Rect2(draw_pos, Vector2(cell_size - 2, cell_size - 2)), border_color, false, 2.0)

		# Yield numbers (only for tiles in territory)
		if tile_pos in current_city.territory:
			var yields = tile.get_yields()
			var font = ThemeDB.fallback_font
			var fs = 9
			var f = yields.get("food", 0)
			var p = yields.get("production", 0)
			var c = yields.get("commerce", 0)
			if f > 0:
				tile_grid.draw_string(font, draw_pos + Vector2(2, 12), str(f), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.3, 0.9, 0.3))
			if p > 0:
				tile_grid.draw_string(font, draw_pos + Vector2(14, 12), str(p), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.9, 0.6, 0.2))
			if c > 0:
				tile_grid.draw_string(font, draw_pos + Vector2(26, 12), str(c), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.9, 0.9, 0.3))

		# City center marker
		if tile_pos == current_city.grid_position:
			tile_grid.draw_string(ThemeDB.fallback_font, draw_pos + Vector2(cell_size / 2 - 5, cell_size - 6), "★", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

func _on_tile_grid_input(event: InputEvent) -> void:
	if current_city == null or not (event is InputEventMouseButton):
		return
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell_size = 38
	var center_offset = Vector2(105, 105)
	var click_pos = event.position

	# Convert click to grid offset
	var rel_pos = (click_pos - center_offset + Vector2(cell_size / 2, cell_size / 2)) / cell_size
	var grid_offset = Vector2i(roundi(rel_pos.x), roundi(rel_pos.y))
	var tile_pos = current_city.grid_position + grid_offset

	# Check if this is in the fat cross
	var fat_cross = GridUtils.get_fat_cross(current_city.grid_position)
	if tile_pos in fat_cross and tile_pos in current_city.territory:
		current_city.toggle_tile_work(tile_pos)
		_update_display()

func _update_culture_display() -> void:
	if current_city == null:
		return

	var culture_names = ["Poor", "Fledgling", "Developing", "Refined", "Influential", "Legendary"]
	var level = min(current_city.culture_level, culture_names.size() - 1)
	var next_threshold = current_city.CULTURE_THRESHOLDS[min(current_city.culture_level + 1, current_city.CULTURE_THRESHOLDS.size() - 1)]

	if culture_label_display:
		var turns_text = ""
		if current_city.culture_yield > 0 and current_city.culture < next_threshold:
			var turns = ceili((next_threshold - current_city.culture) / float(current_city.culture_yield))
			turns_text = " (%d turns)" % turns
		culture_label_display.text = "Culture: %s — %d/%d%s" % [culture_names[level], current_city.culture, next_threshold, turns_text]

	if culture_bar:
		culture_bar.max_value = max(next_threshold, 1)
		culture_bar.value = min(current_city.culture, next_threshold)

func _update_happiness_display() -> void:
	if happiness_container == null or current_city == null:
		return

	for child in happiness_container.get_children():
		child.queue_free()

	var happy = current_city.happiness
	var unhappy = current_city.unhappiness
	var total = min(happy + unhappy, 20)  # Cap at 20 circles

	for i in range(total):
		var dot = Label.new()
		if i < happy:
			dot.text = "●"
			dot.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
		else:
			dot.text = "●"
			dot.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		dot.add_theme_font_size_override("font_size", 10)
		happiness_container.add_child(dot)

func _update_production_queue() -> void:
	if queue_container == null or current_city == null:
		return

	for child in queue_container.get_children():
		child.queue_free()

	if current_city.production_queue.is_empty():
		var empty = Label.new()
		empty.text = "(Empty — Shift-click to queue)"
		empty.add_theme_font_size_override("font_size", 11)
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		queue_container.add_child(empty)
		return

	for i in range(current_city.production_queue.size()):
		var item_id = current_city.production_queue[i]
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)

		# Item name
		var item_name = item_id
		var udata = DataManager.get_unit(item_id)
		if not udata.is_empty():
			item_name = udata.get("name", item_id)
		else:
			var bdata = DataManager.get_building(item_id)
			if not bdata.is_empty():
				item_name = bdata.get("name", item_id)

		var label = Label.new()
		label.text = "%d. %s" % [i + 1, item_name]
		label.add_theme_font_size_override("font_size", 11)
		label.custom_minimum_size = Vector2(140, 0)
		hbox.add_child(label)

		# Remove button
		var remove_btn = Button.new()
		remove_btn.text = "X"
		remove_btn.custom_minimum_size = Vector2(22, 20)
		remove_btn.add_theme_font_size_override("font_size", 10)
		remove_btn.pressed.connect(_on_queue_remove.bind(i))
		hbox.add_child(remove_btn)

		# Move up button
		if i > 0:
			var up_btn = Button.new()
			up_btn.text = "▲"
			up_btn.custom_minimum_size = Vector2(22, 20)
			up_btn.add_theme_font_size_override("font_size", 10)
			up_btn.pressed.connect(_on_queue_move_up.bind(i))
			hbox.add_child(up_btn)

		queue_container.add_child(hbox)

func _on_queue_remove(index: int) -> void:
	if current_city and index < current_city.production_queue.size():
		current_city.production_queue.remove_at(index)
		_update_display()

func _on_queue_move_up(index: int) -> void:
	if current_city and index > 0 and index < current_city.production_queue.size():
		var item = current_city.production_queue[index]
		current_city.production_queue.remove_at(index)
		current_city.production_queue.insert(index - 1, item)
		_update_display()

func _on_whip_pressed() -> void:
	if current_city and current_city.can_whip():
		current_city.whip()
		_update_display()

func _on_buy_pressed() -> void:
	if current_city and current_city.can_hurry_gold():
		current_city.hurry_with_gold()
		_update_display()

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
