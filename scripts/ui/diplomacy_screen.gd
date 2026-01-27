class_name DiplomacyScreen
extends Control
## Diplomacy screen for managing relations with other civilizations.

# UI Elements
var panel: PanelContainer
var title_label: Label
var close_button: Button
var player_list: ItemList
var detail_container: VBoxContainer
var info_panel: PanelContainer
var info_label: RichTextLabel

# Detail panel elements
var civ_name_label: Label
var leader_name_label: Label
var relation_label: Label
var attitude_label: Label
var breakdown_label: Label

# Action buttons
var declare_war_btn: Button
var make_peace_btn: Button
var open_borders_btn: Button
var defensive_pact_btn: Button
var trade_btn: Button

# State
var selected_player = null

func _ready() -> void:
	# Ensure this Control fills the screen so child anchors work
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Allow clicks to pass through to top menu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false

	# Connect signals
	EventBus.show_diplomacy_screen.connect(_on_show_diplomacy)
	EventBus.hide_diplomacy_screen.connect(_on_hide_diplomacy)
	EventBus.close_all_popups.connect(_on_hide_diplomacy)
	EventBus.war_declared.connect(_on_war_declared)
	EventBus.peace_declared.connect(_on_peace_declared)
	EventBus.first_contact.connect(_on_first_contact)

func _build_ui() -> void:
	# Main panel - anchored below top menu like other screens
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
	title_label.text = "Diplomacy"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	close_button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close_pressed)
	header.add_child(close_button)

	# Main content split
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 15)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_hbox)

	# Left side - Player list
	var left_vbox = VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(250, 0)
	content_hbox.add_child(left_vbox)

	var list_header = Label.new()
	list_header.text = "Civilizations"
	list_header.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(list_header)

	player_list = ItemList.new()
	player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_list.item_selected.connect(_on_player_selected)
	left_vbox.add_child(player_list)

	# Right side - Details
	var right_vbox = VBoxContainer.new()
	right_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_hbox.add_child(right_vbox)

	var detail_header = Label.new()
	detail_header.text = "Civilization Details"
	detail_header.add_theme_font_size_override("font_size", 16)
	right_vbox.add_child(detail_header)

	# Detail scroll
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(scroll)

	detail_container = VBoxContainer.new()
	detail_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_container.add_theme_constant_override("separation", 8)
	scroll.add_child(detail_container)

	_setup_detail_content()

	# Info panel at bottom
	info_panel = PanelContainer.new()
	info_panel.custom_minimum_size = Vector2(0, 100)
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

func _setup_detail_content() -> void:
	# Civ name
	civ_name_label = Label.new()
	civ_name_label.text = "Select a civilization"
	civ_name_label.add_theme_font_size_override("font_size", 20)
	detail_container.add_child(civ_name_label)

	# Leader name
	leader_name_label = Label.new()
	leader_name_label.text = ""
	leader_name_label.add_theme_font_size_override("font_size", 14)
	detail_container.add_child(leader_name_label)

	# Relation status
	relation_label = Label.new()
	relation_label.text = ""
	detail_container.add_child(relation_label)

	# Attitude
	attitude_label = Label.new()
	attitude_label.text = ""
	detail_container.add_child(attitude_label)

	# Attitude breakdown
	breakdown_label = Label.new()
	breakdown_label.add_theme_font_size_override("font_size", 12)
	breakdown_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	detail_container.add_child(breakdown_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	detail_container.add_child(spacer)

	# Action buttons row 1
	var btn_row1 = HBoxContainer.new()
	btn_row1.add_theme_constant_override("separation", 10)
	detail_container.add_child(btn_row1)

	declare_war_btn = Button.new()
	declare_war_btn.text = "Declare War"
	declare_war_btn.custom_minimum_size = Vector2(110, 35)
	declare_war_btn.pressed.connect(_on_declare_war_pressed)
	btn_row1.add_child(declare_war_btn)

	make_peace_btn = Button.new()
	make_peace_btn.text = "Make Peace"
	make_peace_btn.custom_minimum_size = Vector2(110, 35)
	make_peace_btn.pressed.connect(_on_make_peace_pressed)
	btn_row1.add_child(make_peace_btn)

	# Action buttons row 2
	var btn_row2 = HBoxContainer.new()
	btn_row2.add_theme_constant_override("separation", 10)
	detail_container.add_child(btn_row2)

	open_borders_btn = Button.new()
	open_borders_btn.text = "Open Borders"
	open_borders_btn.custom_minimum_size = Vector2(110, 35)
	open_borders_btn.pressed.connect(_on_open_borders_pressed)
	btn_row2.add_child(open_borders_btn)

	defensive_pact_btn = Button.new()
	defensive_pact_btn.text = "Defensive Pact"
	defensive_pact_btn.custom_minimum_size = Vector2(120, 35)
	defensive_pact_btn.pressed.connect(_on_defensive_pact_pressed)
	btn_row2.add_child(defensive_pact_btn)

	trade_btn = Button.new()
	trade_btn.text = "Propose Trade"
	trade_btn.custom_minimum_size = Vector2(110, 35)
	trade_btn.pressed.connect(_on_trade_pressed)
	btn_row2.add_child(trade_btn)

	# Hide buttons initially
	_hide_action_buttons()

func _hide_action_buttons() -> void:
	declare_war_btn.visible = false
	make_peace_btn.visible = false
	open_borders_btn.visible = false
	defensive_pact_btn.visible = false
	trade_btn.visible = false

func _on_show_diplomacy(player = null) -> void:
	# Close all other popups first
	EventBus.close_all_popups.emit()
	_refresh_player_list()
	if player:
		_select_player(player)
	visible = true

func _on_hide_diplomacy() -> void:
	visible = false

func _on_close_pressed() -> void:
	EventBus.hide_diplomacy_screen.emit()

func _refresh_player_list() -> void:
	player_list.clear()

	var human = GameManager.human_player
	if human == null:
		return

	for player in GameManager.players:
		if player == human:
			continue

		# Only show met civilizations
		if player.player_id not in human.met_players:
			continue

		var civ_data = DataManager.get_civ(player.civilization_id)
		var civ_name = civ_data.get("name", player.civilization_id)

		# Add status indicator
		var status = ""
		if GameManager.is_at_war(human, player):
			status = " [WAR]"
		elif player.player_id in human.defensive_pact_with:
			status = " [ALLY]"

		player_list.add_item(civ_name + status)
		player_list.set_item_metadata(player_list.item_count - 1, player)

		# Color based on relationship
		if GameManager.is_at_war(human, player):
			player_list.set_item_custom_fg_color(player_list.item_count - 1, Color.RED)
		elif player.player_id in human.defensive_pact_with:
			player_list.set_item_custom_fg_color(player_list.item_count - 1, Color.GREEN)

func _on_player_selected(index: int) -> void:
	var player = player_list.get_item_metadata(index)
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
		breakdown_label.text = ""
		info_label.text = "Select a civilization to view details and diplomatic options."
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
	var attitude = DiplomacySystem.get_attitude_string(selected_player, human)
	attitude_label.text = "Attitude: " + attitude

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
	var breakdown = DiplomacySystem.get_attitude_breakdown(selected_player, human)
	var breakdown_text = ""
	for item in breakdown:
		var sign = "+" if item["value"] > 0 else ""
		breakdown_text += "  %s%d: %s\n" % [sign, item["value"], item["reason"]]
	breakdown_label.text = breakdown_text

	# Update info panel
	info_label.text = "[b]%s[/b]\nRelationship: %s | Attitude: %s" % [
		civ_data.get("name", "Unknown"),
		relation_text,
		attitude
	]

	# Show appropriate buttons
	_update_action_buttons()

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

	open_borders_btn.text = "Cancel Borders" if has_open_borders else "Open Borders"
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
		human.open_borders_with.erase(selected_player.player_id)
		selected_player.open_borders_with.erase(human.player_id)
	else:
		human.open_borders_with.append(selected_player.player_id)
		selected_player.open_borders_with.append(human.player_id)
		EventBus.open_borders_signed.emit(human, selected_player)

	_update_detail_panel()

func _on_defensive_pact_pressed() -> void:
	if selected_player == null:
		return

	var human = GameManager.human_player

	if selected_player.player_id in human.defensive_pact_with:
		human.defensive_pact_with.erase(selected_player.player_id)
		selected_player.defensive_pact_with.erase(human.player_id)
	else:
		human.defensive_pact_with.append(selected_player.player_id)
		selected_player.defensive_pact_with.append(human.player_id)
		EventBus.defensive_pact_signed.emit(human, selected_player)

	_update_detail_panel()

func _on_trade_pressed() -> void:
	if selected_player == null:
		return
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
	if player1.player_id not in player2.met_players:
		player2.met_players.append(player1.player_id)
	if player2.player_id not in player1.met_players:
		player1.met_players.append(player2.player_id)

	if visible:
		_refresh_player_list()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
