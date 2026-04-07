extends Control
## Religion Advisor screen — BTS-style city-religion grid, state religion selection, effects summary.

const BG_COLOR = Color(0.08, 0.08, 0.12, 1.0)
const PANEL_COLOR = Color(0.12, 0.12, 0.18, 1.0)
const HEADER_COLOR = Color(0.15, 0.15, 0.22, 1.0)
const CELL_COLOR = Color(0.1, 0.1, 0.15, 1.0)
const STATE_REL_TINT = Color(0.15, 0.25, 0.15, 1.0)
const SELECTED_BTN_COLOR = Color(0.2, 0.4, 0.3, 1.0)
const NORMAL_BTN_COLOR = Color(0.18, 0.18, 0.25, 1.0)
const HOLY_CITY_COLOR = Color(1.0, 0.85, 0.0)
const BORDER_COLOR = Color(0.3, 0.3, 0.5)

# UI elements
var main_panel: PanelContainer
var grid_container: GridContainer
var grid_scroll: ScrollContainer
var state_religion_vbox: VBoxContainer
var current_religion_label: Label
var religion_buttons_container: VBoxContainer
var anarchy_label: Label
var effects_label: RichTextLabel
var no_religions_label: Label

var current_player = null

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	hide()

	EventBus.show_religion_screen.connect(_on_show)
	EventBus.hide_religion_screen.connect(_on_close)
	EventBus.close_all_popups.connect(_on_close)
	EventBus.religion_founded.connect(_on_religion_event)
	EventBus.religion_spread.connect(_on_religion_spread_event)
	EventBus.state_religion_adopted.connect(_on_state_religion_event)

func _build_ui() -> void:
	# Full-screen dark background
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Main panel
	main_panel = PanelContainer.new()
	main_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_panel.offset_left = 10
	main_panel.offset_right = -10
	main_panel.offset_top = 50
	main_panel.offset_bottom = -10
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.set_border_width_all(2)
	style.border_color = BORDER_COLOR
	style.set_corner_radius_all(8)
	main_panel.add_theme_stylebox_override("panel", style)
	add_child(main_panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	main_panel.add_child(main_vbox)

	# Header
	var header = HBoxContainer.new()
	main_vbox.add_child(header)

	var title = Label.new()
	title.text = "Religion Advisor"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	# Content split: left (grid) + right (state religion)
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 10)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	# Left: Grid in scroll container
	var grid_panel = PanelContainer.new()
	grid_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_panel.size_flags_stretch_ratio = 2.5
	var grid_style = StyleBoxFlat.new()
	grid_style.bg_color = PANEL_COLOR
	grid_style.set_border_width_all(1)
	grid_style.border_color = BORDER_COLOR
	grid_style.set_corner_radius_all(4)
	grid_panel.add_theme_stylebox_override("panel", grid_style)
	content_hbox.add_child(grid_panel)

	var grid_vbox = VBoxContainer.new()
	grid_vbox.add_theme_constant_override("separation", 5)
	grid_panel.add_child(grid_vbox)

	var grid_title = Label.new()
	grid_title.text = "City Religions"
	grid_title.add_theme_font_size_override("font_size", 16)
	grid_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid_vbox.add_child(grid_title)

	no_religions_label = Label.new()
	no_religions_label.text = "No religions have been founded in the world yet."
	no_religions_label.add_theme_font_size_override("font_size", 14)
	no_religions_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	no_religions_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	no_religions_label.hide()
	grid_vbox.add_child(no_religions_label)

	grid_scroll = ScrollContainer.new()
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	grid_vbox.add_child(grid_scroll)

	grid_container = GridContainer.new()
	grid_container.add_theme_constant_override("h_separation", 2)
	grid_container.add_theme_constant_override("v_separation", 2)
	grid_scroll.add_child(grid_container)

	# Right: State Religion panel
	var right_panel = PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(260, 0)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.0
	var right_style = StyleBoxFlat.new()
	right_style.bg_color = PANEL_COLOR
	right_style.set_border_width_all(1)
	right_style.border_color = BORDER_COLOR
	right_style.set_corner_radius_all(4)
	right_panel.add_theme_stylebox_override("panel", right_style)
	content_hbox.add_child(right_panel)

	state_religion_vbox = VBoxContainer.new()
	state_religion_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(state_religion_vbox)

	var state_title = Label.new()
	state_title.text = "State Religion"
	state_title.add_theme_font_size_override("font_size", 18)
	state_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_religion_vbox.add_child(state_title)

	current_religion_label = Label.new()
	current_religion_label.add_theme_font_size_override("font_size", 16)
	current_religion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state_religion_vbox.add_child(current_religion_label)

	var sep = HSeparator.new()
	state_religion_vbox.add_child(sep)

	var switch_label = Label.new()
	switch_label.text = "Switch to:"
	switch_label.add_theme_font_size_override("font_size", 14)
	state_religion_vbox.add_child(switch_label)

	religion_buttons_container = VBoxContainer.new()
	religion_buttons_container.add_theme_constant_override("separation", 4)
	state_religion_vbox.add_child(religion_buttons_container)

	anarchy_label = Label.new()
	anarchy_label.add_theme_font_size_override("font_size", 13)
	anarchy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	state_religion_vbox.add_child(anarchy_label)

	# Bottom: Effects panel
	var effects_panel = PanelContainer.new()
	effects_panel.custom_minimum_size = Vector2(0, 140)
	var eff_style = StyleBoxFlat.new()
	eff_style.bg_color = PANEL_COLOR
	eff_style.set_border_width_all(1)
	eff_style.border_color = BORDER_COLOR
	eff_style.set_corner_radius_all(4)
	effects_panel.add_theme_stylebox_override("panel", eff_style)
	main_vbox.add_child(effects_panel)

	effects_label = RichTextLabel.new()
	effects_label.bbcode_enabled = true
	effects_label.fit_content = true
	effects_label.scroll_active = true
	effects_label.add_theme_font_size_override("normal_font_size", 14)
	effects_panel.add_child(effects_label)

func _on_show() -> void:
	EventBus.close_all_popups.emit()
	current_player = GameManager.human_player
	_refresh_all()
	show()

func _on_close() -> void:
	hide()

func _refresh_all() -> void:
	if current_player == null:
		return
	_build_city_religion_grid()
	_build_state_religion_panel()
	_update_effects_panel()

func _get_founded_religions_sorted() -> Array:
	var founded = ReligionSystem.get_founded_religions()
	# Sort by founding_order from religions.json
	founded.sort_custom(func(a, b):
		var a_data = DataManager.get_religion(a)
		var b_data = DataManager.get_religion(b)
		return a_data.get("founding_order", 99) < b_data.get("founding_order", 99)
	)
	return founded

func _build_city_religion_grid() -> void:
	# Clear existing grid
	for child in grid_container.get_children():
		child.queue_free()

	var founded = _get_founded_religions_sorted()

	if founded.is_empty():
		no_religions_label.show()
		grid_container.hide()
		return

	no_religions_label.hide()
	grid_container.show()

	grid_container.columns = 1 + founded.size()

	# Header row
	_add_grid_cell("City", HEADER_COLOR, Color.WHITE, true, 140)
	for religion_id in founded:
		var rel_data = DataManager.get_religion(religion_id)
		var symbol = rel_data.get("symbol", "?")
		var rel_name = rel_data.get("name", religion_id)
		var is_state = (religion_id == current_player.state_religion)
		var bg = STATE_REL_TINT if is_state else HEADER_COLOR
		_add_grid_cell(symbol + " " + rel_name, bg, Color.WHITE, true, 100)

	# City rows
	for city in current_player.cities:
		# City name
		var city_label_text = city.city_name
		if city.is_capital():
			city_label_text += " *"
		_add_grid_cell(city_label_text, CELL_COLOR, Color.WHITE, false, 140)

		# Religion cells
		for religion_id in founded:
			var is_state = (religion_id == current_player.state_religion)
			var bg = STATE_REL_TINT if is_state else CELL_COLOR

			if religion_id in city.religions:
				var rel_data = DataManager.get_religion(religion_id)
				var symbol = rel_data.get("symbol", "?")
				var rel_color = Color(rel_data.get("color", "#FFFFFF"))
				var text = symbol

				# Holy city marker
				if city.holy_city_of == religion_id:
					text += " ★"
					_add_grid_cell(text, bg, HOLY_CITY_COLOR, false, 100)
				else:
					_add_grid_cell(text, bg, rel_color, false, 100)
			else:
				_add_grid_cell("", bg, Color.WHITE, false, 100)

func _add_grid_cell(text: String, bg_color: Color, font_color: Color, is_header: bool, min_width: int) -> void:
	var cell = PanelContainer.new()
	cell.custom_minimum_size = Vector2(min_width, 32)
	var cell_style = StyleBoxFlat.new()
	cell_style.bg_color = bg_color
	cell_style.set_corner_radius_all(2)
	cell.add_theme_stylebox_override("panel", cell_style)

	var label = Label.new()
	label.text = text
	label.add_theme_color_override("font_color", font_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_header:
		label.add_theme_font_size_override("font_size", 13)
	else:
		label.add_theme_font_size_override("font_size", 15)
	cell.add_child(label)

	grid_container.add_child(cell)

func _build_state_religion_panel() -> void:
	# Update current religion label
	if current_player.state_religion != "":
		var rel_data = DataManager.get_religion(current_player.state_religion)
		var symbol = rel_data.get("symbol", "?")
		var rel_name = rel_data.get("name", current_player.state_religion)
		current_religion_label.text = "Current: %s %s" % [symbol, rel_name]
		current_religion_label.add_theme_color_override("font_color", Color(rel_data.get("color", "#FFFFFF")))
	else:
		current_religion_label.text = "Current: No State Religion"
		current_religion_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	# Clear and rebuild buttons
	for child in religion_buttons_container.get_children():
		child.queue_free()

	var available = ReligionSystem.get_available_state_religions(current_player)
	var has_free_religion = CivicsSystem.has_civic_effect(current_player, "no_state_religion")

	# "No State Religion" button
	var no_rel_btn = Button.new()
	no_rel_btn.text = "No State Religion"
	no_rel_btn.custom_minimum_size = Vector2(0, 35)
	var is_current_none = (current_player.state_religion == "")
	_style_religion_button(no_rel_btn, is_current_none)
	if is_current_none:
		no_rel_btn.disabled = true
	elif has_free_religion:
		no_rel_btn.disabled = true
	else:
		no_rel_btn.pressed.connect(_on_religion_selected.bind(""))
	religion_buttons_container.add_child(no_rel_btn)

	# Religion buttons
	for religion_id in available:
		if religion_id == "":
			continue  # Already handled above

		var rel_data = DataManager.get_religion(religion_id)
		var symbol = rel_data.get("symbol", "?")
		var rel_name = rel_data.get("name", religion_id)

		var btn = Button.new()
		btn.text = "%s %s" % [symbol, rel_name]
		btn.custom_minimum_size = Vector2(0, 35)
		var is_current = (religion_id == current_player.state_religion)
		_style_religion_button(btn, is_current)

		if is_current:
			btn.disabled = true
		elif has_free_religion:
			btn.disabled = true
		else:
			btn.pressed.connect(_on_religion_selected.bind(religion_id))

		religion_buttons_container.add_child(btn)

	# Anarchy warning
	if has_free_religion:
		anarchy_label.text = "Free Religion civic: cannot adopt a state religion."
		anarchy_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
	else:
		var anarchy_turns = CivicsSystem._calculate_anarchy_turns(current_player)
		if anarchy_turns > 0:
			anarchy_label.text = "Switching state religion causes %d turn(s) of anarchy!" % anarchy_turns
			anarchy_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		else:
			anarchy_label.text = "No anarchy (Spiritual trait)."
			anarchy_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))

func _style_religion_button(btn: Button, is_current: bool) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = SELECTED_BTN_COLOR if is_current else NORMAL_BTN_COLOR
	style.set_border_width_all(1)
	style.border_color = Color(0.4, 0.6, 0.4) if is_current else Color(0.3, 0.3, 0.4)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = style.bg_color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover_style)

func _on_religion_selected(religion_id: String) -> void:
	if current_player == null:
		return

	# Don't change to same religion
	if religion_id == current_player.state_religion:
		return

	# Block if Free Religion civic
	if CivicsSystem.has_civic_effect(current_player, "no_state_religion"):
		return

	# Calculate and apply anarchy
	var anarchy_turns = CivicsSystem._calculate_anarchy_turns(current_player)
	if anarchy_turns > 0 and current_player.anarchy_turns <= 0:
		CivicsSystem._start_anarchy(current_player, anarchy_turns)

	# Apply the change
	if religion_id == "":
		ReligionSystem.clear_state_religion(current_player)
		EventBus.notification_added.emit("You have adopted No State Religion.", "religion")
	else:
		ReligionSystem.adopt_state_religion(current_player, religion_id)
		var rel_data = DataManager.get_religion(religion_id)
		var rel_name = rel_data.get("name", religion_id)
		EventBus.notification_added.emit("You have adopted %s as your state religion." % rel_name, "religion")

	_refresh_all()

func _update_effects_panel() -> void:
	var text = ""

	# Current state religion summary
	if current_player.state_religion != "":
		var rel_data = DataManager.get_religion(current_player.state_religion)
		var rel_name = rel_data.get("name", current_player.state_religion)
		var symbol = rel_data.get("symbol", "?")
		var color_hex = rel_data.get("color", "#FFFFFF")

		text += "[b]State Religion:[/b] [color=%s]%s %s[/color]\n" % [color_hex, symbol, rel_name]

		# Count cities with state religion
		var cities_with = 0
		var total_cities = current_player.cities.size()
		for city in current_player.cities:
			if current_player.state_religion in city.religions:
				cities_with += 1
		text += "Cities with %s: %d / %d\n" % [rel_name, cities_with, total_cities]

		# Happiness from religion
		var total_happiness = 0
		for city in current_player.cities:
			total_happiness += ReligionSystem.get_religious_happiness(city)
		if total_happiness > 0:
			text += "Religious happiness: +%d (across all cities)\n" % total_happiness

		# Shrine income
		var holy_city = ReligionSystem.get_holy_city(current_player.state_religion)
		if holy_city and holy_city.player_owner == current_player:
			var shrine_gold = ReligionSystem.get_religious_gold(holy_city)
			if shrine_gold > 0:
				text += "Holy City shrine income: +%d gold/turn (%s)\n" % [shrine_gold, holy_city.city_name]
			else:
				text += "Holy City: %s (no shrine built yet)\n" % holy_city.city_name
		elif holy_city:
			text += "Holy City: %s (owned by %s)\n" % [holy_city.city_name, holy_city.player_owner.player_name if holy_city.player_owner else "Unknown"]
	else:
		text += "[b]State Religion:[/b] None\n"

	text += "\n"

	# World religion overview
	text += "[b]Founded Religions:[/b]\n"
	var founded = _get_founded_religions_sorted()
	if founded.is_empty():
		text += "  No religions founded yet.\n"
	else:
		for religion_id in founded:
			var rel_data = DataManager.get_religion(religion_id)
			var symbol = rel_data.get("symbol", "?")
			var rel_name = rel_data.get("name", religion_id)
			var color_hex = rel_data.get("color", "#FFFFFF")
			var founder = ReligionSystem.get_religion_founder(religion_id)
			var founder_name = founder.player_name if founder else "Unknown"
			var holy_city = ReligionSystem.get_holy_city(religion_id)
			var holy_city_name = holy_city.city_name if holy_city else "Unknown"

			# Count player cities with this religion
			var player_city_count = 0
			for city in current_player.cities:
				if religion_id in city.religions:
					player_city_count += 1

			text += "  [color=%s]%s %s[/color] — Founded by %s, Holy City: %s, In %d of your cities\n" % [
				color_hex, symbol, rel_name, founder_name, holy_city_name, player_city_count
			]

	effects_label.text = text

func _on_religion_event(_player, _religion, _holy_city) -> void:
	if visible:
		_refresh_all()

func _on_religion_spread_event(_religion, _city) -> void:
	if visible:
		_refresh_all()

func _on_state_religion_event(_player, _religion) -> void:
	if visible:
		_refresh_all()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
