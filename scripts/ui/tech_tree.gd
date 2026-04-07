class_name TechTree
extends Control
## Technology tree screen showing all techs and research options.

# BTS-style grid layout: 20 columns x 14 rows
const TECH_NODE_SIZE = Vector2(180, 50)
const CELL_WIDTH = 220   # Horizontal spacing between grid columns
const CELL_HEIGHT = 54   # Vertical spacing between grid rows

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
const BG_COLOR = Color(0.08, 0.08, 0.12, 1.0)
# BTS-authentic colors
const RESEARCHED_COLOR = Color(0.33, 0.59, 0.34)   # #559957 muted green
const CURRENT_COLOR = Color(0.41, 0.62, 0.65)       # #689ea5 teal
const AVAILABLE_COLOR = Color(0.39, 0.41, 0.63)     # #6468a0 slate blue
const UNAVAILABLE_COLOR = Color(0.27, 0.27, 0.27)   # #444444 dark gray

# Era order

func _ready() -> void:
	# Allow clicks to pass through to top menu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_ui()
	EventBus.show_tech_tree.connect(_on_show_tech_tree)
	EventBus.hide_tech_tree.connect(_on_close_pressed)
	EventBus.close_all_popups.connect(_on_close_pressed)
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
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_right = -10
	panel.offset_top = 50  # Below the 40px top menu
	panel.offset_bottom = -10
	add_child(panel)

	# Header with current research
	current_research_label = Label.new()
	current_research_label.name = "CurrentResearch"
	current_research_label.anchor_left = 0.0
	current_research_label.anchor_right = 0.9  # Leave room for close button
	current_research_label.anchor_top = 0.0
	current_research_label.anchor_bottom = 0.0
	current_research_label.offset_left = 20
	current_research_label.offset_top = 10
	current_research_label.offset_bottom = 45
	current_research_label.add_theme_font_size_override("font_size", 18)
	panel.add_child(current_research_label)

	# Close button (top right)
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.anchor_left = 1.0
	close_button.anchor_right = 1.0
	close_button.anchor_top = 0.0
	close_button.anchor_bottom = 0.0
	close_button.offset_left = -40
	close_button.offset_right = -10
	close_button.offset_top = 10
	close_button.offset_bottom = 40
	close_button.pressed.connect(_on_close_pressed)
	panel.add_child(close_button)

	# Scroll container for tech tree
	scroll_container = ScrollContainer.new()
	scroll_container.name = "ScrollContainer"
	scroll_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll_container.offset_left = 10
	scroll_container.offset_top = 50
	scroll_container.offset_right = -10
	scroll_container.offset_bottom = -120  # Leave room for info panel
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll_container)

	tech_container = Control.new()
	tech_container.name = "TechContainer"
	scroll_container.add_child(tech_container)

	# Info panel (bottom)
	info_panel = Panel.new()
	info_panel.name = "InfoPanel"
	info_panel.anchor_left = 0.0
	info_panel.anchor_right = 1.0
	info_panel.anchor_top = 1.0
	info_panel.anchor_bottom = 1.0
	info_panel.offset_left = 10
	info_panel.offset_right = -10
	info_panel.offset_top = -110
	info_panel.offset_bottom = -10
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
	# Close all other popups first
	EventBus.close_all_popups.emit()
	current_player = GameManager.human_player
	_build_tech_tree()
	show()
	# Update layout after showing so panel.size is computed
	call_deferred("_update_layout")

func _update_layout() -> void:
	# Layout is now handled by anchors, but keep for compatibility
	pass

func _build_tech_tree() -> void:
	# Clear existing nodes
	for child in tech_container.get_children():
		child.queue_free()
	tech_nodes.clear()

	# Update current research display
	_update_current_research()

	# Position techs using BTS grid coordinates (gridX, gridY)
	var max_x = 0
	var max_y = 0

	for tech_id in DataManager.techs:
		if tech_id.begins_with("_"):
			continue
		var tech = DataManager.get_tech(tech_id)
		var grid_x = tech.get("grid_x", tech.get("gridX", 1))
		var grid_y = tech.get("grid_y", tech.get("gridY", 1))

		var node = _create_tech_node(tech_id)
		var px = (grid_x - 1) * CELL_WIDTH + 20
		var py = (grid_y - 1) * CELL_HEIGHT + 10
		node.position = Vector2(px, py)
		tech_nodes[tech_id] = node
		tech_container.add_child(node)

		max_x = max(max_x, px + TECH_NODE_SIZE.x)
		max_y = max(max_y, py + TECH_NODE_SIZE.y)

	# Set container size for scrolling
	tech_container.custom_minimum_size = Vector2(max_x + 40, max_y + 40)

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

	# Tech name + cost on one line (compact)
	var cost = int(DataManager.get_tech_cost(tech_id) * GameManager.get_speed_multiplier())
	var name_label = Label.new()
	name_label.text = "%s (%d)" % [tech.get("name", tech_id), cost]
	name_label.position = Vector2(4, 2)
	name_label.size = Vector2(TECH_NODE_SIZE.x - 8, 18)
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.clip_text = true
	node.add_child(name_label)

	# Unlock badges row (bottom half of card)
	var unlocks = DataManager.get_tech_unlocks(tech_id)
	var badge_hbox = HBoxContainer.new()
	badge_hbox.position = Vector2(4, 22)
	badge_hbox.add_theme_constant_override("separation", 2)
	node.add_child(badge_hbox)

	var unlock_units = unlocks.get("units", [])
	var unlock_buildings = unlocks.get("buildings", [])
	var unlock_improvements = unlocks.get("improvements", [])

	for i in range(mini(unlock_units.size(), 3)):
		badge_hbox.add_child(_create_badge("U", Color(0.85, 0.2, 0.2)))
	for i in range(mini(unlock_buildings.size(), 3)):
		badge_hbox.add_child(_create_badge("B", Color(0.2, 0.35, 0.85)))
	for i in range(mini(unlock_improvements.size(), 2)):
		badge_hbox.add_child(_create_badge("I", Color(0.2, 0.7, 0.25)))

	# Progress bar for currently-researching tech
	if state == "current" and current_player != null:
		var progress_bar = ProgressBar.new()
		progress_bar.position = Vector2(2, TECH_NODE_SIZE.y - 8)
		progress_bar.custom_minimum_size = Vector2(TECH_NODE_SIZE.x - 4, 6)
		progress_bar.size = Vector2(TECH_NODE_SIZE.x - 4, 6)
		progress_bar.max_value = cost
		progress_bar.value = current_player.research_progress
		progress_bar.show_percentage = false
		var bar_bg = StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.15, 0.15, 0.15)
		bar_bg.set_corner_radius_all(2)
		progress_bar.add_theme_stylebox_override("background", bar_bg)
		var bar_fill = StyleBoxFlat.new()
		bar_fill.bg_color = Color(0.3, 0.8, 0.3)
		bar_fill.set_corner_radius_all(2)
		progress_bar.add_theme_stylebox_override("fill", bar_fill)
		node.add_child(progress_bar)

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

func _create_badge(letter: String, bg_color: Color) -> Label:
	var badge = Label.new()
	badge.text = letter
	badge.custom_minimum_size = Vector2(16, 16)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", Color.WHITE)
	var badge_style = StyleBoxFlat.new()
	badge_style.bg_color = bg_color
	badge_style.corner_radius_top_left = 3
	badge_style.corner_radius_top_right = 3
	badge_style.corner_radius_bottom_left = 3
	badge_style.corner_radius_bottom_right = 3
	badge_style.content_margin_left = 2
	badge_style.content_margin_right = 2
	badge.add_theme_stylebox_override("normal", badge_style)
	return badge

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
	# Create a container for connection lines (behind tech nodes)
	var line_container = Node2D.new()
	line_container.name = "LineContainer"
	line_container.z_index = -1
	tech_container.add_child(line_container)

	var researched_techs = []
	if current_player != null:
		researched_techs = current_player.researched_techs

	for tech_id in tech_nodes:
		var tech = DataManager.get_tech(tech_id)
		var and_prereqs = tech.get("prerequisites", [])
		var or_prereqs = tech.get("or_prerequisites", [])
		var all_prereqs = and_prereqs + or_prereqs
		var to_node = tech_nodes[tech_id]
		var to_pos = to_node.position + Vector2(0, TECH_NODE_SIZE.y / 2)  # Left-middle of target

		for prereq in all_prereqs:
			if prereq not in tech_nodes:
				continue
			var from_node = tech_nodes[prereq]
			var from_pos = from_node.position + Vector2(TECH_NODE_SIZE.x, TECH_NODE_SIZE.y / 2)  # Right-middle of source

			# Determine line color
			var prereq_researched = prereq in researched_techs
			var tech_researched = tech_id in researched_techs
			var line_color: Color
			if prereq_researched and tech_researched:
				line_color = Color(0.2, 0.75, 0.2)   # Green
			elif prereq_researched:
				line_color = Color(0.85, 0.85, 0.2)  # Yellow
			else:
				line_color = Color(0.5, 0.5, 0.6)    # Gray

			# L-shaped routing: right from source → bend → left into target
			var line = Line2D.new()
			line.width = 2.0
			line.default_color = line_color

			if abs(from_pos.y - to_pos.y) < 4:
				# Same row — straight horizontal line
				line.add_point(from_pos)
				line.add_point(to_pos)
			else:
				# Different rows — L-bend at horizontal midpoint
				var mid_x = (from_pos.x + to_pos.x) / 2
				line.add_point(from_pos)
				line.add_point(Vector2(mid_x, from_pos.y))
				line.add_point(Vector2(mid_x, to_pos.y))
				line.add_point(to_pos)

			line_container.add_child(line)

			# Arrowhead at destination
			var arrow_size = 6.0
			var arrow = Polygon2D.new()
			arrow.polygon = PackedVector2Array([
				to_pos,
				to_pos + Vector2(-arrow_size, -arrow_size / 2),
				to_pos + Vector2(-arrow_size, arrow_size / 2)
			])
			arrow.color = line_color
			line_container.add_child(arrow)

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
	var and_prereqs = tech.get("prerequisites", [])
	var or_prereqs = tech.get("or_prerequisites", [])
	if not and_prereqs.is_empty():
		text += "\nRequires ALL: "
		var names = []
		for prereq in and_prereqs:
			var pt = DataManager.get_tech(prereq)
			names.append(pt.get("name", prereq))
		text += ", ".join(names)
	if not or_prereqs.is_empty():
		text += "\nRequires ANY: "
		var names = []
		for prereq in or_prereqs:
			var pt = DataManager.get_tech(prereq)
			names.append(pt.get("name", prereq))
		text += " or ".join(names)

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
