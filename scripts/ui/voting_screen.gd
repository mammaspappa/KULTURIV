extends Control
## Screen for UN/Apostolic Palace voting on resolutions and elections.

# UI Elements
var panel: PanelContainer
var title_label: Label
var close_button: Button
var source_tabs: TabContainer
var un_container: VBoxContainer
var ap_container: VBoxContainer
var active_vote_panel: PanelContainer
var vote_result_label: RichTextLabel

# State
var current_player_id: int = -1

func _ready() -> void:
	# Ensure this Control fills the screen so child anchors work
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Allow clicks to pass through to top menu
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	visible = false

	# Connect signals
	EventBus.show_voting_screen.connect(_on_show)
	EventBus.hide_voting_screen.connect(_on_close)
	EventBus.close_all_popups.connect(_on_close)
	EventBus.vote_started.connect(_on_vote_started)
	EventBus.vote_completed.connect(_on_vote_completed)

func _build_ui() -> void:
	# Main panel positioned just below top menu
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 10
	panel.offset_right = -10
	panel.offset_top = 50  # Just below 40px top menu
	panel.offset_bottom = -10
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
	style.border_color = Color(0.3, 0.4, 0.5)
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
	title_label.text = "World Congress"
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	close_button = Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close)
	header.add_child(close_button)

	# Tabs for UN and Apostolic Palace
	source_tabs = TabContainer.new()
	source_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(source_tabs)

	# UN Tab
	un_container = VBoxContainer.new()
	un_container.name = "United Nations"
	un_container.add_theme_constant_override("separation", 10)
	source_tabs.add_child(un_container)

	# Apostolic Palace Tab
	ap_container = VBoxContainer.new()
	ap_container.name = "Apostolic Palace"
	ap_container.add_theme_constant_override("separation", 10)
	source_tabs.add_child(ap_container)

	# Active vote panel (shown during voting)
	active_vote_panel = PanelContainer.new()
	active_vote_panel.custom_minimum_size = Vector2(0, 120)
	active_vote_panel.visible = false
	var vote_style = StyleBoxFlat.new()
	vote_style.bg_color = Color(0.15, 0.2, 0.25)
	vote_style.corner_radius_top_left = 6
	vote_style.corner_radius_top_right = 6
	vote_style.corner_radius_bottom_left = 6
	vote_style.corner_radius_bottom_right = 6
	vote_style.content_margin_left = 15
	vote_style.content_margin_right = 15
	vote_style.content_margin_top = 10
	vote_style.content_margin_bottom = 10
	active_vote_panel.add_theme_stylebox_override("panel", vote_style)
	main_vbox.add_child(active_vote_panel)

	vote_result_label = RichTextLabel.new()
	vote_result_label.bbcode_enabled = true
	vote_result_label.fit_content = true
	active_vote_panel.add_child(vote_result_label)

func _on_show() -> void:
	# Close all other popups first
	EventBus.close_all_popups.emit()

	if GameManager and GameManager.human_player:
		current_player_id = GameManager.human_player.player_id
	_refresh_all()
	visible = true

func _on_close() -> void:
	visible = false

func _refresh_all() -> void:
	_refresh_source_tab(un_container, "united_nations")
	_refresh_source_tab(ap_container, "apostolic_palace")

func _refresh_source_tab(container: VBoxContainer, source_id: String) -> void:
	# Clear existing
	for child in container.get_children():
		child.queue_free()

	if not VotingSystem:
		var no_sys = Label.new()
		no_sys.text = "Voting System not available"
		container.add_child(no_sys)
		return

	var source_data = VotingSystem.get_vote_source(source_id)
	if source_data.is_empty():
		var no_source = Label.new()
		no_source.text = "This vote source is not yet available."
		no_source.add_theme_color_override("font_color", Color.GRAY)
		container.add_child(no_source)
		return

	# Check if source is active
	var is_active = VotingSystem.is_vote_source_active(source_id)

	# Header info
	var info_panel = _create_source_info_panel(source_id, source_data, is_active)
	container.add_child(info_panel)

	if not is_active:
		var inactive_label = Label.new()
		inactive_label.text = "Build %s to activate voting." % source_data.get("name", source_id)
		inactive_label.add_theme_color_override("font_color", Color.YELLOW)
		container.add_child(inactive_label)
		return

	# Secretary/Resident info
	var leader_panel = _create_leader_panel(source_id)
	container.add_child(leader_panel)

	# Available resolutions
	var resolutions_label = Label.new()
	resolutions_label.text = "Available Resolutions"
	resolutions_label.add_theme_font_size_override("font_size", 16)
	container.add_child(resolutions_label)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(scroll)

	var resolutions_vbox = VBoxContainer.new()
	resolutions_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resolutions_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(resolutions_vbox)

	var resolutions = VotingSystem.get_available_resolutions(source_id)
	if resolutions.is_empty():
		var none_label = Label.new()
		none_label.text = "No resolutions available at this time."
		none_label.add_theme_color_override("font_color", Color.GRAY)
		resolutions_vbox.add_child(none_label)
	else:
		for res_id in resolutions:
			var res_data = resolutions[res_id]
			var res_panel = _create_resolution_panel(source_id, res_id, res_data)
			resolutions_vbox.add_child(res_panel)

	# Active resolutions in effect
	var active_label = Label.new()
	active_label.text = "Active Resolutions"
	active_label.add_theme_font_size_override("font_size", 16)
	container.add_child(active_label)

	var active_vbox = VBoxContainer.new()
	active_vbox.add_theme_constant_override("separation", 4)
	container.add_child(active_vbox)

	var active = VotingSystem.get_active_resolutions(source_id)
	if active.is_empty():
		var no_active = Label.new()
		no_active.text = "No resolutions currently in effect."
		no_active.add_theme_color_override("font_color", Color.GRAY)
		active_vbox.add_child(no_active)
	else:
		for res_id in active:
			var res_label = Label.new()
			var res_data = DataManager.get_vote_resolution(res_id) if DataManager else {}
			res_label.text = "- %s" % res_data.get("name", res_id)
			res_label.add_theme_color_override("font_color", Color.LIGHT_GREEN)
			active_vbox.add_child(res_label)

func _create_source_info_panel(source_id: String, source_data: Dictionary, is_active: bool) -> PanelContainer:
	var panel_node = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.12, 0.18)
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
	hbox.add_theme_constant_override("separation", 20)
	panel_node.add_child(hbox)

	var name_label = Label.new()
	name_label.text = source_data.get("name", source_id)
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color.GOLD if is_active else Color.GRAY)
	hbox.add_child(name_label)

	var status_label = Label.new()
	status_label.text = "[ACTIVE]" if is_active else "[INACTIVE]"
	status_label.add_theme_color_override("font_color", Color.GREEN if is_active else Color.RED)
	hbox.add_child(status_label)

	if source_id == "apostolic_palace":
		var religion_label = Label.new()
		var ap_religion = source_data.get("required_religion", "")
		if ap_religion != "":
			religion_label.text = "State Religion: %s" % ap_religion.capitalize()
			religion_label.add_theme_color_override("font_color", Color.MEDIUM_PURPLE)
		hbox.add_child(religion_label)

	return panel_node

func _create_leader_panel(source_id: String) -> PanelContainer:
	var panel_node = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.18, 0.22)
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

	var leader_id = VotingSystem.get_vote_leader(source_id)
	var leader_title = "Secretary General" if source_id == "united_nations" else "Resident"

	var title_lbl = Label.new()
	title_lbl.text = "%s:" % leader_title
	title_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(title_lbl)

	var name_lbl = Label.new()
	if leader_id >= 0 and GameManager:
		var leader = GameManager.get_player(leader_id)
		if leader:
			var civ_data = DataManager.get_civ(leader.civilization_id) if DataManager else {}
			name_lbl.text = civ_data.get("name", "Player %d" % leader_id)
			name_lbl.add_theme_color_override("font_color", Color.GOLD)
		else:
			name_lbl.text = "None"
			name_lbl.add_theme_color_override("font_color", Color.GRAY)
	else:
		name_lbl.text = "None elected"
		name_lbl.add_theme_color_override("font_color", Color.GRAY)
	name_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(name_lbl)

	# Vote count info
	var votes_lbl = Label.new()
	var player_votes = VotingSystem.get_player_votes(source_id, current_player_id)
	var total_votes = VotingSystem.get_total_votes(source_id)
	votes_lbl.text = "Your Votes: %d / %d Total" % [player_votes, total_votes]
	votes_lbl.add_theme_font_size_override("font_size", 12)
	votes_lbl.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	hbox.add_child(votes_lbl)

	# Call election button (only for leader)
	if leader_id == current_player_id:
		var election_btn = Button.new()
		election_btn.text = "Call Election"
		election_btn.pressed.connect(func(): _call_election(source_id))
		hbox.add_child(election_btn)

	return panel_node

func _create_resolution_panel(source_id: String, res_id: String, res_data: Dictionary) -> PanelContainer:
	var panel_node = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.18, 0.18, 0.22)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel_node.add_theme_stylebox_override("panel", style)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	panel_node.add_child(hbox)

	var info_vbox = VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)

	var name_lbl = Label.new()
	name_lbl.text = res_data.get("name", res_id)
	name_lbl.add_theme_font_size_override("font_size", 14)
	info_vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = res_data.get("description", "")
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_vbox.add_child(desc_lbl)

	# Effects preview
	var effects = res_data.get("effects", {})
	if not effects.is_empty():
		var effects_lbl = Label.new()
		effects_lbl.text = _format_effects(effects)
		effects_lbl.add_theme_font_size_override("font_size", 10)
		effects_lbl.add_theme_color_override("font_color", Color.LIGHT_GREEN)
		info_vbox.add_child(effects_lbl)

	# Threshold info
	var threshold = res_data.get("population_threshold", 50)
	var threshold_lbl = Label.new()
	threshold_lbl.text = "%d%% needed" % threshold
	threshold_lbl.add_theme_font_size_override("font_size", 11)
	threshold_lbl.add_theme_color_override("font_color", Color.YELLOW)
	hbox.add_child(threshold_lbl)

	# Propose button (only for Secretary General)
	var leader_id = VotingSystem.get_vote_leader(source_id)
	if leader_id == current_player_id:
		var propose_btn = Button.new()
		propose_btn.text = "Propose"
		propose_btn.custom_minimum_size = Vector2(70, 30)
		propose_btn.pressed.connect(func(): _propose_resolution(source_id, res_id))
		hbox.add_child(propose_btn)

	return panel_node

func _format_effects(effects: Dictionary) -> String:
	var parts = []
	for effect in effects:
		var value = effects[effect]
		match effect:
			"no_nukes":
				parts.append("Nuclear weapons banned")
			"open_borders":
				parts.append("All borders open")
			"global_civic":
				parts.append("All must adopt: %s" % str(value).capitalize())
			"defense_pact":
				parts.append("Mutual defense")
			"trade_embargo":
				parts.append("Trade embargo")
			"stop_war":
				parts.append("End all wars")
			"free_trade":
				parts.append("Free trade routes")
			"global_warming_reduction":
				parts.append("Reduce pollution: %d%%" % value)
			"victory":
				parts.append("DIPLOMATIC VICTORY")
			_:
				parts.append("%s: %s" % [effect, str(value)])
	return ", ".join(parts)

func _call_election(source_id: String) -> void:
	if VotingSystem:
		VotingSystem.call_election(source_id, current_player_id)
		_refresh_all()
		EventBus.notification_added.emit("Election called for %s" % source_id.replace("_", " ").capitalize(), "vote")

func _propose_resolution(source_id: String, resolution_id: String) -> void:
	if VotingSystem:
		VotingSystem.propose_resolution(source_id, resolution_id, current_player_id)
		_show_voting_ui(source_id, resolution_id)

func _show_voting_ui(source_id: String, resolution_id: String) -> void:
	active_vote_panel.visible = true

	var res_data = DataManager.get_vote_resolution(resolution_id) if DataManager else {}
	vote_result_label.text = "[center][b]Vote in Progress[/b][/center]\n\n"
	vote_result_label.text += "Resolution: [color=yellow]%s[/color]\n" % res_data.get("name", resolution_id)
	vote_result_label.text += res_data.get("description", "") + "\n\n"
	vote_result_label.text += "[color=green]FOR[/color] | [color=red]AGAINST[/color] | [color=gray]ABSTAIN[/color]"

	# Clear old buttons from vote panel
	for child in active_vote_panel.get_children():
		if child is HBoxContainer:
			child.queue_free()

	# Create voting buttons
	var btn_hbox = HBoxContainer.new()
	btn_hbox.add_theme_constant_override("separation", 20)
	active_vote_panel.add_child(btn_hbox)

	var for_btn = Button.new()
	for_btn.text = "Vote FOR"
	for_btn.custom_minimum_size = Vector2(100, 35)
	var for_style = StyleBoxFlat.new()
	for_style.bg_color = Color(0.2, 0.4, 0.2)
	for_style.corner_radius_top_left = 4
	for_style.corner_radius_top_right = 4
	for_style.corner_radius_bottom_left = 4
	for_style.corner_radius_bottom_right = 4
	for_btn.add_theme_stylebox_override("normal", for_style)
	for_btn.pressed.connect(func(): _cast_vote(source_id, resolution_id, "for"))
	btn_hbox.add_child(for_btn)

	var against_btn = Button.new()
	against_btn.text = "Vote AGAINST"
	against_btn.custom_minimum_size = Vector2(100, 35)
	var against_style = StyleBoxFlat.new()
	against_style.bg_color = Color(0.4, 0.2, 0.2)
	against_style.corner_radius_top_left = 4
	against_style.corner_radius_top_right = 4
	against_style.corner_radius_bottom_left = 4
	against_style.corner_radius_bottom_right = 4
	against_btn.add_theme_stylebox_override("normal", against_style)
	against_btn.pressed.connect(func(): _cast_vote(source_id, resolution_id, "against"))
	btn_hbox.add_child(against_btn)

	var abstain_btn = Button.new()
	abstain_btn.text = "Abstain"
	abstain_btn.custom_minimum_size = Vector2(80, 35)
	abstain_btn.pressed.connect(func(): _cast_vote(source_id, resolution_id, "abstain"))
	btn_hbox.add_child(abstain_btn)

func _cast_vote(_source_id: String, _resolution_id: String, vote: String) -> void:
	if VotingSystem:
		var vote_for = (vote == "for")
		VotingSystem.cast_vote(current_player_id, vote_for)
		active_vote_panel.visible = false
		_refresh_all()

func _on_vote_started(source_id: String, resolution_id: String, _proposer_id: int) -> void:
	if visible:
		_show_voting_ui(source_id, resolution_id)

func _on_vote_completed(source_id: String, resolution_id: String, passed: bool, _result: Dictionary) -> void:
	if visible:
		active_vote_panel.visible = true
		var res_data = DataManager.get_vote_resolution(resolution_id) if DataManager else {}
		vote_result_label.text = "[center][b]Vote Complete[/b][/center]\n\n"
		vote_result_label.text += "Resolution: [color=yellow]%s[/color]\n" % res_data.get("name", resolution_id)
		if passed:
			vote_result_label.text += "[color=green][b]PASSED[/b][/color]"
		else:
			vote_result_label.text += "[color=red][b]FAILED[/b][/color]"

		# Auto-hide after delay
		await get_tree().create_timer(3.0).timeout
		active_vote_panel.visible = false
		_refresh_all()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
