class_name VictoryScreen
extends Control
## Dual-purpose victory screen: mid-game progress advisor (F8) and win/loss display.

var winner = null  # Player (untyped to avoid load-order issues)
var victory_type: String = ""
var is_game_over: bool = false

# UI elements
var panel: PanelContainer
var main_vbox: VBoxContainer
var title_label: Label

# Progress mode elements
var progress_container: VBoxContainer

# Game over elements
var gameover_container: VBoxContainer
var message_label: Label
var stats_label: RichTextLabel
var continue_button: Button
var main_menu_button: Button

const BG_COLOR = Color(0.08, 0.08, 0.12, 1.0)
const BORDER_COLOR = Color(0.4, 0.4, 0.5)
const BAR_BG_COLOR = Color(0.15, 0.15, 0.2)
const BAR_FILL_COLOR = Color(0.3, 0.6, 0.3)
const BAR_HIGH_COLOR = Color(0.6, 0.8, 0.3)
const BAR_COMPLETE_COLOR = Color(0.9, 0.8, 0.2)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_ui()
	EventBus.victory_achieved.connect(_on_victory_achieved)
	EventBus.game_over.connect(_on_game_over)
	EventBus.show_victory_progress.connect(_on_show_progress)
	EventBus.close_all_popups.connect(_on_close)
	hide()

func _create_ui() -> void:
	# Semi-transparent overlay
	var bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.6)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Main panel
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 80
	panel.offset_right = -80
	panel.offset_top = 50
	panel.offset_bottom = -30
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.set_border_width_all(3)
	style.border_color = Color.GOLD
	style.set_corner_radius_all(12)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(main_vbox)

	# Header
	var header = HBoxContainer.new()
	main_vbox.add_child(header)

	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.add_theme_color_override("font_color", Color.GOLD)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title_label)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(_on_close)
	header.add_child(close_btn)

	# Progress mode container
	progress_container = VBoxContainer.new()
	progress_container.add_theme_constant_override("separation", 12)
	progress_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(progress_container)

	# Game over container
	gameover_container = VBoxContainer.new()
	gameover_container.add_theme_constant_override("separation", 10)
	gameover_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(gameover_container)

	message_label = Label.new()
	message_label.add_theme_font_size_override("font_size", 20)
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gameover_container.add_child(message_label)

	stats_label = RichTextLabel.new()
	stats_label.bbcode_enabled = true
	stats_label.fit_content = false
	stats_label.scroll_active = true
	stats_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_label.add_theme_font_size_override("normal_font_size", 15)
	gameover_container.add_child(stats_label)

	var btn_hbox = HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 30)
	gameover_container.add_child(btn_hbox)

	continue_button = Button.new()
	continue_button.text = "Continue Playing"
	continue_button.custom_minimum_size = Vector2(160, 45)
	continue_button.pressed.connect(_on_close)
	btn_hbox.add_child(continue_button)

	main_menu_button = Button.new()
	main_menu_button.text = "Main Menu"
	main_menu_button.custom_minimum_size = Vector2(160, 45)
	main_menu_button.pressed.connect(_on_main_menu_pressed)
	btn_hbox.add_child(main_menu_button)

func _on_show_progress() -> void:
	EventBus.close_all_popups.emit()
	is_game_over = false
	_show_progress_mode()
	show()

func _on_victory_achieved(player, type: String) -> void:
	winner = player
	victory_type = type
	is_game_over = true
	EventBus.close_all_popups.emit()
	_show_gameover_mode()
	show()

func _on_game_over(player, type: String) -> void:
	winner = player
	victory_type = type
	is_game_over = true
	EventBus.close_all_popups.emit()
	_show_gameover_mode()
	show()

func _on_close() -> void:
	hide()

func _show_progress_mode() -> void:
	title_label.text = "Victory Progress"
	title_label.add_theme_color_override("font_color", Color.GOLD)
	progress_container.show()
	gameover_container.hide()
	_build_progress_display()

func _show_gameover_mode() -> void:
	var player_won = (winner == GameManager.human_player)

	if player_won:
		title_label.text = "VICTORY!"
		title_label.add_theme_color_override("font_color", Color.GOLD)
	else:
		title_label.text = "DEFEAT"
		title_label.add_theme_color_override("font_color", Color.RED)

	progress_container.hide()
	gameover_container.show()
	_build_gameover_display()

func _build_progress_display() -> void:
	# Clear existing
	for child in progress_container.get_children():
		child.queue_free()

	var player = GameManager.human_player
	if player == null:
		return

	var progress = VictorySystem.get_victory_progress(player)

	# Conquest
	var conquest = progress.get("conquest", {})
	var c_eliminated = conquest.get("eliminated", 0)
	var c_total = conquest.get("total_rivals", 1)
	var c_pct = conquest.get("percent", 0.0)
	_add_progress_row("Conquest", c_pct,
		"Rivals eliminated: %d / %d" % [c_eliminated, c_total])

	# Domination
	var dom = progress.get("domination", {})
	var d_land = dom.get("land_percent", 0.0)
	var d_pop = dom.get("pop_percent", 0.0)
	var d_land_need = dom.get("land_needed", 0.64)
	var d_pop_need = dom.get("pop_needed", 0.64)
	var d_pct = min(d_land / d_land_need, d_pop / d_pop_need)
	_add_progress_row("Domination", clampf(d_pct, 0.0, 1.0),
		"Land: %d%% / %d%%  |  Population: %d%% / %d%%" % [
			int(d_land * 100), int(d_land_need * 100),
			int(d_pop * 100), int(d_pop_need * 100)])

	# Cultural
	var cult = progress.get("cultural", {})
	var culture_legendary = cult.get("legendary_cities", 0)
	var culture_needed = cult.get("needed", 3)
	var culture_highest = cult.get("highest_culture", 0)
	var culture_threshold = cult.get("threshold", 50000)
	var culture_pct = float(culture_legendary) / max(culture_needed, 1)
	if culture_legendary < culture_needed:
		# Show progress of best city
		culture_pct = clampf(float(culture_highest) / max(culture_threshold, 1) / culture_needed, 0.0, 0.99)
	_add_progress_row("Cultural", clampf(culture_pct, 0.0, 1.0),
		"Legendary cities: %d / %d  |  Best city: %s / %s culture" % [
			culture_legendary, culture_needed,
			_format_number(culture_highest), _format_number(culture_threshold)])

	# Space Race
	var space = progress.get("space", {})
	var s_parts = space.get("parts_built", 0)
	var s_needed = space.get("parts_needed", 6)
	var s_apollo = space.get("has_apollo", false)
	var s_pct = float(s_parts) / max(s_needed, 1)
	var s_detail = "Parts: %d / %d" % [s_parts, s_needed]
	if not s_apollo:
		s_detail += "  |  Apollo Program: not built"
	else:
		s_detail += "  |  Apollo Program: complete"
	_add_progress_row("Space Race", clampf(s_pct, 0.0, 1.0), s_detail)

	# Diplomatic
	var has_un = false
	if VotingSystem:
		has_un = VotingSystem.is_source_active("un")
	_add_progress_row("Diplomatic", 0.0 if not has_un else 0.5,
		"United Nations: %s" % ("Active" if has_un else "Not yet built"))

	# Score
	var score_data = progress.get("score", {})
	var my_score = score_data.get("current", 0)
	var turns_left = score_data.get("turns_remaining", 0)

	# Find best AI score
	var best_ai_score = 0
	var best_ai_name = ""
	for p in GameManager.players:
		if p != player:
			p.calculate_score()
			if p.score > best_ai_score:
				best_ai_score = p.score
				best_ai_name = DataManager.get_civ(p.civilization_id).get("name", "Unknown")

	var score_pct = float(my_score) / max(my_score + best_ai_score, 1)
	_add_progress_row("Score", clampf(score_pct, 0.0, 1.0),
		"You: %d  |  Best rival: %d (%s)  |  %d turns remaining" % [
			my_score, best_ai_score, best_ai_name, max(turns_left, 0)])

func _add_progress_row(title: String, percent: float, detail: String) -> void:
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	progress_container.add_child(row)

	# Title + percentage
	var title_hbox = HBoxContainer.new()
	row.add_child(title_hbox)

	var title_lbl = Label.new()
	title_lbl.text = title
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_hbox.add_child(title_lbl)

	var pct_lbl = Label.new()
	pct_lbl.text = "%d%%" % int(percent * 100)
	pct_lbl.add_theme_font_size_override("font_size", 18)
	if percent >= 1.0:
		pct_lbl.add_theme_color_override("font_color", BAR_COMPLETE_COLOR)
	elif percent >= 0.5:
		pct_lbl.add_theme_color_override("font_color", BAR_HIGH_COLOR)
	title_hbox.add_child(pct_lbl)

	# Progress bar
	var bar_bg = PanelContainer.new()
	bar_bg.custom_minimum_size = Vector2(0, 20)
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = BAR_BG_COLOR
	bg_style.set_corner_radius_all(4)
	bar_bg.add_theme_stylebox_override("panel", bg_style)
	row.add_child(bar_bg)

	# Fill
	var fill = ColorRect.new()
	fill.anchor_left = 0.0
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_right = clampf(percent, 0.0, 1.0)
	fill.offset_left = 2
	fill.offset_top = 2
	fill.offset_bottom = -2
	fill.offset_right = -2
	if percent >= 1.0:
		fill.color = BAR_COMPLETE_COLOR
	elif percent >= 0.5:
		fill.color = BAR_HIGH_COLOR
	else:
		fill.color = BAR_FILL_COLOR
	bar_bg.add_child(fill)

	# Detail text
	var detail_lbl = Label.new()
	detail_lbl.text = detail
	detail_lbl.add_theme_font_size_override("font_size", 13)
	detail_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(detail_lbl)

func _build_gameover_display() -> void:
	if winner == null:
		return

	var player_won = (winner == GameManager.human_player)
	var victory_name = _get_victory_name(victory_type)
	var civ_name = DataManager.get_civ(winner.civilization_id).get("name", "Unknown")

	if player_won:
		message_label.text = "Congratulations! You have achieved a %s Victory!\nYour civilization will be remembered throughout history." % victory_name
	else:
		message_label.text = "The %s has achieved a %s Victory.\nYour civilization has been overshadowed." % [civ_name, victory_name]

	# Stats
	var text = "[b]Final Statistics[/b]\n"
	text += "[color=gray]───────────────────────────[/color]\n\n"

	for player in GameManager.players:
		player.calculate_score()
		var p_civ_name = DataManager.get_civ(player.civilization_id).get("name", "Unknown")
		var marker = "  [color=gold]<-- Winner[/color]" if player == winner else ""
		var p_color = "white" if player == GameManager.human_player else "gray"
		text += "[color=%s][b]%s[/b]: %d points%s[/color]\n" % [p_color, p_civ_name, player.score, marker]
		text += "[color=gray]  Cities: %d  |  Population: %d  |  Technologies: %d[/color]\n\n" % [
			player.cities.size(), player.get_total_population(), player.researched_techs.size()]

	text += "\n[color=gray]Game completed in %d turns (%s)[/color]" % [
		TurnManager.current_turn, TurnManager.get_year_string()]

	stats_label.text = text

func _format_number(n: int) -> String:
	if n >= 1000:
		return "%d,%03d" % [n / 1000, n % 1000]
	return str(n)

func _get_victory_name(type: String) -> String:
	match type:
		"conquest": return "Conquest"
		"domination": return "Domination"
		"cultural": return "Cultural"
		"space": return "Space Race"
		"score": return "Score"
		"diplomatic": return "Diplomatic"
		_: return type.capitalize()

func _on_main_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close()
			get_viewport().set_input_as_handled()
