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
var panel: Panel
var title_label: Label
var close_button: Button
var confirm_button: Button
var category_containers: Dictionary = {}  # category -> VBoxContainer
var civic_buttons: Dictionary = {}  # civic_id -> Button
var info_panel: Panel
var info_label: RichTextLabel
var anarchy_label: Label

# Colors
const BG_COLOR = Color(0.08, 0.08, 0.12, 1.0)
const SELECTED_COLOR = Color(0.3, 0.5, 0.3)
const AVAILABLE_COLOR = Color(0.25, 0.25, 0.35)
const UNAVAILABLE_COLOR = Color(0.15, 0.15, 0.15)
const CURRENT_COLOR = Color(0.2, 0.4, 0.5)
const PENDING_COLOR = Color(0.5, 0.5, 0.2)

func _ready() -> void:
	_create_ui()
	EventBus.show_civics_screen.connect(_on_show_civics_screen)
	EventBus.hide_civics_screen.connect(_on_close_pressed)
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
	title_label.text = "Civics"
	title_label.position = Vector2(20, 10)
	title_label.add_theme_font_size_override("font_size", 24)
	panel.add_child(title_label)

	# Close button
	close_button = Button.new()
	close_button.name = "CloseButton"
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(30, 30)
	close_button.pressed.connect(_on_close_pressed)
	panel.add_child(close_button)

	# Confirm button
	confirm_button = Button.new()
	confirm_button.name = "ConfirmButton"
	confirm_button.text = "Confirm Changes"
	confirm_button.custom_minimum_size = Vector2(150, 40)
	confirm_button.pressed.connect(_on_confirm_pressed)
	confirm_button.disabled = true
	panel.add_child(confirm_button)

	# Anarchy warning label
	anarchy_label = Label.new()
	anarchy_label.name = "AnarchyLabel"
	anarchy_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	anarchy_label.add_theme_font_size_override("font_size", 14)
	panel.add_child(anarchy_label)

	# Create category containers (horizontal layout)
	var categories_container = HBoxContainer.new()
	categories_container.name = "Categories"
	categories_container.position = Vector2(20, 60)
	categories_container.add_theme_constant_override("separation", 15)
	panel.add_child(categories_container)

	for category in CivicsSystem.CIVIC_CATEGORIES:
		var category_box = _create_category_container(category)
		categories_container.add_child(category_box)
		category_containers[category] = category_box

	# Info panel (bottom)
	info_panel = Panel.new()
	info_panel.name = "InfoPanel"
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.12, 0.12, 0.18)
	info_panel.add_theme_stylebox_override("panel", info_style)
	panel.add_child(info_panel)

	info_label = RichTextLabel.new()
	info_label.name = "InfoLabel"
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_panel.add_child(info_label)

func _create_category_container(category: String) -> VBoxContainer:
	var vbox = VBoxContainer.new()
	vbox.name = category.capitalize() + "Category"
	vbox.custom_minimum_size = Vector2(160, 0)

	# Category header
	var header = Label.new()
	header.name = "Header"
	header.text = CATEGORY_NAMES.get(category, category.capitalize())
	header.add_theme_font_size_override("font_size", 16)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	# Separator
	var sep = HSeparator.new()
	vbox.add_child(sep)

	return vbox

func _on_show_civics_screen() -> void:
	current_player = GameManager.human_player
	pending_changes.clear()
	_build_civics_list()
	_update_layout()
	show()

func _build_civics_list() -> void:
	civic_buttons.clear()

	for category in CivicsSystem.CIVIC_CATEGORIES:
		var container = category_containers[category]

		# Clear existing civic buttons
		for child in container.get_children():
			if child is Button:
				child.queue_free()

		# Add civic buttons
		var civics = DataManager.get_civics_by_category(category)
		for civic_id in civics:
			var button = _create_civic_button(civic_id, category)
			container.add_child(button)
			civic_buttons[civic_id] = button

	_update_civic_states()

func _create_civic_button(civic_id: String, _category: String) -> Button:
	var civic = DataManager.get_civic(civic_id)
	var button = Button.new()
	button.name = civic_id
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

		# Determine state
		var is_current = current_player.civics.get(category, "") == civic_id
		var is_pending = pending_changes.get(category, "") == civic_id
		var can_adopt = CivicsSystem.can_adopt_civic(current_player, civic_id)

		# Set button style
		var style = StyleBoxFlat.new()
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4

		if is_pending:
			style.bg_color = PENDING_COLOR
			button.disabled = false
		elif is_current:
			style.bg_color = CURRENT_COLOR
			button.disabled = false
		elif can_adopt:
			style.bg_color = AVAILABLE_COLOR
			button.disabled = false
		else:
			style.bg_color = UNAVAILABLE_COLOR
			button.disabled = true

		button.add_theme_stylebox_override("normal", style)
		button.add_theme_stylebox_override("hover", style)

func _on_civic_button_pressed(civic_id: String) -> void:
	var civic = DataManager.get_civic(civic_id)
	var category = civic.get("category", "")

	if category == "":
		return

	# Check if already current
	var current_civic = current_player.civics.get(category, "")
	if current_civic == civic_id:
		# Remove from pending if it was there
		pending_changes.erase(category)
	elif CivicsSystem.can_adopt_civic(current_player, civic_id):
		# Add to pending changes
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
	text += "\n%s\n" % civic.get("description", "")

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
			anarchy_label.text = "Warning: Changing civics will cause %d turn(s) of anarchy!" % anarchy_turns
			anarchy_label.show()
		else:
			anarchy_label.text = "No anarchy (Spiritual trait)"
			anarchy_label.show()
	else:
		anarchy_label.hide()

func _on_confirm_pressed() -> void:
	if current_player == null or pending_changes.is_empty():
		return

	# Apply civic changes
	CivicsSystem.change_civics(current_player, pending_changes)
	pending_changes.clear()

	# Refresh UI
	_update_civic_states()
	_update_confirm_button()

	# Notify
	EventBus.notification_added.emit("Civics changed!", "civics")

func _on_close_pressed() -> void:
	pending_changes.clear()
	hide()
	EventBus.hide_civics_screen.emit()

func _update_layout() -> void:
	if panel == null:
		return

	var panel_size = panel.size

	# Position close button
	close_button.position = Vector2(panel_size.x - 50, 10)

	# Position confirm button
	confirm_button.position = Vector2(panel_size.x - 180, panel_size.y - 60)

	# Position anarchy label
	anarchy_label.position = Vector2(20, panel_size.y - 55)

	# Info panel at bottom
	info_panel.position = Vector2(20, panel_size.y - 180)
	info_panel.size = Vector2(panel_size.x - 40, 110)
	info_label.position = Vector2(10, 10)
	info_label.size = Vector2(info_panel.size.x - 20, info_panel.size.y - 20)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_visible():
		_update_layout()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_close_pressed()
			get_viewport().set_input_as_handled()
