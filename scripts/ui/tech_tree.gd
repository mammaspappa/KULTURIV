class_name TechTree
extends Control
## Technology tree screen showing all techs and research options.

const TECH_NODE_SIZE = Vector2(140, 70)
const TECH_SPACING_X = 180
const TECH_SPACING_Y = 90

var tech_nodes: Dictionary = {}  # tech_id -> Control
var current_player = null  # Player (untyped to avoid load-order issues)

# UI elements
var panel: Panel
var scroll_container: ScrollContainer
var tech_container: Control
var info_panel: Panel
var info_label: Label
var close_button: Button
var current_research_label: Label

# Colors
const BG_COLOR = Color(0.08, 0.08, 0.12, 0.95)
const RESEARCHED_COLOR = Color(0.2, 0.6, 0.2)
const AVAILABLE_COLOR = Color(0.3, 0.3, 0.5)
const UNAVAILABLE_COLOR = Color(0.2, 0.2, 0.2)
const CURRENT_COLOR = Color(0.6, 0.6, 0.2)

# Era order
const ERA_ORDER = ["ancient", "classical", "medieval", "renaissance", "industrial", "modern", "future"]

func _ready() -> void:
	_create_ui()
	EventBus.show_tech_tree.connect(_on_show_tech_tree)
	EventBus.hide_tech_tree.connect(_on_close_pressed)
	hide()

func _create_ui() -> void:
	# Main panel
	panel = Panel.new()
	panel.name = "Panel"
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.5)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.02
	panel.anchor_right = 0.98
	panel.anchor_top = 0.02
	panel.anchor_bottom = 0.98
	add_child(panel)

	# Header with current research
	current_research_label = Label.new()
	current_research_label.name = "CurrentResearch"
	current_research_label.position = Vector2(20, 10)
	current_research_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(current_research_label)

	# Close button
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close_pressed)
	panel.add_child(close_button)

	# Scroll container for tech tree
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.position = Vector2(10, 50)
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll_container)

	tech_container = Control.new()
	tech_container.name = "TechContainer"
	scroll_container.add_child(tech_container)

	# Info panel (bottom)
	info_panel = Panel.new()
	info_panel.name = "InfoPanel"
	info_panel.custom_minimum_size = Vector2(300, 100)
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.15, 0.15, 0.2)
	info_panel.add_theme_stylebox_override("panel", info_style)
	panel.add_child(info_panel)

	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.position = Vector2(10, 10)
	info_label.add_theme_font_size_override("font_size", 12)
	info_panel.add_child(info_label)

func _on_show_tech_tree() -> void:
	current_player = GameManager.human_player
	_build_tech_tree()
	_update_layout()
	show()

func _update_layout() -> void:
	# Update positions based on panel size
	var panel_size = panel.size
	close_button.position = Vector2(panel_size.x - 50, 10)
	scroll_container.size = Vector2(panel_size.x - 20, panel_size.y - 170)
	info_panel.position = Vector2(10, panel_size.y - 110)
	info_panel.size = Vector2(panel_size.x - 20, 100)

func _build_tech_tree() -> void:
	# Clear existing nodes
	for node in tech_nodes.values():
		node.queue_free()
	tech_nodes.clear()

	# Update current research display
	_update_current_research()

	# Group techs by era
	var eras: Dictionary = {}
	for tech_id in DataManager.techs:
		var tech = DataManager.get_tech(tech_id)
		var era = tech.get("era", "ancient")
		if not eras.has(era):
			eras[era] = []
		eras[era].append(tech_id)

	# Position techs by era
	var x_pos = 20
	var max_y = 0

	for era in ERA_ORDER:
		if not eras.has(era):
			continue

		var y_pos = 20

		# Era label
		var era_label = Label.new()
		era_label.text = era.capitalize()
		era_label.position = Vector2(x_pos, y_pos - 20)
		era_label.add_theme_font_size_override("font_size", 16)
		era_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		tech_container.add_child(era_label)

		for tech_id in eras[era]:
			var node = _create_tech_node(tech_id)
			node.position = Vector2(x_pos, y_pos)
			tech_nodes[tech_id] = node
			tech_container.add_child(node)
			y_pos += TECH_SPACING_Y
			max_y = max(max_y, y_pos)

		x_pos += TECH_SPACING_X

	# Set container size
	tech_container.custom_minimum_size = Vector2(x_pos, max_y + 50)

	# Draw connections after positioning
	_draw_connections()

func _create_tech_node(tech_id: String) -> Control:
	var tech = DataManager.get_tech(tech_id)
	var node = Panel.new()
	node.name = tech_id
	node.custom_minimum_size = TECH_NODE_SIZE

	# Determine state and color
	var state = _get_tech_state(tech_id)
	var color: Color
	match state:
		"researched":
			color = RESEARCHED_COLOR
		"current":
			color = CURRENT_COLOR
		"available":
			color = AVAILABLE_COLOR
		_:
			color = UNAVAILABLE_COLOR

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = color.lightened(0.3)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	node.add_theme_stylebox_override("panel", style)

	# Tech name label
	var name_label = Label.new()
	name_label.text = tech.get("name", tech_id)
	name_label.position = Vector2(5, 5)
	name_label.size = Vector2(TECH_NODE_SIZE.x - 10, 20)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.clip_text = true
	node.add_child(name_label)

	# Cost label
	var cost_label = Label.new()
	var cost = int(DataManager.get_tech_cost(tech_id) * GameManager.get_speed_multiplier())
	cost_label.text = "%d beakers" % cost
	cost_label.position = Vector2(5, 25)
	cost_label.add_theme_font_size_override("font_size", 10)
	cost_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	node.add_child(cost_label)

	# If available and not researched, make clickable
	if state == "available":
		var button = Button.new()
		button.custom_minimum_size = TECH_NODE_SIZE
		button.size = TECH_NODE_SIZE
		button.flat = true
		button.pressed.connect(_on_tech_selected.bind(tech_id))
		button.mouse_entered.connect(_on_tech_hovered.bind(tech_id))
		node.add_child(button)
	else:
		# Still allow hover for info
		var button = Button.new()
		button.custom_minimum_size = TECH_NODE_SIZE
		button.size = TECH_NODE_SIZE
		button.flat = true
		button.disabled = state != "available"
		button.mouse_entered.connect(_on_tech_hovered.bind(tech_id))
		node.add_child(button)

	return node

func _get_tech_state(tech_id: String) -> String:
	if current_player == null:
		return "unavailable"

	if current_player.has_tech(tech_id):
		return "researched"

	if current_player.current_research == tech_id:
		return "current"

	if DataManager.is_tech_available(tech_id, current_player.researched_techs):
		return "available"

	return "unavailable"

func _draw_connections() -> void:
	# Create a custom draw node for lines
	var line_container = Node2D.new()
	line_container.name = "LineContainer"
	line_container.z_index = -1
	tech_container.add_child(line_container)
	line_container.set_script(load("res://scripts/ui/tech_lines.gd") if ResourceLoader.exists("res://scripts/ui/tech_lines.gd") else null)

	# Store line data for drawing
	var lines = []
	for tech_id in tech_nodes:
		var prereqs = DataManager.get_tech_prerequisites(tech_id)
		var to_node = tech_nodes[tech_id]
		var to_pos = to_node.position + Vector2(0, TECH_NODE_SIZE.y / 2)

		for prereq in prereqs:
			if prereq in tech_nodes:
				var from_node = tech_nodes[prereq]
				var from_pos = from_node.position + Vector2(TECH_NODE_SIZE.x, TECH_NODE_SIZE.y / 2)
				lines.append({"from": from_pos, "to": to_pos})

	# Draw lines manually
	for line_data in lines:
		var line = Line2D.new()
		line.add_point(line_data.from)
		line.add_point(line_data.to)
		line.default_color = Color(0.5, 0.5, 0.6)
		line.width = 2.0
		line_container.add_child(line)

func _update_current_research() -> void:
	if current_player == null:
		current_research_label.text = "No Research"
		return

	if current_player.current_research == "":
		current_research_label.text = "Select a technology to research"
		return

	var tech = DataManager.get_tech(current_player.current_research)
	var cost = int(DataManager.get_tech_cost(current_player.current_research) * GameManager.get_speed_multiplier())
	var progress = current_player.research_progress
	var output = current_player.get_research_output()
	var turns_left = ceili((cost - progress) / max(output, 1))

	current_research_label.text = "Researching: %s (%d/%d, %d turns)" % [
		tech.get("name", current_player.current_research),
		progress,
		cost,
		turns_left
	]

func _on_tech_selected(tech_id: String) -> void:
	if current_player == null:
		return

	current_player.start_research(tech_id)
	_build_tech_tree()

func _on_tech_hovered(tech_id: String) -> void:
	var tech = DataManager.get_tech(tech_id)
	var text = "%s\n" % tech.get("name", tech_id)
	text += tech.get("description", "No description available.") + "\n\n"

	# Show unlocks
	var unlocks = tech.get("unlocks", {})
	if not unlocks.is_empty():
		text += "Unlocks:\n"
		if unlocks.has("units"):
			for unit_id in unlocks.units:
				var unit = DataManager.get_unit(unit_id)
				text += "  - Unit: %s\n" % unit.get("name", unit_id)
		if unlocks.has("buildings"):
			for building_id in unlocks.buildings:
				var building = DataManager.get_building(building_id)
				text += "  - Building: %s\n" % building.get("name", building_id)
		if unlocks.has("improvements"):
			for imp_id in unlocks.improvements:
				text += "  - Improvement: %s\n" % imp_id.capitalize()

	# Show prerequisites
	var prereqs = DataManager.get_tech_prerequisites(tech_id)
	if not prereqs.is_empty():
		text += "\nRequires: "
		var prereq_names = []
		for prereq in prereqs:
			var prereq_tech = DataManager.get_tech(prereq)
			prereq_names.append(prereq_tech.get("name", prereq))
		text += ", ".join(prereq_names)

	info_label.text = text

func _on_close_pressed() -> void:
	hide()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_T:
			_on_close_pressed()
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		if visible:
			_update_layout()
