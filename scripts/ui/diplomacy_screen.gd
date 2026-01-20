class_name DiplomacyScreen
extends Control
## Diplomacy screen for managing relations with other civilizations.

# UI Elements
var player_list: VBoxContainer
var detail_panel: Panel
var selected_player = null

# Detail panel elements
var civ_name_label: Label
var leader_name_label: Label
var relation_label: Label
var attitude_label: Label

# Action buttons
var declare_war_btn: Button
var make_peace_btn: Button
var open_borders_btn: Button
var defensive_pact_btn: Button
var trade_btn: Button

func _ready() -> void:
	_setup_ui()

	# Connect signals
	EventBus.show_diplomacy_screen.connect(_on_show_diplomacy)
	EventBus.hide_diplomacy_screen.connect(_on_hide_diplomacy)
	EventBus.war_declared.connect(_on_war_declared)
	EventBus.peace_declared.connect(_on_peace_declared)
	EventBus.first_contact.connect(_on_first_contact)

	# Start hidden
	visible = false

func _setup_ui() -> void:
	# Main container
	anchor_left = 0.1
	anchor_right = 0.9
	anchor_top = 0.1
	anchor_bottom = 0.9

	# Background
	var bg = Panel.new()
	bg.name = "Background"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.4, 0.5)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	bg.add_theme_stylebox_override("panel", style)
	add_child(bg)

	# Title
	var title = Label.new()
	title.text = "Diplomacy"
	title.position = Vector2(20, 10)
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.position = Vector2(size.x - 50, 10)
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(_on_close_pressed)
	add_child(close_btn)

	# Split container - player list on left, details on right
	var split = HSplitContainer.new()
	split.position = Vector2(20, 50)
	split.size = Vector2(size.x - 40, size.y - 70)
	split.split_offset = 200
	add_child(split)

	# Player list panel
	var list_panel = Panel.new()
	list_panel.custom_minimum_size = Vector2(180, 0)
	split.add_child(list_panel)

	# Scroll container for player list
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.position = Vector2(5, 5)
	scroll.size = Vector2(170, list_panel.size.y - 10)
	list_panel.add_child(scroll)

	player_list = VBoxContainer.new()
	player_list.name = "PlayerList"
	scroll.add_child(player_list)

	# Detail panel
	detail_panel = Panel.new()
	detail_panel.custom_minimum_size = Vector2(400, 0)
	split.add_child(detail_panel)

	_setup_detail_panel()

func _setup_detail_panel() -> void:
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.position = Vector2(20, 20)
	vbox.add_theme_constant_override("separation", 10)
	detail_panel.add_child(vbox)

	# Civ name
	civ_name_label = Label.new()
	civ_name_label.text = "Select a civilization"
	civ_name_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(civ_name_label)

	# Leader name
	leader_name_label = Label.new()
	leader_name_label.text = ""
	leader_name_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(leader_name_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	# Relation status
	relation_label = Label.new()
	relation_label.text = ""
	vbox.add_child(relation_label)

	# Attitude
	attitude_label = Label.new()
	attitude_label.text = ""
	vbox.add_child(attitude_label)

	# Attitude breakdown (detailed)
	var breakdown_label = Label.new()
	breakdown_label.name = "BreakdownLabel"
	breakdown_label.add_theme_font_size_override("font_size", 12)
	breakdown_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	vbox.add_child(breakdown_label)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)

	# Action buttons
	var btn_container = HBoxContainer.new()
	btn_container.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_container)

	declare_war_btn = Button.new()
	declare_war_btn.text = "Declare War"
	declare_war_btn.custom_minimum_size = Vector2(100, 30)
	declare_war_btn.pressed.connect(_on_declare_war_pressed)
	btn_container.add_child(declare_war_btn)

	make_peace_btn = Button.new()
	make_peace_btn.text = "Make Peace"
	make_peace_btn.custom_minimum_size = Vector2(100, 30)
	make_peace_btn.pressed.connect(_on_make_peace_pressed)
	btn_container.add_child(make_peace_btn)

	# Second row
	var btn_container2 = HBoxContainer.new()
	btn_container2.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_container2)

	open_borders_btn = Button.new()
	open_borders_btn.text = "Open Borders"
	open_borders_btn.custom_minimum_size = Vector2(100, 30)
	open_borders_btn.pressed.connect(_on_open_borders_pressed)
	btn_container2.add_child(open_borders_btn)

	defensive_pact_btn = Button.new()
	defensive_pact_btn.text = "Defensive Pact"
	defensive_pact_btn.custom_minimum_size = Vector2(120, 30)
	defensive_pact_btn.pressed.connect(_on_defensive_pact_pressed)
	btn_container2.add_child(defensive_pact_btn)

	# Third row - trade
	var btn_container3 = HBoxContainer.new()
	btn_container3.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_container3)

	trade_btn = Button.new()
	trade_btn.text = "Propose Trade"
	trade_btn.custom_minimum_size = Vector2(100, 30)
	trade_btn.pressed.connect(_on_trade_pressed)
	btn_container3.add_child(trade_btn)

	# Hide buttons initially
	_hide_action_buttons()

func _hide_action_buttons() -> void:
	declare_war_btn.visible = false
	make_peace_btn.visible = false
	open_borders_btn.visible = false
	defensive_pact_btn.visible = false
	trade_btn.visible = false

func _on_show_diplomacy(player = null) -> void:
	_refresh_player_list()
	if player:
		_select_player(player)
	visible = true

func _on_hide_diplomacy() -> void:
	visible = false

func _on_close_pressed() -> void:
	EventBus.hide_diplomacy_screen.emit()

func _refresh_player_list() -> void:
	# Clear existing
	for child in player_list.get_children():
		child.queue_free()

	# Add met players
	var human = GameManager.human_player
	if human == null:
		return

	for player in GameManager.players:
		if player == human:
			continue

		# Only show met civilizations
		if player.player_id not in human.met_players:
			continue

		var btn = Button.new()
		var civ_data = DataManager.get_civ(player.civilization_id)
		btn.text = civ_data.get("name", player.civilization_id)
		btn.custom_minimum_size = Vector2(170, 35)
		btn.pressed.connect(_on_player_button_pressed.bind(player))

		# Color based on relationship
		if GameManager.is_at_war(human, player):
			btn.add_theme_color_override("font_color", Color.RED)
		elif player.player_id in human.defensive_pact_with:
			btn.add_theme_color_override("font_color", Color.GREEN)

		player_list.add_child(btn)

func _on_player_button_pressed(player) -> void:
	_select_player(player)

func _select_player(player) -> void:
	selected_player = player
	_update_detail_panel()

func _update_detail_panel() -> void:
	if selected_player == null:
		civ_name_label.text = "Select a civilization"
		leader_name_label.text = ""
		relation_label.text = ""
		attitude_label.text = ""
		_hide_action_buttons()
		return

	var human = GameManager.human_player

	# Civ and leader names
	var civ_data = DataManager.get_civ(selected_player.civilization_id)
	var leader_data = DataManager.get_leader(selected_player.leader_id)

	civ_name_label.text = civ_data.get("name", selected_player.civilization_id)
	leader_name_label.text = "Leader: " + leader_data.get("name", selected_player.leader_id)

	# Relationship status
	var relation_text = ""
	var relation_color = Color.WHITE

	if GameManager.is_at_war(human, selected_player):
		relation_text = "At War"
		relation_color = Color.RED
	elif selected_player.player_id in human.defensive_pact_with:
		relation_text = "Defensive Pact"
		relation_color = Color.GREEN
	elif selected_player.player_id in human.open_borders_with:
		relation_text = "Open Borders"
		relation_color = Color.CYAN
	else:
		relation_text = "Neutral"
		relation_color = Color.YELLOW

	relation_label.text = "Status: " + relation_text
	relation_label.add_theme_color_override("font_color", relation_color)

	# Attitude
	var attitude = _calculate_attitude(selected_player)
	attitude_label.text = "Attitude: " + attitude

	# Color based on attitude
	var attitude_color = Color.WHITE
	match attitude:
		"Friendly":
			attitude_color = Color.GREEN
		"Pleased":
			attitude_color = Color.LIGHT_GREEN
		"Cautious":
			attitude_color = Color.YELLOW
		"Annoyed":
			attitude_color = Color.ORANGE
		"Furious":
			attitude_color = Color.RED
	attitude_label.add_theme_color_override("font_color", attitude_color)

	# Attitude breakdown
	var breakdown_label = detail_panel.get_node_or_null("VBoxContainer/BreakdownLabel")
	if breakdown_label == null:
		# Find it in the children
		for child in detail_panel.get_children():
			if child is VBoxContainer:
				breakdown_label = child.get_node_or_null("BreakdownLabel")
				break

	if breakdown_label:
		var breakdown = DiplomacySystem.get_attitude_breakdown(selected_player, human)
		var breakdown_text = ""
		for item in breakdown:
			var sign = "+" if item["value"] > 0 else ""
			breakdown_text += "  %s%d: %s\n" % [sign, item["value"], item["reason"]]
		breakdown_label.text = breakdown_text

	# Show appropriate buttons
	_update_action_buttons()

func _calculate_attitude(player) -> String:
	return DiplomacySystem.get_attitude_string(player, GameManager.human_player)

func _update_action_buttons() -> void:
	if selected_player == null:
		_hide_action_buttons()
		return

	var human = GameManager.human_player
	var at_war = GameManager.is_at_war(human, selected_player)

	# War/Peace buttons
	declare_war_btn.visible = not at_war
	make_peace_btn.visible = at_war

	# Treaties (only available if not at war)
	open_borders_btn.visible = not at_war
	defensive_pact_btn.visible = not at_war
	trade_btn.visible = not at_war

	# Update button states
	var has_open_borders = selected_player.player_id in human.open_borders_with
	var has_pact = selected_player.player_id in human.defensive_pact_with

	open_borders_btn.text = "Cancel Open Borders" if has_open_borders else "Open Borders"
	defensive_pact_btn.text = "Cancel Pact" if has_pact else "Defensive Pact"

func _on_declare_war_pressed() -> void:
	if selected_player == null:
		return

	GameManager.declare_war(GameManager.human_player, selected_player)
	_update_detail_panel()
	_refresh_player_list()

func _on_make_peace_pressed() -> void:
	if selected_player == null:
		return

	GameManager.make_peace(GameManager.human_player, selected_player)
	_update_detail_panel()
	_refresh_player_list()

func _on_open_borders_pressed() -> void:
	if selected_player == null:
		return

	var human = GameManager.human_player

	if selected_player.player_id in human.open_borders_with:
		# Cancel open borders
		human.open_borders_with.erase(selected_player.player_id)
		selected_player.open_borders_with.erase(human.player_id)
	else:
		# Sign open borders
		human.open_borders_with.append(selected_player.player_id)
		selected_player.open_borders_with.append(human.player_id)
		EventBus.open_borders_signed.emit(human, selected_player)

	_update_detail_panel()

func _on_defensive_pact_pressed() -> void:
	if selected_player == null:
		return

	var human = GameManager.human_player

	if selected_player.player_id in human.defensive_pact_with:
		# Cancel pact
		human.defensive_pact_with.erase(selected_player.player_id)
		selected_player.defensive_pact_with.erase(human.player_id)
	else:
		# Sign pact
		human.defensive_pact_with.append(selected_player.player_id)
		selected_player.defensive_pact_with.append(human.player_id)
		EventBus.defensive_pact_signed.emit(human, selected_player)

	_update_detail_panel()

func _on_trade_pressed() -> void:
	if selected_player == null:
		return

	# Open trade screen
	EventBus.show_trade_screen.emit(GameManager.human_player, selected_player)

func _on_war_declared(_aggressor, _target) -> void:
	if visible:
		_refresh_player_list()
		_update_detail_panel()

func _on_peace_declared(_player1, _player2) -> void:
	if visible:
		_refresh_player_list()
		_update_detail_panel()

func _on_first_contact(player1, player2) -> void:
	# Add to met players list
	if player1.player_id not in player2.met_players:
		player2.met_players.append(player1.player_id)
	if player2.player_id not in player1.met_players:
		player1.met_players.append(player2.player_id)

	if visible:
		_refresh_player_list()
