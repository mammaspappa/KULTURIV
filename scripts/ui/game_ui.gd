extends Control
## Main game UI that shows information and controls.

# Top bar elements
@onready var turn_label: Label = $TopBar/HBoxContainer/TurnLabel
@onready var gold_label: Label = $TopBar/HBoxContainer/GoldLabel
@onready var science_label: Label = $TopBar/HBoxContainer/ScienceLabel
@onready var civ_label: Label = $TopBar/HBoxContainer/CivLabel

# Unit panel
@onready var unit_panel: Panel = $UnitPanel
@onready var unit_name_label: Label = $UnitPanel/VBoxContainer/UnitName
@onready var unit_strength_label: Label = $UnitPanel/VBoxContainer/UnitStrength
@onready var unit_movement_label: Label = $UnitPanel/VBoxContainer/UnitMovement
@onready var unit_health_bar: ProgressBar = $UnitPanel/VBoxContainer/UnitHealth
@onready var fortify_button: Button = $UnitPanel/VBoxContainer/ActionButtons/FortifyButton
@onready var skip_button: Button = $UnitPanel/VBoxContainer/ActionButtons/SkipButton

# Other elements
@onready var end_turn_button: Button = $EndTurnButton
@onready var tech_button: Button = $TopBar/HBoxContainer/TechButton
@onready var diplomacy_button: Button = $TopBar/HBoxContainer/DiplomacyButton

# State
var selected_unit = null  # Unit (untyped to avoid load-order issues)

# Notification system
var notifications: Array = []
var notification_container: VBoxContainer
const MAX_NOTIFICATIONS = 5
const NOTIFICATION_DURATION = 5.0

func _ready() -> void:
	# Connect signals
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.unit_selected.connect(_on_unit_selected)
	EventBus.unit_deselected.connect(_on_unit_deselected)
	EventBus.unit_moved.connect(_on_unit_moved)

	# Connect buttons
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if fortify_button:
		fortify_button.pressed.connect(_on_fortify_pressed)
	if skip_button:
		skip_button.pressed.connect(_on_skip_pressed)
	if tech_button:
		tech_button.pressed.connect(_on_tech_pressed)
	if diplomacy_button:
		diplomacy_button.pressed.connect(_on_diplomacy_pressed)

	# Initial state
	unit_panel.visible = false

	# Setup notification system
	_setup_notifications()

	# Initial UI update
	call_deferred("_update_top_bar")

func _process(delta: float) -> void:
	# Update unit panel if a unit is selected
	if selected_unit:
		_update_unit_panel()

	# Update notifications
	_update_notifications(delta)

func _on_turn_started(turn: int, player) -> void:
	if player == GameManager.human_player:
		_update_top_bar()

func _on_turn_ended(_turn: int, _player) -> void:
	pass

func _on_unit_selected(unit) -> void:
	if unit.player_owner == GameManager.human_player:
		selected_unit = unit
		unit_panel.visible = true
		_update_unit_panel()

func _on_unit_deselected(_unit) -> void:
	selected_unit = null
	unit_panel.visible = false

func _on_unit_moved(_unit, _from: Vector2i, _to: Vector2i) -> void:
	if selected_unit:
		_update_unit_panel()

func _on_end_turn_pressed() -> void:
	TurnManager.end_turn()

func _on_fortify_pressed() -> void:
	if selected_unit:
		selected_unit.fortify()
		_update_unit_panel()

func _on_skip_pressed() -> void:
	if selected_unit:
		selected_unit.skip_turn()
		_update_unit_panel()

func _on_tech_pressed() -> void:
	EventBus.show_tech_tree.emit()

func _on_diplomacy_pressed() -> void:
	EventBus.show_diplomacy_screen.emit()

func _update_top_bar() -> void:
	if not is_inside_tree():
		return

	# Turn info
	if turn_label:
		turn_label.text = "Turn %d - %s" % [TurnManager.current_turn, TurnManager.get_year_string()]

	var player = GameManager.human_player
	if player == null:
		return

	# Gold
	if gold_label:
		var gold_per_turn = player.gold_per_turn
		var sign = "+" if gold_per_turn >= 0 else ""
		gold_label.text = "Gold: %d (%s%d)" % [player.gold, sign, gold_per_turn]

	# Science
	if science_label:
		var research = player.current_research
		if research != "":
			var tech_data = DataManager.get_tech(research)
			var progress = player.research_progress
			var cost = int(DataManager.get_tech_cost(research) * GameManager.get_speed_multiplier())
			science_label.text = "%s: %d/%d" % [tech_data.get("name", research), progress, cost]
		else:
			science_label.text = "No Research"

	# Civilization
	if civ_label:
		var civ_data = DataManager.get_civ(player.civilization_id)
		civ_label.text = civ_data.get("name", "Unknown")

func _update_unit_panel() -> void:
	if selected_unit == null:
		return

	var unit_data = DataManager.get_unit(selected_unit.unit_id)

	# Name
	if unit_name_label:
		unit_name_label.text = unit_data.get("name", selected_unit.unit_id)

	# Strength
	if unit_strength_label:
		var strength = selected_unit.get_strength()
		unit_strength_label.text = "Strength: %.1f" % strength

	# Movement
	if unit_movement_label:
		var base_move = selected_unit.get_base_movement()
		unit_movement_label.text = "Movement: %.1f/%d" % [selected_unit.movement_remaining, base_move]

	# Health
	if unit_health_bar:
		unit_health_bar.value = selected_unit.health
		unit_health_bar.max_value = selected_unit.max_health

	# Button states
	if fortify_button:
		fortify_button.disabled = selected_unit.has_acted or selected_unit.get_strength() <= 0
	if skip_button:
		skip_button.disabled = selected_unit.has_acted

# Notification system
func _setup_notifications() -> void:
	# Create notification container
	notification_container = VBoxContainer.new()
	notification_container.name = "NotificationContainer"
	notification_container.position = Vector2(10, 50)
	notification_container.custom_minimum_size = Vector2(350, 200)
	notification_container.add_theme_constant_override("separation", 5)
	add_child(notification_container)

	# Connect notification signals
	_connect_notification_signals()

func _connect_notification_signals() -> void:
	EventBus.research_completed.connect(_on_research_completed)
	EventBus.city_grew.connect(_on_city_grew)
	EventBus.city_production_completed.connect(_on_city_production_completed)
	EventBus.unit_destroyed.connect(_on_unit_destroyed)
	EventBus.combat_ended.connect(_on_combat_ended)
	EventBus.tile_improved.connect(_on_tile_improved_notification)
	EventBus.game_saved.connect(_on_game_saved)
	EventBus.game_loaded.connect(_on_game_loaded)
	EventBus.first_contact.connect(_on_first_contact)
	EventBus.great_person_born.connect(_on_great_person_born)
	EventBus.religion_founded.connect(_on_religion_founded)
	EventBus.war_declared.connect(_on_war_declared)
	EventBus.peace_declared.connect(_on_peace_declared)

func _on_research_completed(player, tech: String) -> void:
	if player == GameManager.human_player:
		var tech_data = DataManager.get_tech(tech)
		_add_notification("Research completed: %s" % tech_data.get("name", tech), "tech")

func _on_city_grew(city, pop: int) -> void:
	if city.player_owner == GameManager.human_player:
		_add_notification("%s grew to size %d" % [city.city_name, pop], "city")

func _on_city_production_completed(city, item: String) -> void:
	if city.player_owner == GameManager.human_player:
		var item_name = item
		var unit_data = DataManager.get_unit(item)
		if not unit_data.is_empty():
			item_name = unit_data.get("name", item)
		else:
			var building_data = DataManager.get_building(item)
			if not building_data.is_empty():
				item_name = building_data.get("name", item)
		_add_notification("%s completed: %s" % [city.city_name, item_name], "production")

func _on_unit_destroyed(unit) -> void:
	if unit.player_owner == GameManager.human_player:
		var unit_data = DataManager.get_unit(unit.unit_id)
		_add_notification("Unit lost: %s" % unit_data.get("name", unit.unit_id), "combat")

func _on_combat_ended(winner, loser) -> void:
	if winner.player_owner == GameManager.human_player:
		var loser_data = DataManager.get_unit(loser.unit_id)
		_add_notification("Victory! Defeated %s" % loser_data.get("name", loser.unit_id), "combat")

func _on_tile_improved_notification(pos: Vector2i, improvement: String) -> void:
	# Only notify for human player's improvements
	var tile = GameManager.hex_grid.get_tile(pos) if GameManager.hex_grid else null
	if tile and tile.tile_owner == GameManager.human_player:
		var imp_name = improvement.replace("_", " ").capitalize()
		_add_notification("%s completed" % imp_name, "improvement")

func _on_game_saved() -> void:
	_add_notification("Game saved", "system")

func _on_game_loaded() -> void:
	_add_notification("Game loaded", "system")

func _on_first_contact(player1, player2) -> void:
	if player1 == GameManager.human_player:
		var civ_data = DataManager.get_civ(player2.civilization_id)
		_add_notification("Met the %s!" % civ_data.get("name", "Unknown"), "diplomacy")
	elif player2 == GameManager.human_player:
		var civ_data = DataManager.get_civ(player1.civilization_id)
		_add_notification("Met the %s!" % civ_data.get("name", "Unknown"), "diplomacy")

func _on_great_person_born(city, gp_type: String) -> void:
	if city.player_owner == GameManager.human_player:
		var gp_name = "Great " + gp_type.capitalize()
		_add_notification("%s born in %s!" % [gp_name, city.city_name], "great_person")

func _on_religion_founded(player, religion_id: String, city) -> void:
	var rel_data = DataManager.get_religion(religion_id)
	var rel_name = rel_data.get("name", religion_id)
	if player == GameManager.human_player:
		_add_notification("%s founded in %s!" % [rel_name, city.city_name], "religion")
	else:
		var civ_data = DataManager.get_civ(player.civilization_id)
		_add_notification("%s founded %s" % [civ_data.get("name", "Unknown"), rel_name], "religion")

func _on_war_declared(aggressor, target) -> void:
	if target == GameManager.human_player:
		var civ_data = DataManager.get_civ(aggressor.civilization_id)
		_add_notification("%s declared war!" % civ_data.get("name", "Unknown"), "diplomacy")
	elif aggressor == GameManager.human_player:
		pass  # Player initiated, no notification needed

func _on_peace_declared(player1, player2) -> void:
	var other = player2 if player1 == GameManager.human_player else player1
	if player1 == GameManager.human_player or player2 == GameManager.human_player:
		var civ_data = DataManager.get_civ(other.civilization_id)
		_add_notification("Peace with %s" % civ_data.get("name", "Unknown"), "diplomacy")

func _add_notification(message: String, type: String) -> void:
	var notif = {
		"message": message,
		"type": type,
		"time": NOTIFICATION_DURATION
	}
	notifications.append(notif)

	# Limit notifications
	while notifications.size() > MAX_NOTIFICATIONS:
		notifications.pop_front()

	_rebuild_notification_display()

func _update_notifications(delta: float) -> void:
	var expired = []
	for notif in notifications:
		notif.time -= delta
		if notif.time <= 0:
			expired.append(notif)

	for notif in expired:
		notifications.erase(notif)

	if not expired.is_empty():
		_rebuild_notification_display()

	# Update opacity for fading
	for i in range(notification_container.get_child_count()):
		var label = notification_container.get_child(i)
		if i < notifications.size():
			var alpha = min(1.0, notifications[i].time)
			label.modulate.a = alpha

func _rebuild_notification_display() -> void:
	# Clear existing
	for child in notification_container.get_children():
		child.queue_free()

	# Create labels for each notification
	for notif in notifications:
		var label = Label.new()
		label.text = notif.message
		label.add_theme_font_size_override("font_size", 14)

		# Color based on type
		var color = Color.WHITE
		match notif.type:
			"tech":
				color = Color.CYAN
			"city":
				color = Color.GREEN
			"production":
				color = Color.YELLOW
			"combat":
				color = Color.ORANGE_RED
			"improvement":
				color = Color.LIGHT_GREEN
			"system":
				color = Color.LIGHT_GRAY
			"diplomacy":
				color = Color.MEDIUM_PURPLE
			"great_person":
				color = Color.GOLD
			"religion":
				color = Color.MEDIUM_AQUAMARINE

		label.add_theme_color_override("font_color", color)

		# Add background
		var panel = Panel.new()
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0, 0, 0, 0.7)
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.content_margin_left = 8
		style.content_margin_right = 8
		style.content_margin_top = 4
		style.content_margin_bottom = 4
		panel.add_theme_stylebox_override("panel", style)
		panel.add_child(label)

		notification_container.add_child(panel)
