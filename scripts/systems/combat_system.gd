extends Node
## Handles combat resolution between units.

## Ensure war is declared between the two players if not already at war
func _ensure_war_declared(attacker, defender) -> void:
	if attacker.player_owner == null or defender.player_owner == null:
		return

	var att_player = attacker.player_owner
	var def_player = defender.player_owner

	# If not already at war, declare war
	if not att_player.is_at_war_with(def_player.player_id):
		att_player.declare_war_on(def_player.player_id)
		def_player.declare_war_on(att_player.player_id)
		EventBus.war_declared.emit(att_player, def_player)

## Compute the BTS damage formula from tunables for the given strength differential.
func _damage_from_diff(str_diff: float) -> float:
	var base: float = float(DataManager.get_tunable("combat.damage.base", 20.0))
	var mult: float = float(DataManager.get_tunable("combat.damage.strength_multiplier", 3.0))
	var lo: float = float(DataManager.get_tunable("combat.damage.min", 12.0))
	var hi: float = float(DataManager.get_tunable("combat.damage.max", 40.0))
	return clamp(base + str_diff * mult, lo, hi)

## Resolve combat between attacker and defender (BTS-authentic damage formula)
func resolve_combat(attacker, defender) -> Dictionary:
	if attacker == null or defender == null:
		return {}

	# Attacking triggers war declaration if not already at war
	_ensure_war_declared(attacker, defender)

	# Get combat strengths with all modifiers
	var att_strength = _get_effective_strength(attacker, true, defender)
	var def_strength = _get_effective_strength(defender, false, attacker)

	# BTS damage formula via tunables (combat.damage.{base,strength_multiplier,min,max})
	var damage_to_defender = _damage_from_diff(att_strength - def_strength)
	var damage_to_attacker = _damage_from_diff(def_strength - att_strength)

	# First strikes: attacker deals full damage rounds before defender can respond
	var att_first_strikes = attacker.get_first_strikes()
	var def_first_strikes = defender.get_first_strikes()

	EventBus.combat_started.emit(attacker, defender)

	# Attacker's first strikes (defender takes damage, attacker does not)
	for i in range(att_first_strikes):
		if defender.health <= 0:
			break
		defender.take_damage(damage_to_defender)
		EventBus.first_strike.emit(attacker, defender, damage_to_defender)

	# Defender's first strikes (attacker takes damage, defender does not)
	for i in range(def_first_strikes):
		if attacker.health <= 0:
			break
		attacker.take_damage(damage_to_attacker)
		EventBus.first_strike.emit(defender, attacker, damage_to_attacker)

	# Check if either died from first strikes
	if defender.health <= 0 or attacker.health <= 0:
		return _finalize_combat(attacker, defender)

	# Main combat rounds — alternating damage until one side reaches 0 HP
	var max_rounds: int = int(DataManager.get_tunable("combat.max_combat_rounds", 100))
	var withdraw_threshold: float = float(DataManager.get_tunable("combat.withdraw_threshold", 0.30))
	var rounds = 0

	while attacker.health > 0 and defender.health > 0 and rounds < max_rounds:
		rounds += 1

		# Attacker strikes first in each round
		defender.take_damage(damage_to_defender)
		EventBus.combat_round.emit(attacker, defender, damage_to_defender, 0)

		if defender.health <= 0:
			break

		# Defender strikes back
		attacker.take_damage(damage_to_attacker)
		EventBus.combat_round.emit(attacker, defender, 0, damage_to_attacker)

		# Withdrawal check for attacker when below the configured HP fraction
		if attacker.health > 0 and attacker.health < attacker.max_health * withdraw_threshold:
			if randf() < attacker.get_withdraw_chance():
				EventBus.unit_withdrew.emit(attacker)
				break

	return _finalize_combat(attacker, defender)

func _get_effective_strength(unit, is_attacking: bool, opponent) -> float:
	var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
	var strength = unit.get_combat_strength(is_attacking, tile, opponent)

	# BTS: all civilizations get a combat bonus vs barbarian units (configurable in combat.json)
	if opponent and opponent.player_owner and opponent.player_owner.is_barbarian():
		if unit.player_owner and not unit.player_owner.is_barbarian():
			strength *= float(DataManager.get_tunable("combat.barbarian_bonus", 1.25))

	return strength

func _finalize_combat(attacker, defender) -> Dictionary:
	var result = {
		"attacker_won": attacker.health > defender.health,
		"attacker": attacker,
		"defender": defender
	}

	# Attacker uses up action regardless
	attacker.has_acted = true
	attacker.movement_remaining = 0
	attacker.update_visual()

	if defender.health <= 0:
		result["winner"] = attacker
		result["loser"] = defender
		var xp = _calculate_xp(defender, attacker)
		attacker.gain_experience(xp)
		EventBus.combat_ended.emit(attacker, defender)
		# Remember defender position/owner before they die
		var def_pos = defender.grid_position
		var def_owner = defender.player_owner
		# Defender dies
		defender.die()
		# Check for city capture (works for both AI and human combat)
		if is_instance_valid(attacker) and attacker.health > 0:
			_check_city_capture_after_combat(attacker, def_pos, def_owner)
	elif attacker.health <= 0:
		result["winner"] = defender
		result["loser"] = attacker
		var xp = _calculate_xp(attacker, defender)
		defender.gain_experience(xp)
		EventBus.combat_ended.emit(defender, attacker)
		# Attacker dies
		attacker.die()
	else:
		# Attacker withdrew - no winner
		result["winner"] = null
		result["loser"] = null

	return result

## After combat, check if a city was left undefended and should be captured
func _check_city_capture_after_combat(attacker, defender_pos: Vector2i, defender_owner) -> void:
	var city = GameManager.get_city_at(defender_pos)
	if city == null or city.player_owner != defender_owner:
		return

	# Check if there are still enemy defenders on the tile
	var remaining_defenders = GameManager.get_units_at(defender_pos)
	for unit in remaining_defenders:
		if unit.player_owner == defender_owner and unit.get_strength() > 0:
			return  # Still has defenders

	# Move attacker onto the city tile
	if attacker.grid_position != defender_pos:
		attacker.grid_position = defender_pos
		attacker.position = GridUtils.grid_to_pixel(defender_pos)

	# AI auto-captures; human gets dialog via game_world
	if attacker.player_owner.is_human:
		# Human players get capture handled by game_world._check_city_capture
		return
	else:
		# AI always captures (may raze small cities)
		if GameManager.game_world:
			if city.population <= 1 and city.can_be_razed():
				GameManager.game_world.raze_city(city)
			else:
				GameManager.game_world.capture_city(city, attacker.player_owner)

func _calculate_xp(defeated, victor) -> int:
	var defeated_strength = DataManager.get_unit_strength(defeated.unit_id)
	var victor_strength = DataManager.get_unit_strength(victor.unit_id)
	var base_xp = int(defeated_strength / max(victor_strength, 1.0) * 4)
	return max(1, base_xp)

## Calculate odds for UI display (BTS-style simulation)
func calculate_odds(attacker, defender) -> Dictionary:
	var att_strength = _get_effective_strength(attacker, true, defender)
	var def_strength = _get_effective_strength(defender, false, attacker)

	# BTS damage formula via tunables
	var dmg_to_def = _damage_from_diff(att_strength - def_strength)
	var dmg_to_att = _damage_from_diff(def_strength - att_strength)

	# Simulate: how many rounds to kill each side
	var rounds_to_kill_def = ceil(defender.health / dmg_to_def)
	var rounds_to_kill_att = ceil(attacker.health / dmg_to_att)

	# First strikes shift the balance
	var att_fs = attacker.get_first_strikes()
	var def_fs = defender.get_first_strikes()
	# First strikes give free damage rounds
	var def_hp_after_fs = max(1, defender.health - att_fs * dmg_to_def)
	var att_hp_after_fs = max(1, attacker.health - def_fs * dmg_to_att)

	rounds_to_kill_def = ceil(def_hp_after_fs / dmg_to_def)
	rounds_to_kill_att = ceil(att_hp_after_fs / dmg_to_att)

	# Win chance approximation based on rounds needed
	var win_min: float = float(DataManager.get_tunable("combat.win_chance_clamp.min", 0.05))
	var win_max: float = float(DataManager.get_tunable("combat.win_chance_clamp.max", 0.95))
	var win_certain: float = float(DataManager.get_tunable("combat.win_chance_clamp.certain_win", 0.99))
	var loss_certain: float = float(DataManager.get_tunable("combat.win_chance_clamp.certain_loss", 0.01))
	var win_chance: float
	if rounds_to_kill_def <= 0:
		win_chance = win_certain
	elif rounds_to_kill_att <= 0:
		win_chance = loss_certain
	else:
		win_chance = clamp(float(rounds_to_kill_att) / (rounds_to_kill_att + rounds_to_kill_def), win_min, win_max)

	return {
		"win_chance": win_chance,
		"attacker_strength": att_strength,
		"defender_strength": def_strength,
		"ratio": att_strength / max(def_strength, 0.1)
	}

## Get a summary of combat modifiers for UI
func get_combat_modifiers(unit, is_attacking: bool, opponent = null) -> Array:
	var modifiers = []

	# Base strength
	var base_strength = DataManager.get_unit_strength(unit.unit_id)
	modifiers.append({"name": "Base Strength", "value": base_strength, "is_percentage": false})

	# Health penalty
	var health_percent = unit.health / unit.max_health
	if health_percent < 1.0:
		modifiers.append({"name": "Health", "value": (health_percent - 1.0) * 100, "is_percentage": true})

	# Fortification bonus
	if not is_attacking and unit.is_fortified:
		modifiers.append({"name": "Fortified", "value": unit.fortify_bonus * 100, "is_percentage": true})

	# Terrain bonus
	if not is_attacking and GameManager.hex_grid:
		var tile = GameManager.hex_grid.get_tile(unit.grid_position)
		if tile:
			var def_bonus = tile.get_defense_bonus()
			if def_bonus > 0:
				modifiers.append({"name": "Terrain", "value": def_bonus * 100, "is_percentage": true})

	# Promotion bonuses
	if opponent:
		var opp_class = opponent.get_unit_class()
		for promo in unit.promotions:
			var effects = DataManager.get_promotion_effects(promo)
			var bonus_key = "bonus_vs_" + opp_class
			if effects.has(bonus_key):
				var promo_data = DataManager.get_promotion(promo)
				modifiers.append({"name": promo_data.get("name", promo), "value": effects[bonus_key] * 100, "is_percentage": true})

	return modifiers


# =============================================================================
# AIR COMBAT SYSTEM
# =============================================================================

## Check if an air unit can perform an air strike on a target
func can_air_strike(air_unit, target_pos: Vector2i) -> bool:
	if air_unit == null:
		return false

	var unit_data = DataManager.get_unit(air_unit.unit_id)
	if unit_data.get("unit_class", "") != "air":
		return false

	if not ("air_bomb" in air_unit.get_abilities()):
		return false

	if air_unit.has_acted:
		return false

	# Check range
	var distance = GridUtils.chebyshev_distance(air_unit.grid_position, target_pos)
	var max_range = unit_data.get("range", 6)
	if distance > max_range:
		return false

	return true

## Perform an air strike on a target tile (bombing run)
func air_strike(air_unit, target_pos: Vector2i) -> Dictionary:
	if not can_air_strike(air_unit, target_pos):
		return {"success": false, "reason": "Cannot perform air strike"}

	var result = {
		"success": true,
		"damage_dealt": 0,
		"intercepted": false,
		"air_unit_destroyed": false,
		"targets_hit": []
	}

	var unit_data = DataManager.get_unit(air_unit.unit_id)
	var bomb_damage = unit_data.get("bomb_damage", 16)
	var air_strength = unit_data.get("air_strength", 16.0)

	# Check for interception
	var interceptor = _find_interceptor(air_unit, target_pos)
	if interceptor != null:
		result["intercepted"] = true
		var intercept_result = _resolve_air_intercept(interceptor, air_unit)
		result["intercept_damage"] = intercept_result.damage_to_attacker

		if air_unit.health <= 0:
			result["air_unit_destroyed"] = true
			air_unit.die()
			return result

	# Apply bombing damage to units on tile
	var target_tile = GameManager.hex_grid.get_tile(target_pos) if GameManager.hex_grid else null
	if target_tile:
		var units_at_target = GameManager.get_units_at(target_pos)
		var bomb_var_min: float = float(DataManager.get_tunable("combat.air.bomb_damage_variance_min", 0.7))
		var bomb_var_max: float = float(DataManager.get_tunable("combat.air.bomb_damage_variance_max", 1.0))
		for target_unit in units_at_target:
			if target_unit.player_owner != air_unit.player_owner:
				var damage = bomb_damage * randf_range(bomb_var_min, bomb_var_max)
				target_unit.take_damage(damage)
				result["damage_dealt"] += damage
				result["targets_hit"].append(target_unit)

				if target_unit.health <= 0:
					target_unit.die()

		# Damage city if present
		var city = GameManager.get_city_at(target_pos)
		if city and city.player_owner != air_unit.player_owner:
			# Reduce city defenses
			var defense_factor: float = float(DataManager.get_tunable("combat.air.city_bomb_defense_damage_factor", 0.5))
			city.set_meta("defense_damage", city.get_meta("defense_damage", 0) + bomb_damage * defense_factor)
			result["city_damaged"] = true

	air_unit.has_acted = true
	EventBus.air_strike.emit(air_unit, target_pos, result)
	return result

## Find an interceptor that can intercept the incoming air unit
func _find_interceptor(air_unit, target_pos: Vector2i):
	var potential_interceptors = []

	# Check for fighters in range
	for player in GameManager.players:
		if player.player_id == air_unit.player_owner.player_id:
			continue
		if not player.is_at_war_with(air_unit.player_owner.player_id):
			continue

		for unit in player.units:
			var unit_data = DataManager.get_unit(unit.unit_id)
			if "intercept" not in unit.get_abilities():
				continue

			var intercept_range = unit_data.get("range", 6)
			var distance = GridUtils.chebyshev_distance(unit.grid_position, target_pos)
			if distance <= intercept_range:
				potential_interceptors.append(unit)

	if potential_interceptors.is_empty():
		return null

	# Pick best interceptor (highest intercept chance)
	var default_chance: float = float(DataManager.get_tunable("combat.air.default_intercept_chance", 0.4))
	var best = potential_interceptors[0]
	var best_chance = DataManager.get_unit(best.unit_id).get("intercept_chance", default_chance)
	for interceptor in potential_interceptors:
		var chance = DataManager.get_unit(interceptor.unit_id).get("intercept_chance", default_chance)
		if chance > best_chance:
			best = interceptor
			best_chance = chance

	# Roll for interception
	if randf() < best_chance:
		return best

	return null

## Resolve air-to-air intercept combat
func _resolve_air_intercept(interceptor, attacker) -> Dictionary:
	var result = {
		"damage_to_attacker": 0,
		"damage_to_interceptor": 0
	}

	var int_data = DataManager.get_unit(interceptor.unit_id)
	var att_data = DataManager.get_unit(attacker.unit_id)

	var int_strength = int_data.get("air_strength", 16.0)
	var att_strength = att_data.get("air_strength", 16.0)

	# Interceptor has advantage. Base damages and variance window are configurable.
	var att_base: float = float(DataManager.get_tunable("combat.air.intercept_damage_to_attacker_base", 25.0))
	var int_base: float = float(DataManager.get_tunable("combat.air.intercept_damage_to_interceptor_base", 15.0))
	var var_min: float = float(DataManager.get_tunable("combat.air.intercept_variance_min", 0.8))
	var var_max: float = float(DataManager.get_tunable("combat.air.intercept_variance_max", 1.2))
	var ratio = int_strength / max(att_strength, 1.0)
	var damage_to_attacker = att_base * ratio * randf_range(var_min, var_max)
	var damage_to_interceptor = int_base / max(ratio, 0.5) * randf_range(var_min, var_max)

	attacker.take_damage(damage_to_attacker)
	interceptor.take_damage(damage_to_interceptor)

	result["damage_to_attacker"] = damage_to_attacker
	result["damage_to_interceptor"] = damage_to_interceptor

	EventBus.air_intercept.emit(interceptor, attacker, result)

	if interceptor.health <= 0:
		interceptor.die()

	return result

## Air superiority mission - patrol and intercept
func air_superiority_mission(air_unit, patrol_pos: Vector2i) -> bool:
	if air_unit == null:
		return false

	var unit_data = DataManager.get_unit(air_unit.unit_id)
	if "air_superiority" not in air_unit.get_abilities():
		return false

	# Set unit to intercept mode
	air_unit.set_meta("air_superiority_active", true)
	air_unit.set_meta("patrol_position", patrol_pos)
	air_unit.has_acted = true

	EventBus.air_superiority_started.emit(air_unit, patrol_pos)
	return true


# =============================================================================
# NUCLEAR WEAPONS SYSTEM
# =============================================================================

## Check if a nuclear strike can be performed
func can_nuke(nuke_unit, target_pos: Vector2i) -> bool:
	if nuke_unit == null:
		return false

	var unit_data = DataManager.get_unit(nuke_unit.unit_id)
	if "nuke" not in nuke_unit.get_abilities():
		return false

	if nuke_unit.has_acted:
		return false

	# Check if Manhattan Project has been built (globally enables nukes)
	if not GameManager.get_meta("manhattan_project_built", false):
		return false

	# Check range
	var distance = GridUtils.chebyshev_distance(nuke_unit.grid_position, target_pos)
	var max_range = unit_data.get("range", 12)
	if distance > max_range:
		return false

	return true

## Launch a nuclear strike
func launch_nuke(nuke_unit, target_pos: Vector2i) -> Dictionary:
	if not can_nuke(nuke_unit, target_pos):
		return {"success": false, "reason": "Cannot launch nuclear strike"}

	var unit_data = DataManager.get_unit(nuke_unit.unit_id)
	var nuke_damage = unit_data.get("nuke_damage", 50)
	var nuke_radius = unit_data.get("nuke_radius", 2)

	var result = {
		"success": true,
		"target": target_pos,
		"radius": nuke_radius,
		"units_destroyed": [],
		"cities_damaged": [],
		"population_killed": 0,
		"fallout_tiles": [],
		"intercepted": false
	}

	# Check for SDI interception
	var target_tile = GameManager.hex_grid.get_tile(target_pos) if GameManager.hex_grid else null
	if target_tile and target_tile.owner_id != -1:
		var defender = GameManager.get_player(target_tile.owner_id)
		if defender and defender.has_project("sdi"):
			var intercept_chance: float = float(DataManager.get_tunable("combat.nuke.sdi_intercept_chance", 0.75))
			if randf() < intercept_chance:
				result["intercepted"] = true
				result["success"] = false
				nuke_unit.die()  # Nuke is consumed
				EventBus.nuke_intercepted.emit(nuke_unit, target_pos, defender)
				return result

	# Get all tiles in blast radius
	var affected_tiles = GridUtils.get_tiles_in_range(target_pos, nuke_radius)
	affected_tiles.append(target_pos)  # Include center

	for tile_pos in affected_tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos) if GameManager.hex_grid else null
		if tile == null:
			continue

		var distance_from_center = GridUtils.chebyshev_distance(target_pos, tile_pos)
		var falloff: float = float(DataManager.get_tunable("combat.nuke.distance_falloff_factor", 0.5))
		var damage_multiplier = 1.0 - (float(distance_from_center) / float(nuke_radius + 1)) * falloff

		# Destroy units on tile
		var units_on_tile = GameManager.get_units_at(tile_pos)
		for unit in units_on_tile:
			var damage = nuke_damage * damage_multiplier
			unit.take_damage(damage)
			if unit.health <= 0:
				result["units_destroyed"].append(unit)
				unit.die()

		# Damage city if present
		var city = GameManager.get_city_at(tile_pos)
		if city:
			var pop_killed = _nuke_city_damage(city, damage_multiplier, tile_pos == target_pos)
			result["population_killed"] += pop_killed
			result["cities_damaged"].append({"city": city, "pop_killed": pop_killed})

		# Create fallout on tile
		if tile.terrain_id != "ocean" and tile.terrain_id != "coast":
			_create_fallout(tile)
			result["fallout_tiles"].append(tile_pos)

	# The nuke is consumed
	nuke_unit.die()

	# Diplomatic consequences - everyone hates the nuke user
	_apply_nuke_diplomacy_penalty(nuke_unit.player_owner)

	EventBus.nuke_launched.emit(nuke_unit, target_pos, result)
	return result

## Apply nuclear damage to a city
func _nuke_city_damage(city, damage_multiplier: float, is_ground_zero: bool) -> int:
	var pop_killed = 0

	if is_ground_zero:
		# Ground zero: kill a configurable population fraction
		var gz_min: float = float(DataManager.get_tunable("combat.nuke.ground_zero_pop_kill_min", 0.3))
		var gz_max: float = float(DataManager.get_tunable("combat.nuke.ground_zero_pop_kill_max", 0.7))
		var kill_percent = randf_range(gz_min, gz_max)
		pop_killed = int(city.population * kill_percent)
		city.population = max(1, city.population - pop_killed)

		# Destroy random buildings
		var b_min: int = int(DataManager.get_tunable("combat.nuke.ground_zero_buildings_min", 2))
		var b_max: int = int(DataManager.get_tunable("combat.nuke.ground_zero_buildings_max", 5))
		var buildings_to_destroy = min(city.buildings.size(), randi_range(b_min, b_max))
		for i in range(buildings_to_destroy):
			if city.buildings.size() > 0:
				var idx = randi() % city.buildings.size()
				city.buildings.remove_at(idx)

		# Reset production
		city.production_progress = 0
	else:
		# Outer radius: smaller kill fraction, scaled by distance falloff
		var o_min: float = float(DataManager.get_tunable("combat.nuke.outer_pop_kill_min", 0.1))
		var o_max: float = float(DataManager.get_tunable("combat.nuke.outer_pop_kill_max", 0.3))
		var kill_percent = randf_range(o_min, o_max) * damage_multiplier
		pop_killed = int(city.population * kill_percent)
		city.population = max(1, city.population - pop_killed)

	# Cause unhappiness
	var unhappy: int = int(DataManager.get_tunable("combat.nuke.unhappiness_per_strike", 3))
	var unhappy_turns: int = int(DataManager.get_tunable("combat.nuke.unhappiness_turns", 10))
	city.set_meta("nuke_unhappiness", city.get_meta("nuke_unhappiness", 0) + unhappy)
	city.set_meta("nuke_unhappiness_turns", unhappy_turns)

	return pop_killed

## Create fallout on a tile
func _create_fallout(tile) -> void:
	tile.set_meta("fallout", true)
	tile.set_meta("fallout_turns", int(DataManager.get_tunable("combat.nuke.fallout_duration_turns", 20)))

	# Fallout destroys improvements
	if tile.improvement != "":
		tile.improvement = ""

	# Fallout removes features (forests burn, etc.)
	if tile.feature_id in ["forest", "jungle"]:
		tile.feature_id = ""

	EventBus.fallout_created.emit(tile)

## Apply diplomatic penalty for using nukes
func _apply_nuke_diplomacy_penalty(attacker_player) -> void:
	var penalty: int = int(DataManager.get_tunable("combat.nuke.diplomacy_penalty", -5))
	for player in GameManager.players:
		if player.player_id == attacker_player.player_id:
			continue

		# Configurable diplomacy hit with everyone for using nukes
		player.add_diplomacy_memory(attacker_player.player_id, "used_nuke", penalty)

	EventBus.diplomacy_modifier_changed.emit(attacker_player, "used_nuke")

## Clean up fallout each turn
## Check if a siege unit can bombard a city
func can_bombard(unit, target_pos: Vector2i) -> bool:
	if unit == null or unit.has_acted:
		return false
	var unit_data = DataManager.get_unit(unit.unit_id)
	if "bombard" not in unit_data.get("abilities", []):
		return false
	# Must be adjacent to target city
	var distance = GridUtils.chebyshev_distance(unit.grid_position, target_pos)
	if distance > 1:
		return false
	# Target must have a city
	var city = GameManager.get_city_at(target_pos)
	if city == null or city.player_owner == unit.player_owner:
		return false
	return true

## Bombard a city, reducing its defense strength
func bombard_city(attacker, target_pos: Vector2i) -> Dictionary:
	var result = {"success": false}
	if not can_bombard(attacker, target_pos):
		return result

	_ensure_war_declared(attacker, GameManager.get_city_at(target_pos))

	var city = GameManager.get_city_at(target_pos)
	var unit_data = DataManager.get_unit(attacker.unit_id)
	var bombard_str = unit_data.get("bombard_strength", 5)

	# Reduce city defense (per-point reduction is configurable)
	var per_point: float = float(DataManager.get_tunable("combat.bombard.defense_reduction_per_point", 0.02))
	var defense_reduction = bombard_str * per_point
	city.defense_damage = min(city.defense_damage + defense_reduction, 1.0)  # Cap at 100% damaged

	result["success"] = true
	result["defense_reduction"] = defense_reduction
	result["total_damage"] = city.defense_damage

	# Collateral damage to defending units
	var default_limit: float = float(DataManager.get_tunable("combat.bombard.default_collateral_limit", 0.5))
	var max_targets: int = int(DataManager.get_tunable("combat.bombard.max_collateral_targets", 4))
	var collateral = unit_data.get("collateral_damage", 0)
	var collateral_limit = unit_data.get("collateral_limit", default_limit)
	if collateral > 0:
		var defenders = GameManager.get_units_at(target_pos)
		var damaged_count = 0
		for defender in defenders:
			if defender.player_owner != attacker.player_owner and damaged_count < max_targets:
				var dmg = defender.max_health * collateral * 0.01
				var min_health = defender.max_health * (1.0 - collateral_limit)
				defender.health = max(min_health, defender.health - dmg)
				damaged_count += 1

	attacker.has_acted = true
	attacker.movement_remaining = 0
	EventBus.notification_added.emit("Bombarded %s! Defense reduced to %d%%" % [city.city_name, int((1.0 - city.defense_damage) * 100)])
	return result

func process_fallout_decay() -> void:
	if GameManager.hex_grid == null:
		return

	for x in range(GameManager.hex_grid.width):
		for y in range(GameManager.hex_grid.height):
			var tile = GameManager.hex_grid.get_tile(Vector2i(x, y))
			if tile and tile.get_meta("fallout", false):
				var turns_left = tile.get_meta("fallout_turns", 0) - 1
				if turns_left <= 0:
					tile.set_meta("fallout", false)
					tile.remove_meta("fallout_turns")
					EventBus.fallout_cleared.emit(tile)
				else:
					tile.set_meta("fallout_turns", turns_left)
