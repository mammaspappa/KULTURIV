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

## Resolve combat between attacker and defender
func resolve_combat(attacker, defender) -> Dictionary:
	if attacker == null or defender == null:
		return {}

	# Attacking triggers war declaration if not already at war
	_ensure_war_declared(attacker, defender)

	# Get combat strengths with all modifiers
	var att_strength = _get_effective_strength(attacker, true, defender)
	var def_strength = _get_effective_strength(defender, false, attacker)

	# Calculate base damage
	var strength_ratio = att_strength / max(def_strength, 0.1)
	var base_damage = 30.0 * strength_ratio
	var variance = randf_range(0.8, 1.2)
	var damage_to_defender = base_damage * variance
	var damage_to_attacker = (30.0 / max(strength_ratio, 0.1)) * randf_range(0.8, 1.2)

	# First strikes (attacker deals damage first)
	var att_first_strikes = attacker.get_first_strikes()
	var def_first_strikes = defender.get_first_strikes()

	# Apply first strike damage
	if att_first_strikes > def_first_strikes:
		var first_strike_damage = damage_to_defender * 0.1 * (att_first_strikes - def_first_strikes)
		defender.take_damage(first_strike_damage)
		EventBus.first_strike.emit(attacker, defender, first_strike_damage)
	elif def_first_strikes > att_first_strikes:
		var first_strike_damage = damage_to_attacker * 0.1 * (def_first_strikes - att_first_strikes)
		attacker.take_damage(first_strike_damage)
		EventBus.first_strike.emit(defender, attacker, first_strike_damage)

	# Check if either died from first strikes
	if defender.health <= 0 or attacker.health <= 0:
		return _finalize_combat(attacker, defender)

	# Main combat rounds
	EventBus.combat_started.emit(attacker, defender)

	var max_rounds = 20  # Safety limit
	var rounds = 0

	while attacker.health > 0 and defender.health > 0 and rounds < max_rounds:
		rounds += 1

		# Both deal damage simultaneously
		var att_dmg = damage_to_defender * randf_range(0.1, 0.2)
		var def_dmg = damage_to_attacker * randf_range(0.1, 0.2)

		defender.take_damage(att_dmg)
		attacker.take_damage(def_dmg)

		EventBus.combat_round.emit(attacker, defender, att_dmg, def_dmg)

		# Withdrawal check for attacker
		if attacker.health < 30 and attacker.health > 0:
			if randf() < attacker.get_withdraw_chance():
				EventBus.unit_withdrew.emit(attacker)
				break

	return _finalize_combat(attacker, defender)

func _get_effective_strength(unit, is_attacking: bool, opponent) -> float:
	var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
	return unit.get_combat_strength(is_attacking, tile, opponent)

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
		# Defender dies
		defender.die()
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

func _calculate_xp(defeated, victor) -> int:
	var defeated_strength = DataManager.get_unit_strength(defeated.unit_id)
	var victor_strength = DataManager.get_unit_strength(victor.unit_id)
	var base_xp = int(defeated_strength / max(victor_strength, 1.0) * 4)
	return max(1, base_xp)

## Calculate odds for UI display
func calculate_odds(attacker, defender) -> Dictionary:
	var att_strength = _get_effective_strength(attacker, true, defender)
	var def_strength = _get_effective_strength(defender, false, attacker)
	var ratio = att_strength / max(def_strength, 0.1)

	return {
		"win_chance": clamp(ratio / (ratio + 1), 0.05, 0.95),
		"attacker_strength": att_strength,
		"defender_strength": def_strength,
		"ratio": ratio
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
