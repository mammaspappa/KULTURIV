class_name CivicsScreen
extends Control
## Civics management screen showing all civic categories and options.

const CATEGORY_NAMES = {
	"government": "Government",
	"legal": "Legal",
	"labor": "Labor",
	"economy": "Economy",
	"religion": "Religion"
}

var current_player = null  # Player (untyped to avoid load-order issues)
var pending_changes: Dictionary = {}  # category -> civic_id

# UI elements
var panel: PanelContainer
var category_containers: Dictionary = {}  # category -> VBoxContainer
var civic_buttons: Dictionary = {}  # civic_id -> Button
var info_label: RichTextLabel
var anarchy_label: Label
var confirm_button: Button

# Colors
const BG_COLOR = Color(0.08, 0.08, 0.12, 1.0)
const SELECTED_COLOR = Color(0.3, 0.5, 0.3)
const AVAILABLE_COLOR = Color(0.25, 0.25, 0.35)
const UNAVAILABLE_COLOR = Color(0.15, 0.15, 0.15)
const CURRENT_COLOR = Color(0.2, 0.4, 0.5)
const PENDING_COLOR = Color(0.5, 0.5, 0.2)
const BORDER_COLOR = Color(0.4, 0.4, 0.5)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_ui()
	EventBus.show_civics_screen.connect(_on_show_civics_screen)
	EventBus.hide_civics_screen.connect(_on_close_pressed)
	EventBus.close_all_popups.connect(_on_close_pressed)
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
	panel.offset_left = 10
	panel.offset_right = -10
	panel.offset_top = 50
	panel.offset_bottom = -10
	var style = StyleBoxFlat.new()
	style.bg_color = BG_COLOR
	style.set_border_width_all(2)
	style.border_color = BORDER_COLOR
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	panel.add_child(main_vbox)

	# Header row
	var header = HBoxContainer.new()
	main_vbox.add_child(header)

	var title = Label.new()
	title.text = "Civics"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(_on_close_pressed)
	header.add_child(close_btn)

	# Category columns
	var categories_hbox = HBoxContainer.new()
	categories_hbox.add_theme_constant_override("separation", 15)
	categories_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(categories_hbox)

	for category in CivicsSystem.CIVIC_CATEGORIES:
		var category_box = _create_category_container(category)
		categories_hbox.add_child(category_box)
		category_containers[category] = category_box

	# Bottom section: info panel + confirm area
	var bottom_hbox = HBoxContainer.new()
	bottom_hbox.add_theme_constant_override("separation", 10)
	bottom_hbox.custom_minimum_size = Vector2(0, 130)
	main_vbox.add_child(bottom_hbox)

	# Info panel (left, expanding)
	var info_panel = PanelContainer.new()
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.12, 0.12, 0.18)
	info_style.set_border_width_all(1)
	info_style.border_color = BORDER_COLOR
	info_style.set_corner_radius_all(4)
	info_panel.add_theme_stylebox_override("panel", info_style)
	bottom_hbox.add_child(info_panel)

	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = false
	info_label.scroll_active = true
	info_label.add_theme_font_size_override("normal_font_size", 14)
	info_panel.add_child(info_label)

	# Right column: anarchy + confirm
	var right_vbox = VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(180, 0)
	right_vbox.add_theme_constant_override("separation", 8)
	bottom_hbox.add_child(right_vbox)

	# Spacer to push buttons to bottom
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(spacer)

	anarchy_label = Label.new()
	anarchy_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	anarchy_label.add_theme_font_size_override("font_size", 13)
	anarchy_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	anarchy_label.hide()
	right_vbox.add_child(anarchy_label)

	confirm_button = Button.new()
	confirm_button.text = "Confirm Changes"
	confirm_button.custom_minimum_size = Vector2(170, 40)
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button.disabled = true
	right_vbox.add_child(confirm_button)

func _create_category_container(category: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(160, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)

	# Category header
	var header = Label.new()
	header.text = CATEGORY_NAMES.get(category, category.capitalize())
	header.add_theme_font_size_override("font_size", 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	return vbox

func _on_show_civics_screen() -> void:
	EventBus.close_all_popups.emit()
	current_player = GameManager.human_player
	pending_changes.clear()
	_build_civics_list()
	show()

func _build_civics_list() -> void:
	civic_buttons.clear()

	for category in CivicsSystem.CIVIC_CATEGORIES:
		var container = category_containers[category]

		# Clear existing civic buttons (keep header + separator)
		for child in container.get_children():
			if child is Button:
				child.queue_free()

		# Add civic buttons
		var civics = DataManager.get_civics_by_category(category)
		for civic_id in civics:
			var button = _create_civic_button(civic_id)
			container.add_child(button)
			civic_buttons[civic_id] = button

	_update_civic_states()
	_update_confirm_button()

func _create_civic_button(civic_id: String) -> Button:
	var civic = DataManager.get_civic(civic_id)
	var button = Button.new()
	button.text = civic.get("name", civic_id)
	button.custom_minimum_size = Vector2(150, 35)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.pressed.connect(_on_civic_button_pressed.bind(civic_id))
	button.mouse_entered.connect(_on_civic_hovered.bind(civic_id))
	return button

func _update_civic_states() -> void:
	if current_player == null:
		return

	for civic_id in civic_buttons:
		var button = civic_buttons[civic_id]
		var civic = DataManager.get_civic(civic_id)
		var category = civic.get("category", "")

		var is_current = current_player.civics.get(category, "") == civic_id
		var is_pending = pending_changes.get(category, "") == civic_id
		var can_adopt = CivicsSystem.can_adopt_civic(current_player, civic_id)

		# Update button text with current marker
		var base_name = civic.get("name", civic_id)
		if is_current and not is_pending:
			button.text = base_name + " (current)"
		elif is_pending:
			button.text = base_name + " -> new"
		else:
			button.text = base_name

		# Set button style
		var style = StyleBoxFlat.new()
		style.set_corner_radius_all(4)

		if is_pending:
			style.bg_color = PENDING_COLOR
			style.border_color = Color(0.6, 0.6, 0.3)
			button.disabled = false
		elif is_current:
			style.bg_color = CURRENT_COLOR
			style.border_color = Color(0.3, 0.5, 0.6)
			button.disabled = false
		elif can_adopt:
			style.bg_color = AVAILABLE_COLOR
			style.border_color = Color(0.3, 0.3, 0.4)
			button.disabled = false
		else:
			style.bg_color = UNAVAILABLE_COLOR
			style.border_color = Color(0.2, 0.2, 0.2)
			button.disabled = true

		style.set_border_width_all(1)
		button.add_theme_stylebox_override("normal", style)

		var hover_style = style.duplicate()
		hover_style.bg_color = style.bg_color.lightened(0.15)
		button.add_theme_stylebox_override("hover", hover_style)

func _on_civic_button_pressed(civic_id: String) -> void:
	var civic = DataManager.get_civic(civic_id)
	var category = civic.get("category", "")
	if category == "":
		return

	var current_civic = current_player.civics.get(category, "")
	if current_civic == civic_id:
		# Cancel pending change for this category
		pending_changes.erase(category)
	elif CivicsSystem.can_adopt_civic(current_player, civic_id):
		pending_changes[category] = civic_id

	_update_civic_states()
	_update_confirm_button()

func _on_civic_hovered(civic_id: String) -> void:
	var civic = DataManager.get_civic(civic_id)
	_update_info_panel(civic_id, civic)

func _update_info_panel(civic_id: String, civic: Dictionary) -> void:
	var text = "[b]%s[/b]\n" % civic.get("name", civic_id)

	# Required tech
	var required_tech = civic.get("required_tech", "")
	if required_tech != "":
		var tech_name = DataManager.get_tech(required_tech).get("name", required_tech)
		var has_tech = current_player.has_tech(required_tech) if current_player else false
		var color = "green" if has_tech else "red"
		text += "[color=%s]Requires: %s[/color]\n" % [color, tech_name]
	else:
		text += "[color=gray]No technology required[/color]\n"

	# Upkeep
	var upkeep = civic.get("upkeep", "none")
	text += "Upkeep: %s\n" % upkeep.capitalize()

	# Description
	var desc = civic.get("description", "")
	if desc != "":
		text += "\n%s\n" % desc

	# Effects
	var effects = civic.get("effects", {})
	if not effects.is_empty():
		text += "\n[b]Effects:[/b]\n"
		for effect_key in effects:
			if effect_key == "anarchy_length":
				continue
			var value = effects[effect_key]
			var effect_text = _format_effect(effect_key, value)
			if effect_text != "":
				text += "  - %s\n" % effect_text

	info_label.text = text

func _format_effect(key: String, value) -> String:
	match key:
		"happy_per_military_unit":
			return "+%d happiness per military unit in city" % value
		"largest_city_happiness":
			return "+%d happiness in 5 largest cities" % value
		"specialist_commerce_bonus":
			return "+%d research per specialist" % value
		"military_production_modifier":
			return "+%d%% military unit production" % value
		"war_weariness_modifier":
			return "%d%% war weariness" % value
		"town_commerce_bonus":
			return "+%d commerce from towns" % value
		"can_hurry_with_gold":
			return "Can hurry production with gold" if value else ""
		"can_hurry_with_population":
			return "Can sacrifice population to hurry production" if value else ""
		"free_unit_experience":
			return "+%d experience for new military units" % value
		"capital_production_modifier":
			return "+%d%% production in capital" % value
		"capital_commerce_modifier":
			return "+%d%% commerce in capital" % value
		"culture_modifier":
			return "+%d%% culture in all cities" % value
		"worker_speed_modifier":
			return "+%d%% worker build speed" % value
		"unlimited_artist_slots", "unlimited_scientist_slots", "unlimited_merchant_slots":
			return "Unlimited %s specialists" % key.replace("unlimited_", "").replace("_slots", "")
		"cottage_growth_modifier":
			return "+%d%% cottage growth" % value
		"no_foreign_trade":
			return "No foreign trade routes" if value else ""
		"free_specialist_per_city":
			return "+%d free specialist in each city" % value
		"trade_route_modifier":
			return "+%d%% trade route yield" % value
		"no_distance_maintenance":
			return "No distance maintenance" if value else ""
		"no_corporations":
			return "Corporations disabled" if value else ""
		"health_per_city":
			return "+%d health per city" % value
		"happiness_per_religion":
			return "+%d happiness per religion in city" % value
		"great_people_modifier":
			return "+%d%% great people birth rate" % value
		"military_unit_maintenance":
			return "+%d%% military unit maintenance" % value
		"requires_state_religion":
			return "Requires state religion" if value else ""
		"no_non_state_religion_spread":
			return "Non-state religions cannot spread" if value else ""
		"no_state_religion":
			return "Cannot have state religion" if value else ""
		"state_religion_building_production":
			return "+%d%% production for religious buildings" % value
		"missionary_build_speed":
			return "+%d%% missionary build speed" % value
		"state_religion_free_experience":
			return "+%d XP for units in state religion cities" % value
		_:
			if value is bool:
				return "%s: %s" % [key.capitalize().replace("_", " "), "Yes" if value else "No"]
			return "%s: %s" % [key.capitalize().replace("_", " "), str(value)]

func _update_confirm_button() -> void:
	var has_changes = not pending_changes.is_empty()
	confirm_button.disabled = not has_changes

	if has_changes and current_player:
		var anarchy_turns = CivicsSystem._calculate_anarchy_turns(current_player)
		if anarchy_turns > 0:
			anarchy_label.text = "Warning: %d turn(s) of anarchy!" % anarchy_turns
			anarchy_label.show()
		else:
			anarchy_label.text = "No anarchy (Spiritual trait)"
			anarchy_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
			anarchy_label.show()
	else:
		anarchy_label.hide()

func _on_confirm_pressed() -> void:
	if current_player == null or pending_changes.is_empty():
		return

	CivicsSystem.change_civics(current_player, pending_changes)
	pending_changes.clear()

	_update_civic_states()
	_update_confirm_button()
	EventBus.notification_added.emit("Civics changed!", "civics")

func _on_close_pressed() -> void:
	pending_changes.clear()
	hide()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
