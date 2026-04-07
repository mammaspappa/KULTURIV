extends Control
## Multiplayer connection screen — host a Pitboss server or join an existing one.
## Supports WebSocket (firewall-friendly, default) and ENet (low-latency LAN).

signal back_pressed()
signal start_game(settings: Dictionary)

# Colors (matching main menu style)
const GOLD = Color(0.85, 0.7, 0.3)
const GOLD_LIGHT = Color(0.9, 0.8, 0.5)
const GOLD_BRIGHT = Color(1.0, 0.9, 0.6)
const BUTTON_BG = Color(0.12, 0.1, 0.08, 0.8)
const BUTTON_HOVER = Color(0.18, 0.15, 0.1, 0.85)
const BUTTON_BORDER = Color(0.6, 0.5, 0.2)
const PANEL_BG = Color(0.08, 0.07, 0.06, 0.9)

# UI nodes
var tab_container: TabContainer
var host_panel: VBoxContainer
var join_panel: VBoxContainer
var player_list_panel: VBoxContainer
var status_label: Label

# Host controls
var host_port_input: SpinBox
var host_max_players: SpinBox
var host_map_width: SpinBox
var host_map_height: SpinBox
var host_turn_timer: SpinBox
var host_transport: OptionButton
var host_button: Button
var start_button: Button

# Join controls — phase 1: connect
var join_address_input: LineEdit
var join_port_input: SpinBox
var join_name_input: LineEdit
var join_transport: OptionButton
var join_button: Button

# Join controls — phase 2: pick civ (shown after connecting)
var join_civ_container: VBoxContainer
var join_civ_option: OptionButton
var join_register_button: Button

# Player list
var player_list: VBoxContainer

var is_visible_screen: bool = false

func _ready() -> void:
	visible = false
	_build_ui()
	_connect_signals()

func show_screen() -> void:
	visible = true
	is_visible_screen = true

func hide_screen() -> void:
	visible = false
	is_visible_screen = false

func _connect_signals() -> void:
	EventBus.mp_player_list_updated.connect(_on_player_list_updated)
	EventBus.mp_connected_to_server.connect(_on_connected)
	EventBus.mp_connection_failed.connect(_on_connection_failed)
	EventBus.mp_server_disconnected.connect(_on_server_disconnected)
	EventBus.mp_server_info_received.connect(_on_server_info_received)
	EventBus.mp_registration_rejected.connect(_on_registration_rejected)
	EventBus.mp_game_starting.connect(_on_game_starting)

func _build_ui() -> void:
	# Dark background
	var bg = ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = Color(0.05, 0.07, 0.1)
	add_child(bg)

	# Title
	var title = Label.new()
	title.text = "MULTIPLAYER"
	title.set_anchors_preset(PRESET_TOP_WIDE)
	title.offset_top = 30
	title.offset_bottom = 70
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# Main container
	var main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_preset(PRESET_FULL_RECT)
	main_hbox.offset_top = 80
	main_hbox.offset_bottom = -60
	main_hbox.offset_left = 50
	main_hbox.offset_right = -50
	main_hbox.add_theme_constant_override("separation", 20)
	add_child(main_hbox)

	# Left side: tabs for host/join
	tab_container = TabContainer.new()
	tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_container.size_flags_stretch_ratio = 1.5
	main_hbox.add_child(tab_container)

	_build_host_panel()
	_build_join_panel()

	# Right side: player list
	var right_panel = PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right_style = StyleBoxFlat.new()
	right_style.bg_color = PANEL_BG
	right_style.set_border_width_all(1)
	right_style.border_color = BUTTON_BORDER
	right_style.set_corner_radius_all(4)
	right_style.set_content_margin_all(10)
	right_panel.add_theme_stylebox_override("panel", right_style)
	main_hbox.add_child(right_panel)

	player_list_panel = VBoxContainer.new()
	right_panel.add_child(player_list_panel)

	var list_title = Label.new()
	list_title.text = "Connected Players"
	list_title.add_theme_font_size_override("font_size", 20)
	list_title.add_theme_color_override("font_color", GOLD)
	player_list_panel.add_child(list_title)

	var separator = HSeparator.new()
	player_list_panel.add_child(separator)

	player_list = VBoxContainer.new()
	player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_list_panel.add_child(player_list)

	# Status label
	status_label = Label.new()
	status_label.text = ""
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_color", GOLD_LIGHT)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	player_list_panel.add_child(status_label)

	# Back button
	var back_btn = _create_button("Back")
	back_btn.set_anchors_preset(PRESET_BOTTOM_LEFT)
	back_btn.offset_left = 50
	back_btn.offset_bottom = -15
	back_btn.offset_top = -55
	back_btn.pressed.connect(func(): _on_back())
	add_child(back_btn)

func _build_host_panel() -> void:
	host_panel = VBoxContainer.new()
	host_panel.name = "Host Game"
	host_panel.add_theme_constant_override("separation", 10)
	tab_container.add_child(host_panel)

	_add_label(host_panel, "Port:")
	host_port_input = SpinBox.new()
	host_port_input.min_value = 1024
	host_port_input.max_value = 65535
	host_port_input.value = 7878
	host_panel.add_child(host_port_input)

	_add_label(host_panel, "Max Players:")
	host_max_players = SpinBox.new()
	host_max_players.min_value = 2
	host_max_players.max_value = 8
	host_max_players.value = 4
	host_panel.add_child(host_max_players)

	_add_label(host_panel, "Map Width:")
	host_map_width = SpinBox.new()
	host_map_width.min_value = 20
	host_map_width.max_value = 160
	host_map_width.value = 80
	host_panel.add_child(host_map_width)

	_add_label(host_panel, "Map Height:")
	host_map_height = SpinBox.new()
	host_map_height.min_value = 15
	host_map_height.max_value = 100
	host_map_height.value = 50
	host_panel.add_child(host_map_height)

	_add_label(host_panel, "Turn Timer (seconds, 0=unlimited):")
	host_turn_timer = SpinBox.new()
	host_turn_timer.min_value = 0
	host_turn_timer.max_value = 3600
	host_turn_timer.value = 300
	host_turn_timer.step = 30
	host_panel.add_child(host_turn_timer)

	_add_label(host_panel, "Transport:")
	host_transport = OptionButton.new()
	host_transport.add_item("WebSocket (firewall-friendly)", 0)
	host_transport.add_item("ENet (low-latency LAN)", 1)
	host_transport.selected = 0
	host_panel.add_child(host_transport)

	host_button = _create_button("Start Server")
	host_button.pressed.connect(_on_host_pressed)
	host_panel.add_child(host_button)

	start_button = _create_button("Start Game")
	start_button.visible = false
	start_button.pressed.connect(_on_start_game_pressed)
	host_panel.add_child(start_button)

func _build_join_panel() -> void:
	join_panel = VBoxContainer.new()
	join_panel.name = "Join Game"
	join_panel.add_theme_constant_override("separation", 10)
	tab_container.add_child(join_panel)

	# Phase 1: connection details
	_add_label(join_panel, "Server Address:")
	join_address_input = LineEdit.new()
	join_address_input.placeholder_text = "localhost"
	join_address_input.text = "localhost"
	join_panel.add_child(join_address_input)

	_add_label(join_panel, "Port:")
	join_port_input = SpinBox.new()
	join_port_input.min_value = 1024
	join_port_input.max_value = 65535
	join_port_input.value = 7878
	join_panel.add_child(join_port_input)

	_add_label(join_panel, "Player Name:")
	join_name_input = LineEdit.new()
	join_name_input.placeholder_text = "Player"
	join_name_input.text = "Player"
	join_panel.add_child(join_name_input)

	_add_label(join_panel, "Transport:")
	join_transport = OptionButton.new()
	join_transport.add_item("WebSocket (firewall-friendly)", 0)
	join_transport.add_item("ENet (low-latency LAN)", 1)
	join_transport.selected = 0
	join_panel.add_child(join_transport)

	join_button = _create_button("Connect")
	join_button.pressed.connect(_on_join_pressed)
	join_panel.add_child(join_button)

	# Phase 2: civ selection (hidden until connected and server info received)
	join_civ_container = VBoxContainer.new()
	join_civ_container.visible = false
	join_civ_container.add_theme_constant_override("separation", 10)
	join_panel.add_child(join_civ_container)

	var sep = HSeparator.new()
	join_civ_container.add_child(sep)

	_add_label(join_civ_container, "Choose Civilization:")
	join_civ_option = OptionButton.new()
	join_civ_container.add_child(join_civ_option)

	join_register_button = _create_button("Join")
	join_register_button.pressed.connect(_on_register_pressed)
	join_civ_container.add_child(join_register_button)

# --- BUTTON HANDLERS ---

func _on_host_pressed() -> void:
	var port = int(host_port_input.value)
	var transport_str = "websocket" if host_transport.selected == 0 else "enet"
	var settings = {
		"map_width": int(host_map_width.value),
		"map_height": int(host_map_height.value),
		"num_players": int(host_max_players.value),
		"difficulty": 4,
		"game_speed": 1,
	}
	NetworkManager.turn_time_limit = host_turn_timer.value
	var err = NetworkManager.host_game(port, settings, transport_str)
	if err == OK:
		status_label.text = "Server started on port %d" % port
		host_button.disabled = true
		start_button.visible = true
	else:
		status_label.text = "Failed to start server: %s" % error_string(err)

func _on_join_pressed() -> void:
	var address = join_address_input.text if join_address_input.text != "" else "localhost"
	var port = int(join_port_input.value)
	var transport_str = "websocket" if join_transport.selected == 0 else "enet"

	var err = NetworkManager.join_game(address, port, transport_str)
	if err == OK:
		status_label.text = "Connecting to %s:%d..." % [address, port]
		join_button.disabled = true
	else:
		status_label.text = "Failed to connect: %s" % error_string(err)

func _on_register_pressed() -> void:
	if join_civ_option.selected < 0:
		status_label.text = "Please select a civilization"
		return

	var selected_civ = join_civ_option.get_item_metadata(join_civ_option.selected)
	var info = {
		"name": join_name_input.text if join_name_input.text != "" else "Player",
		"civ": selected_civ,
		"leader": DataManager.get_civ(selected_civ).get("leaders", [""])[0],
	}

	NetworkManager.register_with_server(info)
	join_register_button.disabled = true
	status_label.text = "Registering as %s..." % DataManager.get_civ(selected_civ).get("name", selected_civ)

func _on_start_game_pressed() -> void:
	NetworkManager.server_start_game()

func _on_back() -> void:
	NetworkManager.disconnect_from_game()
	hide_screen()
	back_pressed.emit()

# --- SIGNAL HANDLERS ---

func _on_player_list_updated(players: Array) -> void:
	# Clear old entries
	for child in player_list.get_children():
		child.queue_free()

	for p in players:
		var entry = Label.new()
		entry.text = "%s (%s)" % [p.get("name", "Unknown"), p.get("civ", "?")]
		entry.add_theme_font_size_override("font_size", 16)
		entry.add_theme_color_override("font_color", GOLD_LIGHT)
		player_list.add_child(entry)

	status_label.text = "%d player(s) connected" % players.size()

func _on_connected() -> void:
	status_label.text = "Connected — waiting for server info..."
	join_button.disabled = true

func _on_server_info_received(info: Dictionary) -> void:
	var taken_civs: Array = info.get("taken_civs", [])

	# Populate civ dropdown with only available civs
	join_civ_option.clear()
	var civs = DataManager.get_all_civs()
	var civ_index = 0
	for civ_id in civs:
		if civ_id == "barbarian":
			continue
		if civ_id in taken_civs:
			continue
		var civ_data = civs[civ_id]
		join_civ_option.add_item(civ_data.get("name", civ_id), civ_index)
		join_civ_option.set_item_metadata(civ_index, civ_id)
		civ_index += 1

	if civ_index == 0:
		status_label.text = "No civilizations available"
		join_civ_container.visible = false
		return

	join_civ_container.visible = true
	join_register_button.disabled = false
	status_label.text = "Connected — choose your civilization"

func _on_connection_failed() -> void:
	status_label.text = "Connection failed"
	join_button.disabled = false
	join_civ_container.visible = false

func _on_server_disconnected() -> void:
	status_label.text = "Server disconnected"
	join_button.disabled = false
	join_civ_container.visible = false

func _on_registration_rejected(reason: String) -> void:
	status_label.text = "Rejected: %s" % reason
	join_register_button.disabled = false

func _on_game_starting(settings: Dictionary) -> void:
	# Transition to game scene
	hide_screen()
	settings["multiplayer"] = true
	GameManager.start_new_game(settings)
	TurnManager.simultaneous_mode = true
	get_tree().change_scene_to_file("res://scenes/main/game.tscn")

# --- UI HELPERS ---

func _add_label(parent: VBoxContainer, text: String) -> void:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", GOLD_LIGHT)
	parent.add_child(label)

func _create_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(200, 40)

	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = BUTTON_BG
	normal_style.border_color = BUTTON_BORDER
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(4)
	normal_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal_style)

	var hover_style = normal_style.duplicate()
	hover_style.bg_color = BUTTON_HOVER
	hover_style.border_color = GOLD
	btn.add_theme_stylebox_override("hover", hover_style)

	btn.add_theme_color_override("font_color", GOLD_LIGHT)
	btn.add_theme_color_override("font_hover_color", GOLD_BRIGHT)
	btn.add_theme_font_size_override("font_size", 16)

	return btn
