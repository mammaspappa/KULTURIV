extends Control
## Screen for managing espionage operations against other civilizations.

# UI Elements
var panel: PanelContainer
var title_label: Label
var close_button: Button
var targets_list: ItemList
var missions_container: VBoxContainer
var points_label: Label
var info_panel: PanelContainer
var info_label: RichTextLabel

# State
var selected_target_id: int = -1
var current_player_id: int = -1

func _ready() -> void:
	_build_ui()
	visible = false

	# Connect signals
	EventBus.show_espionage_screen.connect(_on_show)

func _build_ui() -> void:
	# Background overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main panel
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 600)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.15, 0.98)
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
	center.add_child(panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(main_vbox)

	# Header
	var header = HBoxContainer.new()
	main_vbox.add_child(header)

	title_label = Label.new()
	title_label.text = "Espionage"
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

	# Left side - Target list
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(250, 0)
	content_hbox.add_child(left_vbox)

	var targets_header = Label.new()
	targets_header.text = "Target Civilizations"
	targets_header.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(targets_header)

	targets_list = ItemList.new()
	targets_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	targets_list.item_selected.connect(_on_target_selected)
	left_vbox.add_child(targets_list)

	# Espionage points display
	points_label = Label.new()
	points_label.add_theme_font_size_override("font_size", 14)
	left_vbox.add_child(points_label)

	# Right side - Missions
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(right_vbox)

	var missions_header = Label.new()
	missions_header.text = "Available Missions"
	missions_header.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(missions_header)

	# Missions scroll
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)

	missions_container = VBoxContainer.new()
	missions_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	missions_container.add_theme_constant_override("separation", 8)
	scroll.add_child(missions_container)

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
	if GameManager and GameManager.human_player:
		current_player_id = GameManager.human_player.player_id
	_refresh_targets()
	visible = true

func _on_close() -> void:
	visible = false

func _refresh_targets() -> void:
	targets_list.clear()

	var player = GameManager.human_player if GameManager else null
	if player == null:
		return

	# List all met players
	for other_id in player.met_players:
		var other = GameManager.get_player(other_id) if GameManager else null
		if other:
			var civ_data = DataManager.get_civ(other.civilization_id)
			var civ_name = civ_data.get("name", "Unknown")
			var points = EspionageSystem.get_espionage_points(current_player_id, other_id) if EspionageSystem else 0
			targets_list.add_item("%s (%d EP)" % [civ_name, points])
			targets_list.set_item_metadata(targets_list.item_count - 1, other_id)

	# Update total points display
	var total_ep = 0
	if EspionageSystem:
		for other_id in player.met_players:
			total_ep += EspionageSystem.get_espionage_points(current_player_id, other_id)
	points_label.text = "Total Espionage Points: %d" % total_ep

func _on_target_selected(index: int) -> void:
	selected_target_id = targets_list.get_item_metadata(index)
	_refresh_missions()

func _refresh_missions() -> void:
	# Clear existing
	for child in missions_container.get_children():
		child.queue_free()

	if selected_target_id < 0:
		info_label.text = "Select a target civilization to see available missions."
		return

	var player = GameManager.human_player if GameManager else null
	var target = GameManager.get_player(selected_target_id) if GameManager else null

	if player == null or target == null:
		return

	var points = EspionageSystem.get_espionage_points(current_player_id, selected_target_id) if EspionageSystem else 0

	# Get all missions and show availability
	var missions = EspionageSystem.get_all_missions() if EspionageSystem else {}

	for mission_id in missions:
		var mission = missions[mission_id]
		var mission_panel = _create_mission_panel(mission_id, mission, player, target, points)
		missions_container.add_child(mission_panel)

	# Update info
	var civ_data = DataManager.get_civ(target.civilization_id)
	info_label.text = "[b]Target:[/b] %s\n[b]Espionage Points:[/b] %d\n[b]Relationship:[/b] %s" % [
		civ_data.get("name", "Unknown"),
		points,
		target.get_relationship(current_player_id).capitalize()
	]

func _create_mission_panel(mission_id: String, mission: Dictionary, player, target, points: int) -> PanelContainer:
	var panel_node = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel_node.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	panel_node.add_child(hbox)

	# Mission info
	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_label = Label.new()
	name_label.text = mission.get("name", mission_id)
	name_label.add_theme_font_size_override("font_size", 15)
	info_vbox.add_child(name_label)

	var desc_label = Label.new()
	desc_label.text = mission.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_vbox.add_child(desc_label)

	# Stats
	var stats_hbox = HBoxContainer.new()
	stats_hbox.add_theme_constant_override("separation", 20)
	info_vbox.add_child(stats_hbox)

	var cost = EspionageSystem.calculate_mission_cost(mission_id, player, target, null) if EspionageSystem else mission.get("base_cost", 100)
	var cost_label = Label.new()
	cost_label.text = "Cost: %d EP" % cost
	cost_label.add_theme_font_size_override("font_size", 12)
	cost_label.add_theme_color_override("font_color", Color.YELLOW if points >= cost else Color.RED)
	stats_hbox.add_child(cost_label)

	var success_label = Label.new()
	success_label.text = "Success: %d%%" % mission.get("success_chance_base", 50)
	success_label.add_theme_font_size_override("font_size", 12)
	success_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
	stats_hbox.add_child(success_label)

	var discovery_label = Label.new()
	discovery_label.text = "Discovery: %d%%" % mission.get("discovery_chance", 0)
	discovery_label.add_theme_font_size_override("font_size", 12)
	discovery_label.add_theme_color_override("font_color", Color.ORANGE if mission.get("discovery_chance", 0) > 30 else Color.LIGHT_GRAY)
	stats_hbox.add_child(discovery_label)

	# Requirements indicator
	if mission.get("requires_spy_in_city", false):
		var spy_label = Label.new()
		spy_label.text = "[Spy Required]"
		spy_label.add_theme_font_size_override("font_size", 11)
		spy_label.add_theme_color_override("font_color", Color.CORAL)
		stats_hbox.add_child(spy_label)

	# Execute button
	var exec_button = Button.new()
	exec_button.text = "Execute"
	exec_button.custom_minimum_size = Vector2(80, 35)

	# Check if can execute
	var can_execute = points >= cost
	if mission.get("requires_spy_in_city", false):
		can_execute = false  # Would need spy selection UI

	var tech_req = mission.get("tech_required", "")
	if tech_req != "" and player and not player.has_tech(tech_req):
		can_execute = false

	exec_button.disabled = not can_execute

	if can_execute:
		exec_button.pressed.connect(func(): _execute_mission(mission_id, player, target))

	hbox.add_child(exec_button)

	return panel_node

func _execute_mission(mission_id: String, player, target) -> void:
	if not EspionageSystem:
		return

	var result = EspionageSystem.execute_mission(mission_id, player, target, null)

	# Show result
	var msg = result.get("message", "Mission executed")
	if result.get("discovered", false):
		msg += " [Discovered!]"
	if result.get("spy_captured", false):
		msg += " [Spy captured!]"

	EventBus.notification_added.emit(msg, "espionage")

	# Refresh display
	_refresh_targets()
	_refresh_missions()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
