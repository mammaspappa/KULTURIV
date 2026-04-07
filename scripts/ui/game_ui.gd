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
@onready var religion_button: Button = $TopBar/HBoxContainer/ReligionButton
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

# Promotion UI
var promote_button: Button = null
var promotion_popup: PanelContainer = null
var promotion_list_container: VBoxContainer = null

# Upgrade, disband, and bombard buttons
var upgrade_button: Button = null
var disband_button: Button = null
var bombard_button: Button = null

# Enhanced unit panel elements
var xp_bar: ProgressBar = null
var xp_label: Label = null
var promotions_container: HFlowContainer = null
var unit_stack_container: VBoxContainer = null
var combat_preview_panel: PanelContainer = null
var combat_preview_labels: Dictionary = {}
var last_combat_preview_pos: Vector2i = Vector2i(-1, -1)

# Top bar extras
var resource_label: Label = null
var gp_label: Label = null

# Scoreboard
var scoreboard_panel: PanelContainer = null
var scoreboard_container: VBoxContainer = null

# Tile tooltip
var tile_tooltip: PanelContainer = null
var tooltip_labels: Dictionary = {}  # key -> Label
var hover_grid_pos: Vector2i = Vector2i(-1, -1)
var hover_time: float = 0.0
const TOOLTIP_DELAY = 0.3

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
	if religion_button:
		religion_button.pressed.connect(_on_religion_pressed)
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

	# Setup top bar extras (resource icons, GP progress)
	_setup_top_bar_extras()

	# Setup scoreboard
	_setup_scoreboard()

	# Setup enhanced unit panel elements
	_setup_unit_panel_extras()

	# Setup combat preview
	_setup_combat_preview()

	# Setup tile tooltip
	_setup_tile_tooltip()

	# Setup promotion UI
	_setup_promotion_ui()

	# Setup notification system
	_setup_notifications()

	# Setup multiplayer HUD (turn timer, player status)
	_setup_multiplayer_hud()

	# Initial UI update
	call_deferred("_update_top_bar")

func _process(delta: float) -> void:
	# Update unit panel if a unit is selected
	if selected_unit:
		_update_unit_panel()

	# Update combat preview
	_process_combat_preview()

	# Update tile tooltip
	_process_tile_tooltip(delta)

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
			KEY_F7:
				EventBus.show_religion_screen.emit()
				get_viewport().set_input_as_handled()
			KEY_F8:
				EventBus.show_victory_progress.emit()
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
	if GameManager.spectator_mode:
		# In spectator mode, update UI for the first player each round
		if player == GameManager.players[0]:
			_update_top_bar()
			_update_scoreboard()
	elif player == GameManager.human_player:
		_update_top_bar()
		_update_scoreboard()
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
		_update_unit_stack()

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
	# Prefer 3D camera
	var camera_3d = GameManager.get_meta("camera_3d") if GameManager.has_meta("camera_3d") else null
	if camera_3d:
		camera_3d.center_on_grid(unit.grid_position)
		return

	# Fallback: look for 2D camera
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

func _on_religion_pressed() -> void:
	EventBus.show_religion_screen.emit()

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
		turn_label.text = "Turn %d - %s (%s Era)" % [TurnManager.current_turn, TurnManager.get_year_string(), TurnManager.get_era()]

	var player = GameManager.human_player
	if player == null:
		if GameManager.spectator_mode and GameManager.players.size() > 0:
			player = GameManager.players[0]
		else:
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

	# Resource icons and GP progress
	_update_top_bar_extras()

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
	if promote_button:
		promote_button.visible = selected_unit.can_promote()
	if upgrade_button:
		upgrade_button.visible = selected_unit.can_upgrade()
		if selected_unit.can_upgrade():
			var target_data = DataManager.get_unit(selected_unit.get_upgrade_target())
			upgrade_button.text = "Upgrade (%dg)" % selected_unit.get_upgrade_cost()
			upgrade_button.tooltip_text = "Upgrade to %s" % target_data.get("name", "")
	if disband_button:
		disband_button.visible = selected_unit.get_strength() > 0 or selected_unit.can_build_improvements()
	if bombard_button:
		# Show bombard button for siege units near enemy cities
		var can_bombard = false
		if "bombard" in selected_unit.get_abilities():
			for dx in range(-1, 2):
				for dy in range(-1, 2):
					if dx == 0 and dy == 0: continue
					var adj_pos = selected_unit.grid_position + Vector2i(dx, dy)
					if CombatSystem.can_bombard(selected_unit, adj_pos):
						can_bombard = true
						break
				if can_bombard: break
		bombard_button.visible = can_bombard

	# XP bar, promotions, and stack (only update when unit state changes)
	_update_unit_xp_and_promotions()

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

# Scoreboard
func _setup_scoreboard() -> void:
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	scoreboard_panel.position = Vector2(-155, 45)
	scoreboard_panel.custom_minimum_size = Vector2(145, 0)
	scoreboard_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.7)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6)
	scoreboard_panel.add_theme_stylebox_override("panel", style)

	scoreboard_container = VBoxContainer.new()
	scoreboard_container.add_theme_constant_override("separation", 2)
	scoreboard_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scoreboard_panel.add_child(scoreboard_container)
	add_child(scoreboard_panel)

func _update_scoreboard() -> void:
	if scoreboard_container == null:
		return
	if GameManager.human_player == null and not GameManager.spectator_mode:
		return

	for child in scoreboard_container.get_children():
		child.queue_free()

	# Collect players for scoreboard (exclude barbarians)
	var entries = []
	for player in GameManager.players:
		if player.civilization_id == "barbarian":
			continue
		if GameManager.spectator_mode:
			# Spectator sees all players
			player.calculate_score()
			entries.append(player)
		elif player == GameManager.human_player or player.player_id in GameManager.human_player.met_players:
			player.calculate_score()
			entries.append(player)
		elif not player.cities.is_empty():
			entries.append(null)  # Placeholder for unmet civ

	# Sort known entries by score descending
	entries.sort_custom(func(a, b):
		if a == null: return false
		if b == null: return true
		return a.score > b.score
	)

	for player in entries:
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

		if player == null:
			var unknown = Label.new()
			unknown.text = "??? — ???"
			unknown.add_theme_font_size_override("font_size", 11)
			unknown.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			unknown.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(unknown)
		else:
			# Color dot
			var dot = Label.new()
			dot.text = "●"
			dot.add_theme_font_size_override("font_size", 11)
			dot.add_theme_color_override("font_color", player.color)
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(dot)

			# Civ name
			var civ_data = DataManager.get_civ(player.civilization_id)
			var name_label = Label.new()
			var short_name = civ_data.get("adjective", civ_data.get("name", "???"))
			name_label.text = short_name
			name_label.add_theme_font_size_override("font_size", 11)
			name_label.custom_minimum_size = Vector2(70, 0)
			name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

			# Color based on relationship
			if player == GameManager.human_player:
				name_label.add_theme_color_override("font_color", Color.WHITE)
			elif player.player_id in GameManager.human_player.at_war_with:
				name_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
			else:
				name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			hbox.add_child(name_label)

			# Score
			var score_label = Label.new()
			score_label.text = str(player.score)
			score_label.add_theme_font_size_override("font_size", 11)
			score_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.6))
			score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hbox.add_child(score_label)

		scoreboard_container.add_child(hbox)

# Top bar extras
func _setup_top_bar_extras() -> void:
	var hbox = $TopBar/HBoxContainer
	if hbox == null:
		return

	# Resource label (after gold/science)
	resource_label = Label.new()
	resource_label.add_theme_font_size_override("font_size", 12)
	resource_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.7))
	hbox.add_child(resource_label)
	hbox.move_child(resource_label, 3)  # After gold and science labels

	# GP progress label
	gp_label = Label.new()
	gp_label.add_theme_font_size_override("font_size", 12)
	gp_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	hbox.add_child(gp_label)
	hbox.move_child(gp_label, 4)  # After resource label

func _update_top_bar_extras() -> void:
	var player = GameManager.human_player
	if player == null:
		return

	# Resource icons
	if resource_label:
		var resources = player.get_available_resources()
		if resources.is_empty():
			resource_label.text = ""
		else:
			var strategic = []
			var luxury = []
			for res_id in resources:
				var res_data = DataManager.get_resource(res_id)
				var symbol = res_data.get("symbol", "?")
				var name = res_data.get("name", res_id)
				if res_data.get("type", "") == "strategic":
					strategic.append(symbol)
				elif res_data.get("type", "") == "luxury":
					luxury.append(symbol)
			var parts = []
			if not strategic.is_empty():
				parts.append(" ".join(strategic))
			if not luxury.is_empty():
				parts.append(" ".join(luxury))
			resource_label.text = " | ".join(parts)

	# GP progress (closest city to GP birth)
	if gp_label:
		var best_city_name = ""
		var best_progress = 0
		var best_threshold = 100
		for city in player.cities:
			var gp_progress = city.get_meta("gp_progress", 0)
			var gp_points = city.get_great_people_points()
			var total_pts = 0
			for gp_type in gp_points:
				total_pts += gp_points[gp_type]
			if total_pts > 0:
				var threshold = 100 + (GreatPeopleSystem.great_people_born.get(player.player_id, 0) * 50)
				var remaining = threshold - gp_progress
				if best_city_name == "" or remaining < (best_threshold - best_progress):
					best_city_name = city.city_name
					best_progress = gp_progress
					best_threshold = threshold

		if best_city_name != "":
			gp_label.text = "GP: %d/%d" % [best_progress, best_threshold]
		else:
			gp_label.text = ""

# Enhanced unit panel
func _setup_unit_panel_extras() -> void:
	var vbox = $UnitPanel/VBoxContainer
	if vbox == null:
		return

	# XP bar and label (after health bar)
	xp_label = Label.new()
	xp_label.add_theme_font_size_override("font_size", 11)
	xp_label.visible = false
	vbox.add_child(xp_label)
	vbox.move_child(xp_label, vbox.get_child_count() - 1)

	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(0, 8)
	xp_bar.show_percentage = false
	xp_bar.visible = false
	vbox.add_child(xp_bar)
	vbox.move_child(xp_bar, vbox.get_child_count() - 1)

	# Promotions display
	promotions_container = HFlowContainer.new()
	promotions_container.custom_minimum_size = Vector2(0, 0)
	promotions_container.visible = false
	vbox.add_child(promotions_container)
	vbox.move_child(promotions_container, vbox.get_child_count() - 1)

	# Unit stack list (at the bottom of unit panel)
	unit_stack_container = VBoxContainer.new()
	unit_stack_container.add_theme_constant_override("separation", 2)
	unit_stack_container.visible = false
	vbox.add_child(unit_stack_container)

func _setup_combat_preview() -> void:
	combat_preview_panel = PanelContainer.new()
	combat_preview_panel.visible = false
	combat_preview_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.05, 0.05, 0.92)
	style.border_color = Color(0.6, 0.3, 0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	combat_preview_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	for key in ["title", "odds", "attacker", "defender", "modifiers"]:
		var label = Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(label)
		combat_preview_labels[key] = label

	combat_preview_labels["title"].add_theme_font_size_override("font_size", 13)
	combat_preview_labels["title"].add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))

	combat_preview_panel.add_child(vbox)
	add_child(combat_preview_panel)

func _update_unit_xp_and_promotions() -> void:
	if selected_unit == null:
		if xp_bar: xp_bar.visible = false
		if xp_label: xp_label.visible = false
		if promotions_container: promotions_container.visible = false
		return

	var strength = selected_unit.get_strength()
	var is_military = strength > 0

	# XP bar
	if xp_bar and xp_label and is_military:
		var xp = selected_unit.experience
		var xp_needed = selected_unit._xp_for_next_level()
		xp_bar.max_value = xp_needed
		xp_bar.value = min(xp, xp_needed)
		xp_label.text = "Level %d — XP: %d/%d" % [selected_unit.level, xp, xp_needed]
		xp_bar.visible = true
		xp_label.visible = true
	elif xp_bar:
		xp_bar.visible = false
		xp_label.visible = false

	# Promotion badges
	if promotions_container:
		for child in promotions_container.get_children():
			child.queue_free()

		if not selected_unit.promotions.is_empty():
			for promo_id in selected_unit.promotions:
				var promo_data = DataManager.promotions.get(promo_id, {})
				var badge = Label.new()
				badge.text = promo_data.get("name", promo_id)
				badge.add_theme_font_size_override("font_size", 10)
				badge.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
				badge.tooltip_text = promo_data.get("description", "")
				promotions_container.add_child(badge)
			promotions_container.visible = true
		else:
			promotions_container.visible = false

func _update_unit_stack() -> void:
	if unit_stack_container == null:
		return

	for child in unit_stack_container.get_children():
		child.queue_free()

	if selected_unit == null:
		unit_stack_container.visible = false
		return

	var units_at = GameManager.get_units_at(selected_unit.grid_position)
	# Filter to own units only, exclude selected
	var stack = []
	for u in units_at:
		if u != selected_unit and u.player_owner == GameManager.human_player:
			stack.append(u)

	if stack.is_empty():
		unit_stack_container.visible = false
		return

	var header = Label.new()
	header.text = "Stack (%d):" % (stack.size() + 1)
	header.add_theme_font_size_override("font_size", 11)
	header.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	unit_stack_container.add_child(header)

	for u in stack.slice(0, 5):  # Show max 5 stacked units
		var udata = DataManager.get_unit(u.unit_id)
		var btn = Button.new()
		var hp_pct = int(u.health / u.max_health * 100)
		btn.text = "%s (HP:%d%%)" % [udata.get("name", u.unit_id), hp_pct]
		btn.custom_minimum_size = Vector2(0, 22)
		btn.add_theme_font_size_override("font_size", 10)
		btn.pressed.connect(func(): _select_unit_from_stack(u))
		unit_stack_container.add_child(btn)

	if stack.size() > 5:
		var more = Label.new()
		more.text = "...+%d more" % (stack.size() - 5)
		more.add_theme_font_size_override("font_size", 10)
		unit_stack_container.add_child(more)

	unit_stack_container.visible = true

func _select_unit_from_stack(unit) -> void:
	if unit and is_instance_valid(unit):
		EventBus.unit_selected.emit(unit)

func _process_combat_preview() -> void:
	if selected_unit == null or combat_preview_panel == null:
		if combat_preview_panel: combat_preview_panel.visible = false
		last_combat_preview_pos = Vector2i(-1, -1)
		return

	if selected_unit.get_strength() <= 0:
		combat_preview_panel.visible = false
		return

	var raycast = GameManager.get_meta("input_raycast") if GameManager.has_meta("input_raycast") else null
	if raycast == null:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var grid_pos = raycast.screen_to_grid(mouse_pos)

	if grid_pos == Vector2i(-1, -1) or grid_pos == selected_unit.grid_position:
		combat_preview_panel.visible = false
		last_combat_preview_pos = Vector2i(-1, -1)
		return

	# Check for enemy unit at position
	var enemy_units = GameManager.get_units_at(grid_pos)
	var target = null
	for u in enemy_units:
		if u.player_owner != GameManager.human_player and u.get_strength() > 0:
			target = u
			break

	if target == null:
		combat_preview_panel.visible = false
		last_combat_preview_pos = Vector2i(-1, -1)
		return

	# Only recalculate if position changed
	if grid_pos != last_combat_preview_pos:
		last_combat_preview_pos = grid_pos
		var odds = CombatSystem.calculate_odds(selected_unit, target)
		var modifiers = CombatSystem.get_combat_modifiers(selected_unit, true, target)

		var att_data = DataManager.get_unit(selected_unit.unit_id)
		var def_data = DataManager.get_unit(target.unit_id)

		combat_preview_labels["title"].text = "Combat Odds"
		combat_preview_labels["odds"].text = "Win: %d%%" % int(odds.get("win_chance", 0.5) * 100)
		var win_chance = odds.get("win_chance", 0.5)
		if win_chance >= 0.7:
			combat_preview_labels["odds"].add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		elif win_chance >= 0.4:
			combat_preview_labels["odds"].add_theme_color_override("font_color", Color(0.9, 0.9, 0.3))
		else:
			combat_preview_labels["odds"].add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))

		combat_preview_labels["attacker"].text = "%s: %.1f str" % [att_data.get("name", "Attacker"), odds.get("attacker_strength", 0)]
		combat_preview_labels["defender"].text = "%s: %.1f str" % [def_data.get("name", "Defender"), odds.get("defender_strength", 0)]

		var mod_text = ""
		for mod in modifiers.slice(0, 5):
			mod_text += mod + "\n"
		combat_preview_labels["modifiers"].text = mod_text.strip_edges()

	combat_preview_panel.visible = true
	# Position near cursor
	var tooltip_pos = mouse_pos + Vector2(16, -80)
	var viewport_size = get_viewport_rect().size
	if tooltip_pos.x + 200 > viewport_size.x:
		tooltip_pos.x = mouse_pos.x - 200
	if tooltip_pos.y < 50:
		tooltip_pos.y = mouse_pos.y + 16
	combat_preview_panel.position = tooltip_pos

# Tile tooltip system
func _setup_tile_tooltip() -> void:
	tile_tooltip = PanelContainer.new()
	tile_tooltip.visible = false
	tile_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.9)
	style.border_color = Color(0.4, 0.4, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	tile_tooltip.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	for key in ["terrain", "yields", "resource", "improvement", "defense", "owner"]:
		var label = Label.new()
		label.add_theme_font_size_override("font_size", 12)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(label)
		tooltip_labels[key] = label

	tooltip_labels["terrain"].add_theme_font_size_override("font_size", 13)

	tile_tooltip.add_child(vbox)
	add_child(tile_tooltip)

func _process_tile_tooltip(delta: float) -> void:
	var raycast = GameManager.get_meta("input_raycast") if GameManager.has_meta("input_raycast") else null
	if raycast == null:
		return

	var mouse_pos = get_viewport().get_mouse_position()
	var grid_pos = raycast.screen_to_grid(mouse_pos)

	if grid_pos != hover_grid_pos:
		hover_grid_pos = grid_pos
		hover_time = 0.0
		if tile_tooltip:
			tile_tooltip.visible = false
		return

	if grid_pos == Vector2i(-1, -1):
		return

	hover_time += delta
	if hover_time >= TOOLTIP_DELAY and tile_tooltip and not tile_tooltip.visible:
		_show_tile_tooltip(grid_pos, mouse_pos)

	# Reposition with cursor
	if tile_tooltip and tile_tooltip.visible:
		_position_tooltip(mouse_pos)

func _show_tile_tooltip(grid_pos: Vector2i, mouse_pos: Vector2) -> void:
	if GameManager.hex_grid == null or GameManager.human_player == null:
		return

	var tile = GameManager.hex_grid.get_tile(grid_pos)
	if tile == null:
		return

	var GameTileClass = preload("res://scripts/map/game_tile.gd")
	var vis = tile.get_visibility_for_player(GameManager.human_player.player_id)

	if vis == GameTileClass.VisibilityState.UNEXPLORED:
		return

	# Terrain + feature
	var terrain_data = DataManager.get_terrain(tile.terrain_id)
	var terrain_name = terrain_data.get("name", tile.terrain_id.capitalize())
	if tile.feature_id != "":
		var feature_data = DataManager.get_feature(tile.feature_id)
		terrain_name += " - " + feature_data.get("name", tile.feature_id.capitalize())
	tooltip_labels["terrain"].text = terrain_name
	tooltip_labels["terrain"].visible = true

	# Yields
	var yields = tile.get_yields()
	tooltip_labels["yields"].text = "Food: %d  Prod: %d  Com: %d" % [yields.get("food", 0), yields.get("production", 0), yields.get("commerce", 0)]
	tooltip_labels["yields"].visible = true

	# Resource (only visible tiles)
	if vis == GameTileClass.VisibilityState.VISIBLE and tile.resource_id != "":
		var res_data = DataManager.get_resource(tile.resource_id)
		tooltip_labels["resource"].text = "Resource: %s" % res_data.get("name", tile.resource_id.capitalize())
		tooltip_labels["resource"].visible = true
	else:
		tooltip_labels["resource"].visible = false

	# Improvement
	if vis == GameTileClass.VisibilityState.VISIBLE and tile.improvement_id != "":
		var imp_data = DataManager.get_improvement(tile.improvement_id)
		var imp_name = imp_data.get("name", tile.improvement_id.replace("_", " ").capitalize())
		var road_text = ""
		if tile.road_level == 1:
			road_text = " + Road"
		elif tile.road_level == 2:
			road_text = " + Railroad"
		tooltip_labels["improvement"].text = "Improvement: %s%s" % [imp_name, road_text]
		tooltip_labels["improvement"].visible = true
	elif vis == GameTileClass.VisibilityState.VISIBLE and tile.road_level > 0:
		tooltip_labels["improvement"].text = "Road" if tile.road_level == 1 else "Railroad"
		tooltip_labels["improvement"].visible = true
	else:
		tooltip_labels["improvement"].visible = false

	# Defense
	var defense = tile.get_defense_bonus()
	if defense > 0:
		tooltip_labels["defense"].text = "Defense: +%d%%" % int(defense * 100)
		tooltip_labels["defense"].add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
		tooltip_labels["defense"].visible = true
	else:
		tooltip_labels["defense"].visible = false

	# Owner
	if tile.tile_owner != null:
		var civ_data = DataManager.get_civ(tile.tile_owner.civilization_id)
		var owner_name = civ_data.get("name", tile.tile_owner.player_name)
		tooltip_labels["owner"].text = "Owner: %s" % owner_name
		tooltip_labels["owner"].add_theme_color_override("font_color", tile.tile_owner.color)
		tooltip_labels["owner"].visible = true
	else:
		tooltip_labels["owner"].visible = false

	tile_tooltip.visible = true
	_position_tooltip(mouse_pos)

func _position_tooltip(mouse_pos: Vector2) -> void:
	if tile_tooltip == null:
		return
	var viewport_size = get_viewport_rect().size
	var tooltip_size = tile_tooltip.size
	var pos = mouse_pos + Vector2(16, 16)
	if pos.x + tooltip_size.x > viewport_size.x:
		pos.x = mouse_pos.x - tooltip_size.x - 8
	if pos.y + tooltip_size.y > viewport_size.y:
		pos.y = mouse_pos.y - tooltip_size.y - 8
	tile_tooltip.position = pos

# Promotion system
func _setup_promotion_ui() -> void:
	# Add promote button to the unit panel action buttons
	promote_button = Button.new()
	promote_button.text = "Promote"
	promote_button.custom_minimum_size = Vector2(80, 30)
	promote_button.tooltip_text = "Choose a promotion for this unit"
	promote_button.pressed.connect(_on_promote_pressed)
	promote_button.visible = false
	var action_buttons = $UnitPanel/VBoxContainer/ActionButtons
	if action_buttons:
		action_buttons.add_child(promote_button)

	# Upgrade button
	upgrade_button = Button.new()
	upgrade_button.text = "Upgrade"
	upgrade_button.custom_minimum_size = Vector2(80, 30)
	upgrade_button.visible = false
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	if action_buttons:
		action_buttons.add_child(upgrade_button)

	# Disband button
	disband_button = Button.new()
	disband_button.text = "Disband"
	disband_button.custom_minimum_size = Vector2(80, 30)
	disband_button.visible = false
	disband_button.pressed.connect(_on_disband_pressed)
	if action_buttons:
		action_buttons.add_child(disband_button)

	# Bombard button (for siege units)
	bombard_button = Button.new()
	bombard_button.text = "Bombard"
	bombard_button.custom_minimum_size = Vector2(80, 30)
	bombard_button.visible = false
	bombard_button.pressed.connect(_on_bombard_pressed)
	if action_buttons:
		action_buttons.add_child(bombard_button)

	# Create promotion popup overlay
	promotion_popup = PanelContainer.new()
	promotion_popup.visible = false
	promotion_popup.custom_minimum_size = Vector2(320, 200)
	promotion_popup.set_anchors_preset(Control.PRESET_CENTER)
	promotion_popup.mouse_filter = Control.MOUSE_FILTER_STOP

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_color = Color(0.6, 0.5, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	promotion_popup.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	var title = Label.new()
	title.text = "Choose Promotion"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	vbox.add_child(title)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(296, 150)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	promotion_list_container = VBoxContainer.new()
	promotion_list_container.add_theme_constant_override("separation", 4)
	scroll.add_child(promotion_list_container)
	vbox.add_child(scroll)

	var close_button = Button.new()
	close_button.text = "Cancel"
	close_button.pressed.connect(_close_promotion_popup)
	vbox.add_child(close_button)

	promotion_popup.add_child(vbox)
	add_child(promotion_popup)

func _on_upgrade_pressed() -> void:
	if selected_unit and selected_unit.can_upgrade():
		selected_unit.upgrade()
		_update_unit_panel()

func _on_disband_pressed() -> void:
	if selected_unit:
		selected_unit.disband()
		selected_unit = null
		unit_panel.visible = false

func _on_bombard_pressed() -> void:
	if selected_unit == null:
		return
	# Find adjacent enemy city to bombard
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0: continue
			var adj_pos = selected_unit.grid_position + Vector2i(dx, dy)
			if CombatSystem.can_bombard(selected_unit, adj_pos):
				CombatSystem.bombard_city(selected_unit, adj_pos)
				_update_unit_panel()
				return

func _on_promote_pressed() -> void:
	if selected_unit == null or not selected_unit.can_promote():
		return
	_show_promotion_popup()

func _show_promotion_popup() -> void:
	if promotion_popup == null or promotion_list_container == null or selected_unit == null:
		return

	# Clear existing entries
	for child in promotion_list_container.get_children():
		child.queue_free()

	var available = selected_unit._get_available_promotions()
	for promo_id in available:
		var promo_data = DataManager.promotions.get(promo_id, {})
		var button = Button.new()
		var promo_name = promo_data.get("name", promo_id.replace("_", " ").capitalize())
		var description = promo_data.get("description", "")
		var prereqs = promo_data.get("prerequisites", [])
		var prereq_text = ""
		if not prereqs.is_empty():
			var prereq_names = []
			for p in prereqs:
				var pd = DataManager.promotions.get(p, {})
				prereq_names.append(pd.get("name", p))
			prereq_text = " (requires: %s)" % ", ".join(prereq_names)
		button.text = "%s — %s%s" % [promo_name, description, prereq_text]
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.custom_minimum_size = Vector2(280, 35)
		button.tooltip_text = "%s\n%s%s" % [promo_name, description, prereq_text]
		button.pressed.connect(_on_promotion_chosen.bind(promo_id))
		promotion_list_container.add_child(button)

	promotion_popup.visible = true
	# Position at center of screen
	promotion_popup.position = (get_viewport_rect().size - promotion_popup.size) / 2

func _on_promotion_chosen(promo_id: String) -> void:
	if selected_unit == null:
		return
	selected_unit.add_promotion(promo_id)
	var promo_data = DataManager.promotions.get(promo_id, {})
	var promo_name = promo_data.get("name", promo_id)
	_add_notification("Unit promoted: %s" % promo_name, "system")
	_close_promotion_popup()
	_update_unit_panel()

func _close_promotion_popup() -> void:
	if promotion_popup:
		promotion_popup.visible = false

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

func _on_notification_added(message: String, type: String = "info") -> void:
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
	var rel_symbol = rel_data.get("symbol", "?")
	var rel_color_str = rel_data.get("color", "#FFFFFF")
	var rel_color = Color(rel_color_str)

	# Show prominent centered popup (BTS style)
	var dialog = AcceptDialog.new()
	dialog.title = "Religion Founded"
	dialog.dialog_text = ""
	dialog.get_ok_button().text = "OK"

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Large religion symbol
	var symbol_label = Label.new()
	symbol_label.text = rel_symbol
	symbol_label.add_theme_font_size_override("font_size", 48)
	symbol_label.add_theme_color_override("font_color", rel_color)
	symbol_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(symbol_label)

	# Religion name
	var name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# Holy city info
	var city_label = Label.new()
	city_label.add_theme_font_size_override("font_size", 14)
	city_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	city_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(city_label)

	if player == GameManager.human_player:
		name_label.text = "%s has been founded!" % rel_name
		city_label.text = "Holy City: %s" % city.city_name
	else:
		var civ_data = DataManager.get_civ(player.civilization_id)
		name_label.text = "%s has been founded!" % rel_name
		city_label.text = "Founded by %s in %s" % [civ_data.get("name", "Unknown"), city.city_name]

	dialog.add_child(vbox)
	dialog.min_size = Vector2(320, 200)
	add_child(dialog)
	dialog.popup_centered()

	# Also add corner notification
	_add_notification("%s founded in %s!" % [rel_name, city.city_name], "religion")

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

# =============================================================================
# MULTIPLAYER HUD
# =============================================================================

var mp_turn_timer_label: Label = null
var mp_player_status_container: VBoxContainer = null
var mp_waiting_label: Label = null

func _setup_multiplayer_hud() -> void:
	if not GameManager.is_multiplayer():
		return

	# Turn timer display (top-right area)
	mp_turn_timer_label = Label.new()
	mp_turn_timer_label.name = "MPTurnTimer"
	mp_turn_timer_label.set_anchors_preset(PRESET_TOP_RIGHT)
	mp_turn_timer_label.offset_right = -20
	mp_turn_timer_label.offset_top = 45
	mp_turn_timer_label.add_theme_font_size_override("font_size", 20)
	mp_turn_timer_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	mp_turn_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mp_turn_timer_label.text = ""
	add_child(mp_turn_timer_label)

	# Player status panel (below turn timer)
	mp_player_status_container = VBoxContainer.new()
	mp_player_status_container.name = "MPPlayerStatus"
	mp_player_status_container.set_anchors_preset(PRESET_TOP_RIGHT)
	mp_player_status_container.offset_right = -20
	mp_player_status_container.offset_top = 75
	mp_player_status_container.offset_left = -200
	mp_player_status_container.add_theme_constant_override("separation", 3)
	add_child(mp_player_status_container)

	# Waiting label (shown after ending turn)
	mp_waiting_label = Label.new()
	mp_waiting_label.name = "MPWaiting"
	mp_waiting_label.set_anchors_preset(PRESET_CENTER)
	mp_waiting_label.offset_top = -100
	mp_waiting_label.add_theme_font_size_override("font_size", 24)
	mp_waiting_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	mp_waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mp_waiting_label.text = ""
	mp_waiting_label.visible = false
	add_child(mp_waiting_label)

	# Connect MP signals
	EventBus.mp_turn_timer_updated.connect(_on_mp_timer_updated)
	EventBus.mp_turn_status_updated.connect(_on_mp_turn_status_updated)

func _on_mp_timer_updated(remaining: float) -> void:
	if mp_turn_timer_label == null:
		return
	if remaining <= 0:
		mp_turn_timer_label.text = ""
	else:
		var minutes = int(remaining) / 60
		var seconds = int(remaining) % 60
		mp_turn_timer_label.text = "%d:%02d" % [minutes, seconds]
		# Turn red when under 30 seconds
		if remaining < 30:
			mp_turn_timer_label.add_theme_color_override("font_color", Color.RED)
		else:
			mp_turn_timer_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))

func _on_mp_turn_status_updated(ended_players: Array) -> void:
	if mp_player_status_container == null:
		return

	# Clear old entries
	for child in mp_player_status_container.get_children():
		child.queue_free()

	# Show status for each human player
	for player in GameManager.human_players:
		var label = Label.new()
		var done = player.player_id in ended_players
		label.text = "%s: %s" % [player.player_name, "Done" if done else "Playing"]
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Color.GREEN if done else Color(0.8, 0.8, 0.6))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		mp_player_status_container.add_child(label)

	# Show waiting message if local player has ended turn
	var local_id = NetworkManager.get_local_player_id()
	if local_id in ended_players and mp_waiting_label:
		var waiting_for = []
		for player in GameManager.human_players:
			if player.player_id not in ended_players:
				waiting_for.append(player.player_name)
		if not waiting_for.is_empty():
			mp_waiting_label.text = "Waiting for: %s" % ", ".join(waiting_for)
			mp_waiting_label.visible = true
		else:
			mp_waiting_label.visible = false
	elif mp_waiting_label:
		mp_waiting_label.visible = false
