extends Control
## Screen for viewing spaceship construction progress for Space Race victory.

# UI Elements
var panel: PanelContainer
var title_label: Label
var close_button: Button
var parts_container: VBoxContainer
var status_label: RichTextLabel
var launch_button: Button

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
	EventBus.project_completed.connect(_on_project_completed)

func _build_ui() -> void:
	# Background overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.7)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main panel
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 500)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	style.border_color = Color(0.2, 0.3, 0.5)
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_width_left = 3
	style.border_width_right = 3
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	panel.add_child(main_vbox)

	# Header
	var header = HBoxContainer.new()
	main_vbox.add_child(header)

	title_label = Label.new()
	title_label.text = "Spaceship Progress"
	title_label.add_theme_font_size_override("font_size", 26)
	title_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	close_button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(35, 35)
	close_button.pressed.connect(_on_close)
	header.add_child(close_button)

	# Spaceship visual representation
	var ship_container = CenterContainer.new()
	ship_container.custom_minimum_size = Vector2(0, 150)
	main_vbox.add_child(ship_container)

	var ship_hbox = HBoxContainer.new()
	ship_hbox.add_theme_constant_override("separation", 5)
	ship_container.add_child(ship_hbox)

	# This will be updated dynamically
	parts_container = ship_hbox

	# Separator
	var sep = HSeparator.new()
	main_vbox.add_child(sep)

	# Parts detail list
	var parts_scroll = ScrollContainer.new()
	parts_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(parts_scroll)

	var parts_grid = GridContainer.new()
	parts_grid.columns = 2
	parts_grid.add_theme_constant_override("h_separation", 20)
	parts_grid.add_theme_constant_override("v_separation", 10)
	parts_scroll.add_child(parts_grid)

	# Will be populated by _refresh_display

	# Status panel
	status_label = RichTextLabel.new()
	status_label.bbcode_enabled = true
	status_label.fit_content = true
	status_label.custom_minimum_size = Vector2(0, 80)
	main_vbox.add_child(status_label)

	# Launch button
	launch_button = Button.new()
	launch_button.text = "LAUNCH SPACESHIP"
	launch_button.custom_minimum_size = Vector2(200, 50)
	launch_button.add_theme_font_size_override("font_size", 18)
	launch_button.pressed.connect(_on_launch_pressed)
	launch_button.disabled = true

	var button_center = CenterContainer.new()
	button_center.add_child(launch_button)
	main_vbox.add_child(button_center)

func _on_show() -> void:
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

	# Clear parts container
	for child in parts_container.get_children():
		child.queue_free()

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
		style_normal.corner_radius_top_left = 6
		style_normal.corner_radius_top_right = 6
		style_normal.corner_radius_bottom_left = 6
		style_normal.corner_radius_bottom_right = 6
		launch_button.add_theme_stylebox_override("normal", style_normal)
	else:
		launch_button.text = "NOT READY"

func _build_ship_visual(status: Dictionary) -> void:
	# Simple ASCII-style representation of spaceship parts
	var part_order = ["thrusters", "engine", "casing", "life_support", "stasis_chamber", "docking_bay", "cockpit"]

	for part_key in part_order:
		var part_data = status.get(part_key, {"have": 0, "need": 1})
		var have = part_data.get("have", 0)
		var need = part_data.get("need", 1)
		var info = PART_INFO.get(part_key, {"name": part_key, "icon": "?", "color": Color.WHITE})

		# Create visual blocks for each instance
		var blocks_needed = need
		for i in range(blocks_needed):
			var block = PanelContainer.new()
			block.custom_minimum_size = Vector2(40, 60)

			var style = StyleBoxFlat.new()
			if i < have:
				style.bg_color = info.color
			else:
				style.bg_color = Color(0.2, 0.2, 0.2, 0.5)
				style.border_color = info.color
				style.border_width_top = 2
				style.border_width_bottom = 2
				style.border_width_left = 2
				style.border_width_right = 2

			style.corner_radius_top_left = 4
			style.corner_radius_top_right = 4
			style.corner_radius_bottom_left = 4
			style.corner_radius_bottom_right = 4
			block.add_theme_stylebox_override("panel", style)

			var label = Label.new()
			label.text = info.icon
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			label.add_theme_font_size_override("font_size", 20)
			if i >= have:
				label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			block.add_child(label)

			block.tooltip_text = "%s (%d/%d)" % [info.name, min(i + 1, have), need]

			parts_container.add_child(block)

func _update_status_text(status: Dictionary) -> void:
	var text = "[center][b]Spaceship Assembly Status[/b][/center]\n\n"

	# List each part
	for part_key in PART_INFO:
		var part_data = status.get(part_key, {"have": 0, "need": 1})
		var have = part_data.get("have", 0)
		var need = part_data.get("need", 1)
		var min_need = part_data.get("min", need)
		var info = PART_INFO[part_key]

		var color = "green" if have >= need else ("yellow" if have >= min_need else "red")
		var status_icon = "[color=green]OK[/color]" if have >= need else ("[color=yellow]MIN[/color]" if have >= min_need else "[color=red]MISSING[/color]")

		text += "[color=%s]%s: %d/%d[/color] %s\n" % [color, info.name, have, need, status_icon]

	text += "\n"

	if status.get("ready", false):
		var travel_time = status.get("travel_time", -1)
		text += "[color=green][b]SPACESHIP READY FOR LAUNCH![/b][/color]\n"
		if travel_time > 0:
			text += "Estimated travel time: [b]%d turns[/b]\n" % travel_time

		# Calculate success chance
		var casing_have = status.get("casing", {}).get("have", 0)
		var success_chance = min(100, casing_have * 20)
		text += "Launch success chance: [b]%d%%[/b]" % success_chance
	else:
		text += "[color=yellow]Complete all required parts to launch.[/color]"

	status_label.text = text

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
