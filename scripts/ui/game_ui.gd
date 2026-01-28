extends Control
## Main game UI that shows information and controls.

# Top bar elements
@onready var turn_label: Label = $TopBar/HBoxContainer/TurnLabel
@onready var gold_label: Label = $TopBar/HBoxContainer/GoldLabel
@onready var science_label: Label = $TopBar/HBoxContainer/ScienceLabel
@onready var science_rate_slider: HSlider = $TopBar/HBoxContainer/ScienceRateContainer/ScienceRateSlider
@onready var science_rate_value: Label = $TopBar/HBoxContainer/ScienceRateContainer/ScienceRateValue
@onready var civ_label: Label = $TopBar/HBoxContainer/CivLabel

# Unit panel
@onready var unit_panel: Panel = $UnitPanel
@onready var unit_name_label: Label = $UnitPanel/VBoxContainer/UnitName
@onready var unit_strength_label: Label = $UnitPanel/VBoxContainer/UnitStrength
@onready var unit_movement_label: Label = $UnitPanel/VBoxContainer/UnitMovement
@onready var unit_health_bar: ProgressBar = $UnitPanel/VBoxContainer/UnitHealth
@onready var fortify_button: Button = $UnitPanel/VBoxContainer/ActionButtons/FortifyButton
@onready var skip_button: Button = $UnitPanel/VBoxContainer/ActionButtons/SkipButton

# Worker actions
@onready var worker_actions: VBoxContainer = $UnitPanel/VBoxContainer/WorkerActions
@onready var worker_buttons_container: GridContainer = $UnitPanel/VBoxContainer/WorkerActions/WorkerButtonsContainer

# Other elements
@onready var end_turn_button: Button = $EndTurnButton
@onready var tech_button: Button = $TopBar/HBoxContainer/TechButton
@onready var civics_button: Button = $TopBar/HBoxContainer/CivicsButton
@onready var diplomacy_button: Button = $TopBar/HBoxContainer/DiplomacyButton
@onready var espionage_button: Button = $TopBar/HBoxContainer/EspionageButton
@onready var voting_button: Button = $TopBar/HBoxContainer/VotingButton
@onready var spaceship_button: Button = $TopBar/HBoxContainer/SpaceshipButton

# State
var selected_unit = null  # Unit (untyped to avoid load-order issues)
var worker_actions_dirty: bool = true  # Flag to track when worker actions need updating
var last_unit_position: Vector2i = Vector2i.ZERO
var last_unit_acted: bool = false
var last_unit_order: int = -1

# Unit cycling state
var skipped_units_this_turn: Array = []  # Units that have been skipped, won't cycle to them

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
	EventBus.unit_action_completed.connect(_on_unit_action_completed)
	EventBus.unit_movement_finished.connect(_on_unit_movement_finished)
	EventBus.cycle_to_next_unit.connect(_cycle_to_next_unit)

	# Connect buttons
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if fortify_button:
		fortify_button.pressed.connect(_on_fortify_pressed)
	if skip_button:
		skip_button.pressed.connect(_on_skip_pressed)
	if tech_button:
		tech_button.pressed.connect(_on_tech_pressed)
	if civics_button:
		civics_button.pressed.connect(_on_civics_pressed)
	if diplomacy_button:
		diplomacy_button.pressed.connect(_on_diplomacy_pressed)
	if espionage_button:
		espionage_button.pressed.connect(_on_espionage_pressed)
	if voting_button:
		voting_button.pressed.connect(_on_voting_pressed)
	if spaceship_button:
		spaceship_button.pressed.connect(_on_spaceship_pressed)
	if science_rate_slider:
		science_rate_slider.value_changed.connect(_on_science_rate_changed)
		# Initialize slider to player's current science rate
		if GameManager and GameManager.human_player:
			science_rate_slider.value = GameManager.human_player.science_rate * 100

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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("open_civics"):
		EventBus.show_civics_screen.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_diplomacy"):
		EventBus.show_diplomacy_screen.emit()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_E:
				EventBus.show_espionage_screen.emit()
				get_viewport().set_input_as_handled()
			KEY_U:
				EventBus.show_voting_screen.emit()
				get_viewport().set_input_as_handled()
			KEY_P:
				EventBus.show_spaceship_screen.emit()
				get_viewport().set_input_as_handled()
			KEY_T:
				EventBus.show_tech_tree.emit()
				get_viewport().set_input_as_handled()
			KEY_R:
				_try_worker_action("road")
				get_viewport().set_input_as_handled()
			KEY_M:
				_try_worker_action("mine")
				get_viewport().set_input_as_handled()
			KEY_I:
				_try_worker_action("farm")
				get_viewport().set_input_as_handled()
			KEY_O:
				_try_worker_action("cottage")
				get_viewport().set_input_as_handled()
			KEY_A:
				_try_automate_worker()
				get_viewport().set_input_as_handled()
			KEY_TAB:
				# Cycle to next unit that needs orders
				_cycle_to_next_unit()
				get_viewport().set_input_as_handled()
			KEY_PERIOD:
				# Skip current unit and cycle to next
				if selected_unit and selected_unit.player_owner == GameManager.human_player:
					selected_unit.skip_turn()
				get_viewport().set_input_as_handled()

func _on_turn_started(turn: int, player) -> void:
	if player == GameManager.human_player:
		_update_top_bar()
		# Clear skipped units list at start of turn
		skipped_units_this_turn.clear()
		# Auto-select first unit needing orders
		call_deferred("_cycle_to_next_unit")

func _on_turn_ended(_turn: int, _player) -> void:
	pass

func _on_unit_selected(unit) -> void:
	if unit.player_owner == GameManager.human_player:
		selected_unit = unit
		unit_panel.visible = true
		worker_actions_dirty = true  # Force refresh of worker buttons
		_update_unit_panel()

func _on_unit_deselected(_unit) -> void:
	selected_unit = null
	unit_panel.visible = false

func _on_unit_moved(_unit, _from: Vector2i, _to: Vector2i) -> void:
	if selected_unit:
		_update_unit_panel()

## Called when a unit completes an action (fortify, skip, sleep)
func _on_unit_action_completed(unit) -> void:
	if unit == selected_unit and unit.player_owner == GameManager.human_player:
		# Track skipped units so we don't cycle back to them
		if unit not in skipped_units_this_turn:
			skipped_units_this_turn.append(unit)
		# Cycle to next unit after a brief delay
		call_deferred("_cycle_to_next_unit")

## Called when a unit runs out of movement points
func _on_unit_movement_finished(unit) -> void:
	if unit == selected_unit and unit.player_owner == GameManager.human_player:
		# Cycle to next unit after movement is done
		call_deferred("_cycle_to_next_unit")

## Find and select the next unit that needs orders
func _cycle_to_next_unit() -> void:
	var player = GameManager.human_player
	if player == null:
		return

	var best_unit = null
	var best_distance = INF

	# Reference position: current selected unit or camera position
	var ref_pos = Vector2i.ZERO
	if selected_unit:
		ref_pos = selected_unit.grid_position
	elif GameManager.game_world and GameManager.game_world.has_node("Camera"):
		var camera = GameManager.game_world.get_node("Camera")
		ref_pos = GridUtils.pixel_to_grid(camera.position)

	# Find units that need orders
	for unit in player.units:
		if unit == null or not is_instance_valid(unit):
			continue

		# Skip units that have already been skipped this turn
		if unit in skipped_units_this_turn:
			continue

		# Skip units that have already acted or have no movement
		if unit.has_acted or unit.movement_remaining <= 0:
			continue

		# Skip units with active orders (fortified, sleeping, automating)
		if unit.current_order in [unit.UnitOrder.FORTIFY, unit.UnitOrder.SLEEP, unit.UnitOrder.BUILD, unit.UnitOrder.AUTOMATE]:
			continue

		# Skip units currently moving
		if unit.is_moving:
			continue

		# Calculate distance from reference position
		var dist = GridUtils.chebyshev_distance(ref_pos, unit.grid_position)
		if dist < best_distance:
			best_distance = dist
			best_unit = unit

	if best_unit:
		# Select the unit
		_select_unit(best_unit)
	else:
		# No units need orders - deselect current
		if selected_unit:
			EventBus.unit_deselected.emit(selected_unit)

## Select a unit and center camera on it
func _select_unit(unit) -> void:
	# Deselect previous unit
	if selected_unit and selected_unit != unit:
		selected_unit.is_selected = false
		selected_unit.update_visual()

	# Select new unit
	unit.is_selected = true
	unit.update_visual()
	selected_unit = unit
	unit_panel.visible = true
	worker_actions_dirty = true
	_update_unit_panel()

	# Emit signal
	EventBus.unit_selected.emit(unit)

	# Center camera on unit
	_center_camera_on_unit(unit)

## Center the camera on a unit
func _center_camera_on_unit(unit) -> void:
	if GameManager.game_world == null:
		return

	var camera = GameManager.game_world.get_node_or_null("GameCamera")
	if camera and camera.has_method("center_on"):
		camera.center_on(unit.position)
	elif camera:
		camera.position = unit.position

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

func _on_civics_pressed() -> void:
	EventBus.show_civics_screen.emit()

func _on_diplomacy_pressed() -> void:
	EventBus.show_diplomacy_screen.emit()

func _on_espionage_pressed() -> void:
	EventBus.show_espionage_screen.emit()

func _on_voting_pressed() -> void:
	EventBus.show_voting_screen.emit()

func _on_spaceship_pressed() -> void:
	EventBus.show_spaceship_screen.emit()

func _on_science_rate_changed(value: float) -> void:
	if GameManager and GameManager.human_player:
		# Convert 0-100 slider value to 0.0-1.0 rate
		GameManager.human_player.science_rate = value / 100.0
		# Update the percentage label
		if science_rate_value:
			science_rate_value.text = "%d%%" % int(value)
		# Recalculate all city yields to reflect the new rate
		for city in GameManager.human_player.cities:
			city.calculate_yields()
		# Update the top bar to show new science/gold values
		_update_top_bar()

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
		var science_output = player.get_research_output()
		if research != "":
			var tech_data = DataManager.get_tech(research)
			var progress = player.research_progress
			var cost = int(DataManager.get_tech_cost(research) * GameManager.get_speed_multiplier())
			var turns_left = ceili((cost - progress) / max(science_output, 1)) if science_output > 0 else 999
			science_label.text = "%s: %d/%d (+%d, %d turns)" % [tech_data.get("name", research), progress, cost, science_output, turns_left]
		else:
			science_label.text = "No Research (+%d)" % science_output

	# Update science rate slider and label
	if science_rate_slider and science_rate_value:
		science_rate_slider.value = player.science_rate * 100
		science_rate_value.text = "%d%%" % int(player.science_rate * 100)

	# Civilization
	if civ_label:
		var civ_data = DataManager.get_civ(player.civilization_id)
		civ_label.text = civ_data.get("name", "Unknown")

func _update_unit_panel() -> void:
	if selected_unit == null:
		return

	var unit_data = DataManager.get_unit(selected_unit.unit_id)

	# Name (include build status if building)
	if unit_name_label:
		var name_text = unit_data.get("name", selected_unit.unit_id)
		if selected_unit.current_order == selected_unit.UnitOrder.BUILD and selected_unit.order_target_improvement != "":
			var remaining = ImprovementSystem.get_remaining_turns(selected_unit)
			var imp_name = selected_unit.order_target_improvement.replace("_", " ").capitalize()
			name_text += " (Building %s: %d turns)" % [imp_name, remaining]
		unit_name_label.text = name_text

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

	# Only update worker actions when state changes
	var current_order = selected_unit.current_order
	if worker_actions_dirty or last_unit_position != selected_unit.grid_position or last_unit_acted != selected_unit.has_acted or last_unit_order != current_order:
		_update_worker_actions()
		last_unit_position = selected_unit.grid_position
		last_unit_acted = selected_unit.has_acted
		last_unit_order = current_order
		worker_actions_dirty = false

func _update_worker_actions() -> void:
	if worker_actions == null or worker_buttons_container == null:
		return

	# Clear existing buttons
	for child in worker_buttons_container.get_children():
		child.queue_free()

	# Show for workers or units with special actions (missionaries, transports, etc.)
	var is_worker = selected_unit != null and selected_unit.can_build_improvements()
	var can_spread = selected_unit != null and selected_unit.can_spread_religion()
	var is_transport = selected_unit != null and selected_unit.is_transport()
	var is_loaded = selected_unit != null and selected_unit.is_loaded()

	if selected_unit == null or (not is_worker and not can_spread and not is_transport and not is_loaded):
		worker_actions.visible = false
		return

	worker_actions.visible = true

	# Handle transport loading/unloading
	if is_transport and not selected_unit.cargo.is_empty():
		var unload_button = Button.new()
		unload_button.text = "Unload (%d)" % selected_unit.cargo.size()
		unload_button.custom_minimum_size = Vector2(110, 30)
		unload_button.tooltip_text = "Unload all units from transport"
		unload_button.pressed.connect(_on_unload_pressed)
		# Check if can unload (must be adjacent to land)
		unload_button.disabled = not selected_unit.can_unload_unit(selected_unit.cargo[0]) if not selected_unit.cargo.is_empty() else true
		worker_buttons_container.add_child(unload_button)

	# Handle unit loading into transport
	if is_loaded:
		var disembark_button = Button.new()
		disembark_button.text = "Disembark"
		disembark_button.custom_minimum_size = Vector2(110, 30)
		disembark_button.tooltip_text = "Leave transport"
		disembark_button.pressed.connect(_on_disembark_pressed)
		disembark_button.disabled = not selected_unit.transport.can_unload_unit(selected_unit) if selected_unit.transport else true
		worker_buttons_container.add_child(disembark_button)

	# Check if land unit can load onto a transport at same position
	if not is_loaded and not is_transport and selected_unit != null:
		var available_transport = _find_transport_at_position(selected_unit.grid_position)
		if available_transport and available_transport.can_load_unit(selected_unit):
			var load_button = Button.new()
			load_button.text = "Load"
			load_button.custom_minimum_size = Vector2(110, 30)
			load_button.tooltip_text = "Load onto transport"
			load_button.pressed.connect(_on_load_pressed.bind(available_transport))
			worker_buttons_container.add_child(load_button)

	# Handle missionary spread religion action
	if can_spread:
		var spread_button = Button.new()
		spread_button.text = "Spread Religion"
		spread_button.custom_minimum_size = Vector2(110, 30)
		var religion_id = selected_unit.player_owner.state_religion if selected_unit.player_owner else ""
		var rel_data = DataManager.get_religion(religion_id) if religion_id != "" else {}
		var rel_name = rel_data.get("name", "Religion")
		spread_button.tooltip_text = "Spread %s to this city" % rel_name
		spread_button.pressed.connect(_on_spread_religion_pressed)
		worker_buttons_container.add_child(spread_button)

	# If not a worker, stop here (only show spread religion button)
	if not is_worker:
		return

	# Get tile at unit's position
	var tile = GameManager.hex_grid.get_tile(selected_unit.grid_position) if GameManager.hex_grid else null
	if tile == null:
		return

	# Check if automated - show stop automation button
	if selected_unit.current_order == selected_unit.UnitOrder.AUTOMATE:
		var stop_button = Button.new()
		stop_button.text = "Stop Automation"
		stop_button.custom_minimum_size = Vector2(110, 30)
		stop_button.pressed.connect(_on_stop_automation_pressed)
		worker_buttons_container.add_child(stop_button)
		return

	# Check if currently building - show cancel button
	if selected_unit.current_order == selected_unit.UnitOrder.BUILD:
		var cancel_button = Button.new()
		cancel_button.text = "Cancel"
		cancel_button.custom_minimum_size = Vector2(110, 30)
		cancel_button.pressed.connect(_on_cancel_build_pressed)
		worker_buttons_container.add_child(cancel_button)
		return

	# Can't build if unit has already acted
	if selected_unit.has_acted:
		var label = Label.new()
		label.text = "No actions remaining"
		label.add_theme_font_size_override("font_size", 12)
		worker_buttons_container.add_child(label)
		return

	var buttons_added = 0

	# Road button
	if ImprovementSystem.can_build_road(selected_unit, tile):
		var road_button = _create_worker_button("Road", "road", ImprovementSystem.get_build_time("road"))
		worker_buttons_container.add_child(road_button)
		buttons_added += 1

	# Railroad button
	if ImprovementSystem.can_build_railroad(selected_unit, tile):
		var railroad_button = _create_worker_button("Railroad", "railroad", ImprovementSystem.get_build_time("railroad"))
		worker_buttons_container.add_child(railroad_button)
		buttons_added += 1

	# Get available improvements for this tile
	var available_improvements = ImprovementSystem.get_available_improvements(selected_unit, tile)
	for imp_id in available_improvements:
		var imp_data = DataManager.get_improvement(imp_id)
		var imp_name = imp_data.get("name", imp_id.replace("_", " ").capitalize())
		var build_time = ImprovementSystem.get_build_time(imp_id)
		var button = _create_worker_button(imp_name, imp_id, build_time)
		worker_buttons_container.add_child(button)
		buttons_added += 1

	# Automate button (always available for workers)
	var automate_button = Button.new()
	automate_button.text = "Automate (A)"
	automate_button.custom_minimum_size = Vector2(110, 30)
	automate_button.tooltip_text = "Automate worker to build improvements"
	automate_button.pressed.connect(_on_automate_pressed)
	worker_buttons_container.add_child(automate_button)
	buttons_added += 1

	# Show message if no actions available
	if buttons_added == 0:
		var label = Label.new()
		label.text = "No improvements available"
		label.add_theme_font_size_override("font_size", 12)
		worker_buttons_container.add_child(label)

func _create_worker_button(display_name: String, improvement_id: String, turns: int) -> Button:
	var button = Button.new()
	button.text = "%s (%dt)" % [display_name, turns]
	button.custom_minimum_size = Vector2(110, 30)
	button.tooltip_text = "Build %s - %d turns" % [display_name, turns]
	button.pressed.connect(_on_worker_build_pressed.bind(improvement_id))
	return button

func _on_worker_build_pressed(improvement_id: String) -> void:
	if selected_unit == null or not selected_unit.can_build_improvements():
		return

	if improvement_id == "road":
		ImprovementSystem.start_build_road(selected_unit)
	elif improvement_id == "railroad":
		ImprovementSystem.start_build_railroad(selected_unit)
	else:
		ImprovementSystem.start_build(selected_unit, improvement_id)

	_update_unit_panel()

func _on_cancel_build_pressed() -> void:
	if selected_unit == null:
		return

	ImprovementSystem.cancel_build(selected_unit)
	_update_unit_panel()

func _on_spread_religion_pressed() -> void:
	if selected_unit == null:
		return

	if selected_unit.spread_religion():
		_add_notification("Religion spread successfully!", "religion")
		# Check if unit was consumed (died)
		if not is_instance_valid(selected_unit) or selected_unit.is_queued_for_deletion():
			selected_unit = null
			unit_panel.visible = false
		else:
			_update_unit_panel()
	else:
		_add_notification("Failed to spread religion", "warning")

func _on_automate_pressed() -> void:
	if selected_unit == null or not selected_unit.can_build_improvements():
		return

	selected_unit.automate()
	_add_notification("Worker automated", "system")
	_update_unit_panel()

func _on_unload_pressed() -> void:
	if selected_unit == null or not selected_unit.is_transport():
		return

	var count = selected_unit.unload_all()
	if count > 0:
		_add_notification("Unloaded %d unit(s)" % count, "system")
	_update_unit_panel()

func _on_disembark_pressed() -> void:
	if selected_unit == null or not selected_unit.is_loaded():
		return

	var transport = selected_unit.transport
	if transport and transport.unload_unit(selected_unit):
		_add_notification("Unit disembarked", "system")
	_update_unit_panel()

func _on_load_pressed(transport) -> void:
	if selected_unit == null or transport == null:
		return

	if transport.load_unit(selected_unit):
		_add_notification("Unit loaded onto transport", "system")
		# Deselect since unit is now hidden
		EventBus.unit_deselected.emit(selected_unit)
		selected_unit = null
		unit_panel.visible = false

func _find_transport_at_position(pos: Vector2i):
	if GameManager.human_player == null:
		return null
	for unit in GameManager.human_player.units:
		if unit.grid_position == pos and unit.is_transport():
			return unit
	return null

func _on_stop_automation_pressed() -> void:
	if selected_unit == null:
		return

	selected_unit.stop_automation()
	_add_notification("Automation stopped", "system")
	_update_unit_panel()

## Try to perform a worker action via keyboard shortcut
func _try_worker_action(action: String) -> void:
	if selected_unit == null or not selected_unit.can_build_improvements():
		return

	if selected_unit.has_acted:
		return

	var tile = GameManager.hex_grid.get_tile(selected_unit.grid_position) if GameManager.hex_grid else null
	if tile == null:
		return

	match action:
		"road":
			if ImprovementSystem.can_build_road(selected_unit, tile):
				ImprovementSystem.start_build_road(selected_unit)
				_update_unit_panel()
		"railroad":
			if ImprovementSystem.can_build_railroad(selected_unit, tile):
				ImprovementSystem.start_build_railroad(selected_unit)
				_update_unit_panel()
		_:
			# Other improvements (mine, farm, cottage, etc.)
			if ImprovementSystem.can_build(selected_unit, tile, action):
				ImprovementSystem.start_build(selected_unit, action)
				_update_unit_panel()

## Automate worker via keyboard shortcut
func _try_automate_worker() -> void:
	if selected_unit == null or not selected_unit.can_build_improvements():
		return

	if selected_unit.current_order == selected_unit.UnitOrder.AUTOMATE:
		selected_unit.stop_automation()
		_add_notification("Automation stopped", "system")
	else:
		selected_unit.automate()
		_add_notification("Worker automated", "system")
	_update_unit_panel()

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
	EventBus.civic_changed.connect(_on_civic_changed)
	EventBus.anarchy_started.connect(_on_anarchy_started)
	EventBus.anarchy_ended.connect(_on_anarchy_ended)
	EventBus.golden_age_started.connect(_on_golden_age_started)
	EventBus.golden_age_ended.connect(_on_golden_age_ended)
	EventBus.trade_accepted.connect(_on_trade_accepted)
	EventBus.trade_rejected.connect(_on_trade_rejected)
	EventBus.notification_added.connect(_on_notification_added)

func _on_notification_added(message: String, type: String) -> void:
	_add_notification(message, type)

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

func _on_civic_changed(player, category: String, civic_id: String) -> void:
	if player == GameManager.human_player:
		var civic_name = DataManager.get_civic_name(civic_id)
		_add_notification("Adopted %s (%s)" % [civic_name, category.capitalize()], "civics")

func _on_anarchy_started(player, turns: int) -> void:
	if player == GameManager.human_player:
		_add_notification("Anarchy! %d turn(s) of disorder" % turns, "civics")

func _on_anarchy_ended(player) -> void:
	if player == GameManager.human_player:
		_add_notification("Anarchy has ended", "civics")

func _on_golden_age_started(player) -> void:
	if player == GameManager.human_player:
		_add_notification("Golden Age has begun! (%d turns)" % player.golden_age_turns, "great_person")

func _on_golden_age_ended(player) -> void:
	if player == GameManager.human_player:
		_add_notification("Golden Age has ended", "great_person")

func _on_trade_accepted(from_player, to_player, _offer: Dictionary) -> void:
	if from_player == GameManager.human_player:
		var civ_data = DataManager.get_civ(to_player.civilization_id)
		_add_notification("Trade accepted by %s" % civ_data.get("name", "Unknown"), "diplomacy")
	elif to_player == GameManager.human_player:
		var civ_data = DataManager.get_civ(from_player.civilization_id)
		_add_notification("Accepted trade from %s" % civ_data.get("name", "Unknown"), "diplomacy")

func _on_trade_rejected(from_player, to_player) -> void:
	if from_player == GameManager.human_player:
		var civ_data = DataManager.get_civ(to_player.civilization_id)
		_add_notification("Trade rejected by %s" % civ_data.get("name", "Unknown"), "diplomacy")

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
			"civics":
				color = Color.SANDY_BROWN
			"espionage":
				color = Color.SLATE_GRAY
			"event":
				color = Color.ORANGE
			"vote":
				color = Color.LIGHT_BLUE
			"victory":
				color = Color.GOLD
			"warning":
				color = Color.RED
			"project":
				color = Color.MEDIUM_SPRING_GREEN

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
