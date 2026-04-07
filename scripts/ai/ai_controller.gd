extends Node
## AI controller for computer-controlled players.
## Uses leader personality (flavor values) to make decisions.
## Applies difficulty bonuses based on game settings.

const PathfindingClass = preload("res://scripts/map/pathfinding.gd")
const UnitClass = preload("res://scripts/entities/unit.gd")
const AIStrategyClass = preload("res://scripts/ai/ai_strategy.gd")

# Flavor thresholds for decision making
const HIGH_FLAVOR = 7
const MEDIUM_FLAVOR = 4
const LOW_FLAVOR = 2

# City specialization types
enum CitySpecialization {
	HYBRID,       # Balanced city
	PRODUCTION,   # Focus on hammers/military
	SCIENCE,      # Focus on research
	GOLD,         # Focus on commerce
	MILITARY,     # Garrison city, border defense
	CULTURE,      # Cultural expansion/victory
	FOOD          # Growth focused city
}

# Simulation logger (null during normal gameplay, set by ai_simulation.gd)
static var sim_logger = null

# Per-turn caches (cleared at start of each execute_turn)
var _cached_flavor: Dictionary = {}
var _cached_personality: Dictionary = {}
var _cached_ai_bonuses: Dictionary = {}
var _cached_player_id: int = -1
var _cached_has_coastal: int = -1  # -1=unchecked, 0=no, 1=yes
var _cached_has_spies: int = -1

# War/peace cooldown: "player_id:other_id" -> turn when peace was last made
# Prevents rapid war cycling (declare → peace → declare loop)
var peace_cooldown: Dictionary = {}  # String -> int (turn number)
const PEACE_COOLDOWN_TURNS = 20  # Must wait 20 turns after peace before redeclaring war

## Execute a full turn for an AI player
func execute_turn(player) -> void:
	if player.is_human:
		return
	# The base barbarian player (id=-1) uses its own simple AI (BarbarianSystem)
	# Spawned barbarian civilizations (id >= 0) use the full civ AI
	if player.civilization_id == "barbarian" and player.player_id == -1:
		return

	# Clear per-turn caches
	_cached_flavor = {}
	_cached_personality = {}
	_cached_ai_bonuses = {}
	_cached_player_id = player.player_id
	_cached_has_coastal = -1
	_cached_has_spies = -1

	# Get leader flavor values for personality-based decisions
	var flavor = _get_leader_flavor(player)

	# Process diplomacy first (skip unmet players handled internally)
	_process_diplomacy(player, flavor)

	# Process research
	_process_research(player, flavor)

	# Process espionage (skip if no espionage capability)
	if _has_espionage_capability(player):
		_process_espionage(player, flavor)

	# Strategic planning (city sites, war targets, defense — runs once before units)
	AIStrategyClass.update_strategy(player, flavor)

	# Process units in two passes:
	# Pass 1: Assign military escorts to settlers/workers outside cities
	var escort_assignments = _assign_escorts(player)

	# Pass 2: Process all units (escorts move with their charges)
	for unit in player.units.duplicate():
		if unit == null or not is_instance_valid(unit):
			continue
		_process_unit_ai(unit, player, flavor, escort_assignments)

	# Process cities
	for city in player.cities:
		var prev_production = city.current_production
		_process_city_ai(city, player, flavor)
		if sim_logger and city.current_production != "" and city.current_production != prev_production:
			sim_logger.log_decision(player.player_name, "production", "set_production",
				"%s -> %s" % [city.city_name, city.current_production], "")

	# Process civics adoption (scaled by game speed)
	var civics_interval = max(1, int(10 * GameManager.get_speed_multiplier()))
	if TurnManager.current_turn % civics_interval == player.player_id % civics_interval:
		_process_civics(player, flavor)

	# Process naval strategy (skip if no coastal cities)
	if _has_coastal_cities(player):
		_process_naval_strategy(player, flavor)

	# Process Great People — use them strategically
	_process_great_people(player, flavor)

## Get leader flavor values (cached per turn)
func _get_leader_flavor(player) -> Dictionary:
	if not _cached_flavor.is_empty() and _cached_player_id == player.player_id:
		return _cached_flavor

	# Spawned barbarian civs: hardcoded aggressive flavor (no leader)
	if player.civilization_id == "barbarian" and player.player_id >= 0:
		_cached_flavor = {
			"military": 9, "gold": 2, "science": 2, "culture": 1,
			"religion": 0, "expansion": 3, "growth": 3, "production": 7
		}
		return _cached_flavor

	var leader_data = DataManager.get_leader(player.leader_id)
	var flavor = leader_data.get("flavor", {
		"military": 5, "gold": 5, "science": 5, "culture": 5,
		"religion": 5, "expansion": 5, "growth": 5, "production": 5
	}).duplicate()
	# Apply AI aggressiveness modifier from game settings
	var aggro = GameManager.ai_aggressiveness
	if aggro == "peaceful":
		flavor["military"] = int(flavor.get("military", 5) * 0.5)
	elif aggro == "aggressive":
		flavor["military"] = int(flavor.get("military", 5) * 1.5)

	_cached_flavor = flavor
	return flavor

## Get full leader personality data (cached per turn)
func _get_leader_personality(player) -> Dictionary:
	if not _cached_personality.is_empty() and _cached_player_id == player.player_id:
		return _cached_personality

	# Spawned barbarian civs: use the personality stored on player object
	if player.civilization_id == "barbarian" and player.player_id >= 0 and not player.ai_personality.is_empty():
		_cached_personality = player.ai_personality
		return _cached_personality

	var leader_data = DataManager.get_leader(player.leader_id)
	_cached_personality = {
		"base_peace_weight": leader_data.get("base_peace_weight", 5),
		"warmonger_respect": leader_data.get("warmonger_respect", 1),
		"max_war_rand": leader_data.get("max_war_rand", 100),
		"make_peace_rand": leader_data.get("make_peace_rand", 30),
		"dogpile_war_rand": leader_data.get("dogpile_war_rand", 50),
		"raze_city_prob": leader_data.get("raze_city_prob", 20),
		"build_unit_prob": leader_data.get("build_unit_prob", 40),
		"wonder_construct_rand": leader_data.get("wonder_construct_rand", 30),
		"espionage_weight": leader_data.get("espionage_weight", 80),
		"base_attitude": leader_data.get("base_attitude", 0),
	}
	return _cached_personality

## Get difficulty bonuses for AI (cached per turn)
func _get_ai_bonuses() -> Dictionary:
	if not _cached_ai_bonuses.is_empty():
		return _cached_ai_bonuses
	var handicap_id = DataManager.get_handicap_id_by_level(GameManager.difficulty)
	_cached_ai_bonuses = DataManager.get_ai_bonuses(handicap_id)
	return _cached_ai_bonuses

## Check if player has any espionage capability (cached per turn)
func _has_espionage_capability(player) -> bool:
	if _cached_has_spies != -1:
		return _cached_has_spies == 1

	# Check if player has any espionage points accumulated
	for other in GameManager.players:
		if other == player:
			continue
		var points = EspionageSystem.get_espionage_points(player.player_id, other.player_id)
		if points >= 50:
			_cached_has_spies = 1
			return true

	_cached_has_spies = 0
	return false

## Check if player has coastal cities (cached per turn)
func _has_coastal_cities(player) -> bool:
	if _cached_has_coastal != -1:
		return _cached_has_coastal == 1

	for city in player.cities:
		if _is_coastal_city(city):
			_cached_has_coastal = 1
			return true

	_cached_has_coastal = 0
	return false

## Process AI diplomacy decisions
func _process_diplomacy(player, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)
	var is_barb_civ = player.civilization_id == "barbarian" and player.player_id >= 0
	var met_count = 0

	for other in GameManager.players:
		if other == player or other.player_id not in player.met_players:
			continue
		if other.player_id == -1:
			continue  # Skip base barbarian player
		met_count += 1

		# Barbarian civs: always at war, never make peace, never trade
		if is_barb_civ:
			if not GameManager.is_at_war(player, other):
				GameManager.declare_war(player, other)
			continue

		# Skip if at war
		if GameManager.is_at_war(player, other):
			# Never make peace with barbarian civs — they'll just re-declare
			if other.civilization_id != "barbarian":
				_consider_peace(player, other, military_flavor)
			continue

		# Consider treaties
		_consider_treaties(player, other, flavor)

		# Consider trade (limit to avoid spam — max 2 trade checks per turn)
		if met_count <= 2:
			_consider_trade(player, other, flavor)

		# Consider war
		_consider_war(player, other, flavor)

## Consider making peace or capitulating (BTS personality-driven)
func _consider_peace(player, other, military_flavor: int) -> void:
	# Check if AI should offer capitulation (become vassal)
	if DiplomacySystem.should_offer_capitulation(player, other):
		player.become_vassal_of(other.player_id)
		EventBus.notification_added.emit("%s has capitulated to %s!" % [player.player_name, other.player_name])
		GameManager.make_peace(player, other)
		if sim_logger:
			sim_logger.log_decision(player.player_name, "peace", "capitulate", other.player_name, "war_score_critical")
		return

	var personality = _get_leader_personality(player)

	# BTS make_peace_rand: roll each turn — higher = more willing to consider peace
	# Warmongers (make_peace_rand=80 like Genghis) rarely want peace
	# Peaceful leaders (make_peace_rand=10 like Gandhi) will stay in war once committed
	# But peace_weight affects the threshold for accepting peace
	if randi() % max(int(personality.make_peace_rand), 1) != 0:
		# Didn't trigger peace consideration this turn
		# But still check if we're losing badly
		var our_power = DiplomacySystem._calculate_power(player)
		var their_power = DiplomacySystem._calculate_power(other)
		if our_power < their_power * 0.5:
			# Badly losing — even warmongers consider peace
			if not other.is_human:
				_make_peace_with_cooldown(player, other)
		return

	# Don't consider peace in the first 10 turns of war (scaled by game speed)
	var war_key = "%d:%d" % [player.player_id, other.player_id]
	var war_start = peace_cooldown.get("war_start_" + war_key, 0)
	var min_war_turns = int(10 * GameManager.get_speed_multiplier())
	if TurnManager.current_turn - war_start < min_war_turns:
		return

	var our_power = DiplomacySystem._calculate_power(player)
	var their_power = DiplomacySystem._calculate_power(other)

	# Peaceful leaders (high peace_weight) seek peace more readily
	var peace_threshold = 0.7 + personality.base_peace_weight * 0.05  # 0.7 to 1.2
	if our_power < their_power * peace_threshold:
		if other.is_human:
			return  # Wait for human to propose
		_make_peace_with_cooldown(player, other)
	elif personality.base_peace_weight > 6 and our_power < their_power * 1.2:
		# Very peaceful leaders seek peace even when roughly equal
		if randf() < 0.3:
			if not other.is_human:
				_make_peace_with_cooldown(player, other)

## Consider treaties (open borders, defensive pact)
func _consider_treaties(player, other, flavor: Dictionary) -> void:
	var attitude = DiplomacySystem.calculate_attitude(player, other)

	# Open borders - easier to get
	if other.player_id not in player.open_borders_with:
		if attitude >= -2:  # Cautious or better
			var expansion_flavor = flavor.get("expansion", 5)
			if expansion_flavor >= MEDIUM_FLAVOR or attitude >= 3:
				# Propose open borders
				if not other.is_human:
					if DiplomacySystem.would_accept_proposal(player, other, "open_borders"):
						player.open_borders_with.append(other.player_id)
						other.open_borders_with.append(player.player_id)
						EventBus.open_borders_signed.emit(player, other)

	# Defensive pact - requires good relations
	if other.player_id not in player.defensive_pact_with:
		if attitude >= 3:  # Pleased or better
			var military_flavor = flavor.get("military", 5)
			# Low military AI wants protection, high military wants allies
			if military_flavor < LOW_FLAVOR or attitude >= 5:
				if not other.is_human:
					if DiplomacySystem.would_accept_proposal(player, other, "defensive_pact"):
						player.defensive_pact_with.append(other.player_id)
						other.defensive_pact_with.append(player.player_id)
						EventBus.defensive_pact_signed.emit(player, other)

## Consider trade deals
func _consider_trade(player, other, flavor: Dictionary) -> void:
	# Only trade occasionally to avoid spam
	if randf() > 0.2:
		return

	var gold_flavor = flavor.get("gold", 5)
	var science_flavor = flavor.get("science", 5)

	# Check if we have tradeable techs
	var our_techs = TradeSystem.get_tradeable_techs(player, other)
	var their_techs = TradeSystem.get_tradeable_techs(other, player)

	if our_techs.is_empty() and their_techs.is_empty():
		return

	# Create a trade proposal
	var proposal = TradeSystem.create_proposal(player, other)

	# Tech for tech trade
	if not our_techs.is_empty() and not their_techs.is_empty():
		TradeSystem.add_tech_to_offer(proposal, true, our_techs[0])
		TradeSystem.add_tech_to_offer(proposal, false, their_techs[0])

		if TradeSystem.is_proposal_valid(proposal):
			if not other.is_human:
				if TradeSystem.would_ai_accept(proposal, other.player_id):
					EventBus.trade_accepted.emit(player, other, proposal)
			else:
				# Propose to human player
				EventBus.trade_proposed.emit(player, other, proposal)

## Record peace and start cooldown timer
func _make_peace_with_cooldown(player, other) -> void:
	GameManager.make_peace(player, other)
	var key = "%d:%d" % [player.player_id, other.player_id]
	var key_rev = "%d:%d" % [other.player_id, player.player_id]
	peace_cooldown[key] = TurnManager.current_turn
	peace_cooldown[key_rev] = TurnManager.current_turn
	if sim_logger:
		sim_logger.log_decision(player.player_name, "peace", "make_peace", other.player_name,
			"cooldown until turn %d" % (TurnManager.current_turn + PEACE_COOLDOWN_TURNS))

## Consider declaring war (BTS personality-driven)
func _consider_war(player, other, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)
	var personality = _get_leader_personality(player)

	# Check peace cooldown — cannot redeclare war too soon after making peace
	var cooldown_key = "%d:%d" % [player.player_id, other.player_id]
	var last_peace_turn = peace_cooldown.get(cooldown_key, -999)
	var scaled_cooldown = int(PEACE_COOLDOWN_TURNS * GameManager.get_speed_multiplier())
	if TurnManager.current_turn - last_peace_turn < scaled_cooldown:
		return  # Still in cooldown period

	# BTS max_war_rand: lower = more warlike. Chance per turn scales with personality.
	# Alexander (50) = 8%, Gandhi (400) = 1%, Montezuma (40) = 10%
	var war_chance = 400.0 / max(personality.max_war_rand, 1)
	if randf() * 100.0 > war_chance:
		return  # Didn't roll war this turn

	var attitude = DiplomacySystem.calculate_attitude(player, other)

	# Attitude threshold: aggressive leaders attack at cautious, peaceful need hostility
	# Gandhi (peace=10): need attitude < 0. Alexander (peace=2): need attitude < 3.
	# BTS uses base_peace_weight to scale threshold, but we shift up so wars actually happen
	var war_attitude_threshold = 3 - personality.base_peace_weight / 3
	if attitude > war_attitude_threshold:
		return

	# Check military power
	var our_power = DiplomacySystem._calculate_power(player)
	var their_power = DiplomacySystem._calculate_power(other)

	# Required power ratio: aggressive need only equal power, peaceful need big advantage
	var required_ratio = 1.0 + personality.base_peace_weight * 0.1
	required_ratio = clamp(required_ratio, 1.0, 2.0)

	# Dogpile bonus: if target is already at war, we need less advantage
	var target_at_war = other.at_war_with.size() > 0
	if target_at_war:
		var dogpile_chance = int(personality.dogpile_war_rand)
		if randi() % max(dogpile_chance, 1) == 0:
			required_ratio *= 0.7  # Much lower bar for dogpiling

	# Warmonger respect: leaders who respect strength don't attack stronger foes
	if personality.warmonger_respect >= 2 and their_power > our_power:
		return

	if our_power > their_power * required_ratio:
		# Check defensive pact allies
		var pact_allies_power = 0
		for ally_id in other.defensive_pact_with:
			var ally = GameManager.get_player(ally_id)
			if ally and ally != player:
				pact_allies_power += DiplomacySystem._calculate_power(ally)

		if our_power > (their_power + pact_allies_power) * required_ratio:
			GameManager.declare_war(player, other)
			# Track war start turn for minimum war duration
			var war_key = "%d:%d" % [player.player_id, other.player_id]
			peace_cooldown["war_start_" + war_key] = TurnManager.current_turn
			if sim_logger:
				sim_logger.log_decision(player.player_name, "war", "declare_war", other.player_name,
					"power=%.0f vs %.0f, ratio=%.1f, peace_weight=%d, dogpile=%s" % [
						our_power, their_power, our_power / max(their_power, 1),
						personality.base_peace_weight, str(target_at_war)])

## Process AI espionage decisions
func _process_espionage(player, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)
	var gold_flavor = flavor.get("gold", 5)
	var science_flavor = flavor.get("science", 5)

	# AI uses espionage more when aggressive or behind in tech
	var espionage_priority = (military_flavor + gold_flavor) / 2

	# Only do espionage occasionally (25-50% chance per turn based on personality)
	if randf() > 0.25 + espionage_priority * 0.025:
		return

	# Find best target (enemies or rivals)
	var best_target = null
	var best_target_score = -1

	for other in GameManager.players:
		if other == player or other.player_id not in player.met_players:
			continue

		# Calculate target priority
		var target_score = 0

		# Prefer enemies
		if GameManager.is_at_war(player, other):
			target_score += 50

		# Prefer those with more tech
		target_score += (other.researched_techs.size() - player.researched_techs.size()) * 5

		# Prefer those we dislike
		var attitude = DiplomacySystem.calculate_attitude(player, other)
		target_score -= attitude * 3

		# Check if we have espionage points against them
		var points = EspionageSystem.get_espionage_points(player.player_id, other.player_id)
		if points < 50:
			continue  # Not enough points to do anything

		if target_score > best_target_score:
			best_target_score = target_score
			best_target = other

	if best_target == null:
		return

	# Find best mission to execute
	var target_city = best_target.cities[0] if not best_target.cities.is_empty() else null
	var available_missions = EspionageSystem.get_available_missions(player, best_target, target_city)

	if available_missions.is_empty():
		return

	# Prioritize missions based on personality
	var best_mission = null
	var best_mission_score = -1

	for mission_id in available_missions:
		var mission_score = _score_espionage_mission(mission_id, player, best_target, target_city, flavor)
		if mission_score > best_mission_score:
			best_mission_score = mission_score
			best_mission = mission_id

	if best_mission != null:
		var result = EspionageSystem.execute_mission(best_mission, player, best_target, target_city)
		# AI doesn't need to react to results, just execute

## Score an espionage mission based on AI personality
func _score_espionage_mission(mission_id: String, player, target, target_city, flavor: Dictionary) -> int:
	var score = 10  # Base score

	var military_flavor = flavor.get("military", 5)
	var gold_flavor = flavor.get("gold", 5)
	var science_flavor = flavor.get("science", 5)

	match mission_id:
		"steal_treasury":
			score += gold_flavor * 5
		"steal_technology":
			score += science_flavor * 8
			# Higher priority if behind in tech
			if target.researched_techs.size() > player.researched_techs.size():
				score += 30
		"sabotage_production":
			score += military_flavor * 4
			# Higher priority if at war
			if GameManager.is_at_war(player, target):
				score += 20
		"destroy_building":
			score += military_flavor * 3
		"incite_revolt":
			score += military_flavor * 5
			if GameManager.is_at_war(player, target):
				score += 25
		"poison_water", "spread_unhappiness":
			score += military_flavor * 2
			if GameManager.is_at_war(player, target):
				score += 15
		"counter_espionage":
			score += 5  # Defensive, lower priority for AI
		"see_demographics", "investigate_city", "see_research":
			score += 5  # Information gathering, low priority
		"force_civic_change", "force_religion_change":
			score += military_flavor * 3

	# Reduce score for risky missions if AI is cautious (low military flavor)
	var mission_data = DataManager.get_espionage_mission(mission_id)
	if mission_data:
		var discovery_chance = mission_data.get("discovery_chance", 0)
		if discovery_chance > 50 and military_flavor < MEDIUM_FLAVOR:
			score -= 20

	return score

## Assign military escorts to settlers and workers outside safe territory
func _assign_escorts(player) -> Dictionary:
	var assignments = {}  # military_unit_id -> civilian_unit_id

	# Find civilians that need escorts (outside cities)
	var civilians_needing_escort = []
	for unit in player.units:
		if unit == null or not is_instance_valid(unit):
			continue
		if not (unit.can_found_city() or unit.can_build_improvements()):
			continue
		# Settlers always need escorts; workers need them outside friendly cities
		var in_city = GameManager.get_city_at(unit.grid_position) != null
		if unit.can_found_city() or not in_city:
			civilians_needing_escort.append(unit)

	# Find available military units to escort (not in cities, not already assigned)
	var available_military = []
	for unit in player.units:
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.get_strength() <= 0:
			continue
		if unit.can_found_city() or unit.can_build_improvements():
			continue
		available_military.append(unit)

	# Prioritize settlers over workers for escort assignment
	civilians_needing_escort.sort_custom(func(a, b): return a.can_found_city() and not b.can_found_city())

	for civilian in civilians_needing_escort:
		# Check if already has a military unit on the same tile
		var has_escort = false
		for mil in available_military:
			if mil.grid_position == civilian.grid_position:
				assignments[mil.get_instance_id()] = civilian.get_instance_id()
				available_military.erase(mil)
				has_escort = true
				break

		if not has_escort and not available_military.is_empty():
			# Find closest idle military unit
			var best_mil = null
			var best_dist = 999
			for mil in available_military:
				var dist = GridUtils.chebyshev_distance(mil.grid_position, civilian.grid_position)
				if dist < best_dist:
					best_dist = dist
					best_mil = mil
			if best_mil and best_dist <= 8:
				assignments[best_mil.get_instance_id()] = civilian.get_instance_id()
				available_military.erase(best_mil)

	return assignments

func _process_unit_ai(unit, player, flavor: Dictionary, escort_assignments: Dictionary = {}) -> void:
	if unit.has_acted or unit.movement_remaining <= 0:
		return

	# Auto-promote units with available promotions
	_auto_promote(unit, player)

	# Skip if currently building
	if unit.current_order == UnitClass.UnitOrder.BUILD:
		return

	# Settler: find good city location
	if unit.can_found_city():
		_settler_ai(unit, player, flavor)
		return

	# Worker: build improvements
	if unit.can_build_improvements():
		_worker_ai(unit, player, flavor)
		return

	# Check if this military unit is assigned as escort
	var escort_target_id = escort_assignments.get(unit.get_instance_id(), -1)
	if escort_target_id != -1:
		# Find the civilian we're escorting
		for civ_unit in player.units:
			if is_instance_valid(civ_unit) and civ_unit.get_instance_id() == escort_target_id:
				# Move toward the civilian's position (follow them)
				if unit.grid_position != civ_unit.grid_position:
					_move_toward(unit, civ_unit.grid_position)
				# If on same tile and enemies nearby, fight them
				if is_instance_valid(unit) and unit.movement_remaining > 0:
					var threats = _find_nearby_enemies(unit, player, 1)
					for threat in threats:
						if is_instance_valid(threat) and GridUtils.are_adjacent(unit.grid_position, threat.grid_position):
							CombatSystem.resolve_combat(unit, threat)
							return
				return

	# Combat unit: attack or explore
	_combat_unit_ai(unit, player, flavor)

## Auto-promote units with tactically appropriate promotions based on role
func _auto_promote(unit, player) -> void:
	if not unit.can_promote():
		return

	var available = unit._get_available_promotions()
	if available.is_empty():
		return

	var unit_class = unit.get_unit_class()
	var at_war = not player.at_war_with.is_empty()

	# Determine desired promotions based on unit role
	var priority_promos: Array = []

	match unit_class:
		"siege":
			# Siege wants collateral damage (barrage) and accuracy
			priority_promos = ["barrage1", "barrage2", "barrage3", "accuracy"]
		"mounted":
			# Mounted wants flanking (kills enemy siege) then combat
			priority_promos = ["flanking1", "flanking2", "combat1", "combat2", "combat3"]
		"melee", "gunpowder":
			if at_war:
				# Attackers want City Raider for assaulting cities
				priority_promos = ["city_raider1", "city_raider2", "city_raider3", "combat1", "combat2", "shock"]
			else:
				# Peacetime: general combat readiness
				priority_promos = ["combat1", "combat2", "combat3", "city_garrison1", "city_garrison2", "shock", "cover"]
		"archery":
			# Archers are excellent city defenders
			priority_promos = ["city_garrison1", "city_garrison2", "city_garrison3", "drill1", "drill2", "combat1"]
		_:
			priority_promos = ["combat1", "combat2", "combat3"]

	# Pick highest priority available promotion
	for promo_id in priority_promos:
		if promo_id in available:
			unit.add_promotion(promo_id)
			if sim_logger:
				sim_logger.log_decision(player.player_name, "promotion", "promote_unit",
					"%s -> %s" % [unit.unit_id, promo_id], unit_class)
			return

	# Fallback: pick first available
	if not available.is_empty():
		unit.add_promotion(available[0])

func _settler_ai(unit, player, flavor: Dictionary) -> void:
	if GameManager.hex_grid == null or GameManager.game_world == null:
		return

	# Check if unit has a strategic assignment
	var assigned_site = _get_assigned_site(unit, player)

	# If no assignment, request one from strategy
	if assigned_site.is_empty():
		assigned_site = AIStrategyClass.get_best_unassigned_site(player)
		if not assigned_site.is_empty():
			AIStrategyClass.assign_settler_to_site(player, unit, assigned_site)
			if sim_logger:
				var pos = assigned_site.position
				sim_logger.log_decision(player.player_name, "settler", "assigned_site",
					"(%d,%d) score=%d" % [pos.x, pos.y, assigned_site.score], "")

	if not assigned_site.is_empty():
		var target_pos: Vector2i = assigned_site.position

		# At or near target? Found city.
		var dist_to_target = GridUtils.chebyshev_distance(unit.grid_position, target_pos)
		if dist_to_target == 0 and _can_settle_here(unit.grid_position, player):
			AIStrategyClass.clear_assignment(player, unit)
			GameManager.game_world.found_city(unit)
			return

		# Move toward target — try pathfinding first, then greedy movement
		var pos_before = unit.grid_position
		_move_toward(unit, target_pos)

		# If pathfinding failed, try greedy neighbor movement
		if unit.grid_position == pos_before and unit.movement_remaining > 0:
			_greedy_move_toward(unit, target_pos)

		# Check if at target after moving
		dist_to_target = GridUtils.chebyshev_distance(unit.grid_position, target_pos)
		if dist_to_target <= 1 and _can_settle_here(unit.grid_position, player):
			AIStrategyClass.clear_assignment(player, unit)
			GameManager.game_world.found_city(unit)
			return

		# If couldn't move at all
		if unit.grid_position == pos_before:
			# Try to settle here
			if _can_settle_here(unit.grid_position, player):
				AIStrategyClass.clear_assignment(player, unit)
				GameManager.game_world.found_city(unit)
				return
			# Try settling on any adjacent tile we can move to
			var neighbors = GridUtils.get_neighbors(unit.grid_position)
			for n_pos in neighbors:
				var n_tile = GameManager.hex_grid.get_tile(n_pos)
				if n_tile and n_tile.is_passable() and not n_tile.is_water() and _can_settle_here(n_pos, player):
					if unit.move_to(n_pos):
						AIStrategyClass.clear_assignment(player, unit)
						GameManager.game_world.found_city(unit)
					return
		return

	# Fallback: no strategic sites — found on current tile if acceptable
	if _can_settle_here(unit.grid_position, player):
		GameManager.game_world.found_city(unit)
		return

	# Try moving to any adjacent settleable tile
	if GameManager.hex_grid:
		var neighbors = GridUtils.get_neighbors(unit.grid_position)
		for n_pos in neighbors:
			if _can_settle_here(n_pos, player):
				_move_toward(unit, n_pos)
				if unit.grid_position == n_pos:
					GameManager.game_world.found_city(unit)
				return

func _get_assigned_site(unit, player) -> Dictionary:
	var uid = unit.get_instance_id()
	for site in player.ai_strategy.get("city_sites", []):
		if site.get("assigned_unit_id", -1) == uid:
			return site
	return {}

func _can_settle_here(pos: Vector2i, player) -> bool:
	var tile = GameManager.hex_grid.get_tile(pos) if GameManager.hex_grid else null
	if tile == null or tile.is_water() or not tile.is_passable():
		return false
	for city in player.cities:
		if GridUtils.chebyshev_distance(pos, city.grid_position) < 4:
			return false
	if GameManager.get_city_at(pos) != null:
		return false
	return true

func _worker_ai(unit, player, flavor: Dictionary) -> void:
	var tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
	if tile == null:
		return

	var production_flavor = flavor.get("production", 5)
	var growth_flavor = flavor.get("growth", 5)
	var gold_flavor = flavor.get("gold", 5)

	# If on owned tile without improvement, build one
	if tile.tile_owner == player and tile.improvement_id == "" and tile.road_level == 0:
		var improvements = ImprovementSystem.get_available_improvements(unit, tile)

		if not improvements.is_empty():
			var chosen = _choose_improvement(tile, improvements, production_flavor, growth_flavor, gold_flavor)
			if chosen != "":
				ImprovementSystem.start_build(unit, chosen)
				return

		# Build road if no improvement available
		if ImprovementSystem.can_build_road(unit, tile):
			ImprovementSystem.start_build_road(unit)
			return

	# Move to unimproved owned tile
	var target = _find_unimproved_tile(unit, player)
	if target != Vector2i(-1, -1):
		_move_toward(unit, target)
	else:
		# Fortify if nothing to do
		unit.fortify()

## Choose improvement based on tile and AI preferences
func _choose_improvement(tile, improvements: Array, prod_flavor: int, growth_flavor: int, gold_flavor: int) -> String:
	# Score each improvement
	var best_imp = ""
	var best_score = -1

	for imp_id in improvements:
		var score = 0
		var imp_data = DataManager.get_improvement(imp_id)
		var yields = imp_data.get("yields", {})

		# Score based on yields and flavor
		score += yields.get("food", 0) * growth_flavor
		score += yields.get("production", 0) * prod_flavor
		score += yields.get("commerce", 0) * gold_flavor

		# Bonus for resource improvements
		if tile.resource_id != "":
			var res_data = DataManager.get_resource(tile.resource_id)
			var required_imp = res_data.get("improvement", "")
			if imp_id == required_imp:
				score += 50  # Big bonus for connecting resources

		if score > best_score:
			best_score = score
			best_imp = imp_id

	return best_imp

func _combat_unit_ai(unit, player, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)
	var unit_data = DataManager.get_unit(unit.unit_id)
	var unit_class = unit_data.get("unit_class", "")

	# 0. Siege units: prefer bombarding cities over direct combat (siege-first warfare)
	if unit_class == "siege" and not player.at_war_with.is_empty():
		var bombard_target = _find_bombard_target(unit, player)
		if bombard_target != Vector2i(-1, -1):
			if CombatSystem.can_bombard(unit, bombard_target):
				CombatSystem.bombard_city(unit, bombard_target)
				if sim_logger:
					sim_logger.log_decision(player.player_name, "combat", "bombard_city",
						"(%d,%d)" % [bombard_target.x, bombard_target.y], unit.unit_id)
				return
			else:
				# Move adjacent to target city to bombard next turn
				_move_toward(unit, bombard_target)
				# Try bombarding after moving
				if CombatSystem.can_bombard(unit, bombard_target):
					CombatSystem.bombard_city(unit, bombard_target)
				return

	# 0b. Non-siege near enemy city: wait for siege to soften defenses before assaulting
	if unit_class != "siege" and not player.at_war_with.is_empty():
		var nearby_enemy_city = _find_nearby_enemy_city(unit, player, 3)
		if nearby_enemy_city != null:
			var has_siege_nearby = _has_siege_units_near(unit.grid_position, player, 4)
			if has_siege_nearby:
				var city_defense = nearby_enemy_city.get_defense_strength()
				if city_defense > unit.get_strength() * 1.5:
					# Siege is nearby and city is still well defended — hold position, let siege bombard
					if not GridUtils.are_adjacent(unit.grid_position, nearby_enemy_city.grid_position):
						_move_toward(unit, nearby_enemy_city.grid_position)
					return  # Wait for bombardment to soften

	# 1. Immediate tactical: attack nearby enemies
	var enemies = _find_nearby_enemies(unit, player, 3)
	if not enemies.is_empty():
		var target = _pick_best_target(unit, enemies, military_flavor)
		if target:
			var odds = CombatSystem.calculate_odds(unit, target)
			var min_odds = 0.35 - (military_flavor - 5) * 0.05
			min_odds = clamp(min_odds, 0.2, 0.5)

			# Lower threshold when defending own territory or desperate
			var in_own_territory = false
			var own_tile = GameManager.hex_grid.get_tile(unit.grid_position) if GameManager.hex_grid else null
			if own_tile and own_tile.tile_owner == player:
				in_own_territory = true
				min_odds *= 0.6  # Fight harder to defend homeland

			if odds.win_chance > min_odds:
				if GridUtils.are_adjacent(unit.grid_position, target.grid_position):
					if sim_logger:
						sim_logger.log_decision(player.player_name, "combat", "attack",
							"%s vs %s at (%d,%d)" % [unit.unit_id, target.unit_id, target.grid_position.x, target.grid_position.y],
							"odds=%.0f%%" % (odds.win_chance * 100))
					CombatSystem.resolve_combat(unit, target)
					return
				else:
					_move_toward(unit, target.grid_position)
					# After moving, check if we're now adjacent and can attack
					if is_instance_valid(unit) and is_instance_valid(target) and unit.movement_remaining > 0:
						if GridUtils.are_adjacent(unit.grid_position, target.grid_position):
							if sim_logger:
								sim_logger.log_decision(player.player_name, "combat", "attack_after_move",
									"%s vs %s" % [unit.unit_id, target.unit_id],
									"odds=%.0f%%" % (odds.win_chance * 100))
							CombatSystem.resolve_combat(unit, target)
					return
			elif sim_logger:
				sim_logger.log_decision(player.player_name, "combat", "skip_bad_odds",
					"%s vs %s" % [unit.unit_id, target.unit_id],
					"odds=%.0f%% < min %.0f%%" % [odds.win_chance * 100, min_odds * 100])

	# 2. Strategic: move toward assigned war target
	if not player.at_war_with.is_empty():
		var war_target = AIStrategyClass.get_war_target_for_unit(player, unit)
		if not war_target.is_empty():
			_move_toward(unit, war_target.city_position)
			# After moving, check for enemies to attack
			if is_instance_valid(unit) and unit.movement_remaining > 0:
				var new_enemies = _find_nearby_enemies(unit, player, 1)
				for enemy in new_enemies:
					if is_instance_valid(enemy) and GridUtils.are_adjacent(unit.grid_position, enemy.grid_position):
						var new_odds = CombatSystem.calculate_odds(unit, enemy)
						if new_odds.win_chance > 0.4:
							CombatSystem.resolve_combat(unit, enemy)
							break
			return

	# 3. Strategic: garrison threatened cities
	var defense_need = AIStrategyClass.get_city_needing_garrison(player, unit)
	if not defense_need.is_empty():
		_move_toward(unit, defense_need.city_position)
		if unit.grid_position == defense_need.city_position:
			unit.fortify()
		return

	# 4. Fallback: garrison undefended own cities
	for city in player.cities:
		var garrison = GameManager.get_units_at(city.grid_position)
		var has_military = false
		for g_unit in garrison:
			if g_unit.player_owner == player and g_unit.get_strength() > 0:
				has_military = true
				break
		if not has_military:
			_move_toward(unit, city.grid_position)
			if unit.grid_position == city.grid_position:
				unit.fortify()
			return

	# 5. Explore unexplored tiles
	var unexplored = _find_nearest_unexplored(unit, player)
	if unexplored != Vector2i(-1, -1):
		_move_toward(unit, unexplored)
		return

	# 6. Nothing to do
	unit.fortify()

## Pick best target from enemies
func _pick_best_target(unit, enemies: Array, military_flavor: int):
	var best_target = null
	var best_score = -INF

	for enemy in enemies:
		var odds = CombatSystem.calculate_odds(unit, enemy)
		var score = odds.win_chance * 100

		# Bonus for killing shot
		if enemy.health <= unit.get_strength() * 10:
			score += 20

		# Aggressive AI prefers attacking
		score += military_flavor * 2

		if score > best_score:
			best_score = score
			best_target = enemy

	return best_target

func _process_city_ai(city, player, flavor: Dictionary) -> void:
	# Consider whipping current production to completion (Slavery civic)
	if city.current_production != "":
		_consider_whipping(city, player)
		return

	# Check strategic production advice first
	var strategic_prod = AIStrategyClass.get_production_advice(player, city, flavor)
	if strategic_prod != "" and city.can_build_unit(strategic_prod):
		city.set_production(strategic_prod)
		return

	var military_flavor = flavor.get("military", 5)
	var science_flavor = flavor.get("science", 5)
	var growth_flavor = flavor.get("growth", 5)
	var production_flavor = flavor.get("production", 5)
	var culture_flavor = flavor.get("culture", 5)
	var expansion_flavor = flavor.get("expansion", 5)

	# Determine city specialization
	var specialization = _determine_city_specialization(city, player, flavor)

	# Apply difficulty bonuses
	var bonuses = _get_ai_bonuses()
	var prod_bonus = bonuses.get("production_percent", 0)

	# Count units
	var num_units = player.units.size()
	var num_cities = player.cities.size()
	var military_units = 0
	var workers = 0
	for u in player.units:
		if u.get_strength() > 0:
			military_units += 1
		if u.can_build_improvements():
			workers += 1

	# Early expansion: settler is top priority when only 1 city (unless at war)
	var map_tiles = GameManager.map_width * GameManager.map_height
	var base_cities = max(3, map_tiles / 300)
	var max_cities = base_cities + expansion_flavor
	if num_cities <= 1 and city.population >= 2 and player.at_war_with.is_empty():
		if city.can_build_unit("settler"):
			city.set_production("settler")
			return

	# Calculate desired military based on flavor, specialization, and personality
	var personality = _get_leader_personality(player)
	var build_unit_prob = personality.get("build_unit_prob", 40)
	var desired_military = num_cities * (1 + military_flavor / 5) * (build_unit_prob / 40.0)
	if specialization == CitySpecialization.MILITARY:
		desired_military *= 1.5

	# Hard cap: never exceed cities*4+6 military units
	var max_military = num_cities * 4 + 6
	# Economic cap: don't build more military if going broke
	var free_supply = num_cities + 2
	if player.gold <= 0 and military_units > free_supply:
		max_military = military_units  # Don't add more when bankrupt
	var need_military = military_units < desired_military and military_units < max_military

	# Calculate army composition — ensure 30% siege when at war
	var siege_count = 0
	for u in player.units:
		var udata = DataManager.get_unit(u.unit_id)
		if udata.get("unit_class", "") == "siege":
			siege_count += 1
	var siege_ratio = float(siege_count) / max(military_units, 1)
	var needs_siege = not player.at_war_with.is_empty() and siege_ratio < 0.3 and military_units >= 3

	if need_military:
		var unit_to_build = _get_best_military_unit(city, player, military_flavor, needs_siege)
		if unit_to_build != "":
			city.set_production(unit_to_build)
			return

	# Need settler?
	if num_cities < max_cities and city.population >= 2:
		if city.can_build_unit("settler"):
			city.set_production("settler")
			return

	# Need worker?
	var desired_workers = max(1, num_cities)
	if workers < desired_workers:
		if city.can_build_unit("worker"):
			city.set_production("worker")
			return

	# Build infrastructure based on flavor AND specialization
	var building_to_build = _get_best_building_for_specialization(city, player, flavor, specialization)
	if building_to_build != "":
		city.set_production(building_to_build)
		return

	# Consider projects (high production cities, late game)
	var project_to_build = _get_best_project(city, player, flavor, specialization)
	if project_to_build != "":
		city.set_production(project_to_build)
		return

	# Default: build military if under cap
	if military_units < max_military:
		var unit_to_build = _get_best_military_unit(city, player, military_flavor)
		if unit_to_build != "":
			city.set_production(unit_to_build)
			return

	# Fallback: build ANY available unit or building so city is never idle
	for unit_id in DataManager.units:
		if city.can_build_unit(unit_id):
			var udata = DataManager.get_unit(unit_id)
			if udata.get("combat_strength", 0) > 0 or udata.get("unit_class", "") == "civilian":
				city.set_production(unit_id)
				return
	for bld_id in DataManager.buildings:
		if city.can_build_building(bld_id):
			city.set_production(bld_id)
			return

## Consider using Slavery whip to rush critical production
func _consider_whipping(city, player) -> void:
	# Only whip with Slavery civic active
	if player.civics.get("labor", "") != "slavery":
		return

	if not city.can_whip():
		return

	# Never whip below population 3 (preserves growth)
	if city.population <= 2:
		return

	# Don't whip if already suffering whip anger
	if city.has_meta("whip_anger_turns") and city.get_meta("whip_anger_turns") > 0:
		return

	var should_whip = false
	var at_war = not player.at_war_with.is_empty()
	var prod = city.current_production
	var cost = city.get_production_cost()
	var progress_ratio = float(city.production_progress) / max(cost, 1)

	# At war + building military unit + over 50% complete → whip
	if at_war and prod != "":
		var unit_data = DataManager.get_unit(prod)
		if not unit_data.is_empty() and unit_data.get("strength", 0) > 0:
			if progress_ratio > 0.5:
				should_whip = true

	# Building settler + over 50% complete → whip
	if prod == "settler" and progress_ratio > 0.5:
		should_whip = true

	# Building critical early building with pop >= 4 → whip
	if city.population >= 4:
		if prod in ["granary", "library"]:
			should_whip = true
		elif prod == "barracks" and at_war:
			should_whip = true

	if should_whip:
		city.whip()
		if sim_logger:
			sim_logger.log_decision(player.player_name, "production", "whip",
				"%s in %s (pop %d->%d)" % [prod, city.city_name, city.population + 1, city.population], "")

func _process_research(player, flavor: Dictionary) -> void:
	# Manage science rate based on gold situation
	_manage_science_rate(player)

	if player.current_research != "":
		return

	# Find available techs
	var available_techs = []
	for tech_id in DataManager.techs:
		if player.can_research(tech_id):
			available_techs.append(tech_id)

	if available_techs.is_empty():
		return

	# Prioritize techs based on leader flavor
	var best_tech = available_techs[0]
	var best_score = -INF

	for tech_id in available_techs:
		var score = _evaluate_tech(tech_id, player, flavor)
		if score > best_score:
			best_score = score
			best_tech = tech_id

	player.start_research(best_tech)
	if sim_logger:
		var tech_name = DataManager.get_tech(best_tech).get("name", best_tech)
		sim_logger.log_decision(player.player_name, "research", "start_research", tech_name,
			"score=%.0f, available=%d" % [best_score, available_techs.size()])

## Manage science vs gold slider based on economic situation
func _manage_science_rate(player) -> void:
	# Estimate current gold per turn at current science rate
	var est_gpt = _estimate_gold_per_turn(player)

	if player.gold <= 10 or est_gpt < -5:
		# Need more gold — find break-even science rate
		while player.science_rate > 0.0:
			player.science_rate = max(0.0, player.science_rate - 0.1)
			for city in player.cities:
				city.calculate_yields()
			est_gpt = _estimate_gold_per_turn(player)
			if est_gpt >= 0 or player.science_rate <= 0.01:
				break
	elif player.gold > 100 and est_gpt >= 5 and player.science_rate < 1.0:
		# Can afford more science — try increasing
		var old_rate = player.science_rate
		player.science_rate = min(1.0, player.science_rate + 0.1)
		for city in player.cities:
			city.calculate_yields()
		# Verify it's still affordable
		if _estimate_gold_per_turn(player) < 0:
			player.science_rate = old_rate
			for city in player.cities:
				city.calculate_yields()

## Estimate gold per turn based on current city yields and known costs
func _estimate_gold_per_turn(player) -> int:
	var total_gold = 0
	for city in player.cities:
		total_gold += city.gold_yield

	# Estimate maintenance (mirrors turn_manager logic)
	var num_cities = player.cities.size()
	var capital_pos = Vector2i.ZERO
	for city in player.cities:
		if "palace" in city.buildings:
			capital_pos = city.grid_position
			break

	var maintenance = 0
	for city in player.cities:
		var dist = GridUtils.chebyshev_distance(city.grid_position, capital_pos)
		var dist_cost = int(dist * 0.5)
		if "courthouse" in city.buildings:
			dist_cost = dist_cost / 2
		var count_cost = int((num_cities - 1) * 0.5)
		maintenance += dist_cost + count_cost

	# Unit supply
	var military_count = 0
	for unit in player.units:
		if DataManager.get_unit_strength(unit.unit_id) > 0:
			military_count += 1
	var free_units = num_cities + 2
	var excess = max(0, military_count - free_units)

	# Inflation
	var inflation = min(1.0 + TurnManager.current_turn * 0.001, 1.5)
	maintenance = int(maintenance * inflation)
	excess = int(excess * inflation)

	return total_gold - maintenance - excess

func _evaluate_tech(tech_id: String, player, flavor: Dictionary) -> float:
	var score = 0.0
	var tech = DataManager.get_tech(tech_id)
	var unlocks = tech.get("unlocks", {})

	var military_flavor = flavor.get("military", 5)
	var science_flavor = flavor.get("science", 5)
	var gold_flavor = flavor.get("gold", 5)
	var culture_flavor = flavor.get("culture", 5)
	var religion_flavor = flavor.get("religion", 5)

	# Value units - more if military focused
	if unlocks.has("units"):
		score += unlocks.units.size() * 10 * (military_flavor / 5.0)

	# Value buildings
	if unlocks.has("buildings"):
		for building_id in unlocks.buildings:
			var building = DataManager.get_building(building_id)
			var effects = building.get("effects", {})

			# Science buildings
			if effects.has("science_percent") or effects.has("science"):
				score += 15 * (science_flavor / 5.0)
			# Gold buildings
			if effects.has("gold_percent") or effects.has("gold"):
				score += 10 * (gold_flavor / 5.0)
			# Culture buildings
			if effects.has("culture"):
				score += 10 * (culture_flavor / 5.0)
			# Military buildings
			if effects.has("experience") or effects.has("happiness"):
				score += 8 * (military_flavor / 5.0)

			score += 5  # Base building value

	# Value improvements
	if unlocks.has("improvements"):
		score += unlocks.improvements.size() * 3

	# Religion techs
	if unlocks.has("religions"):
		score += 20 * (religion_flavor / 5.0)

	# Cheaper is better
	var cost = DataManager.get_tech_cost(tech_id)
	score += max(0, 50 - cost / 20)

	# === Strategic beelining bonuses (Civ4 BTS key tech paths) ===
	var num_techs = player.researched_techs.size()

	# Early game priorities (< 10 techs researched)
	if num_techs < 10:
		match tech_id:
			"bronze_working": score += 40  # Slavery civic + chopping + copper reveal
			"pottery": score += 25  # Cottages for economy
			"writing": score += 20  # Libraries for research
			"animal_husbandry": score += 15  # Horse reveal

	# Economy critical path — always valuable, scaled by flavor
	match tech_id:
		"mathematics": score += 30 * (science_flavor / 5.0)  # Chop bonus, catapults
		"currency": score += 35 * (gold_flavor / 5.0)  # Trade routes, gold
		"code_of_laws": score += 25 * (gold_flavor / 5.0)  # Courthouses for expansion

	# Military beeline (aggressive leaders)
	if military_flavor >= HIGH_FLAVOR:
		match tech_id:
			"construction": score += 30  # Catapults — siege!
			"machinery": score += 25  # Macemen, crossbowmen
			"civil_service": score += 20  # Macemen, Bureaucracy civic

	# Science beeline (research-focused leaders)
	if science_flavor >= HIGH_FLAVOR:
		match tech_id:
			"philosophy": score += 20  # Pacifism civic
			"education": score += 25  # Universities
			"liberalism": score += 40  # Free tech!

	# Religion founding (devout leaders without a religion)
	if religion_flavor >= HIGH_FLAVOR and player.state_religion == "":
		match tech_id:
			"meditation", "polytheism": score += 30
			"monotheism", "theology": score += 20

	# Bonus for techs that reveal strategic resources on tiles we own
	var reveals = tech.get("reveals_resource", "")
	if reveals != "" and GameManager.hex_grid:
		for city in player.cities:
			for tile_pos in city.territory:
				var r_tile = GameManager.hex_grid.get_tile(tile_pos)
				if r_tile and r_tile.resource_id == reveals:
					score += 20
					break

	return score

# Helper functions
func _is_good_city_location(pos: Vector2i, player) -> bool:
	# Must be 4+ tiles from OWN cities
	for city in player.cities:
		if GridUtils.chebyshev_distance(pos, city.grid_position) < 4:
			return false

	# Must be 3+ tiles from OTHER players' cities (avoid overlap but don't block expansion)
	for other in GameManager.players:
		if other == player:
			continue
		for city in other.cities:
			if GridUtils.chebyshev_distance(pos, city.grid_position) < 3:
				return false

	# Check tile is on land
	if GameManager.hex_grid == null:
		return false
	var center_tile = GameManager.hex_grid.get_tile(pos)
	if center_tile == null or center_tile.is_water() or not center_tile.is_passable():
		return false

	# Check has enough food-producing tiles nearby
	var good_tiles = 0
	var tiles = GridUtils.get_tiles_in_range(pos, 2)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile != null and tile.get_food() >= 1:
			good_tiles += 1

	return good_tiles >= 2

func _find_best_city_location(unit, player, flavor: Dictionary) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_score = -1

	var growth_flavor = flavor.get("growth", 5)
	var production_flavor = flavor.get("production", 5)
	var gold_flavor = flavor.get("gold", 5)

	# Search in expanding rings
	for radius in range(1, 15):
		var tiles = GridUtils.get_tiles_at_range(unit.grid_position, radius)
		for tile_pos in tiles:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null or not tile.is_passable() or tile.is_water():
				continue

			if _is_good_city_location(tile_pos, player):
				var score = _evaluate_city_location(tile_pos, growth_flavor, production_flavor, gold_flavor)
				if score > best_score:
					best_score = score
					best_pos = tile_pos

		if best_pos != Vector2i(-1, -1):
			break

	return best_pos

func _evaluate_city_location(pos: Vector2i, growth_flavor: int, prod_flavor: int, gold_flavor: int) -> int:
	var score = 0
	var tiles = GridUtils.get_tiles_in_range(pos, 2)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile != null:
			score += tile.get_food() * growth_flavor
			score += tile.get_production() * prod_flavor
			score += tile.get_commerce() * gold_flavor
			if tile.resource_id != "":
				score += 15  # Resources are always valuable
	return score

## Greedy movement toward target — picks closest valid neighbor.
## Used as fallback when pathfinding fails.
func _greedy_move_toward(unit, target: Vector2i) -> void:
	if GameManager.hex_grid == null or unit.movement_remaining <= 0:
		return

	var best_pos = unit.grid_position
	var best_dist = GridUtils.chebyshev_distance(unit.grid_position, target)

	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	for n_pos in neighbors:
		# Use the unit's own can_move_to which checks all restrictions
		if unit.can_move_to(n_pos):
			var dist = GridUtils.chebyshev_distance(n_pos, target)
			if dist < best_dist:
				best_dist = dist
				best_pos = n_pos

	if best_pos != unit.grid_position:
		unit.move_to(best_pos)

func _move_toward(unit, target: Vector2i) -> void:
	if GameManager.hex_grid == null:
		return

	var pathfinder = PathfindingClass.new(GameManager.hex_grid, unit)
	var path = pathfinder.find_path_with_movement(
		unit.grid_position, target, unit.movement_remaining
	)

	if path.size() > 0:
		# Move along path as far as possible
		for pos in path:
			if unit.movement_remaining > 0:
				unit.move_to(pos)
			else:
				break

func _find_unimproved_tile(unit, player) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_score = -INF

	# Check owned tiles with scoring (not just distance)
	for city in player.cities:
		var city_needs_prod = _city_needs_production_rush(city)
		for tile_pos in city.territory:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null:
				continue
			if tile.improvement_id == "" and tile.road_level == 0 and not tile.is_water():
				var dist = GridUtils.chebyshev_distance(unit.grid_position, tile_pos)
				var score = 100.0 - dist * 5.0  # Base: closer is better

				# Forest chopping priority: boost forest tiles near cities needing production
				if tile.feature_id == "forest":
					if city_needs_prod:
						score += 30  # High priority: city is building settler/wonder/military
					# Tiles where forest should be cleared for better improvements
					if tile.has_fresh_water() or tile.terrain_id == "hills":
						score += 15  # River farms or hill mines are better without forest

				# Resource tiles are always high priority
				if tile.resource_id != "":
					score += 25

				if score > best_score:
					best_score = score
					best_pos = tile_pos

	return best_pos

## Check if a city has urgent production needs (settler, wonder, military at war)
func _city_needs_production_rush(city) -> bool:
	if city.current_production == "":
		return false
	if city.current_production == "settler":
		return true
	# Check if building a wonder
	var building = DataManager.get_building(city.current_production)
	if not building.is_empty() and building.get("wonder_type", "") != "":
		return true
	# Check if building military while at war
	if city.player_owner and not city.player_owner.at_war_with.is_empty():
		var unit_data = DataManager.get_unit(city.current_production)
		if not unit_data.is_empty() and unit_data.get("strength", 0) > 0:
			return true
	return false

func _find_nearby_enemies(unit, player, range_val: int) -> Array:
	var enemies = []
	if GameManager.hex_grid == null:
		return enemies

	var tiles = GridUtils.get_tiles_in_range(unit.grid_position, range_val)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile == null:
			continue
		var units_here = GameManager.get_units_at(tile_pos)
		for other_unit in units_here:
			if other_unit.player_owner != player and other_unit.get_strength() > 0:
				if GameManager.is_at_war(player, other_unit.player_owner):
					enemies.append(other_unit)

	return enemies

func _find_nearest_unexplored(unit, player) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_dist = INF

	# Visibility state constant
	const UNEXPLORED = 0

	# Search in expanding rings
	for radius in range(1, 20):
		var tiles = GridUtils.get_tiles_at_range(unit.grid_position, radius)
		for tile_pos in tiles:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null:
				continue

			var visibility = tile.get_visibility_for_player(player.player_id)
			if visibility == UNEXPLORED:
				# Check if we can actually reach a tile next to it
				var neighbors = GridUtils.get_neighbors(tile_pos)
				for neighbor in neighbors:
					var neighbor_tile = GameManager.hex_grid.get_tile(neighbor)
					if neighbor_tile != null and neighbor_tile.is_passable() and not neighbor_tile.is_water():
						var dist = GridUtils.chebyshev_distance(unit.grid_position, neighbor)
						if dist < best_dist:
							best_dist = dist
							best_pos = neighbor

		if best_pos != Vector2i(-1, -1):
			break

	return best_pos

## Find nearest enemy city that a siege unit can bombard
func _find_bombard_target(unit, player) -> Vector2i:
	var best_pos = Vector2i(-1, -1)
	var best_dist = INF

	for enemy_id in player.at_war_with:
		var enemy = GameManager.get_player(enemy_id)
		if enemy == null:
			continue
		for city in enemy.cities:
			var dist = GridUtils.chebyshev_distance(unit.grid_position, city.grid_position)
			if dist < best_dist:
				best_dist = dist
				best_pos = city.grid_position

	# Only return targets within reasonable range (siege is slow)
	if best_dist <= 8:
		return best_pos
	return Vector2i(-1, -1)

## Find nearby enemy city within given range
func _find_nearby_enemy_city(unit, player, search_range: int):
	var best_city = null
	var best_dist = INF

	for enemy_id in player.at_war_with:
		var enemy = GameManager.get_player(enemy_id)
		if enemy == null:
			continue
		for city in enemy.cities:
			var dist = GridUtils.chebyshev_distance(unit.grid_position, city.grid_position)
			if dist <= search_range and dist < best_dist:
				best_dist = dist
				best_city = city

	return best_city

## Check if player has siege units near a position
func _has_siege_units_near(pos: Vector2i, player, search_range: int) -> bool:
	for unit in player.units:
		var udata = DataManager.get_unit(unit.unit_id)
		if udata.get("unit_class", "") == "siege":
			if GridUtils.chebyshev_distance(pos, unit.grid_position) <= search_range:
				return true
	return false

func _get_best_military_unit(city, player, military_flavor: int, needs_siege: bool = false) -> String:
	# Analyze enemy army composition to build counters
	var enemy_classes = {}
	for other in GameManager.players:
		if other == player or other.player_id not in player.at_war_with:
			continue
		for unit in other.units:
			var udata = DataManager.get_unit(unit.unit_id)
			var uclass = udata.get("unit_class", "")
			enemy_classes[uclass] = enemy_classes.get(uclass, 0) + 1

	var best_unit = ""
	var best_score = 0.0

	for unit_id in DataManager.units:
		if not city.can_build_unit(unit_id):
			continue

		var unit_data = DataManager.get_unit(unit_id)
		var strength = DataManager.get_unit_strength(unit_id)
		var unit_class = unit_data.get("unit_class", "")

		if unit_class not in ["melee", "mounted", "gunpowder", "archery", "armor", "siege"]:
			continue

		var score = float(strength)

		# Counter bonuses: prefer units that counter enemy composition
		if not enemy_classes.is_empty():
			# Mounted counters archery/siege; melee/gunpowder counter mounted; archery/siege counter melee
			if unit_class == "mounted" and (enemy_classes.get("archery", 0) + enemy_classes.get("siege", 0)) > 0:
				score *= 1.3
			elif unit_class in ["melee", "gunpowder"] and enemy_classes.get("mounted", 0) > 0:
				score *= 1.3
			elif unit_class in ["archery", "siege"] and enemy_classes.get("melee", 0) > 0:
				score *= 1.2
			# Siege is always valuable when at war
			if unit_class == "siege":
				score *= 1.2

		# Army composition: strong preference for siege when ratio is low
		if needs_siege and unit_class == "siege":
			score *= 2.0
		# Boost mounted to counter enemy siege (flanking kills siege)
		if not enemy_classes.is_empty() and enemy_classes.get("siege", 0) > 0 and unit_class == "mounted":
			score *= 1.4

		if score > best_score:
			best_score = score
			best_unit = unit_id

	return best_unit

## Get the best project to build based on AI flavor and game state
func _get_best_project(city, player, flavor: Dictionary, specialization) -> String:
	# Only high-production cities should build projects
	if city.production_yield < 15:
		return ""

	# Only production-focused cities build projects
	if specialization not in [CitySpecialization.PRODUCTION, CitySpecialization.HYBRID]:
		return ""

	var science_flavor = flavor.get("science", 5)
	var military_flavor = flavor.get("military", 5)

	var best_project = ""
	var best_score = 0

	for project_id in ProjectsSystem.projects:
		var check = ProjectsSystem.can_build_project(project_id, player, city)
		if not check.can_build:
			continue

		var project = ProjectsSystem.projects[project_id]
		var score = 0
		var project_type = project.get("type", "")

		# Spaceship parts - prioritize if going for space victory
		if project.get("spaceship_part", false):
			score = 100 + science_flavor * 10

		# Apollo Program - high priority for science-focused AI
		elif project_id == "apollo_program":
			score = 80 + science_flavor * 8

		# Manhattan Project - military AI wants nukes
		elif project_id == "manhattan_project":
			score = 50 + military_flavor * 10

		# SDI - defensive, prioritize if nukes exist
		elif project_id == "sdi":
			if ProjectsSystem.global_projects.has("manhattan_project"):
				score = 70

		# The Internet - science AI loves this
		elif project_id == "the_internet":
			score = 60 + science_flavor * 8

		if score > best_score:
			best_score = score
			best_project = project_id

	return best_project

## Determine the best specialization for a city based on location and resources
func _determine_city_specialization(city, player, flavor: Dictionary) -> CitySpecialization:
	if GameManager.hex_grid == null:
		return CitySpecialization.HYBRID

	# Analyze city's tiles
	var total_food = 0
	var total_production = 0
	var total_commerce = 0
	var has_strategic = false
	var coastal = false
	var near_border = false

	for tile_pos in city.territory:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile == null:
			continue

		total_food += tile.get_food()
		total_production += tile.get_production()
		total_commerce += tile.get_commerce()

		if tile.is_water():
			coastal = true

		# Check for strategic resources
		if tile.resource_id != "":
			var res_data = DataManager.get_resource(tile.resource_id)
			if res_data.get("type", "") == "strategic":
				has_strategic = true

	# Check if near enemy borders
	for other in GameManager.players:
		if other == player or other.player_id not in player.met_players:
			continue
		if GameManager.is_at_war(player, other) or DiplomacySystem.calculate_attitude(player, other) < -2:
			for other_city in other.cities:
				if GridUtils.chebyshev_distance(city.grid_position, other_city.grid_position) < 8:
					near_border = true
					break

	# Check if this is the capital (usually best for science/gold)
	var is_capital = player.cities.size() > 0 and city == player.cities[0]

	# Score each specialization
	var scores = {
		CitySpecialization.HYBRID: 10,
		CitySpecialization.PRODUCTION: 0,
		CitySpecialization.SCIENCE: 0,
		CitySpecialization.GOLD: 0,
		CitySpecialization.MILITARY: 0,
		CitySpecialization.CULTURE: 0,
		CitySpecialization.FOOD: 0
	}

	# Production specialization
	if total_production > 30:
		scores[CitySpecialization.PRODUCTION] += 20
	if has_strategic:
		scores[CitySpecialization.PRODUCTION] += 15
	scores[CitySpecialization.PRODUCTION] += flavor.get("production", 5) * 2

	# Science specialization
	if is_capital:
		scores[CitySpecialization.SCIENCE] += 15
	if total_commerce > 25:
		scores[CitySpecialization.SCIENCE] += 10
	scores[CitySpecialization.SCIENCE] += flavor.get("science", 5) * 3

	# Gold specialization
	if coastal:
		scores[CitySpecialization.GOLD] += 10  # Trade routes
	if total_commerce > 30:
		scores[CitySpecialization.GOLD] += 15
	scores[CitySpecialization.GOLD] += flavor.get("gold", 5) * 2

	# Military specialization
	if near_border:
		scores[CitySpecialization.MILITARY] += 25
	if has_strategic:
		scores[CitySpecialization.MILITARY] += 10
	scores[CitySpecialization.MILITARY] += flavor.get("military", 5) * 2

	# Culture specialization
	scores[CitySpecialization.CULTURE] += flavor.get("culture", 5) * 2
	if city.religions.size() > 1:
		scores[CitySpecialization.CULTURE] += 10  # Multiple religions = culture

	# Food specialization
	if total_food > 35:
		scores[CitySpecialization.FOOD] += 20
	scores[CitySpecialization.FOOD] += flavor.get("growth", 5) * 2

	# Find highest scoring specialization
	var best_spec = CitySpecialization.HYBRID
	var best_score = scores[CitySpecialization.HYBRID]

	for spec in scores:
		if scores[spec] > best_score:
			best_score = scores[spec]
			best_spec = spec

	return best_spec

## Get building priority modifiers based on city specialization
func _get_specialization_modifiers(specialization: CitySpecialization) -> Dictionary:
	match specialization:
		CitySpecialization.PRODUCTION:
			return {"production": 2.0, "production_percent": 2.0, "experience": 1.5, "science": 0.8, "gold": 0.8}
		CitySpecialization.SCIENCE:
			return {"science": 2.0, "science_percent": 2.5, "culture": 1.2, "production": 0.7}
		CitySpecialization.GOLD:
			return {"gold": 2.0, "gold_percent": 2.5, "culture": 1.0, "science": 0.8}
		CitySpecialization.MILITARY:
			return {"experience": 3.0, "happiness": 2.0, "production": 1.5, "defense": 2.0, "health": 1.5}
		CitySpecialization.CULTURE:
			return {"culture": 3.0, "happiness": 1.5, "science": 1.0, "great_person": 2.0}
		CitySpecialization.FOOD:
			return {"food": 2.5, "health": 2.0, "happiness": 1.5, "growth": 2.0}
		_:  # HYBRID
			return {}

## Get best building considering city specialization
func _get_best_building_for_specialization(city, player, flavor: Dictionary, specialization: CitySpecialization) -> String:
	var science_flavor = flavor.get("science", 5)
	var gold_flavor = flavor.get("gold", 5)
	var culture_flavor = flavor.get("culture", 5)
	var military_flavor = flavor.get("military", 5)
	var growth_flavor = flavor.get("growth", 5)
	var production_flavor = flavor.get("production", 5)

	# Get specialization modifiers
	var spec_mods = _get_specialization_modifiers(specialization)

	# Score buildings based on flavor AND specialization
	var best_building = ""
	var best_score = -1

	for building_id in DataManager.buildings:
		if not city.can_build_building(building_id):
			continue

		var building = DataManager.get_building(building_id)

		# Wonder handling using leader personality
		var wonder_type = building.get("wonder_type", "")
		if wonder_type != "":
			# Skip if another city already building this wonder
			var already_building = false
			for other_city in player.cities:
				if other_city != city and other_city.current_production == building_id:
					already_building = true
					break
			if already_building:
				continue

			# Leaders with low wonder_construct_rand skip wonders more often
			var personality = _get_leader_personality(player)
			var wonder_rand = personality.get("wonder_construct_rand", 30)
			if randi() % 100 >= wonder_rand:
				continue  # Skip this wonder based on personality

		var effects = building.get("effects", {})
		var score = 0.0

		# Science
		if effects.has("science_percent"):
			var mod = spec_mods.get("science_percent", 1.0)
			score += effects.science_percent * science_flavor / 5 * mod
		if effects.has("science"):
			var mod = spec_mods.get("science", 1.0)
			score += effects.science * science_flavor * mod

		# Gold
		if effects.has("gold_percent"):
			var mod = spec_mods.get("gold_percent", 1.0)
			score += effects.gold_percent * gold_flavor / 5 * mod
		if effects.has("gold"):
			var mod = spec_mods.get("gold", 1.0)
			score += effects.gold * gold_flavor * mod

		# Culture
		if effects.has("culture"):
			var mod = spec_mods.get("culture", 1.0)
			score += effects.culture * culture_flavor * mod

		# Military
		if effects.has("experience"):
			var mod = spec_mods.get("experience", 1.0)
			score += effects.experience * military_flavor * 2 * mod
		if effects.has("happiness"):
			var mod = spec_mods.get("happiness", 1.0)
			score += effects.happiness * 5 * mod

		# Defense bonus (for military cities)
		if effects.has("defense"):
			var mod = spec_mods.get("defense", 1.0)
			score += effects.defense * military_flavor * mod

		# Growth
		if effects.has("food"):
			var mod = spec_mods.get("food", 1.0)
			score += effects.food * growth_flavor * 2 * mod
		if effects.has("health"):
			var mod = spec_mods.get("health", 1.0)
			score += effects.health * growth_flavor * mod

		# Production
		if effects.has("production"):
			var mod = spec_mods.get("production", 1.0)
			score += effects.production * production_flavor * 2 * mod
		if effects.has("production_percent"):
			var mod = spec_mods.get("production_percent", 1.0)
			score += effects.production_percent * production_flavor / 5 * mod

		# Great person points (valuable for culture/science cities)
		if effects.has("great_person_points"):
			var mod = spec_mods.get("great_person", 1.0)
			score += effects.great_person_points * mod * 3

		# Reduce score by cost (prefer cheaper when scores are similar)
		var cost = building.get("cost", 100)
		score -= cost / 50

		if score > best_score:
			best_score = score
			best_building = building_id

	return best_building

func _get_best_building(city, player, flavor: Dictionary) -> String:
	# Fallback version without specialization
	return _get_best_building_for_specialization(city, player, flavor, CitySpecialization.HYBRID)

## Process civics adoption based on leader preferences
func _process_civics(player, flavor: Dictionary) -> void:
	# Get leader data for favorite civic
	var leader_data = DataManager.get_leader(player.leader_id)
	var favorite_civic = leader_data.get("favorite_civic", "")

	# Check each civic category
	for category in CivicsSystem.CIVIC_CATEGORIES:
		var current_civic = player.civics.get(category, "")
		var best_civic = _evaluate_best_civic(player, category, flavor, favorite_civic)

		if best_civic != "" and best_civic != current_civic:
			# Check if we can adopt this civic
			if CivicsSystem.can_adopt_civic(player, best_civic):
				CivicsSystem.change_civic(player, best_civic)

## Evaluate best civic for a category
func _evaluate_best_civic(player, category: String, flavor: Dictionary, favorite_civic: String) -> String:
	var available = CivicsSystem.get_available_civics(player, category)
	if available.is_empty():
		return ""

	var best_civic = ""
	var best_score = -INF

	var military_flavor = flavor.get("military", 5)
	var science_flavor = flavor.get("science", 5)
	var gold_flavor = flavor.get("gold", 5)
	var culture_flavor = flavor.get("culture", 5)
	var religion_flavor = flavor.get("religion", 5)
	var growth_flavor = flavor.get("growth", 5)
	var production_flavor = flavor.get("production", 5)

	for civic_id in available:
		var civic = DataManager.get_civic(civic_id)
		if civic.is_empty():
			continue

		var score = 0.0
		var effects = civic.get("effects", {})

		# Score based on effects and flavor
		if effects.has("military_experience_rate"):
			score += effects.military_experience_rate * military_flavor * 2
		if effects.has("military_production"):
			score += effects.military_production * military_flavor * 3
		if effects.has("science_rate"):
			score += effects.science_rate * science_flavor * 2
		if effects.has("gold_rate"):
			score += effects.gold_rate * gold_flavor * 2
		if effects.has("culture_rate"):
			score += effects.culture_rate * culture_flavor * 2
		if effects.has("happiness"):
			score += effects.happiness * 5
		if effects.has("health"):
			score += effects.health * 3
		if effects.has("growth_rate"):
			score += effects.growth_rate * growth_flavor * 2
		if effects.has("production_rate"):
			score += effects.production_rate * production_flavor * 2
		if effects.has("great_person_rate"):
			score += effects.great_person_rate * science_flavor
		if effects.has("unit_cost"):
			score -= effects.unit_cost * military_flavor  # Negative is good
		if effects.has("unit_support"):
			score += effects.unit_support * military_flavor

		# Religion-based civics
		if effects.has("state_religion_happiness"):
			score += effects.state_religion_happiness * religion_flavor
		if effects.has("missionary_rate"):
			score += effects.missionary_rate * religion_flavor * 2

		# Penalty for upkeep
		var upkeep = civic.get("upkeep", "low")
		match upkeep:
			"low": score -= 2
			"medium": score -= 5
			"high": score -= 10

		# Big bonus for favorite civic
		if civic_id == favorite_civic:
			score += 30

		if score > best_score:
			best_score = score
			best_civic = civic_id

	return best_civic

## Process naval strategy for AI
func _process_naval_strategy(player, flavor: Dictionary) -> void:
	# Check if player has coastal cities
	var coastal_cities = []
	for city in player.cities:
		if _is_coastal_city(city):
			coastal_cities.append(city)

	if coastal_cities.is_empty():
		return

	# Count naval units
	var naval_units = 0
	var transport_units = 0
	var combat_naval = 0

	for unit in player.units:
		var unit_data = DataManager.get_unit(unit.unit_id)
		var domain = unit_data.get("domain", "land")
		if domain == "sea":
			naval_units += 1
			if unit_data.get("cargo", 0) > 0:
				transport_units += 1
			if DataManager.get_unit_strength(unit.unit_id) > 0:
				combat_naval += 1

	# Determine naval need based on map and enemies
	var need_naval = _calculate_naval_need(player, flavor)

	# Build naval units if needed
	if naval_units < need_naval:
		for city in coastal_cities:
			if city.current_production == "":
				var naval_unit = _get_best_naval_unit(city, player, flavor)
				if naval_unit != "":
					city.set_production(naval_unit)
					break

	# Process naval unit AI
	for unit in player.units:
		var unit_data = DataManager.get_unit(unit.unit_id)
		if unit_data.get("domain", "land") == "sea":
			_process_naval_unit_ai(unit, player, flavor)

## Check if a city is coastal
func _is_coastal_city(city) -> bool:
	if GameManager.hex_grid == null:
		return false

	for tile_pos in city.territory:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile and tile.is_water():
			return true

	return false

## Calculate how many naval units the AI should have
func _calculate_naval_need(player, flavor: Dictionary) -> int:
	var military_flavor = flavor.get("military", 5)
	var expansion_flavor = flavor.get("expansion", 5)

	# Base naval need
	var need = 2

	# More if aggressive
	need += int(military_flavor / 3)

	# More if expansionist (need transports for settlers)
	need += int(expansion_flavor / 4)

	# More if at war with naval power
	for other in GameManager.players:
		if other == player:
			continue
		if GameManager.is_at_war(player, other):
			# Check if enemy has coastal cities
			for city in other.cities:
				if _is_coastal_city(city):
					need += 2
					break

	# Cap at reasonable number
	return min(need, 10)

## Get best naval unit to build
func _get_best_naval_unit(city, player, flavor: Dictionary) -> String:
	var military_flavor = flavor.get("military", 5)
	var expansion_flavor = flavor.get("expansion", 5)

	var best_unit = ""
	var best_score = -1

	for unit_id in DataManager.units:
		if not city.can_build_unit(unit_id):
			continue

		var unit_data = DataManager.get_unit(unit_id)
		if unit_data.get("domain", "land") != "sea":
			continue

		var score = 0
		var strength = DataManager.get_unit_strength(unit_id)
		var cargo = unit_data.get("cargo", 0)

		# Combat ships
		score += strength * military_flavor

		# Transport ships (for expansion)
		score += cargo * expansion_flavor * 3

		if score > best_score:
			best_score = score
			best_unit = unit_id

	return best_unit

## Process AI for a single naval unit
func _process_naval_unit_ai(unit, player, flavor: Dictionary) -> void:
	if unit.has_acted or unit.movement_remaining <= 0:
		return

	var unit_data = DataManager.get_unit(unit.unit_id)
	var cargo_capacity = unit_data.get("cargo", 0)

	# Transport ship logic
	if cargo_capacity > 0:
		_process_transport_ai(unit, player, flavor)
		return

	# Combat ship logic
	_process_combat_naval_ai(unit, player, flavor)

## Process AI for transport ships
func _process_transport_ai(unit, player, flavor: Dictionary) -> void:
	var loaded_units = unit.cargo if unit.get("cargo") else []

	# If carrying units, look for landing spot
	if loaded_units.size() > 0:
		var landing = _find_landing_spot(unit, player)
		if landing != Vector2i(-1, -1):
			_move_naval_toward(unit, landing)
			# Unload if adjacent to land
			if _can_unload_at(unit, landing):
				_unload_units(unit, landing)
		return

	# If empty, look for units to load
	var embark_pos = _find_embarkable_unit(unit, player)
	if embark_pos != Vector2i(-1, -1):
		_move_naval_toward(unit, embark_pos)
		# Load if adjacent
		if GridUtils.are_adjacent(unit.grid_position, embark_pos):
			_load_unit(unit, embark_pos)
		return

	# Default: patrol coastal waters
	_patrol_coast(unit, player)

## Process AI for combat ships
func _process_combat_naval_ai(unit, player, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)

	# Look for enemy ships
	var enemy_ship = _find_nearest_enemy_ship(unit, player)
	if enemy_ship:
		var odds = CombatSystem.calculate_odds(unit, enemy_ship)
		var min_odds = 0.4 - (military_flavor - 5) * 0.05
		min_odds = clamp(min_odds, 0.25, 0.5)

		if odds.win_chance > min_odds:
			if GridUtils.are_adjacent(unit.grid_position, enemy_ship.grid_position):
				CombatSystem.resolve_combat(unit, enemy_ship)
				return
			else:
				_move_naval_toward(unit, enemy_ship.grid_position)
				return

	# Blockade enemy ports
	var blockade_target = _find_blockade_target(unit, player)
	if blockade_target != Vector2i(-1, -1):
		_move_naval_toward(unit, blockade_target)
		return

	# Patrol
	_patrol_coast(unit, player)

## Find nearest enemy ship
func _find_nearest_enemy_ship(unit, player):
	var nearest = null
	var nearest_dist = INF

	for other in GameManager.players:
		if other == player:
			continue
		if not GameManager.is_at_war(player, other):
			continue

		for enemy_unit in other.units:
			var enemy_data = DataManager.get_unit(enemy_unit.unit_id)
			if enemy_data.get("domain", "land") != "sea":
				continue

			var dist = GridUtils.chebyshev_distance(unit.grid_position, enemy_unit.grid_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = enemy_unit

	return nearest

## Find enemy port to blockade
func _find_blockade_target(unit, player) -> Vector2i:
	for other in GameManager.players:
		if other == player:
			continue
		if not GameManager.is_at_war(player, other):
			continue

		for city in other.cities:
			if not _is_coastal_city(city):
				continue

			# Find water tile adjacent to city
			var neighbors = GridUtils.get_neighbors(city.grid_position)
			for neighbor_pos in neighbors:
				var tile = GameManager.hex_grid.get_tile(neighbor_pos)
				if tile and tile.is_water():
					return neighbor_pos

	return Vector2i(-1, -1)

## Find a spot to land troops
func _find_landing_spot(unit, player) -> Vector2i:
	# Look for enemy coastal cities
	for other in GameManager.players:
		if other == player:
			continue
		if not GameManager.is_at_war(player, other):
			continue

		for city in other.cities:
			if not _is_coastal_city(city):
				continue

			# Find land tile near the city
			var neighbors = GridUtils.get_neighbors(city.grid_position)
			for neighbor_pos in neighbors:
				var tile = GameManager.hex_grid.get_tile(neighbor_pos)
				if tile and not tile.is_water() and tile.is_passable():
					# Find water adjacent to this land tile
					var water_neighbors = GridUtils.get_neighbors(neighbor_pos)
					for water_pos in water_neighbors:
						var water_tile = GameManager.hex_grid.get_tile(water_pos)
						if water_tile and water_tile.is_water():
							return water_pos

	return Vector2i(-1, -1)

## Find a unit that wants to embark
func _find_embarkable_unit(unit, player) -> Vector2i:
	for land_unit in player.units:
		var land_data = DataManager.get_unit(land_unit.unit_id)
		if land_data.get("domain", "land") != "land":
			continue

		# Check if unit is on coast
		var neighbors = GridUtils.get_neighbors(land_unit.grid_position)
		for neighbor_pos in neighbors:
			var tile = GameManager.hex_grid.get_tile(neighbor_pos)
			if tile and tile.is_water():
				return land_unit.grid_position

	return Vector2i(-1, -1)

## Move naval unit toward target
func _move_naval_toward(unit, target: Vector2i) -> void:
	if GameManager.hex_grid == null:
		return

	# Simple movement toward target on water
	var best_pos = unit.grid_position
	var best_dist = INF

	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	for neighbor_pos in neighbors:
		var tile = GameManager.hex_grid.get_tile(neighbor_pos)
		if tile == null or not tile.is_water():
			continue

		if GameManager.get_unit_at(neighbor_pos) != null:
			continue

		var dist = GridUtils.chebyshev_distance(neighbor_pos, target)
		if dist < best_dist:
			best_dist = dist
			best_pos = neighbor_pos

	if best_pos != unit.grid_position:
		unit.move_to(best_pos)

## Patrol coastal waters
func _patrol_coast(unit, player) -> void:
	# Move randomly in water
	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	neighbors.shuffle()

	for neighbor_pos in neighbors:
		var tile = GameManager.hex_grid.get_tile(neighbor_pos)
		if tile == null or not tile.is_water():
			continue

		if GameManager.get_unit_at(neighbor_pos) != null:
			continue

		unit.move_to(neighbor_pos)
		return

## Check if can unload at position
func _can_unload_at(unit, pos: Vector2i) -> bool:
	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	for neighbor_pos in neighbors:
		var tile = GameManager.hex_grid.get_tile(neighbor_pos)
		if tile and not tile.is_water() and tile.is_passable():
			if GameManager.get_unit_at(neighbor_pos) == null:
				return true
	return false

## Unload units from transport
func _unload_units(unit, target: Vector2i) -> void:
	if not unit.get("cargo"):
		return

	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	for loaded_unit in unit.cargo.duplicate():
		for neighbor_pos in neighbors:
			var tile = GameManager.hex_grid.get_tile(neighbor_pos)
			if tile and not tile.is_water() and tile.is_passable():
				if GameManager.get_unit_at(neighbor_pos) == null:
					loaded_unit.grid_position = neighbor_pos
					loaded_unit.position = GridUtils.grid_to_pixel(neighbor_pos)
					unit.cargo.erase(loaded_unit)
					break

## Load unit onto transport
func _load_unit(unit, pos: Vector2i) -> void:
	var land_unit = GameManager.get_unit_at(pos)
	if land_unit == null:
		return

	var unit_data = DataManager.get_unit(unit.unit_id)
	var cargo_capacity = unit_data.get("cargo", 0)

	if not unit.get("cargo"):
		unit.cargo = []

	if unit.cargo.size() >= cargo_capacity:
		return

	unit.cargo.append(land_unit)
	land_unit.visible = false  # Hide loaded unit

# ============ GREAT PERSON STRATEGY ============

## Use Great People intelligently based on type and game state
func _process_great_people(player, flavor: Dictionary) -> void:
	for unit in player.units.duplicate():
		if unit == null or not is_instance_valid(unit):
			continue
		var unit_data = DataManager.get_unit(unit.unit_id)
		if unit_data.get("unit_class", "") != "great_person":
			continue
		# Skip Great Generals (handled by existing attachment logic)
		if unit.unit_id == "great_general":
			continue

		match unit.unit_id:
			"great_scientist":
				_use_great_scientist(unit, player)
			"great_engineer":
				_use_great_engineer(unit, player)
			"great_merchant":
				_use_great_merchant(unit, player)
			"great_artist":
				_use_great_artist(unit, player)
			"great_prophet":
				_use_great_prophet(unit, player)
			_:
				# Default: settle in best city
				GreatPeopleSystem.use_great_person(unit, "settle")

func _use_great_scientist(unit, player) -> void:
	var capital = _get_capital(player)
	if capital and "academy" not in capital.buildings:
		# Build academy in capital (massive research boost — best early use)
		if unit.grid_position == capital.grid_position:
			GreatPeopleSystem.use_great_person(unit, "build_academy")
			if sim_logger:
				sim_logger.log_decision(player.player_name, "great_person", "build_academy",
					capital.city_name, "")
		else:
			_move_toward(unit, capital.grid_position)
	else:
		# Capital already has academy — bulb a tech
		GreatPeopleSystem.use_great_person(unit, "discover_tech")
		if sim_logger:
			sim_logger.log_decision(player.player_name, "great_person", "discover_tech", "", "")

func _use_great_engineer(unit, player) -> void:
	# Rush production in the city with the most valuable item being built
	var best_city = _get_highest_production_city(player)
	if best_city and best_city.current_production != "":
		if unit.grid_position == best_city.grid_position:
			GreatPeopleSystem.use_great_person(unit, "hurry_production")
			if sim_logger:
				sim_logger.log_decision(player.player_name, "great_person", "hurry_production",
					best_city.city_name, best_city.current_production)
		else:
			_move_toward(unit, best_city.grid_position)
	else:
		GreatPeopleSystem.use_great_person(unit, "settle")

func _use_great_merchant(unit, player) -> void:
	if player.gold < 100:
		# Trade mission for gold when treasury is low
		GreatPeopleSystem.use_great_person(unit, "trade_mission")
		if sim_logger:
			sim_logger.log_decision(player.player_name, "great_person", "trade_mission", "", "gold=%d" % player.gold)
	else:
		GreatPeopleSystem.use_great_person(unit, "settle")

func _use_great_artist(unit, player) -> void:
	# Culture bomb in border cities, otherwise settle
	var border_city = _get_border_city(player)
	if border_city:
		if unit.grid_position == border_city.grid_position:
			GreatPeopleSystem.use_great_person(unit, "culture_bomb")
			if sim_logger:
				sim_logger.log_decision(player.player_name, "great_person", "culture_bomb",
					border_city.city_name, "")
		else:
			_move_toward(unit, border_city.grid_position)
	else:
		GreatPeopleSystem.use_great_person(unit, "settle")

func _use_great_prophet(unit, player) -> void:
	# Build shrine in holy city if we have one
	var holy_city = _get_holy_city(player)
	if holy_city:
		if unit.grid_position == holy_city.grid_position:
			GreatPeopleSystem.use_great_person(unit, "build_shrine")
			if sim_logger:
				sim_logger.log_decision(player.player_name, "great_person", "build_shrine",
					holy_city.city_name, "")
		else:
			_move_toward(unit, holy_city.grid_position)
	else:
		GreatPeopleSystem.use_great_person(unit, "settle")

# ============ GREAT PERSON HELPERS ============

func _get_capital(player):
	for city in player.cities:
		if "palace" in city.buildings:
			return city
	return player.cities[0] if not player.cities.is_empty() else null

func _get_highest_production_city(player):
	var best_city = null
	var best_prod = -1
	for city in player.cities:
		if city.current_production != "" and city.production_yield > best_prod:
			best_prod = city.production_yield
			best_city = city
	return best_city

func _get_border_city(player):
	# Find a city near foreign borders (benefits most from culture bomb)
	for city in player.cities:
		for other in GameManager.players:
			if other == player:
				continue
			for other_city in other.cities:
				if GridUtils.chebyshev_distance(city.grid_position, other_city.grid_position) <= 6:
					return city
	return null

func _get_holy_city(player):
	# Find a city that is a holy city for a religion
	for city in player.cities:
		if city.holy_city_of != "":
			return city
	return null
