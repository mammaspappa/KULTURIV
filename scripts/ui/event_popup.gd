extends Control
## Popup dialog for displaying random events and player choices.

signal choice_made(event_data, choice_index)

# UI Elements
var panel: PanelContainer
var title_label: Label
var description_label: RichTextLabel
var choices_container: VBoxContainer
var category_icon: TextureRect

# Current event
var current_event: Dictionary = {}

# Category colors
const CATEGORY_COLORS = {
	"natural_disaster": Color.ORANGE_RED,
	"disaster": Color.RED,
	"discovery": Color.GOLD,
	"economic": Color.GREEN,
	"cultural": Color.PURPLE,
	"science": Color.CYAN,
	"military": Color.DARK_RED,
	"diplomatic": Color.MEDIUM_PURPLE,
	"growth": Color.LIGHT_GREEN,
	"unrest": Color.DARK_ORANGE,
	"religious": Color.MEDIUM_AQUAMARINE,
	"prosperity": Color.YELLOW,
	"espionage": Color.SLATE_GRAY,
	"immigration": Color.SKY_BLUE
}

func _ready() -> void:
	_build_ui()
	visible = false

	# Connect to event signals
	EventBus.random_event_triggered.connect(_on_event_triggered)

func _build_ui() -> void:
	# Semi-transparent background overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Main panel
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 300)
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.2, 0.95)
	panel_style.border_color = Color(0.4, 0.4, 0.5)
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 20
	panel_style.content_margin_right = 20
	panel_style.content_margin_top = 15
	panel_style.content_margin_bottom = 15
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	# Main VBox
	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 15)
	panel.add_child(main_vbox)

	# Header with category color bar
	var header_container = HBoxContainer.new()
	header_container.add_theme_constant_override("separation", 10)
	main_vbox.add_child(header_container)

	# Category color indicator
	category_icon = TextureRect.new()
	category_icon.custom_minimum_size = Vector2(8, 40)
	header_container.add_child(category_icon)

	# Title
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 22)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(title_label)

	# Separator
	var sep = HSeparator.new()
	main_vbox.add_child(sep)

	# Description
	description_label = RichTextLabel.new()
	description_label.bbcode_enabled = true
	description_label.fit_content = true
	description_label.custom_minimum_size = Vector2(0, 60)
	description_label.add_theme_font_size_override("normal_font_size", 16)
	main_vbox.add_child(description_label)

	# Choices container
	choices_container = VBoxContainer.new()
	choices_container.add_theme_constant_override("separation", 8)
	main_vbox.add_child(choices_container)

func _on_event_triggered(event_data: Dictionary) -> void:
	show_event(event_data)

func show_event(event_data: Dictionary) -> void:
	current_event = event_data

	# Set title with category color
	var category = event_data.get("category", "misc")
	var category_color = CATEGORY_COLORS.get(category, Color.WHITE)
	title_label.text = event_data.get("name", "Event")
	title_label.add_theme_color_override("font_color", category_color)

	# Update category indicator
	var indicator_style = StyleBoxFlat.new()
	indicator_style.bg_color = category_color
	var panel_node = PanelContainer.new()
	panel_node.add_theme_stylebox_override("panel", indicator_style)
	panel_node.custom_minimum_size = Vector2(8, 40)

	# Set description
	description_label.text = event_data.get("description", "Something has happened.")

	# Build choice buttons
	_build_choices(event_data.get("choices", []))

	visible = true

func _build_choices(choices: Array) -> void:
	# Clear existing
	for child in choices_container.get_children():
		child.queue_free()

	# Create button for each choice
	for i in range(choices.size()):
		var choice = choices[i]
		var button = Button.new()
		button.text = choice.get("text", "Option %d" % (i + 1))
		button.custom_minimum_size = Vector2(0, 40)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Style
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = Color(0.25, 0.25, 0.3)
		style_normal.corner_radius_top_left = 4
		style_normal.corner_radius_top_right = 4
		style_normal.corner_radius_bottom_left = 4
		style_normal.corner_radius_bottom_right = 4
		style_normal.content_margin_left = 10
		style_normal.content_margin_right = 10
		button.add_theme_stylebox_override("normal", style_normal)

		var style_hover = style_normal.duplicate()
		style_hover.bg_color = Color(0.35, 0.35, 0.45)
		button.add_theme_stylebox_override("hover", style_hover)

		var style_pressed = style_normal.duplicate()
		style_pressed.bg_color = Color(0.2, 0.2, 0.25)
		button.add_theme_stylebox_override("pressed", style_pressed)

		# Add effect preview tooltip
		var effects = choice.get("effects", {})
		var tooltip = _format_effects_tooltip(effects)
		if tooltip != "":
			button.tooltip_text = tooltip

		# Connect
		var choice_idx = i
		button.pressed.connect(func(): _on_choice_selected(choice_idx))

		choices_container.add_child(button)

func _format_effects_tooltip(effects: Dictionary) -> String:
	var lines = []

	for effect in effects:
		var value = effects[effect]
		match effect:
			"gold":
				lines.append("Gold: %+d" % value)
			"population":
				lines.append("Population: %+d" % value)
			"food_bonus":
				lines.append("Food: %+d" % value)
			"production_bonus":
				lines.append("Production: %+d" % value)
			"research_bonus":
				lines.append("Research: %+d" % value)
			"culture":
				lines.append("Culture: %+d" % value)
			"happiness":
				lines.append("Happiness: %+d" % value)
			"health":
				lines.append("Health: %+d" % value)
			"gold_per_turn":
				lines.append("Gold per turn: %+d" % value)
			"great_people_points":
				lines.append("Great People Points: %+d" % value)
			"remove_feature":
				lines.append("Removes: %s" % str(value).capitalize())
			"pillage_improvement":
				lines.append("Improvement destroyed")
			"revolt_chance":
				lines.append("Revolt risk: %d%%" % value)

	return "\n".join(lines)

func _on_choice_selected(choice_index: int) -> void:
	# Process the choice
	if EventsSystem:
		var result = EventsSystem.process_event_choice(current_event, choice_index)

		# Show result notification
		if result.success and not result.effects_applied.is_empty():
			var effects_text = ", ".join(result.effects_applied)
			EventBus.notification_added.emit(current_event.name + ": " + effects_text, "event")

	choice_made.emit(current_event, choice_index)
	visible = false
	current_event = {}

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			# Can't escape events - must choose
			pass
		# Number keys for quick selection
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			var idx = event.keycode - KEY_1
			if idx < current_event.get("choices", []).size():
				_on_choice_selected(idx)
				get_viewport().set_input_as_handled()
