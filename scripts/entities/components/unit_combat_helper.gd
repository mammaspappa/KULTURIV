class_name UnitCombatHelper
extends RefCounted
## Combat strength calculations for Unit, extracted from unit.gd as part of the
## Phase 5 god-object decomposition.
##
## All methods take the unit (and optionally an opponent / target tile) as parameters
## rather than living on the Unit class itself. This makes combat math separately
## testable and removes ~80 lines of cohesive logic from unit.gd.
##
## Unit.gd retains thin wrapper methods that delegate here, so call sites continue to
## use `unit.get_combat_strength(...)` and `unit.get_first_strikes()` unchanged.

## Compute the unit's effective combat strength after every modifier (health, fortify,
## terrain, promotions, traits, great-general, river crossing).
static func get_combat_strength(unit, is_attacking: bool, target_tile = null, defender = null) -> float:
	var strength: float = unit.get_strength()

	# Health penalty
	strength *= (unit.health / unit.max_health)

	# Fortification bonus (defense only)
	if not is_attacking and unit.is_fortified:
		strength *= (1.0 + unit.fortify_bonus)

	# Terrain defense bonus
	if not is_attacking and target_tile != null:
		strength *= (1.0 + target_tile.get_defense_bonus())

	# Promotion bonuses vs specific unit types
	if defender != null:
		var defender_class = defender.get_unit_class()
		var bonus_key = "bonus_vs_" + defender_class
		for promo in unit.promotions:
			var effects = DataManager.get_promotion_effects(promo)
			strength *= (1.0 + effects.get(bonus_key, 0.0))

	# Unit type bonuses (units.json `bonus_vs` map)
	if defender != null:
		var unit_data = DataManager.get_unit(unit.unit_id)
		var defender_class = defender.get_unit_class()
		var bonus_vs = unit_data.get("bonus_vs", {})
		if defender_class in bonus_vs:
			strength *= (1.0 + bonus_vs[defender_class])

	# BTS Aggressive trait: +10% combat for melee/gunpowder/mounted units
	if unit.player_owner and unit.player_owner.has_trait("aggressive"):
		var uc = unit.get_unit_class()
		if uc in ["melee", "gunpowder", "mounted"]:
			strength *= 1.1

	# BTS Protective trait: +25% city defense
	if not is_attacking and unit.player_owner and unit.player_owner.has_trait("protective"):
		var city_at = GameManager.get_city_at(unit.grid_position)
		if city_at != null and city_at.player_owner == unit.player_owner:
			strength *= 1.25

	# Great General attachment bonus (configured in tunables/units.json)
	if unit.attached_great_general != null:
		var gg_bonus: float = float(DataManager.get_tunable("units.great_general.combat_bonus", 0.20))
		strength *= (1.0 + gg_bonus)

	# River crossing penalty (attacker only, -25%; negated by Amphibious promotion)
	if is_attacking and defender != null and GameManager.hex_grid:
		var att_tile = GameManager.hex_grid.get_tile(unit.grid_position)
		if att_tile and not att_tile.river_edges.is_empty():
			var dx = defender.grid_position.x - unit.grid_position.x
			var dy = defender.grid_position.y - unit.grid_position.y
			var edge = direction_to_edge(dx, dy)
			if edge >= 0 and edge in att_tile.river_edges:
				var has_amphibious = false
				for promo in unit.promotions:
					var eff = DataManager.get_promotion_effects(promo)
					if eff.get("no_river_penalty", false):
						has_amphibious = true
						break
				if not has_amphibious:
					strength *= 0.75

	return strength

## Map a (dx,dy) direction to an 8-way edge index (0=N, 1=NE, 2=E, ... 7=NW).
## Returns -1 for non-cardinal/diagonal pairs.
static func direction_to_edge(dx: int, dy: int) -> int:
	if dx == 0 and dy == -1: return 0
	elif dx == 1 and dy == -1: return 1
	elif dx == 1 and dy == 0: return 2
	elif dx == 1 and dy == 1: return 3
	elif dx == 0 and dy == 1: return 4
	elif dx == -1 and dy == 1: return 5
	elif dx == -1 and dy == 0: return 6
	elif dx == -1 and dy == -1: return 7
	return -1

## Total first strikes from base unit data + promotions.
static func get_first_strikes(unit) -> int:
	var base = int(DataManager.get_unit(unit.unit_id).get("first_strikes", 0))
	for promo in unit.promotions:
		var effects = DataManager.get_promotion_effects(promo)
		base += int(effects.get("first_strikes", 0))
	return base

## Withdraw chance from base unit data + promotions, capped at 90%.
static func get_withdraw_chance(unit) -> float:
	var base: float = float(DataManager.get_unit(unit.unit_id).get("withdraw_chance", 0.0))
	for promo in unit.promotions:
		var effects = DataManager.get_promotion_effects(promo)
		base += float(effects.get("withdraw_increase", 0.0))
	return min(base, 0.9)
