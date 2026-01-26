extends Control
## Screen for viewing spaceship construction progress for Space Race victory.

# UI Elements
var panel: PanelContainer
var title_label: Label
var close_button: Button
var parts_list: ItemList
var detail_container: VBoxContainer
var info_panel: PanelContainer
var info_label: RichTextLabel
var launch_button: Button

# Ship visual container
var ship_container: HBoxContainer

# Part display data
const PART_INFO = {
	"cockpit": {"name": "SS Cockpit", "icon": "C", "color": Color.CYAN},
	"life_support": {"name": "SS Life Support", "icon": "L", "color": Color.GREEN},
	"stasis_chamber": {"name": "SS Stasis Chamber", "icon": "S", "color": Color.MEDIUM_PURPLE},
	"docking_bay": {"name": "SS Docking Bay", "icon": "D", "color": Color.ORANGE},
	"engine": {"name": "SS Engine", "icon": "E", "color": Color.RED},
	"casing": {"name": "SS Casing", "icon": "H", "color": Color.SILVER},
	"thrusters": {"name": "SS Thrusters", "icon": "T", "color": Color.YELLOW}
}

func _ready() -> void:
	_build_ui()
	visible = false

	# Connect signals
	EventBus.show_spaceship_screen.connect(_on_show)
	EventBus.hide_spaceship_screen.connect(_on_close)
	EventBus.project_completed.connect(_on_project_completed)

func _build_ui() -> void:
	# Main panel positioned just below top menu
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_right = -10
	panel.offset_top = 50  # Just below 40px top menu
	panel.offset_bottom = -10
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 1.0)
	style.border_color = Color(0.3, 0.3, 0.4)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(main_vbox)

	# Header
	var header = HBoxContainer.new()
	main_vbox.add_child(header)

	title_label = Label.new()
	title_label.text = "Spaceship Progress"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	close_button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close)
	header.add_child(close_button)

	# Main content split
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 15)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	# Left side - Parts list
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(250, 0)
	content_hbox.add_child(left_vbox)

	var list_header = Label.new()
	list_header.text = "Spaceship Parts"
	list_header.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(list_header)

	parts_list = ItemList.new()
	parts_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(parts_list)

	# Launch button under the list
	launch_button = Button.new()
	launch_button.text = "LAUNCH SPACESHIP"
	launch_button.custom_minimum_size = Vector2(200, 45)
	launch_button.add_theme_font_size_override("font_size", 14)
	launch_button.pressed.connect(_on_launch_pressed)
	launch_button.disabled = true
	left_vbox.add_child(launch_button)

	# Right side - Ship visual and details
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(right_vbox)

	var visual_header = Label.new()
	visual_header.text = "Assembly Status"
	visual_header.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(visual_header)

	# Ship visual
	var ship_visual_panel = PanelContainer.new()
	ship_visual_panel.custom_minimum_size = Vector2(0, 150)
	var visual_style = StyleBoxFlat.new()
	visual_style.bg_color = Color(0.08, 0.08, 0.1)
	visual_style.corner_radius_top_left = 4
	visual_style.corner_radius_top_right = 4
	visual_style.corner_radius_bottom_left = 4
	visual_style.corner_radius_bottom_right = 4
	ship_visual_panel.add_theme_stylebox_override("panel", visual_style)
	right_vbox.add_child(ship_visual_panel)

	var ship_center = CenterContainer.new()
	ship_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ship_visual_panel.add_child(ship_center)

	ship_container = HBoxContainer.new()
	ship_container.add_theme_constant_override("separation", 5)
	ship_center.add_child(ship_container)

	# Detail scroll
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)

	detail_container = VBoxContainer.new()
	detail_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_container.add_theme_constant_override("separation", 8)
	scroll.add_child(detail_container)

	# Info panel at bottom
	info_panel = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(0, 120)
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.1, 0.1, 0.12)
	info_style.corner_radius_top_left = 4
	info_style.corner_radius_top_right = 4
	info_style.corner_radius_bottom_left = 4
	info_style.corner_radius_bottom_right = 4
	info_style.content_margin_left = 10
	info_style.content_margin_right = 10
	info_style.content_margin_top = 10
	info_style.content_margin_bottom = 10
	info_panel.add_theme_stylebox_override("panel", info_style)
	main_vbox.add_child(info_panel)

	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_panel.add_child(info_label)

func _on_show() -> void:
	# Close other popup screens
	EventBus.hide_diplomacy_screen.emit()
	EventBus.hide_civics_screen.emit()
	EventBus.hide_trade_screen.emit()
	EventBus.hide_espionage_screen.emit()
	EventBus.hide_voting_screen.emit()
	EventBus.hide_city_screen.emit()
	EventBus.hide_tech_tree.emit()

	_refresh_display()
	visible = true

func _on_close() -> void:
	visible = false

func _on_project_completed(player_id: int, project_id: String, _city) -> void:
	if visible and GameManager and player_id == GameManager.human_player.player_id:
		if project_id.begins_with("ss_"):
			_refresh_display()

func _refresh_display() -> void:
	var player = GameManager.human_player if GameManager else null
	if player == null:
		return

	var status = ProjectsSystem.get_spaceship_status(player.player_id) if ProjectsSystem else {}

	# Refresh parts list
	_refresh_parts_list(status)

	# Build visual representation
	_build_ship_visual(status)

	# Update status text
	_update_status_text(status)

	# Update launch button
	launch_button.disabled = not status.get("ready", false)
	if status.get("ready", false):
		launch_button.text = "LAUNCH SPACESHIP"
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0.2, 0.5, 0.2)
		style_normal.corner_radius_top_left = 4
		style_normal.corner_radius_top_right = 4
		style_normal.corner_radius_bottom_left = 4
		style_normal.corner_radius_bottom_right = 4
		launch_button.add_theme_stylebox_override("normal", style_normal)
	else:
		launch_button.text = "NOT READY"

func _refresh_parts_list(status: Dictionary) -> void:
	parts_list.clear()

	for part_key in PART_INFO:
		var part_data = status.get(part_key, {"have": 0, "need": 1})
		var have = part_data.get("have", 0)
		var need = part_data.get("need", 1)
		var info = PART_INFO[part_key]

		var status_text = "%s: %d/%d" % [info.name, have, need]
		parts_list.add_item(status_text)

		if have >= need:
			parts_list.set_item_custom_fg_color(parts_list.item_count - 1, Color.GREEN)
		elif have > 0:
			parts_list.set_item_custom_fg_color(parts_list.item_count - 1, Color.YELLOW)
		else:
			parts_list.set_item_custom_fg_color(parts_list.item_count - 1, Color.RED)

func _build_ship_visual(status: Dictionary) -> void:
	# Clear existing
	for child in ship_container.get_children():
		child.queue_free()

	var part_order = ["thrusters", "engine", "casing", "life_support", "stasis_chamber", "docking_bay", "cockpit"]

	for part_key in part_order:
		var part_data = status.get(part_key, {"have": 0, "need": 1})
		var have = part_data.get("have", 0)
		var need = part_data.get("need", 1)
		var info = PART_INFO.get(part_key, {"name": part_key, "icon": "?", "color": Color.WHITE})

		var blocks_needed = need
		for i in range(blocks_needed):
			var block = PanelContainer.new()
			block.custom_minimum_size = Vector2(40, 60)

			var block_style = StyleBoxFlat.new()
			if i < have:
				block_style.bg_color = info.color
			else:
				block_style.bg_color = Color(0.2, 0.2, 0.2, 0.5)
				block_style.border_color = info.color
				block_style.border_width_top = 2
				block_style.border_width_bottom = 2
				block_style.border_width_left = 2
				block_style.border_width_right = 2

			block_style.corner_radius_top_left = 4
			block_style.corner_radius_top_right = 4
			block_style.corner_radius_bottom_left = 4
			block_style.corner_radius_bottom_right = 4
			block.add_theme_stylebox_override("panel", block_style)

			var label = Label.new()
			label.text = info.icon
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 20)
			if i >= have:
				label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			block.add_child(label)

			block.tooltip_text = "%s (%d/%d)" % [info.name, min(i + 1, have), need]

			ship_container.add_child(block)

func _update_status_text(status: Dictionary) -> void:
	var text = "[center][b]Spaceship Assembly Status[/b][/center]\n\n"

	var all_complete = true
	for part_key in PART_INFO:
		var part_data = status.get(part_key, {"have": 0, "need": 1})
		var have = part_data.get("have", 0)
		var need = part_data.get("need", 1)
		var info = PART_INFO[part_key]

		if have < need:
			all_complete = false

		var color = "green" if have >= need else ("yellow" if have > 0 else "red")
		var status_icon = "[OK]" if have >= need else "[MISSING]"

		text += "[color=%s]%s: %d/%d %s[/color]\n" % [color, info.name, have, need, status_icon]

	text += "\n"

	if status.get("ready", false):
		var travel_time = status.get("travel_time", -1)
		text += "[color=green][b]SPACESHIP READY FOR LAUNCH![/b][/color]\n"
		if travel_time > 0:
			text += "Estimated travel time: [b]%d turns[/b]\n" % travel_time

		var casing_have = status.get("casing", {}).get("have", 0)
		var success_chance = min(100, casing_have * 20)
		text += "Launch success chance: [b]%d%%[/b]" % success_chance
	else:
		text += "[color=yellow]Complete all required parts to launch.[/color]"

	info_label.text = text

func _on_launch_pressed() -> void:
	var player = GameManager.human_player if GameManager else null
	if player == null:
		return

	if not ProjectsSystem:
		return

	var success = ProjectsSystem.launch_spaceship(player.player_id)

	if success:
		EventBus.notification_added.emit("Spaceship launched successfully! Victory!", "victory")
		visible = false
	else:
		EventBus.notification_added.emit("Spaceship launch failed! Components damaged.", "warning")
		_refresh_display()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
