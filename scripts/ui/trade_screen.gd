class_name TradeScreen
extends Control
## Trade negotiation screen for exchanging resources, gold, and techs.

var current_proposal: Dictionary = {}
var from_player = null
var to_player = null

# UI elements
var panel: Panel
var title_label: Label
var close_button: Button

# Our offer side
var our_gold_spinner: SpinBox
var our_gpt_spinner: SpinBox
var our_resources_list: VBoxContainer
var our_techs_list: VBoxContainer

# Their offer side
var their_gold_spinner: SpinBox
var their_gpt_spinner: SpinBox
var their_resources_list: VBoxContainer
var their_techs_list: VBoxContainer

# Action buttons
var propose_button: Button
var cancel_button: Button
var status_label: Label

# Colors
const BG_COLOR = Color(0.1, 0.1, 0.15, 1.0)
const OFFER_BG_COLOR = Color(0.15, 0.15, 0.2)

func _ready() -> void:
	# Allow clicks to pass through to top menu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_ui()
	EventBus.show_trade_screen.connect(_on_show_trade_screen)
	EventBus.hide_trade_screen.connect(_on_hide_trade_screen)
	EventBus.close_all_popups.connect(_on_hide_trade_screen)
	EventBus.trade_proposed.connect(_on_trade_proposed)
	EventBus.trade_accepted.connect(_on_trade_accepted)
	EventBus.trade_rejected.connect(_on_trade_rejected)
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
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_right = -10
	panel.offset_top = 50  # Below the 40px top menu
	panel.offset_bottom = -10
	add_child(panel)

	# Title
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = "Trade Negotiation"
	title_label.position = Vector2(20, 10)
	title_label.add_theme_font_size_override("font_size", 22)
	panel.add_child(title_label)

	# Close button
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close_pressed)
	panel.add_child(close_button)

	# Main container - split into two sides
	var main_hbox = HBoxContainer.new()
	main_hbox.name = "MainHBox"
	main_hbox.position = Vector2(20, 50)
	main_hbox.add_theme_constant_override("separation", 20)
	panel.add_child(main_hbox)

	# Our offer side
	var our_panel = _create_offer_panel("Your Offer", true)
	main_hbox.add_child(our_panel)

	# Their offer side
	var their_panel = _create_offer_panel("Their Offer", false)
	main_hbox.add_child(their_panel)

	# Bottom buttons
	var button_hbox = HBoxContainer.new()
	button_hbox.name = "ButtonHBox"
	button_hbox.add_theme_constant_override("separation", 20)
	panel.add_child(button_hbox)

	propose_button = Button.new()
	propose_button.text = "Propose Trade"
	propose_button.custom_minimum_size = Vector2(120, 35)
	propose_button.pressed.connect(_on_propose_pressed)
	button_hbox.add_child(propose_button)

	cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(100, 35)
	cancel_button.pressed.connect(_on_close_pressed)
	button_hbox.add_child(cancel_button)

	status_label = Label.new()
	status_label.name = "Status"
	status_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(status_label)

func _create_offer_panel(title: String, is_ours: bool) -> Panel:
	var offer_panel = Panel.new()
	offer_panel.custom_minimum_size = Vector2(300, 400)
	var style = StyleBoxFlat.new()
	style.bg_color = OFFER_BG_COLOR
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	offer_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.position = Vector2(10, 10)
	vbox.add_theme_constant_override("separation", 8)
	offer_panel.add_child(vbox)

	# Title
	var label = Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(label)

	# Gold
	var gold_hbox = HBoxContainer.new()
	gold_hbox.add_theme_constant_override("separation", 5)
	vbox.add_child(gold_hbox)

	var gold_label = Label.new()
	gold_label.text = "Gold:"
	gold_label.custom_minimum_size = Vector2(80, 0)
	gold_hbox.add_child(gold_label)

	var gold_spin = SpinBox.new()
	gold_spin.min_value = 0
	gold_spin.max_value = 10000
	gold_spin.step = 10
	gold_spin.custom_minimum_size = Vector2(100, 0)
	gold_spin.editable = is_ours
	gold_hbox.add_child(gold_spin)

	if is_ours:
		our_gold_spinner = gold_spin
	else:
		their_gold_spinner = gold_spin

	# Gold per turn
	var gpt_hbox = HBoxContainer.new()
	gpt_hbox.add_theme_constant_override("separation", 5)
	vbox.add_child(gpt_hbox)

	var gpt_label = Label.new()
	gpt_label.text = "Gold/Turn:"
	gpt_label.custom_minimum_size = Vector2(80, 0)
	gpt_hbox.add_child(gpt_label)

	var gpt_spin = SpinBox.new()
	gpt_spin.min_value = 0
	gpt_spin.max_value = 100
	gpt_spin.step = 1
	gpt_spin.custom_minimum_size = Vector2(100, 0)
	gpt_spin.editable = is_ours
	gpt_hbox.add_child(gpt_spin)

	if is_ours:
		our_gpt_spinner = gpt_spin
	else:
		their_gpt_spinner = gpt_spin

	# Resources section
	var res_label = Label.new()
	res_label.text = "Resources:"
	res_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(res_label)

	var res_scroll = ScrollContainer.new()
	res_scroll.custom_minimum_size = Vector2(280, 80)
	res_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(res_scroll)

	var res_list = VBoxContainer.new()
	res_list.add_theme_constant_override("separation", 2)
	res_scroll.add_child(res_list)

	if is_ours:
		our_resources_list = res_list
	else:
		their_resources_list = res_list

	# Technologies section
	var tech_label = Label.new()
	tech_label.text = "Technologies:"
	tech_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(tech_label)

	var tech_scroll = ScrollContainer.new()
	tech_scroll.custom_minimum_size = Vector2(280, 100)
	tech_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(tech_scroll)

	var tech_list = VBoxContainer.new()
	tech_list.add_theme_constant_override("separation", 2)
	tech_scroll.add_child(tech_list)

	if is_ours:
		our_techs_list = tech_list
	else:
		their_techs_list = tech_list

	return offer_panel

func show_trade(proposer, receiver) -> void:
	from_player = proposer
	to_player = receiver

	if from_player == null or to_player == null:
		return

	# Close all other popups first
	EventBus.close_all_popups.emit()

	# Create new proposal
	current_proposal = TradeSystem.create_proposal(from_player, to_player)

	# Update title
	var their_civ = DataManager.get_civ(to_player.civilization_id)
	title_label.text = "Trade with %s" % their_civ.get("name", "Unknown")

	# Populate UI
	_populate_resources()
	_populate_techs()
	_update_gold_limits()
	_clear_selections()

	status_label.text = ""
	_update_layout()
	show()

func _populate_resources() -> void:
	# Clear existing
	for child in our_resources_list.get_children():
		child.queue_free()
	for child in their_resources_list.get_children():
		child.queue_free()

	# Our tradeable resources
	var our_resources = TradeSystem.get_tradeable_resources(from_player)
	for res_id in our_resources:
		var res = DataManager.get_resource(res_id)
		var check = CheckBox.new()
		check.text = res.get("name", res_id)
		check.toggled.connect(_on_our_resource_toggled.bind(res_id))
		our_resources_list.add_child(check)

	if our_resources.is_empty():
		var label = Label.new()
		label.text = "(No tradeable resources)"
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.GRAY)
		our_resources_list.add_child(label)

	# Their tradeable resources
	var their_resources = TradeSystem.get_tradeable_resources(to_player)
	for res_id in their_resources:
		var res = DataManager.get_resource(res_id)
		var check = CheckBox.new()
		check.text = res.get("name", res_id)
		check.toggled.connect(_on_their_resource_toggled.bind(res_id))
		their_resources_list.add_child(check)

	if their_resources.is_empty():
		var label = Label.new()
		label.text = "(No tradeable resources)"
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.GRAY)
		their_resources_list.add_child(label)

func _populate_techs() -> void:
	# Clear existing
	for child in our_techs_list.get_children():
		child.queue_free()
	for child in their_techs_list.get_children():
		child.queue_free()

	# Check if tech trading is available (requires Alphabet)
	var can_trade = TradeSystem.can_trade_techs(from_player, to_player)

	if not can_trade:
		# Show message that Alphabet is required
		var label1 = Label.new()
		label1.text = "(Requires Alphabet)"
		label1.add_theme_font_size_override("font_size", 12)
		label1.add_theme_color_override("font_color", Color.GRAY)
		our_techs_list.add_child(label1)

		var label2 = Label.new()
		label2.text = "(Requires Alphabet)"
		label2.add_theme_font_size_override("font_size", 12)
		label2.add_theme_color_override("font_color", Color.GRAY)
		their_techs_list.add_child(label2)
		return

	# Our tradeable techs
	var our_techs = TradeSystem.get_tradeable_techs(from_player, to_player)
	for tech_id in our_techs:
		var tech = DataManager.get_tech(tech_id)
		var check = CheckBox.new()
		check.text = tech.get("name", tech_id)
		check.toggled.connect(_on_our_tech_toggled.bind(tech_id))
		our_techs_list.add_child(check)

	if our_techs.is_empty():
		var label = Label.new()
		label.text = "(No techs to trade)"
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.GRAY)
		our_techs_list.add_child(label)

	# Their tradeable techs
	var their_techs = TradeSystem.get_tradeable_techs(to_player, from_player)
	for tech_id in their_techs:
		var tech = DataManager.get_tech(tech_id)
		var check = CheckBox.new()
		check.text = tech.get("name", tech_id)
		check.toggled.connect(_on_their_tech_toggled.bind(tech_id))
		their_techs_list.add_child(check)

	if their_techs.is_empty():
		var label = Label.new()
		label.text = "(No techs to trade)"
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color.GRAY)
		their_techs_list.add_child(label)

func _update_gold_limits() -> void:
	if our_gold_spinner:
		our_gold_spinner.max_value = from_player.gold if from_player else 0
		our_gold_spinner.value = 0

	if their_gold_spinner:
		their_gold_spinner.max_value = to_player.gold if to_player else 0
		their_gold_spinner.value = 0

func _clear_selections() -> void:
	if our_gold_spinner:
		our_gold_spinner.value = 0
	if our_gpt_spinner:
		our_gpt_spinner.value = 0
	if their_gold_spinner:
		their_gold_spinner.value = 0
	if their_gpt_spinner:
		their_gpt_spinner.value = 0

	current_proposal["from_offers"]["gold"] = 0
	current_proposal["from_offers"]["gold_per_turn"] = 0
	current_proposal["from_offers"]["resources"] = []
	current_proposal["from_offers"]["techs"] = []
	current_proposal["to_offers"]["gold"] = 0
	current_proposal["to_offers"]["gold_per_turn"] = 0
	current_proposal["to_offers"]["resources"] = []
	current_proposal["to_offers"]["techs"] = []

func _on_our_resource_toggled(toggled: bool, res_id: String) -> void:
	if toggled:
		TradeSystem.add_resource_to_offer(current_proposal, true, res_id)
	else:
		current_proposal["from_offers"]["resources"].erase(res_id)

func _on_their_resource_toggled(toggled: bool, res_id: String) -> void:
	if toggled:
		TradeSystem.add_resource_to_offer(current_proposal, false, res_id)
	else:
		current_proposal["to_offers"]["resources"].erase(res_id)

func _on_our_tech_toggled(toggled: bool, tech_id: String) -> void:
	if toggled:
		TradeSystem.add_tech_to_offer(current_proposal, true, tech_id)
	else:
		current_proposal["from_offers"]["techs"].erase(tech_id)

func _on_their_tech_toggled(toggled: bool, tech_id: String) -> void:
	if toggled:
		TradeSystem.add_tech_to_offer(current_proposal, false, tech_id)
	else:
		current_proposal["to_offers"]["techs"].erase(tech_id)

func _on_propose_pressed() -> void:
	# Update gold values from spinners
	current_proposal["from_offers"]["gold"] = int(our_gold_spinner.value)
	current_proposal["from_offers"]["gold_per_turn"] = int(our_gpt_spinner.value)
	current_proposal["to_offers"]["gold"] = int(their_gold_spinner.value)
	current_proposal["to_offers"]["gold_per_turn"] = int(their_gpt_spinner.value)

	# Validate
	if not TradeSystem.is_proposal_valid(current_proposal):
		status_label.text = "Invalid trade proposal"
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	# Check if AI would accept
	if not to_player.is_human:
		var would_accept = TradeSystem.would_ai_accept(current_proposal, to_player.player_id)
		if would_accept:
			EventBus.trade_accepted.emit(from_player, to_player, current_proposal)
		else:
			EventBus.trade_rejected.emit(from_player, to_player)

func _on_trade_proposed(proposer, receiver, _offer: Dictionary) -> void:
	# Only handle if we're the human player and someone is proposing to us
	if receiver == GameManager.human_player and not proposer.is_human:
		show_trade(proposer, receiver)

func _on_trade_accepted(_from, _to, _offer: Dictionary) -> void:
	status_label.text = "Trade accepted!"
	status_label.add_theme_color_override("font_color", Color.GREEN)

	# Close after delay
	get_tree().create_timer(1.5).timeout.connect(_on_close_pressed)

func _on_trade_rejected(_from, _to) -> void:
	status_label.text = "Trade rejected!"
	status_label.add_theme_color_override("font_color", Color.ORANGE_RED)

func _on_close_pressed() -> void:
	hide()
	EventBus.hide_trade_screen.emit()

func _on_show_trade_screen(from_player_arg, to_player_arg) -> void:
	show_trade(from_player_arg, to_player_arg)

func _on_hide_trade_screen() -> void:
	hide()

func _update_layout() -> void:
	if panel == null:
		return

	var panel_size = panel.size

	# Position close button
	close_button.position = Vector2(panel_size.x - 50, 10)

	# Button row at bottom
	var button_hbox = panel.get_node_or_null("ButtonHBox")
	if button_hbox:
		button_hbox.position = Vector2(20, panel_size.y - 60)

	# Status label
	status_label.position = Vector2(300, panel_size.y - 55)

	# Main content size
	var main_hbox = panel.get_node_or_null("MainHBox")
	if main_hbox:
		main_hbox.size = Vector2(panel_size.x - 40, panel_size.y - 130)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_visible():
		_update_layout()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
