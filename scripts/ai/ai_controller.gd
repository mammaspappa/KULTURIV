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
const PEACE_COOLDOWN_TURNS = 35  # Must wait 35 turns after peace before redeclaring war (was 20 — sims showed Aztec re-declaring on Mongolia 3 times in 100 turns with no territorial gain, just churning units)

## Execute a full turn for an AI player
func execute_turn(player) -> void:
	if player.is_human:
		return
	# The base barbarian player (id=-1) uses its own simple AI (BarbarianSystem)
	# Spawned barbarian civilizations (id >= 0) use the full civ AI
	if player.is_barbarian() and player.player_id == -1:
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

	# Pick / update active strategy (tall/wide/warmonger/builder/science/balanced)
	# Strategy is sticky — only changes every few turns to avoid thrashing.
	_pick_strategy(player, flavor)

	# Process diplomacy first (skip unmet players handled internally)
	_process_diplomacy(player, flavor)

	# Process research
	_process_research(player, flavor)

	# Process espionage (skip if no espionage capability)
	if _has_espionage_capability(player):
		_process_espionage(player, flavor)

	# Strategic planning (city sites, war targets, defense — runs once before units)
	AIStrategyClass.update_strategy(player, flavor)

	# Process units in three passes:
	# Pass 1: Assign military escorts to settlers/workers outside cities
	var escort_assignments = _assign_escorts(player)

	# Pass 2: Process civilians (settlers, workers) FIRST so they reach their
	# final positions before escorts try to follow them. Otherwise escorts move
	# to the civilian's old position and lag one tile behind every turn.
	for unit in player.units.duplicate():
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.can_found_city() or unit.can_build_improvements():
			_process_unit_ai(unit, player, flavor, escort_assignments)

	# Pass 3: Process military units (including escorts now matching final civ pos)
	for unit in player.units.duplicate():
		if unit == null or not is_instance_valid(unit):
			continue
		if unit.can_found_city() or unit.can_build_improvements():
			continue  # already processed
		_process_unit_ai(unit, player, flavor, escort_assignments)

	# Peacetime disband: if no active wars and we're losing gold, disband excess
	# military. Prevents the classic "build huge army during war → can't afford it
	# after peace → structural bankruptcy" pattern seen in late-game sims.
	_consider_peacetime_disband(player)

	# Process cities
	for city in player.cities:
		var prev_production = city.current_production
		_process_city_ai(city, player, flavor)
		if sim_logger and city.current_production != "" and city.current_production != prev_production:
			sim_logger.log_decision(player.player_name, "production", "set_production",
				"%s -> %s" % [city.city_name, city.current_production], "")

	# Process civics adoption (scaled by game speed)
	var civics_interval = max(1, GameManager.scaled_turn(10))
	if TurnManager.current_turn % civics_interval == player.player_id % civics_interval:
		_process_civics(player, flavor)

	# Process naval strategy (skip if no coastal cities)
	if _has_coastal_cities(player):
		_process_naval_strategy(player, flavor)

	# Process Great People — use them strategically
	_process_great_people(player, flavor)

## Get leader flavor values (cached per turn)
## Convenience wrapper: read an AI tunable with the player's active strategy
## and current game phase as layers. Use this from all AI decision code
## instead of calling GameManager.get_ai_tunable directly.
func _ai_tun(player, path: String, default):
	return GameManager.get_ai_tunable(
		player.civilization_id, path, default,
		player.active_strategy, GameManager.get_current_phase())

## Leader-trait → strategy bias table. Based on Civ4 BTS trait guides.
## Each trait adds these scores to the strategy picker, leaning leaders
## toward playstyles their traits enable.
##   Aggressive (+combat I melee/gunpowder): warmonger
##   Imperialistic (+settler speed, great generals): wide
##   Expansive (+3 health, cheap workers/granary): wide
##   Creative (+2 culture, cheap theatre/coliseum): wide (border pops)
##   Organized (-50% civic upkeep, cheap lighthouse/courthouse): wide/tall
##   Industrious (+50% wonder prod, cheap forge): builder
##   Philosophical (+100% GPP): science
##   Financial (+1c on 2c tiles, cheap bank): builder
##   Spiritual (no anarchy, cheap temples): flexible — no strong bias
##   Protective (+drill I archery/gunpowder, cheap walls/castle): tall
##   Charismatic (+1 happy, -25% XP promote): wide
const TRAIT_STRATEGY_BIAS = {
	"aggressive":    {"warmonger": 15, "builder": -5, "science": -5},
	"imperialistic": {"wide": 15, "warmonger": 3},
	"expansive":     {"wide": 12, "tall": 3},
	"creative":      {"wide": 10, "builder": 3},
	"organized":     {"wide": 8, "tall": 5},
	"industrious":   {"builder": 15, "science": 3},
	"philosophical": {"science": 15, "builder": 3},
	"financial":     {"builder": 12, "science": 5, "tall": 3},
	"spiritual":     {"builder": 3, "warmonger": 3},  # flexible
	"protective":    {"tall": 12, "builder": 3},
	"charismatic":   {"wide": 8, "warmonger": 3},
}

## Pick the active strategy for this player based on leader flavor, game phase,
## current economy, and neighbor threats. Strategy is sticky (changes at most
## every N turns) to prevent thrashing.
##
## Strategy options: balanced, wide, tall, warmonger, builder, science
##
## Each archetype biases the parameter resolution layer — see ai.json strategies.
func _pick_strategy(player, flavor: Dictionary) -> void:
	# Per-civ forced strategy override (used by the evo tuner to lock civs
	# into a specific archetype for eval). Set via GameManager.ai_overrides[civ_id]["__force_strategy"].
	var civ_overrides = GameManager.ai_overrides.get(player.civilization_id, {})
	if civ_overrides is Dictionary and civ_overrides.has("__force_strategy"):
		player.active_strategy = civ_overrides["__force_strategy"]
		player.active_strategy_sticky_turns = 9999
		return

	# Hysteresis: don't reconsider for at least 10 turns after last switch
	if player.active_strategy_sticky_turns > 0:
		player.active_strategy_sticky_turns -= 1
		return

	var mil = flavor.get("military", 5)
	var sci = flavor.get("science", 5)
	var gold = flavor.get("gold", 5)
	var growth = flavor.get("growth", 5)
	var expansion = flavor.get("expansion", 5)
	var culture = flavor.get("culture", 5)

	# Count real-civ wars and threats
	var real_wars = 0
	for enemy_id in player.at_war_with:
		var e = GameManager.get_player(enemy_id)
		if e and not e.is_barbarian():
			real_wars += 1

	# Count neighbors (real civs we've met) within proximity as threat gauge
	var nearby_threats = 0
	if not player.cities.is_empty():
		var my_pos = player.cities[0].grid_position
		for other in GameManager.players:
			if other == player or other.is_barbarian():
				continue
			if other.player_id not in player.met_players:
				continue
			if other.cities.is_empty():
				continue
			var d = GridUtils.chebyshev_distance(my_pos, other.cities[0].grid_position)
			if d < GameManager.scaled_distance(15):
				nearby_threats += 1

	var num_cities = player.cities.size()
	var gpt = player.gold_per_turn
	var phase = GameManager.get_current_phase()

	# Score each strategy. Higher score wins.
	var scores := {
		"balanced": 10.0,
		"wide": 0.0,
		"tall": 0.0,
		"warmonger": 0.0,
		"builder": 0.0,
		"science": 0.0,
	}

	# ---- Leader trait bias: the strongest single factor in strategy selection ----
	# Per Civ4 BTS guides, leaders' traits heavily shape their natural playstyle.
	var leader_data = DataManager.get_leader(player.leader_id)
	var traits = leader_data.get("traits", [])
	for trait_id in traits:
		var bias = TRAIT_STRATEGY_BIAS.get(trait_id, {})
		for strat in bias.keys():
			if strat in scores:
				scores[strat] += bias[strat]

	# ---- Favorite civic hints at preferred playstyle ----
	# Vassalage/Theocracy → warmonger, Bureaucracy → tall, Free Speech → builder/science,
	# Free Religion → flexible, Emancipation → wide.
	var fav_civic = leader_data.get("favorite_civic", "")
	match fav_civic:
		"vassalage", "theocracy", "nationhood":
			scores["warmonger"] += 8
		"bureaucracy":
			scores["tall"] += 8
		"representation":
			scores["science"] += 6
			scores["tall"] += 3
		"free_speech", "mercantilism":
			scores["builder"] += 6
		"emancipation", "universal_suffrage":
			scores["wide"] += 6
		"pacifism":
			scores["science"] += 8
			scores["warmonger"] -= 10

	# ---- Warmonger: high military flavor, active wars, or many threats ----
	scores["warmonger"] += mil * 2.0
	scores["warmonger"] += real_wars * 15.0
	scores["warmonger"] += nearby_threats * 3.0
	if phase == "early":
		scores["warmonger"] += 5.0  # early warmonger rush
	if gpt < -5:
		scores["warmonger"] -= 20.0  # can't afford war

	# ---- Wide: high expansion flavor, low threats, early game ----
	scores["wide"] += expansion * 2.0
	scores["wide"] += growth * 1.0
	if phase == "early":
		scores["wide"] += 10.0
	if nearby_threats == 0:
		scores["wide"] += 8.0
	if real_wars > 0:
		scores["wide"] -= 15.0
	if gpt < 0:
		scores["wide"] -= 10.0

	# ---- Tall: few cities by choice, high growth, mid game ----
	scores["tall"] += growth * 2.0
	scores["tall"] += gold * 1.5
	if num_cities <= 4:
		scores["tall"] += 8.0
	if phase == "mid":
		scores["tall"] += 5.0
	if real_wars == 0 and nearby_threats <= 1:
		scores["tall"] += 5.0

	# ---- Builder: high production/gold flavor, no wars, economy focus ----
	scores["builder"] += (gold + growth) * 1.5
	scores["builder"] += culture * 1.0
	if real_wars == 0 and nearby_threats <= 1:
		scores["builder"] += 10.0
	if phase == "mid" or phase == "late":
		scores["builder"] += 5.0

	# ---- Science: high science flavor, peaceful, low military ----
	scores["science"] += sci * 2.5
	if real_wars == 0:
		scores["science"] += 8.0
	if nearby_threats <= 1:
		scores["science"] += 5.0
	if mil > 7:
		scores["science"] -= 10.0  # warmonger leaders don't science

	# Emergency override: if a war is on and we're under-garrisoned, force warmonger
	if real_wars > 0:
		var mil_count = 0
		for u in player.units:
			if u.get_strength() > 0:
				mil_count += 1
		if mil_count < num_cities * 2:
			scores["warmonger"] += 30.0

	# Pick highest-scoring strategy
	var best = "balanced"
	var best_score = scores["balanced"]
	for k in scores.keys():
		if scores[k] > best_score:
			best_score = scores[k]
			best = k

	var prev = player.active_strategy
	# Require a significant margin to SWITCH away from current strategy.
	# Prevents thrashing between close-scoring options (e.g. Aztec oscillating
	# warmonger↔tall every 10 turns as threats wax and wane).
	if prev != "" and prev in scores and prev != "balanced":
		var current_score = scores[prev]
		if best_score < current_score + 8:
			best = prev
			best_score = current_score

	player.active_strategy = best
	# Sticky: hold this strategy for at least N turns (scaled by speed + map size)
	player.active_strategy_sticky_turns = GameManager.scaled_turn(15)

	if prev != best and sim_logger:
		sim_logger.log_decision(player.player_name, "strategy", "switch",
			"%s -> %s" % [prev, best],
			"scores=" + JSON.stringify(scores))

func _get_leader_flavor(player) -> Dictionary:
	if not _cached_flavor.is_empty() and _cached_player_id == player.player_id:
		return _cached_flavor

	# Spawned barbarian civs: hardcoded aggressive flavor (no leader)
	if player.is_barbarian() and player.player_id >= 0:
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
	if player.is_barbarian() and player.player_id >= 0 and not player.ai_personality.is_empty():
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
	var is_barb_civ = player.is_barbarian() and player.player_id >= 0
	var met_count = 0

	for other in GameManager.players:
		if other == player or other.player_id not in player.met_players:
			continue
		if other.player_id == -1:
			continue  # Skip base barbarian player
		met_count += 1

		# Barbarian civs: aggressive but not suicidal — declare on neighbors only
		if is_barb_civ:
			if not GameManager.is_at_war(player, other):
				# Only declare if we have military strength AND they're nearby
				var barb_power = DiplomacySystem._calculate_power(player)
				var target_power = DiplomacySystem._calculate_power(other)
				# Limit active wars to 2 (don't fight everyone at once)
				if player.at_war_with.size() < 2 and barb_power > target_power * 0.5:
					# Check proximity — only attack nearby civs (scaled by map size)
					var close_enough = false
					var attack_range = GameManager.scaled_distance(15)
					for city in player.cities:
						for other_city in other.cities:
							if GridUtils.chebyshev_distance(city.grid_position, other_city.grid_position) < attack_range:
								close_enough = true
								break
						if close_enough:
							break
					if close_enough:
						GameManager.declare_war(player, other)
			else:
				# Consider peace if losing badly
				var barb_power = DiplomacySystem._calculate_power(player)
				var target_power = DiplomacySystem._calculate_power(other)
				if barb_power < target_power * 0.3 and randi() % 10 == 0:
					GameManager.make_peace(player, other)
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
	# Don't consider any peace (including capitulation) in the first 10 turns of war
	var war_key = "%d:%d" % [player.player_id, other.player_id]
	var war_start = peace_cooldown.get("war_start_" + war_key, 0)
	var min_war_turns = GameManager.scaled_turn(10)
	if TurnManager.current_turn - war_start < min_war_turns:
		return

	# Check if AI should offer capitulation (become vassal)
	if DiplomacySystem.should_offer_capitulation(player, other):
		player.become_vassal_of(other.player_id)
		EventBus.notification_added.emit("%s has capitulated to %s!" % [player.player_name, other.player_name])
		GameManager.make_peace(player, other)
		if sim_logger:
			sim_logger.log_decision(player.player_name, "peace", "capitulate", other.player_name, "war_score_critical")
		return

	var personality = _get_leader_personality(player)

	var our_power = DiplomacySystem._calculate_power(player)
	var their_power = DiplomacySystem._calculate_power(other)

	# Badly losing — always consider peace regardless of personality
	if our_power < their_power * 0.4:
		if not other.is_human:
			_make_peace_with_cooldown(player, other)
		return

	# BTS make_peace_rand: lower values = more stubborn. Scale to ~5-20% chance per turn.
	# Original was 1/make_peace_rand chance (~1%). Too low — wars never end.
	var peace_roll = 10.0 / max(float(personality.make_peace_rand), 1.0)
	# Boost peace chance based on war duration (wars get stale).
	# Fatigue rate is per "Normal-speed turn", so divide by turn_scale to keep
	# the same wall-clock-feel across speeds.
	var war_duration = TurnManager.current_turn - war_start
	var fatigue_per_turn = 0.002 / GameManager.get_turn_scale()
	var fatigue_bonus = min(war_duration * fatigue_per_turn, 0.15)
	peace_roll += fatigue_bonus

	if randf() > peace_roll:
		return  # Didn't trigger peace consideration this turn

	# Peaceful leaders (high peace_weight) seek peace more readily
	var peace_threshold = 0.8 + personality.base_peace_weight * 0.06  # 0.8 to 1.28
	if our_power < their_power * peace_threshold:
		if other.is_human:
			return  # Wait for human to propose
		_make_peace_with_cooldown(player, other)
	elif personality.base_peace_weight > 4 and our_power < their_power * 1.3:
		# Moderately peaceful leaders seek peace when roughly equal
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

	# BTS: No wars in the very early game — players need time to settle
	var min_war_turn = GameManager.scaled_turn(40)
	if TurnManager.current_turn < min_war_turn:
		return

	# Check peace cooldown — cannot redeclare war too soon after making peace
	var cooldown_key = "%d:%d" % [player.player_id, other.player_id]
	var last_peace_turn = peace_cooldown.get(cooldown_key, -999)
	var scaled_cooldown = GameManager.scaled_turn(PEACE_COOLDOWN_TURNS)
	if TurnManager.current_turn - last_peace_turn < scaled_cooldown:
		return  # Still in cooldown period

	# Limit to max 1 active war for most leaders (aggressive can have 2)
	var current_wars = player.at_war_with.size()
	var max_wars = 1 if personality.base_peace_weight >= 3 else 2
	if current_wars >= max_wars:
		return

	# BTS max_war_rand: lower = more warlike. Chance per turn scales with personality.
	# Alexander (50) = 4%, Gandhi (400) = 0.5%, Montezuma (40) = 5%
	# Halved from original to reduce war frequency.
	var war_chance = 200.0 / max(personality.max_war_rand, 1)
	if randf() * 100.0 > war_chance:
		return  # Didn't roll war this turn

	var attitude = DiplomacySystem.calculate_attitude(player, other)

	# Attitude threshold: BTS-style. Pleased/Friendly = almost never declare.
	# peace_weight 0 (Montezuma): threshold 3, declares on cautious or worse
	# peace_weight 4 (Caesar): threshold 1, declares on annoyed or hostile
	# peace_weight 8 (Gandhi): threshold -1, only with extreme provocation
	var war_attitude_threshold = 3 - personality.base_peace_weight / 2
	if attitude > war_attitude_threshold:
		return

	# Check military power
	var our_power = DiplomacySystem._calculate_power(player)
	var their_power = DiplomacySystem._calculate_power(other)

	# Required power ratio: aggressive need slight advantage, peaceful need clear advantage
	var required_ratio = 1.0 + personality.base_peace_weight * 0.08
	required_ratio = clamp(required_ratio, 1.0, 1.8)

	# Dogpile bonus: if target is already at war, we need less advantage
	var target_at_war = other.at_war_with.size() > 0
	if target_at_war:
		var dogpile_chance = int(personality.dogpile_war_rand)
		if randi() % max(dogpile_chance, 1) == 0:
			required_ratio *= 0.8  # Lower bar for dogpiling (but not as extreme)

	# Warmonger respect: leaders who respect strength avoid stronger foes
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
			# Track war start turn for minimum war duration (both directions)
			var war_key = "%d:%d" % [player.player_id, other.player_id]
			var war_key_rev = "%d:%d" % [other.player_id, player.player_id]
			peace_cooldown["war_start_" + war_key] = TurnManager.current_turn
			peace_cooldown["war_start_" + war_key_rev] = TurnManager.current_turn
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

	# Healed units: clear HEAL/SLEEP order if at full health so they resume acting
	if unit.current_order in [UnitClass.UnitOrder.HEAL, UnitClass.UnitOrder.SLEEP]:
		if unit.health >= 100:
			unit.current_order = UnitClass.UnitOrder.NONE
		else:
			return  # Still healing

	# Fortified units: stay put unless enemies are nearby or we're at war needing troops
	if unit.current_order == UnitClass.UnitOrder.FORTIFY and unit.get_strength() > 0:
		var nearby_threats = _find_nearby_enemies(unit, player, 2)
		var at_war = not player.at_war_with.is_empty()
		# Wake up if: threats nearby, or at war and not garrisoning a city
		var in_city = GameManager.get_city_at(unit.grid_position) != null
		if nearby_threats.is_empty() and (not at_war or in_city):
			return  # Stay fortified — no reason to wake up

	# Settler: find good city location
	if unit.can_found_city():
		_settler_ai(unit, player, flavor)
		if is_instance_valid(unit):
			unit.record_position()
		return

	# Worker: build improvements
	if unit.can_build_improvements():
		_worker_ai(unit, player, flavor)
		if is_instance_valid(unit):
			unit.record_position()
		return

	# Check if this military unit is assigned as escort (persistent or transient)
	var escort_target_id = escort_assignments.get(unit.get_instance_id(), -1)
	# Also check persistent escort meta
	if escort_target_id == -1 and unit.has_meta("escort_target"):
		escort_target_id = unit.get_meta("escort_target")

	if escort_target_id != -1:
		# Find the civilian we're escorting
		var found_civilian = false
		for civ_unit in player.units:
			if is_instance_valid(civ_unit) and civ_unit.get_instance_id() == escort_target_id:
				found_civilian = true
				# Move ONTO the civilian's tile if possible — escorts share a tile
				# with the civilian they're protecting (Civ4 BTS stack mechanic).
				# Use up all movement to catch up.
				while unit.grid_position != civ_unit.grid_position and unit.movement_remaining > 0:
					var pos_before = unit.grid_position
					_move_toward(unit, civ_unit.grid_position)
					if unit.grid_position == pos_before:
						# Couldn't advance — try greedy
						_greedy_move_toward(unit, civ_unit.grid_position)
					if unit.grid_position == pos_before:
						break  # blocked, give up
				# If on same tile and enemies nearby, fight them
				if is_instance_valid(unit) and unit.movement_remaining > 0:
					var threats = _find_nearby_enemies(unit, player, 1)
					for threat in threats:
						if is_instance_valid(threat) and GridUtils.are_adjacent(unit.grid_position, threat.grid_position):
							CombatSystem.resolve_combat(unit, threat)
							return
				# Save persistent assignment
				unit.set_meta("escort_target", escort_target_id)
				return
		# Civilian no longer exists — clear escort duty
		if not found_civilian:
			unit.remove_meta("escort_target")

	# Combat unit: attack or explore
	_combat_unit_ai(unit, player, flavor)

	# Record position for oscillation detection (runs after all unit AI)
	if is_instance_valid(unit):
		unit.record_position()

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

	if sim_logger:
		sim_logger.trace_unit(unit, "tick_start", "history=%s" % str(unit.get_recent_positions()))

	# --- Safety check FIRST: if in own city with danger nearby, wait for escort ---
	# Stuck detection must NOT fire here — sitting in city waiting for escort is legitimate.
	# Use a wider radius (4) than the field check (2) so the settler doesn't bounce
	# in/out of the city as the enemy creeps around at distance 3.
	var city_here = GameManager.get_city_at(unit.grid_position)
	if city_here != null and city_here.player_owner == player:
		# Cooldown: if we recently retreated, stay put for a few turns even if we
		# can't currently see the threat. Otherwise we leave the city, get spooked
		# again, and oscillate forever.
		var cooldown_until = unit.get_meta("retreat_cooldown_until", 0)
		var has_escort_in_city = false
		for u in GameManager.get_units_at(unit.grid_position):
			if u != unit and u.player_owner == player and u.get_strength() > 0:
				has_escort_in_city = true
				break

		var danger_now = false
		for check_pos in GridUtils.get_tiles_in_range(unit.grid_position, 4):
			var enemy_u = GameManager.get_unit_at(check_pos)
			if enemy_u and enemy_u.player_owner != null and enemy_u.player_owner != player and enemy_u.get_strength() > 0:
				var is_barbarian = enemy_u.player_owner.civilization_id == "barbarian"
				if is_barbarian and TurnManager.current_year < -2000:
					continue
				# Peaceful neighbors aren't a threat — only barbs or actual war.
				if is_barbarian or player.is_at_war_with(enemy_u.player_owner.player_id):
					danger_now = true
					break

		var should_wait = (danger_now or TurnManager.current_turn < cooldown_until) and not has_escort_in_city
		if should_wait:
			if sim_logger:
				sim_logger.trace_unit(unit, "wait_in_city",
					"danger=%s cooldown_until=%d no_escort" % [str(danger_now), cooldown_until])
			# Mark city as urgently needing an escort built
			if not city_here.has_meta("needs_escort"):
				city_here.set_meta("needs_escort", true)
			return

	# --- Oscillation/stuck detection: if oscillating or stuck, force a decision ---
	if unit.is_oscillating() or unit.is_stuck(3):
		if sim_logger:
			sim_logger.trace_unit(unit, "stuck_or_oscillating",
				"history=%s" % str(unit.get_recent_positions()))
			sim_logger.log_decision(player.player_name, "settler", "stuck_or_oscillating",
				"pos=(%d,%d)" % [unit.grid_position.x, unit.grid_position.y],
				"history=%s" % str(unit.get_recent_positions()))
		# Clear any assignment that's causing the loop
		AIStrategyClass.clear_assignment(player, unit)
		# Try to settle HERE or on any adjacent tile
		if _can_settle_here(unit.grid_position, player):
			if sim_logger:
				sim_logger.trace_unit(unit, "found_city", "settled in place after stuck")
			GameManager.game_world.found_city(unit)
			return
		var neighbors = GridUtils.get_neighbors(unit.grid_position)
		neighbors.shuffle()
		for n_pos in neighbors:
			if _can_settle_here(n_pos, player):
				if unit.move_to(n_pos):
					if sim_logger:
						sim_logger.trace_unit(unit, "found_city", "settled at neighbor after stuck")
					GameManager.game_world.found_city(unit)
				return
		# Can't settle anywhere nearby — pick a fresh site and try to reach it
		var fresh_site = _find_best_city_location(unit, player, flavor)
		if fresh_site != Vector2i(-1, -1):
			if sim_logger:
				sim_logger.trace_unit(unit, "fresh_site_search",
					"target=(%d,%d)" % [fresh_site.x, fresh_site.y])
			_move_toward(unit, fresh_site)
		else:
			# No explored site available — walk into fog to expand visibility
			if sim_logger:
				sim_logger.trace_unit(unit, "no_target_found", "no fresh site after stuck — exploring fog")
			_walk_toward_fog(unit, player)
		return

	# --- Safety check: real danger (actual enemy UNITS, not just borders) ---
	var has_escort = false
	var units_here = GameManager.get_units_at(unit.grid_position)
	for u in units_here:
		if u != unit and u.player_owner == player and u.get_strength() > 0:
			has_escort = true
			break

	# Only check for actual military units nearby — NOT just enemy borders.
	# Radius 3 so we don't keep oscillating into a tile where an enemy will catch us next turn.
	# Peaceful neighbors are NOT a threat — only actual at-war units and barbarians
	# trigger retreat. Treating any non-friendly unit as danger created an infinite
	# retreat loop where settlers bounced between their capital and the border whenever
	# a peaceful AI's military patrolled nearby.
	var nearby_danger = false
	for check_pos in GridUtils.get_tiles_in_range(unit.grid_position, 3):
		var enemy = GameManager.get_unit_at(check_pos)
		if enemy and enemy.player_owner != null and enemy.player_owner != player and enemy.get_strength() > 0:
			var is_barbarian = enemy.player_owner.civilization_id == "barbarian"
			var at_war = player.is_at_war_with(enemy.player_owner.player_id)
			# Animal era barbarians are weak — ignore them.
			if is_barbarian and TurnManager.current_year < -2000:
				continue
			# Only retreat from units we'd actually fight: barbarians or active enemies.
			if is_barbarian or at_war:
				nearby_danger = true
				break

	if nearby_danger and not has_escort:
		# (in-city case already handled at the top of this function)
		# Retreat to nearest city
		var nearest_city_pos = Vector2i(-1, -1)
		var best_dist = 999
		for city in player.cities:
			var d = GridUtils.chebyshev_distance(unit.grid_position, city.grid_position)
			if d < best_dist:
				best_dist = d
				nearest_city_pos = city.grid_position
		if nearest_city_pos != Vector2i(-1, -1) and best_dist > 0:
			if sim_logger:
				sim_logger.trace_unit(unit, "retreat", "to (%d,%d) dist=%d, danger nearby" % [
					nearest_city_pos.x, nearest_city_pos.y, best_dist])
			# Cooldown: don't leave the city again for 4 turns (scaled) even if danger fades
			unit.set_meta("retreat_cooldown_until", TurnManager.current_turn + GameManager.scaled_turn(4))
			_move_toward(unit, nearest_city_pos)
		return

	# --- Get or validate assignment ---
	var assigned_site = _get_assigned_site(unit, player)

	# Validate existing assignment — it may have become invalid
	if not assigned_site.is_empty():
		if not _can_settle_here(assigned_site.position, player):
			AIStrategyClass.clear_assignment(player, unit)
			assigned_site = {}
			if sim_logger:
				sim_logger.log_decision(player.player_name, "settler", "invalidated_site",
					"site no longer settleable", "")

	# If no assignment, request one
	if assigned_site.is_empty():
		assigned_site = AIStrategyClass.get_best_unassigned_site(player)
		if not assigned_site.is_empty():
			# Double-check the site is still valid before assigning
			if _can_settle_here(assigned_site.position, player):
				AIStrategyClass.assign_settler_to_site(player, unit, assigned_site)
				if sim_logger:
					var pos = assigned_site.position
					sim_logger.log_decision(player.player_name, "settler", "assigned_site",
						"(%d,%d) score=%d" % [pos.x, pos.y, assigned_site.score], "")
			else:
				assigned_site = {}

	# If still no assignment, find one directly
	if assigned_site.is_empty():
		var best_loc = _find_best_city_location(unit, player, flavor)
		if best_loc != Vector2i(-1, -1) and _can_settle_here(best_loc, player):
			assigned_site = {"position": best_loc, "score": 0}

	if not assigned_site.is_empty():
		var target_pos: Vector2i = assigned_site.position
		var dist_to_target = GridUtils.chebyshev_distance(unit.grid_position, target_pos)

		if sim_logger:
			sim_logger.trace_unit(unit, "has_target",
				"target=(%d,%d) dist=%d score=%d" % [
					target_pos.x, target_pos.y, dist_to_target,
					assigned_site.get("score", 0)])

		# At target? Found city.
		if unit.grid_position == target_pos and _can_settle_here(target_pos, player):
			if sim_logger:
				sim_logger.trace_unit(unit, "found_city", "at target")
			AIStrategyClass.clear_assignment(player, unit)
			GameManager.game_world.found_city(unit)
			return

		# Move toward target
		var pos_before = unit.grid_position
		_move_toward(unit, target_pos)

		# If pathfinding failed, try greedy
		if unit.grid_position == pos_before and unit.movement_remaining > 0:
			if sim_logger:
				sim_logger.trace_unit(unit, "pathfind_failed", "trying greedy move")
			_greedy_move_toward(unit, target_pos)

		if sim_logger and unit.grid_position != pos_before:
			sim_logger.trace_unit(unit, "moved",
				"from (%d,%d) to (%d,%d)" % [pos_before.x, pos_before.y,
					unit.grid_position.x, unit.grid_position.y])
		elif sim_logger:
			sim_logger.trace_unit(unit, "no_move",
				"could not advance toward (%d,%d)" % [target_pos.x, target_pos.y])

		# Check if at target after moving
		if unit.grid_position == target_pos and _can_settle_here(target_pos, player):
			if sim_logger:
				sim_logger.trace_unit(unit, "found_city", "reached target this turn")
			AIStrategyClass.clear_assignment(player, unit)
			GameManager.game_world.found_city(unit)
			return

		# Adjacent to target and can settle here? Do it.
		if GridUtils.chebyshev_distance(unit.grid_position, target_pos) <= 1:
			if _can_settle_here(unit.grid_position, player):
				if sim_logger:
					sim_logger.trace_unit(unit, "found_city", "adjacent to target, settling here")
				AIStrategyClass.clear_assignment(player, unit)
				GameManager.game_world.found_city(unit)
				return
		return

	# --- Fallback: no viable sites found — settle anywhere acceptable ---
	if sim_logger:
		sim_logger.trace_unit(unit, "no_assignment", "fallback: try settle here or neighbor")
	if _can_settle_here(unit.grid_position, player):
		if sim_logger:
			sim_logger.trace_unit(unit, "found_city", "fallback in place")
		GameManager.game_world.found_city(unit)
		return
	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	neighbors.shuffle()
	for n_pos in neighbors:
		if _can_settle_here(n_pos, player) and unit.move_to(n_pos):
			if sim_logger:
				sim_logger.trace_unit(unit, "found_city", "fallback at neighbor")
			GameManager.game_world.found_city(unit)
			return

	# Last resort: no settleable site found anywhere reachable. The most likely
	# cause is that _find_best_city_location only checks explored tiles, and the
	# settler is sitting in its capital surrounded by fog. Walk OUTWARD toward
	# the most-fogged neighbor so the settler expands its own visibility instead
	# of idling for ~10 turns waiting on the warrior to scout.
	_walk_toward_fog(unit, player)


## Move the settler one step toward the neighbor with the lowest visibility, so
## it expands its own field of view and can eventually discover a settleable site.
## Skips neighbors it can't legally enter, and avoids backtracking when possible.
func _walk_toward_fog(unit, player) -> void:
	if GameManager.hex_grid == null:
		return
	var best_pos = unit.grid_position
	var best_score = -1
	var recent = unit.get_recent_positions()
	for n_pos in GridUtils.get_neighbors(unit.grid_position):
		if not unit.can_move_to(n_pos):
			continue
		var n_tile = GameManager.hex_grid.get_tile(n_pos)
		if n_tile == null:
			continue
		# Score: prefer neighbors with the most fog in THEIR neighborhood,
		# so each step reveals fresh tiles.
		var fog_score = 0
		for nn_pos in GridUtils.get_tiles_in_range(n_pos, 2):
			var nn_tile = GameManager.hex_grid.get_tile(nn_pos)
			if nn_tile == null:
				continue
			if nn_tile.get_visibility_for_player(player.player_id) == 0:
				fog_score += 1
		# Penalize tiles we just visited to avoid oscillating
		if n_pos in recent:
			fog_score -= 5
		if fog_score > best_score:
			best_score = fog_score
			best_pos = n_pos
	if best_pos != unit.grid_position:
		var pos_before = unit.grid_position
		unit.move_to(best_pos)
		if sim_logger:
			sim_logger.trace_unit(unit, "explore_fog",
				"from (%d,%d) to (%d,%d) fog_score=%d" % [
					pos_before.x, pos_before.y, best_pos.x, best_pos.y, best_score])
	else:
		if sim_logger:
			sim_logger.trace_unit(unit, "idle", "no settleable site, no fog to explore")

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

	if sim_logger:
		var owner_name = tile.tile_owner.player_name if tile.tile_owner else "unowned"
		sim_logger.trace_unit(unit, "tick_start",
			"tile_owner=%s res=%s imp=%s road=%d" % [
				owner_name, tile.resource_id if tile.resource_id != "" else "-",
				tile.improvement_id if tile.improvement_id != "" else "-",
				tile.road_level])

	# Stuck breaker: if stuck for 3+ turns, move randomly to break deadlock
	if unit.is_stuck(3):
		if sim_logger:
			sim_logger.trace_unit(unit, "stuck", "history=%s" % str(unit.get_recent_positions()))
		_random_explore(unit)
		return

	var production_flavor = flavor.get("production", 5)
	var growth_flavor = flavor.get("growth", 5)
	var gold_flavor = flavor.get("gold", 5)

	# If on owned tile: try to build something here
	if tile.tile_owner == player and not tile.is_water():
		# Resource tile without improvement — top priority
		if tile.resource_id != "" and tile.improvement_id == "":
			var improvements = ImprovementSystem.get_available_improvements(unit, tile)
			if not improvements.is_empty():
				var chosen = _choose_improvement(tile, improvements, production_flavor, growth_flavor, gold_flavor)
				if chosen != "":
					if sim_logger:
						sim_logger.trace_unit(unit, "build_start",
							"%s on resource %s" % [chosen, tile.resource_id])
					ImprovementSystem.start_build(unit, chosen)
					return

		# Unimproved tile — build improvement (ok even if road already exists)
		if tile.improvement_id == "":
			var improvements = ImprovementSystem.get_available_improvements(unit, tile)
			# Filter out fort — AI never builds forts proactively
			improvements = improvements.filter(func(i): return i != "fort")
			if not improvements.is_empty():
				var chosen = _choose_improvement(tile, improvements, production_flavor, growth_flavor, gold_flavor)
				if chosen != "":
					if sim_logger:
						sim_logger.trace_unit(unit, "build_start", "%s on plain tile" % chosen)
					ImprovementSystem.start_build(unit, chosen)
					return

		# Tile has improvement but no road — build road to connect
		if tile.improvement_id != "" and tile.road_level == 0 and ImprovementSystem.can_build_road(unit, tile):
			if sim_logger:
				sim_logger.trace_unit(unit, "build_road",
					"on improved tile imp=%s" % tile.improvement_id)
			ImprovementSystem.start_build_road(unit)
			return

		# Fallback: no improvement possible here, but we can lay a road on any owned tile
		# This keeps the worker productive while waiting for tech/border expansion
		if tile.road_level == 0 and tile.improvement_id == "" and ImprovementSystem.can_build_road(unit, tile):
			if sim_logger:
				sim_logger.trace_unit(unit, "build_road", "fallback road on unimproved tile")
			ImprovementSystem.start_build_road(unit)
			return

	# Move to best target: prioritizes resource > improvement > road connection
	var target = _find_best_worker_target(unit, player)
	if target != Vector2i(-1, -1):
		if sim_logger:
			sim_logger.trace_unit(unit, "seek_target",
				"target=(%d,%d) dist=%d" % [target.x, target.y,
					GridUtils.chebyshev_distance(unit.grid_position, target)])
		var pos_before = unit.grid_position
		_move_toward(unit, target)
		if sim_logger:
			if unit.grid_position != pos_before:
				sim_logger.trace_unit(unit, "moved",
					"from (%d,%d) to (%d,%d)" % [pos_before.x, pos_before.y,
						unit.grid_position.x, unit.grid_position.y])
			else:
				sim_logger.trace_unit(unit, "no_move",
					"could not advance toward (%d,%d)" % [target.x, target.y])
	else:
		if sim_logger:
			sim_logger.trace_unit(unit, "fortify", "no work target found")
		unit.fortify()

## Choose improvement based on tile and AI preferences
func _choose_improvement(tile, improvements: Array, prod_flavor: int, growth_flavor: int, gold_flavor: int) -> String:
	# If the tile has a resource with a required improvement, ALWAYS build that.
	# If we can't build it yet (tech not researched), DON'T fallback to a generic
	# improvement — leave the tile alone until the right tech unlocks. Otherwise
	# we'd lock the resource into a cottage and lose the resource bonus.
	if tile.resource_id != "":
		var res_data = DataManager.get_resource(tile.resource_id)
		var required_imp = res_data.get("improvement", "")
		if required_imp != "":
			if required_imp in improvements:
				return required_imp
			else:
				return ""  # Wait for the right tech

	# Score each improvement
	var best_imp = ""
	var best_score = -1

	for imp_id in improvements:
		# AI never builds forts proactively (they're defensive, not economic)
		if imp_id == "fort":
			continue
		var score = 0
		var imp_data = DataManager.get_improvement(imp_id)
		var yields = imp_data.get("yields", {})

		# Score based on yields and flavor
		score += yields.get("food", 0) * growth_flavor
		score += yields.get("production", 0) * prod_flavor
		score += yields.get("commerce", 0) * gold_flavor

		if score > best_score:
			best_score = score
			best_imp = imp_id

	return best_imp

func _combat_unit_ai(unit, player, flavor: Dictionary) -> void:
	var military_flavor = flavor.get("military", 5)
	var unit_data = DataManager.get_unit(unit.unit_id)
	var unit_class = unit_data.get("unit_class", "")

	# Wounded units heal first — don't move while damaged unless adjacent enemy
	# threatens (then we may need to fight or retreat). Heal threshold is 70%.
	# Skip if unit has March promotion (heals while moving anyway).
	if unit.health < 70 and not ("march" in unit.promotions):
		var enemies_adjacent = _find_nearby_enemies(unit, player, 1)
		if enemies_adjacent.is_empty():
			# Safe to heal — fortify (skip turn so movement_remaining stays full)
			if not unit.is_fortified:
				unit.fortify()
			return

	# Stuck/oscillation breaker: if unit is going nowhere, try random move
	if unit.is_oscillating() or unit.is_stuck(2):
		_random_explore(unit)
		return

	# After year -2000: if any of our cities is empty (no garrison), and we're
	# not currently the only defender of our own city, head back to garrison
	# the empty one. Cities without defenders fall to single barb units.
	if TurnManager.current_year >= -2000 and not player.cities.is_empty():
		# Are we currently the sole defender here?
		var here_city = GameManager.get_city_at(unit.grid_position)
		var sole_defender = false
		if here_city and here_city.player_owner == player:
			var others_here = 0
			for u in GameManager.get_units_at(unit.grid_position):
				if u != unit and u.player_owner == player and u.get_strength() > 0:
					others_here += 1
			sole_defender = others_here == 0
		# Find nearest empty city
		if not sole_defender:
			var empty_city_pos = Vector2i(-1, -1)
			var best_dist = 9999
			for c in player.cities:
				var has_def = false
				for u in GameManager.get_units_at(c.grid_position):
					if u.player_owner == player and u.get_strength() > 0:
						has_def = true
						break
				if not has_def:
					var d = GridUtils.chebyshev_distance(unit.grid_position, c.grid_position)
					if d < best_dist:
						best_dist = d
						empty_city_pos = c.grid_position
			if empty_city_pos != Vector2i(-1, -1):
				# Don't abandon active combat — only return if no enemies adjacent
				var enemies_here = _find_nearby_enemies(unit, player, 1)
				if enemies_here.is_empty():
					if unit.grid_position == empty_city_pos:
						unit.fortify()
						return
					_move_toward(unit, empty_city_pos)
					return

	# Animal era (before 2000 BC): no real threat to cities, so explore aggressively
	# Kill animals we bump into, but don't need to garrison
	if TurnManager.current_year < -2000 and player.at_war_with.is_empty():
		# Attack adjacent animals/enemies
		var enemies = _find_nearby_enemies(unit, player, 1)
		for enemy in enemies:
			if GridUtils.are_adjacent(unit.grid_position, enemy.grid_position):
				var odds = CombatSystem.calculate_odds(unit, enemy)
				if odds.win_chance >= 0.5:
					CombatSystem.resolve_combat(unit, enemy)
					return
		# Priority: seek goody huts (tribal villages)
		var goody_pos = _find_nearest_goody_hut(unit, player)
		if goody_pos != Vector2i(-1, -1):
			_move_toward(unit, goody_pos)
			_attack_adjacent_if_good_odds(unit, player)
			return
		# Explore unexplored tiles
		var unexplored = _find_nearest_unexplored(unit, player)
		if unexplored != Vector2i(-1, -1):
			_move_toward(unit, unexplored)
			_attack_adjacent_if_good_odds(unit, player)
			return
		_random_explore(unit)
		return

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

	# 0b. CITY ASSAULT — "break eggs to make an omelette" strategic logic
	# Evaluate whether attacking an enemy city is worth sacrificing units
	if unit_class != "siege" and not player.at_war_with.is_empty():
		var nearby_enemy_city = _find_nearby_enemy_city(unit, player, 3)
		if nearby_enemy_city != null:
			var city_pos = nearby_enemy_city.grid_position

			# Count our forces vs their defenders near the city
			var our_force = 0.0
			var their_defense = 0.0
			var our_units_near = 0
			var tiles_near_city = GridUtils.get_tiles_in_range(city_pos, 2)
			for t_pos in tiles_near_city:
				for u in GameManager.get_units_at(t_pos):
					if u.player_owner == player and u.get_strength() > 0:
						our_force += u.get_strength() * (u.health / 100.0)
						our_units_near += 1
					elif u.player_owner == nearby_enemy_city.player_owner and u.get_strength() > 0:
						their_defense += u.get_strength() * (u.health / 100.0) * 1.5  # Defender bonus

			# Strategic value of the city (higher = worth more sacrifice)
			var city_value = nearby_enemy_city.population * 10 + nearby_enemy_city.buildings.size() * 5
			if nearby_enemy_city.player_owner.cities.size() <= 1:
				city_value *= 2  # Elimination blow — very high value

			# Cost estimate: we might lose ~half our force to take the city
			var estimated_cost = our_force * 0.5

			# Decision: attack if we have enough force AND the city is worth it
			var should_assault = our_force > their_defense * 0.8 and our_units_near >= 2
			# Or if city value greatly exceeds cost (worth the sacrifice)
			if not should_assault and city_value > estimated_cost * 3:
				should_assault = our_units_near >= 1

			if should_assault and GridUtils.are_adjacent(unit.grid_position, city_pos):
				# Find the weakest defender on the city tile to attack
				var city_defenders = GameManager.get_units_at(city_pos)
				var weakest_def = null
				var weakest_str = INF
				for def in city_defenders:
					if def.player_owner != player and def.get_strength() > 0:
						var eff_str = def.get_strength() * (def.health / 100.0)
						if eff_str < weakest_str:
							weakest_str = eff_str
							weakest_def = def
				if weakest_def:
					if sim_logger:
						sim_logger.log_decision(player.player_name, "combat", "city_assault",
							"%s vs %s at %s (force=%.0f vs def=%.0f, value=%d)" % [
								unit.unit_id, weakest_def.unit_id, nearby_enemy_city.city_name,
								our_force, their_defense, city_value], "")
					CombatSystem.resolve_combat(unit, weakest_def)
					return
			elif not should_assault:
				# Not ready to assault — move adjacent and wait for reinforcements
				if not GridUtils.are_adjacent(unit.grid_position, city_pos):
					_move_toward(unit, city_pos)
				return

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

			if odds.win_chance >= min_odds:
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

	# 2. Strategic: move toward assigned war target and assault enemy cities
	if not player.at_war_with.is_empty():
		var war_target = AIStrategyClass.get_war_target_for_unit(player, unit)
		if not war_target.is_empty():
			var target_pos: Vector2i = war_target.city_position
			_move_toward(unit, target_pos)
			# After moving, aggressively attack any adjacent enemy
			if is_instance_valid(unit) and unit.movement_remaining > 0:
				var new_enemies = _find_nearby_enemies(unit, player, 1)
				for enemy in new_enemies:
					if not is_instance_valid(enemy):
						continue
					if not GridUtils.are_adjacent(unit.grid_position, enemy.grid_position):
						continue
					# Lower threshold for city assaults — we MUST take the city
					var is_city_assault = GameManager.get_city_at(enemy.grid_position) != null
					var assault_min_odds = 0.25 if is_city_assault else 0.35
					var new_odds = CombatSystem.calculate_odds(unit, enemy)
					if new_odds.win_chance > assault_min_odds:
						if sim_logger:
							sim_logger.log_decision(player.player_name, "combat",
								"city_assault" if is_city_assault else "attack_after_move",
								"%s vs %s at (%d,%d)" % [unit.unit_id, enemy.unit_id, enemy.grid_position.x, enemy.grid_position.y],
								"odds=%.0f%%" % (new_odds.win_chance * 100))
						CombatSystem.resolve_combat(unit, enemy)
						break
			return

		# No war target assigned — move toward nearest enemy city
		var nearest_enemy_city = _find_nearest_enemy_city(unit, player)
		if nearest_enemy_city != Vector2i(-1, -1):
			_move_toward(unit, nearest_enemy_city)
			# Try to attack after moving
			if is_instance_valid(unit) and unit.movement_remaining > 0:
				var adj_enemies = _find_nearby_enemies(unit, player, 1)
				for enemy in adj_enemies:
					if is_instance_valid(enemy) and GridUtils.are_adjacent(unit.grid_position, enemy.grid_position):
						if sim_logger:
							var odds = CombatSystem.calculate_odds(unit, enemy)
							sim_logger.log_decision(player.player_name, "combat", "attack_march",
								"%s vs %s at (%d,%d)" % [unit.unit_id, enemy.unit_id, enemy.grid_position.x, enemy.grid_position.y],
								"odds=%.0f%%" % (odds.win_chance * 100))
						CombatSystem.resolve_combat(unit, enemy)
						break
			return

	# 3. Strategic: garrison threatened cities (but not while at war — send units to fight)
	if player.at_war_with.is_empty():
		var defense_need = AIStrategyClass.get_city_needing_garrison(player, unit)
		if not defense_need.is_empty():
			_move_toward(unit, defense_need.city_position)
			if unit.grid_position == defense_need.city_position:
				unit.fortify()
			return

	# 4. Fallback: garrison undefended own cities (keep 1 defender per city)
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

	# 5. Hunt barbarians near borders (peacetime priority — clear threats for settlers/workers)
	if player.at_war_with.is_empty():
		var barb_target = _find_nearby_barbarian(unit, player)
		if barb_target != null:
			if GridUtils.are_adjacent(unit.grid_position, barb_target.grid_position):
				var odds = CombatSystem.calculate_odds(unit, barb_target)
				if odds.win_chance >= 0.4:
					CombatSystem.resolve_combat(unit, barb_target)
					return
			else:
				_move_toward(unit, barb_target.grid_position)
				# Attack after moving if adjacent
				if is_instance_valid(unit) and is_instance_valid(barb_target) and unit.movement_remaining > 0:
					if GridUtils.are_adjacent(unit.grid_position, barb_target.grid_position):
						var odds = CombatSystem.calculate_odds(unit, barb_target)
						if odds.win_chance >= 0.4:
							CombatSystem.resolve_combat(unit, barb_target)
				return

	# 6. Seek goody huts (tribal villages)
	var goody_pos = _find_nearest_goody_hut(unit, player)
	if goody_pos != Vector2i(-1, -1):
		_move_toward(unit, goody_pos)
		return

	# 7. Explore unexplored tiles
	var unexplored = _find_nearest_unexplored(unit, player)
	if unexplored != Vector2i(-1, -1):
		_move_toward(unit, unexplored)
		return

	# 8. Nothing to do
	unit.fortify()

## Find a barbarian unit near owned territory (within 8 tiles of any city, visible only)
func _find_nearby_barbarian(unit, player):
	var best_barb = null
	var best_dist = 999

	for other_player in GameManager.players:
		if other_player.civilization_id != "barbarian":
			continue
		for barb_unit in other_player.units:
			if not is_instance_valid(barb_unit) or barb_unit.get_strength() <= 0:
				continue
			# Fog of war: only detect visible barb units
			if GameManager.hex_grid:
				var btile = GameManager.hex_grid.get_tile(barb_unit.grid_position)
				if btile and btile.get_visibility_for_player(player.player_id) < 2:
					continue  # Not currently visible
			# Must be near one of our cities (range scaled by map size)
			var near_our_city = false
			var barb_range = GameManager.scaled_distance(8)
			for city in player.cities:
				if GridUtils.chebyshev_distance(barb_unit.grid_position, city.grid_position) <= barb_range:
					near_our_city = true
					break
			if not near_our_city:
				continue
			var dist = GridUtils.chebyshev_distance(unit.grid_position, barb_unit.grid_position)
			if dist < best_dist:
				best_dist = dist
				best_barb = barb_unit

	return best_barb

## Count barbarian units within ~8 tiles (scaled) of any owned city (visible only)
func _count_barbs_near_cities(player) -> int:
	var count = 0
	var barb_range = GameManager.scaled_distance(8)
	for other_player in GameManager.players:
		if other_player.civilization_id != "barbarian":
			continue
		for barb_unit in other_player.units:
			if not is_instance_valid(barb_unit) or barb_unit.get_strength() <= 0:
				continue
			# Fog of war: only count visible barbs
			if GameManager.hex_grid:
				var btile = GameManager.hex_grid.get_tile(barb_unit.grid_position)
				if btile and btile.get_visibility_for_player(player.player_id) < 2:
					continue
			for city in player.cities:
				if GridUtils.chebyshev_distance(barb_unit.grid_position, city.grid_position) <= barb_range:
					count += 1
					break
	return count

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
	# === URGENT OVERRIDES (ignore current production) ===
	# These override what the city is already building because the situation has
	# changed enough that the previous plan is no longer viable.

	# Override 1: settler stranded here without escort — build a military unit NOW.
	var stranded_settler_here = false
	for u in GameManager.get_units_at(city.grid_position):
		if u.player_owner == player and u.can_found_city():
			var has_mil = false
			for u2 in GameManager.get_units_at(city.grid_position):
				if u2 != u and u2.player_owner == player and u2.get_strength() > 0:
					has_mil = true
					break
			if not has_mil:
				stranded_settler_here = true
				break
	if stranded_settler_here:
		var escort_unit = _get_best_military_unit(city, player, flavor.get("military", 5), false)
		if escort_unit != "" and city.current_production != escort_unit:
			city.set_production(escort_unit)
			return

	# Override 2: war emergency — at war and dangerously under-defended, currently
	# building something that doesn't help. Switch to military immediately.
	# Threshold: below 1 garrison per city (not "1 + spare"), so we don't lock cities
	# into perpetual military build mode and starve them of workers/settlers.
	# Applies to BOTH civ wars and barb wars with imminent threat:
	# - Real civ war: always an emergency if under garrison
	# - Barb war: only an emergency if a barb unit is actually adjacent to this city
	#   (the per-city barbs_near_borders check handles distant threats)
	var has_real_war = false
	for enemy_id in player.at_war_with:
		var enemy_p = GameManager.get_player(enemy_id)
		if enemy_p and enemy_p.civilization_id != "barbarian":
			has_real_war = true
			break
	var barb_at_doorstep = false
	if not has_real_war and not player.at_war_with.is_empty():
		# Check for any enemy unit within 4 tiles of this city — give the AI time
		# to respond before the threat reaches the gates. Mongolia was getting
		# eliminated at T93 because the narrower check (2 tiles) only tripped once
		# a barb was already adjacent.
		for check_pos in GridUtils.get_tiles_in_range(city.grid_position, 4):
			var u = GameManager.get_unit_at(check_pos)
			if u and u.player_owner and u.player_owner != player and u.get_strength() > 0:
				barb_at_doorstep = true
				break
	if (has_real_war or barb_at_doorstep) and city.current_production != "":
		var mil_count = 0
		for u in player.units:
			if u.get_strength() > 0:
				mil_count += 1
		var min_garrison = player.cities.size()
		if mil_count < min_garrison:
			# Is the current production a military unit?
			var prod = city.current_production
			var prod_data = DataManager.get_unit(prod)
			var is_military = not prod_data.is_empty() and prod_data.get("strength", 0) > 0
			if not is_military:
				var emergency_unit = _get_best_military_unit(city, player, flavor.get("military", 5), false)
				if emergency_unit != "" and emergency_unit != prod:
					if sim_logger:
						sim_logger.log_decision(player.player_name, "production", "war_emergency_switch",
							"%s -> %s" % [prod, emergency_unit],
							"real_war, mil=%d, garrison=%d" % [mil_count, min_garrison])
					city.set_production(emergency_unit)
					return

	# Override 3: economic distress — going bankrupt and currently producing something
	# expensive that won't help (settler/wonder/military). Switch to a building that
	# fixes the economy: courthouse (maintenance reduction), market (+gold), library.
	# Sims showed all 3 civs collapsing to 0% science by T100 with -30 to -99 gpt because
	# nothing in the production tree responded to running deficits — cities kept queuing
	# settlers and military as fast as they finished, never reaching the building scorer.
	# Two triggers: (a) near-bankrupt (low gold and deficit), or (b) severe deficit
	# regardless of current gold reserves (structural problem needs immediate action).
	var severe_deficit = player.gold_per_turn < -10
	var near_bankrupt = player.gold_per_turn < -3 and player.gold < 50
	if (severe_deficit or near_bankrupt) and city.current_production != "":
		var prod = city.current_production
		var prod_unit_data = DataManager.get_unit(prod)
		var is_unit_prod = not prod_unit_data.is_empty()
		var prod_bld_data = DataManager.get_building(prod) if not is_unit_prod else {}
		var bld_effects = prod_bld_data.get("effects", {})
		var helps_economy = bld_effects.has("gold") or bld_effects.has("gold_percent") \
			or bld_effects.has("maintenance_reduction") or bld_effects.has("trade_routes") \
			or bld_effects.has("science") or bld_effects.has("science_percent")
		# Don't switch away from a cheap defender if we're below minimum garrison —
		# otherwise the city loops "build warrior → switch to library → next city
		# loops the same way → garrison stays at 0 → bankruptcy disbands what we
		# do have." Let the warrior actually finish first.
		var protect_cheap_mil = false
		if is_unit_prod:
			var pmil_count = 0
			for u in player.units:
				if u.get_strength() > 0:
					pmil_count += 1
			var prod_strength = prod_unit_data.get("strength", 0)
			var prod_cost = prod_unit_data.get("cost", 999)
			if prod_strength > 0 and prod_cost <= 35 and pmil_count < player.cities.size():
				protect_cheap_mil = true
		if (is_unit_prod or not helps_economy) and not protect_cheap_mil:
			var rescue_bld = _get_economic_rescue_building(city, player)
			if rescue_bld != "" and rescue_bld != prod:
				if sim_logger:
					sim_logger.log_decision(player.player_name, "production", "economic_rescue_switch",
						"%s -> %s" % [prod, rescue_bld],
						"gpt=%d, gold=%d" % [player.gold_per_turn, player.gold])
				city.set_production(rescue_bld)
				return

	# Consider whipping current production to completion (Slavery civic)
	if city.current_production != "":
		_consider_whipping(city, player)
		return

	# If city just finished a settler, build an escort unit immediately
	if city.has_meta("needs_escort") and city.get_meta("needs_escort"):
		city.remove_meta("needs_escort")
		var escort = _get_best_military_unit(city, player, flavor.get("military", 5), false)
		if escort != "":
			city.set_production(escort)
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

	# Calculate target city count based on map size and player count
	var map_tiles = GameManager.map_width * GameManager.map_height
	var num_real_players = 0
	for p in GameManager.players:
		if p.civilization_id != "barbarian":
			num_real_players += 1
	var land_per_player = map_tiles / max(num_real_players, 1)
	var max_c_div = _ai_tun(player, "expansion.max_cities_divisor", 150)
	var max_c_ediv = _ai_tun(player, "expansion.max_cities_expansion_divisor", 4)
	var max_c_min = _ai_tun(player, "expansion.max_cities_hard_min", 3)
	var max_c_max = _ai_tun(player, "expansion.max_cities_hard_max", 7)
	# Scale hard_max by map size — on huge maps the default 7 is too tight
	var scaled_max = GameManager.scaled_count(int(max_c_max))
	var max_cities = clampi(land_per_player / int(max_c_div) + expansion_flavor / int(max_c_ediv), int(max_c_min), scaled_max)
	# Dynamic cap: reduce max if economy is struggling — don't expand into bankruptcy
	var freeze_gpt = _ai_tun(player, "expansion.freeze_max_cities_at_gpt", -10)
	var soft_brake_gpt = _ai_tun(player, "expansion.soft_brake_gpt", -3)
	var soft_brake_sci = _ai_tun(player, "expansion.soft_brake_science_rate", 0.5)
	if player.gold_per_turn < freeze_gpt:
		max_cities = num_cities  # Hard freeze at current
	elif player.gold_per_turn < soft_brake_gpt and player.science_rate < soft_brake_sci:
		max_cities = mini(max_cities, num_cities + 1)  # Allow at most 1 more

	# Count settlers already in production or in the field
	var settlers_out = 0
	for u in player.units:
		if u.can_found_city():
			settlers_out += 1

	# Early expansion: settler from capital when only 1 city
	# MUST have at least 2 military (1 to garrison, 1 to escort)
	if num_cities <= 1 and settlers_out == 0 and city.population >= 3 and military_units >= 2:
		if city.can_build_unit("settler"):
			city.set_production("settler")
			city.set_meta("needs_escort", true)
			return
	# If only 1 military and need settlers, build military first
	elif num_cities <= 1 and settlers_out == 0 and city.population >= 3 and military_units < 2:
		var mil_unit = _get_best_military_unit(city, player, military_flavor, false)
		if mil_unit != "":
			city.set_production(mil_unit)
			return

	# Calculate desired military based on flavor, specialization, and personality
	var personality = _get_leader_personality(player)
	var build_unit_prob_default = _ai_tun(player, "military.build_unit_prob_default", 40)
	var build_unit_prob = personality.get("build_unit_prob", build_unit_prob_default)
	var mil_base = _ai_tun(player, "military.desired_per_city_base", 1)
	var mil_div = _ai_tun(player, "military.desired_per_city_flavor_divisor", 5)
	var desired_military = num_cities * (mil_base + military_flavor / float(mil_div)) * (build_unit_prob / float(build_unit_prob_default))
	if specialization == CitySpecialization.MILITARY:
		desired_military *= 1.5
	# Late-game threat scaling: after turn X (scaled), increase desired military per city.
	var late_turn_1 = GameManager.scaled_turn(_ai_tun(player, "military.late_game_floor_turn_1", 150))
	var late_mult_1 = _ai_tun(player, "military.late_game_floor_per_city_1", 2)
	var late_turn_2 = GameManager.scaled_turn(_ai_tun(player, "military.late_game_floor_turn_2", 250))
	var late_mult_2 = _ai_tun(player, "military.late_game_floor_per_city_2", 3)
	if TurnManager.current_turn >= late_turn_1:
		desired_military = max(desired_military, num_cities * late_mult_1)
	if TurnManager.current_turn >= late_turn_2:
		desired_military = max(desired_military, num_cities * late_mult_2)

	# Hard cap: scale with cities but don't over-build
	var max_per_city = _ai_tun(player, "military.max_per_city_mult", 3)
	var max_base = _ai_tun(player, "military.max_military_base", 3)
	var max_military = num_cities * max_per_city + max_base
	# Economic cap: don't build more military if going broke. We react earlier
	# than the previous gold<=0 check — by the time gold hits 0, units are
	# already disbanding to bankruptcy and the AI was still queueing more.
	var free_supply = num_cities + 2
	var bankrupt = player.gold_per_turn < 0 and player.gold < 50
	if bankrupt:
		# Only allow more military if we're below the absolute floor (1 per city).
		# Above that, freeze at current count until economy recovers.
		max_military = max(num_cities, military_units)
	elif player.gold <= 0 and military_units > free_supply:
		max_military = military_units  # Legacy guard
	var need_military = military_units < desired_military and military_units < max_military

	# Calculate army composition — ensure 30% siege when at war
	var siege_count = 0
	for u in player.units:
		var udata = DataManager.get_unit(u.unit_id)
		if udata.get("unit_class", "") == "siege":
			siege_count += 1
	var siege_ratio = float(siege_count) / max(military_units, 1)
	var needs_siege = not player.at_war_with.is_empty() and siege_ratio < 0.3 and military_units >= 3

	# Need at least 1 worker early on
	if workers == 0 and num_cities >= 1:
		if city.can_build_unit("worker"):
			city.set_production("worker")
			return

	# URGENT: settler waiting in city for escort — build military immediately
	var settler_waiting = false
	for u in player.units:
		if u.can_found_city() and GameManager.get_city_at(u.grid_position) != null:
			settler_waiting = true
			break
	if settler_waiting and military_units < num_cities + settlers_out:
		var escort_unit = _get_best_military_unit(city, player, military_flavor, false)
		if escort_unit != "":
			city.set_production(escort_unit)
			return

	# Barbarians near borders — build military to clear them
	var barbs_near_borders = _count_barbs_near_cities(player)
	if barbs_near_borders > 0 and military_units < num_cities + barbs_near_borders:
		var hunter_unit = _get_best_military_unit(city, player, military_flavor, false)
		if hunter_unit != "":
			city.set_production(hunter_unit)
			return

	# Urgent military: if below minimum garrison (1 per city), build military first
	var garrison_minimum = num_cities
	if need_military and military_units < garrison_minimum:
		var unit_to_build = _get_best_military_unit(city, player, military_flavor, needs_siege, bankrupt)
		if unit_to_build != "":
			city.set_production(unit_to_build)
			return

	# After year -2000 (when real barb threats begin), every city MUST have a
	# defender. If THIS city currently has no military unit on it, build one
	# right now regardless of total military count.
	if TurnManager.current_year >= -2000:
		var has_garrison = false
		for u in GameManager.get_units_at(city.grid_position):
			if u.player_owner == player and u.get_strength() > 0:
				has_garrison = true
				break
		if not has_garrison:
			var garrison_unit = _get_best_military_unit(city, player, military_flavor, false, bankrupt)
			if garrison_unit != "":
				city.set_production(garrison_unit)
				return

	# ECONOMY FIX: when running a deficit, prioritize economic buildings in EVERY city
	# before building more settlers/military. This prevents the common pattern of
	# expanding to 4 cities → all building military → maintenance crashes economy.
	# Only skip if we're below garrison minimum (defense comes first).
	if player.gold_per_turn < -3 and military_units >= garrison_minimum:
		var econ_bld = _get_economic_rescue_building(city, player)
		if econ_bld != "":
			city.set_production(econ_bld)
			return

	# Early game military floor: ensure minimum military units before the early
	# game cutoff (scaled by speed + map size). Civs with 1 warrior get
	# eliminated by first contact with barbarians or aggressive neighbors.
	var early_floor_turn = GameManager.scaled_turn(_ai_tun(player, "military.early_game_floor_turn", 50))
	var early_floor_count = _ai_tun(player, "military.early_game_floor_count", 2)
	if military_units < early_floor_count and TurnManager.current_turn < early_floor_turn and workers >= 1:
		var early_mil = _get_best_military_unit(city, player, military_flavor, false)
		if early_mil != "":
			city.set_production(early_mil)
			return

	# New cities MUST get a culture building first to expand borders (BTS priority)
	# Without culture, the city can't work tiles beyond the center
	var has_culture_building = false
	for bld in city.buildings:
		var effects = DataManager.get_building_effects(bld)
		if effects.get("culture", 0) > 0:
			has_culture_building = true
			break
	if not has_culture_building:
		# Try monument first (cheapest culture), then any culture building
		for culture_bld in ["monument", "obelisk"]:
			if city.can_build_building(culture_bld):
				city.set_production(culture_bld)
				return
		# Fall through to general building scorer which will pick culture buildings

	# Build infrastructure early — every city should have key buildings before more military
	var has_basic_infra = false
	for bld in ["granary", "library", "monument", "barracks"]:
		if bld in city.buildings:
			has_basic_infra = true
			break
	if not has_basic_infra:
		var building_to_build = _get_best_building_for_specialization(city, player, flavor, specialization)
		if building_to_build != "":
			city.set_production(building_to_build)
			return

	# AGGRESSIVE EXPANSION: build settler before general military buildup.
	# Civ4 BTS doctrine — expand first, fight later. The previous check ran
	# AFTER need_military, which meant the AI burned 30+ turns building extra
	# warriors past garrison_minimum and never got around to a 2nd settler.
	#
	# Allow multiple settlers in flight (capped) so two cities can pump out
	# colonists in parallel while new sites are still available.
	var settlers_in_production = 0
	for c in player.cities:
		if c.current_production == "settler":
			settlers_in_production += 1
	var inflight_settlers = settlers_out + settlers_in_production
	var slots_remaining = max_cities - num_cities
	# Use the strategy/civ-tunable max inflight, capped by remaining slots
	var max_inflight_tun = _ai_tun(player, "expansion.max_inflight_settlers", 2)
	var max_inflight = clampi(slots_remaining, 0, int(max_inflight_tun))
	# Progressive expansion brake based on science slider — same logic as
	# ai_strategy.update_strategy. Below 70% science we scale parallel settler
	# builds down so the empire stops adding cities before bankruptcy hits.
	if player.science_rate < 0.70:
		if player.science_rate <= 0.30:
			max_inflight = 0
		elif player.science_rate <= 0.50:
			max_inflight = min(max_inflight, 1)
	# Preemptive gpt-margin brake — only when truly bleeding gold.
	# Old thresholds were too strict: gpt=0 (balanced budget) blocked ALL settlers,
	# causing civs to sit on 400+ gold at 1 city for 100+ turns.
	# Now: only block if actively losing money AND low on reserves.
	if player.gold_per_turn < -5 and player.gold < 50:
		max_inflight = 0
	elif player.gold_per_turn < 0 and player.gold < 20:
		max_inflight = 0
	if inflight_settlers < max_inflight and city.population >= 3:
		# Garrison: 1 military per city is enough; we don't need a spare
		# escort here because the urgent-escort path above handles that
		# when the settler actually starts walking.
		if military_units >= num_cities and city.can_build_unit("settler"):
			city.set_production("settler")
			city.set_meta("needs_escort", true)
			return

	# More military if needed — but interleave with buildings (40% chance to build instead)
	if need_military:
		# Check if a building would be more valuable (especially early game)
		var try_building_instead = randf() < 0.4 and military_units >= garrison_minimum
		if try_building_instead:
			var alt_building = _get_best_building_for_specialization(city, player, flavor, specialization)
			if alt_building != "":
				city.set_production(alt_building)
				return
		var unit_to_build = _get_best_military_unit(city, player, military_flavor, needs_siege, bankrupt)
		if unit_to_build != "":
			city.set_production(unit_to_build)
			return

	# Need more workers? (1 per city, more when expanding)
	var desired_workers = max(1, num_cities)
	if workers < desired_workers:
		if city.can_build_unit("worker"):
			city.set_production("worker")
			return

	# Build more infrastructure (wonders, temples, markets, etc.)
	var building_to_build = _get_best_building_for_specialization(city, player, flavor, specialization)
	if building_to_build != "":
		city.set_production(building_to_build)
		return

	# Consider projects (high production cities, late game)
	var project_to_build = _get_best_project(city, player, flavor, specialization)
	if project_to_build != "":
		city.set_production(project_to_build)
		return

	# Default: build military only if at war or significantly under garrison
	if military_units < max_military and (not player.at_war_with.is_empty() or military_units < num_cities):
		var unit_to_build = _get_best_military_unit(city, player, military_flavor)
		if unit_to_build != "":
			city.set_production(unit_to_build)
			return

	# Last resort: build ANY available unit or building so city is never idle
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
## Peacetime disband: when not at war and running a deficit, disband excess
## military units that aren't contributing to the empire. Only applies if we
## have more than a comfortable garrison (2 per city).
func _consider_peacetime_disband(player) -> void:
	# Only in peace
	var real_war = false
	for enemy_id in player.at_war_with:
		var enemy = GameManager.get_player(enemy_id)
		if enemy and enemy.civilization_id != "barbarian":
			real_war = true
			break
	if real_war:
		return

	# Only when bleeding gold
	if player.gold_per_turn >= 0:
		return

	# Count military and identify excess
	var mil_units: Array = []
	for u in player.units:
		if u.get_strength() > 0:
			mil_units.append(u)

	var num_cities = player.cities.size()
	var per_city = _ai_tun(player, "military.comfort_garrison_per_city", 2)
	var comfort_garrison = num_cities * int(per_city)
	var excess = mil_units.size() - comfort_garrison
	if excess <= 0:
		return

	# Disband the weakest excess units, preferring obsolete/outdated units
	# Don't disband units in cities (garrison) or the single strongest unit of its class
	mil_units.sort_custom(func(a, b):
		var sa = DataManager.get_unit_strength(a.unit_id)
		var sb = DataManager.get_unit_strength(b.unit_id)
		return sa < sb)  # weakest first

	var disbanded = 0
	# Disband up to half the excess per turn to smooth the transition
	var to_disband = max(1, excess / 2)
	for u in mil_units:
		if disbanded >= to_disband:
			break
		# Skip garrisoned units (in own city)
		if GameManager.get_city_at(u.grid_position) != null:
			continue
		# Skip injured — let them heal
		if u.health < 100:
			continue
		u.die()
		disbanded += 1
		if sim_logger:
			sim_logger.log_decision(player.player_name, "military", "peacetime_disband",
				u.unit_id, "gpt=%d, mil=%d, garrison=%d" % [player.gold_per_turn, mil_units.size(), comfort_garrison])

func _consider_whipping(city, player) -> void:
	# Only whip with Slavery civic active
	if player.civics.get("labor", "") != "slavery":
		return

	if not city.can_whip():
		return

	# Never whip below population 4 (preserves growth — was 3, raised because
	# sims showed late-game pop collapse from repeated whipping)
	if city.population <= 3:
		return

	# Don't whip if already suffering whip anger
	if city.has_meta("whip_anger_turns") and city.get_meta("whip_anger_turns") > 0:
		return

	# Don't whip if food surplus is zero or negative — whipping removes a citizen
	# from a food tile and the city will starve back down soon after.
	if city.food_surplus <= 1:
		return

	# Don't whip if the city recently whipped (cooldown beyond the anger window)
	var whip_cooldown = GameManager.scaled_turn(_ai_tun(player, "whip.cooldown_turns", 15))
	var last_whip_turn = city.get_meta("last_whip_turn", -100)
	if TurnManager.current_turn - last_whip_turn < whip_cooldown:
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

	# Building settler + over 50% complete → whip (but settlers are costly, keep
	# the same high bar: pop must be >= 5 to afford losing one to a settler)
	if prod == "settler" and progress_ratio > 0.5 and city.population >= 5:
		should_whip = true

	# Building critical early building with pop >= 5 → whip
	if city.population >= 5:
		if prod in ["granary", "library"]:
			should_whip = true
		elif prod == "barracks" and at_war:
			should_whip = true

	if should_whip:
		city.whip()
		city.set_meta("last_whip_turn", TurnManager.current_turn)
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
	# AI manages all commerce sliders: science, culture, espionage
	# Culture slider: only when going for cultural victory or need borders
	var flavor = _get_leader_flavor(player)
	var culture_flavor = flavor.get("culture", 5)

	# Culture slider — only available with Drama tech
	if player.has_tech("drama") and culture_flavor >= HIGH_FLAVOR:
		# High-culture AI allocates some commerce to culture
		player.culture_rate = 0.1
	else:
		player.culture_rate = 0.0

	# Espionage slider — only allocate when player has espionage tech and at war
	if not player.at_war_with.is_empty() and player.has_tech("alphabet"):
		player.espionage_rate = 0.1
	else:
		player.espionage_rate = 0.0

	# Science gets the rest minus culture and espionage
	var max_science = 1.0 - player.culture_rate - player.espionage_rate

	# BTS-style science management: maximize science, only drop when gold reserves
	# fall below a threshold. AI is OK running a deficit while it has cash reserves
	# (investing in research), but must balance the budget before going broke.
	player.science_rate = max_science
	for city in player.cities:
		city.calculate_yields()
	var est_gpt = _estimate_gold_per_turn(player)

	# Allow deficit spending while gold reserves are healthy.
	# Use hysteresis to prevent oscillation: drop science when gold < 80,
	# but only go back to full science when gold > 150. This prevents the
	# yo-yo between 100%/0% science every few turns.
	var gold_floor = 80 if player.science_rate >= 0.5 else 150
	if est_gpt < 0 and player.gold < gold_floor:
		# Reduce science until we break even or hit minimum
		while player.science_rate > 0.0:
			player.science_rate = max(0.0, player.science_rate - 0.1)
			for city in player.cities:
				city.calculate_yields()
			est_gpt = _estimate_gold_per_turn(player)
			if est_gpt >= 0 or player.science_rate <= 0.01:
				break

## Estimate gold per turn based on current city yields and known costs.
## Uses the same calculation as turn_manager._process_gold for accuracy.
func _estimate_gold_per_turn(player) -> int:
	var total_gold = 0
	for city in player.cities:
		total_gold += city.gold_yield

	# === City Maintenance (mirrors turn_manager._process_gold) ===
	var num_cities = player.cities.size()
	var capital_pos = Vector2i.ZERO
	var palace_positions = []
	for city in player.cities:
		if "palace" in city.buildings:
			capital_pos = city.grid_position
		for building_id in city.buildings:
			var effects = DataManager.get_building_effects(building_id)
			if effects.get("second_palace", false):
				palace_positions.append(city.grid_position)
	if palace_positions.is_empty():
		palace_positions.append(capital_pos)

	# Map scale factor (same as turn_manager)
	var map_tiles = float(GameManager.map_width * GameManager.map_height)
	var map_scale = sqrt(4000.0 / max(map_tiles, 100.0))

	var city_maintenance = 0
	for city in player.cities:
		var min_dist = 999
		for palace_pos in palace_positions:
			var d = GridUtils.chebyshev_distance(city.grid_position, palace_pos)
			if d < min_dist:
				min_dist = d
		var dist_cost = int(min_dist * 0.5 * map_scale)
		# Courthouse reduces maintenance
		for building_id in city.buildings:
			var effects = DataManager.get_building_effects(building_id)
			var reduction = effects.get("maintenance_reduction", 0.0)
			if reduction > 0:
				dist_cost = int(dist_cost * (1.0 - reduction))
		var count_cost = int(max(0, num_cities - 1) * 0.5 * map_scale)
		city_maintenance += dist_cost + count_cost

	# Unit supply
	var military_count = 0
	for unit in player.units:
		if DataManager.get_unit_strength(unit.unit_id) > 0:
			military_count += 1
	var free_units = num_cities + 2
	var unit_supply = max(0, military_count - free_units)

	# Inflation (normalized by game speed, same as turn_manager)
	var normalized_turn = TurnManager.current_turn / GameManager.get_speed_multiplier()
	var inflation = min(1.0 + normalized_turn * 0.001, 1.5)
	city_maintenance = int(city_maintenance * inflation)
	unit_supply = int(unit_supply * inflation)

	# Civic upkeep
	var civic_upkeep = 0
	if CivicsSystem:
		civic_upkeep = CivicsSystem.get_civic_upkeep(player)
		if player.has_trait("organized"):
			civic_upkeep = civic_upkeep / 2

	return total_gold - city_maintenance - unit_supply - civic_upkeep

func _evaluate_tech(tech_id: String, player, flavor: Dictionary) -> float:
	var score = 0.0
	var tech = DataManager.get_tech(tech_id)
	var unlocks = tech.get("unlocks", {})

	var military_flavor = flavor.get("military", 5)
	var science_flavor = flavor.get("science", 5)
	var gold_flavor = flavor.get("gold", 5)
	var culture_flavor = flavor.get("culture", 5)
	var religion_flavor = flavor.get("religion", 5)

	# Value units - scale by actual strength improvement over current units
	if unlocks.has("units"):
		var best_current_str = 0.0
		for unit in player.units:
			var s = DataManager.get_unit_strength(unit.unit_id)
			if s > best_current_str:
				best_current_str = s
		for unit_id in unlocks.units:
			var unit_str = DataManager.get_unit_strength(unit_id)
			var unit_class = DataManager.get_unit(unit_id).get("unit_class", "")
			if unit_class in ["melee", "mounted", "gunpowder", "archery", "armor", "siege"]:
				# Strong bonus if this unit is better than what we have
				var improvement = max(0, unit_str - best_current_str)
				score += (10 + improvement * 5) * (military_flavor / 5.0)
			else:
				score += 5 * (military_flavor / 5.0)

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

	# Value improvements — bonus if we have resources matching those improvements
	if unlocks.has("improvements"):
		for imp_id in unlocks.improvements:
			score += 3
			# Check if we have resources in our territory that need this improvement
			var imp_data = DataManager.get_improvement(imp_id)
			var requires_resource = imp_data.get("requires_resource", [])
			if not requires_resource.is_empty():
				for city in player.cities:
					for tile_pos in city.territory:
						var t = GameManager.hex_grid.get_tile(tile_pos) if GameManager.hex_grid else null
						if t and t.resource_id in requires_resource and t.improvement_id == "":
							score += 25  # Big bonus: we have a resource waiting for this tech!
							break

	# Religion techs
	if unlocks.has("religions"):
		score += 20 * (religion_flavor / 5.0)

	# Cheaper is better
	var cost = DataManager.get_tech_cost(tech_id)
	score += max(0, 50 - cost / 20)

	# === Strategic beelining bonuses (Civ4 BTS key tech paths) ===
	var num_techs = player.researched_techs.size()

	# Emergency: if player can only build warriors, STRONGLY boost first military tech
	var has_military_tech = player.has_tech("archery") or player.has_tech("bronze_working")
	if not has_military_tech and num_techs < 5:
		match tech_id:
			"archery": score += 50  # URGENT: need archers for defense
			"bronze_working": score += 50  # URGENT: need axemen

	# === CORE INFRASTRUCTURE TECHS ===
	# These unlock fundamental worker abilities. Without them the worker sits idle.
	# BTS AI researches these first — before any beelining. Scored high enough
	# to beat the military emergency bonus so workers can actually DO something.
	if not player.has_tech("agriculture"):
		if tech_id == "agriculture":
			score += 55  # Farms — essential for city growth, top priority
	if not player.has_tech("the_wheel"):
		if tech_id == "the_wheel":
			score += 50  # Roads! Workers need this ASAP
	if not player.has_tech("mining"):
		if tech_id == "mining":
			score += 45  # Mines — basic production on hills
	if not player.has_tech("animal_husbandry"):
		if tech_id == "animal_husbandry":
			score += 30  # Pastures for cattle/sheep/horse

	# Early game priorities (< 10 techs researched)
	if num_techs < 10:
		match tech_id:
			"bronze_working": score += 35  # Slavery civic + chopping + copper reveal + axeman
			"archery": score += 30  # Archers for city defense
			"pottery": score += 25  # Granary for growth, cottages for economy
			"the_wheel": score += 20  # Roads for connectivity
			"writing": score += 20  # Libraries for research
			"animal_husbandry": score += 15  # Horse reveal
			"hunting": score += 10  # Scouts, camps
			"masonry": score += 10  # Walls for defense

	# Economy critical path — always valuable, scaled by flavor
	match tech_id:
		"mathematics": score += 30 * (science_flavor / 5.0)  # Chop bonus, catapults
		"currency": score += 35 * (gold_flavor / 5.0)  # Trade routes, gold
		"code_of_laws":
			# Courthouses scale with city count — urgent for wide empires
			var cities_bonus = min(player.cities.size() * 5, 30)
			score += (25 + cities_bonus) * (gold_flavor / 5.0)

	# === ECONOMY-DRIVEN RESEARCH ===
	# When running a deficit or low science rate, boost techs that unlock
	# money-making buildings and trade. Prevents the spiral where civs expand
	# but never research the techs needed to sustain the economy.
	var in_deficit = player.gold_per_turn < 0 or player.science_rate < 0.5
	if in_deficit:
		match tech_id:
			"currency": score += 40   # Markets (+25% gold), trade routes
			"code_of_laws": score += 35  # Courthouses (-50% maintenance)
			"guilds": score += 30     # Grocers, trade route bonus
			"banking": score += 30    # Banks (+50% gold)
			"economics": score += 25  # Free Great Merchant
			"pottery": score += 20    # Cottages for commerce
			"writing": score += 15    # Libraries for science
	elif player.cities.size() >= 3 and not player.has_tech("currency"):
		# Even without deficit, 3+ cities should push for Currency (markets + trade)
		if tech_id == "currency":
			score += 25
	if player.cities.size() >= 3 and not player.has_tech("code_of_laws"):
		if tech_id == "code_of_laws":
			score += 20  # Courthouses critical for wide empires

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

	# Religion founding — only boost if player has NO religion at all
	if player.state_religion == "" and player.founded_religion == "":
		var religion_bonus = 15 + religion_flavor * 3  # 18-45 range (toned down)
		match tech_id:
			"meditation", "polytheism": score += religion_bonus
		# Only pursue advanced religion techs if highly religious
		if religion_flavor >= HIGH_FLAVOR:
			match tech_id:
				"monotheism", "theology": score += int(religion_bonus * 0.5)

	# === RESOURCE-MOTIVATED RESEARCH ===
	# If we have resources in our borders that need a specific tech, prioritize it.
	# E.g., marble in borders → boost Masonry; stone → boost Masonry; horses → Animal Husbandry
	if GameManager.hex_grid:
		var resources_in_borders: Dictionary = {}  # resource_id → count
		for city in player.cities:
			for tile_pos in city.territory:
				var res_tile = GameManager.hex_grid.get_tile(tile_pos)
				if res_tile and res_tile.resource_id != "":
					resources_in_borders[res_tile.resource_id] = resources_in_borders.get(res_tile.resource_id, 0) + 1

		# For each resource in our borders, check if the improvement tech is this tech
		for res_id in resources_in_borders.keys():
			var res_data = DataManager.get_resource(res_id)
			var required_imp = res_data.get("improvement", "")
			if required_imp == "":
				continue
			var imp_data = DataManager.get_improvement(required_imp)
			var required_tech = imp_data.get("required_tech", "")
			if required_tech != "" and required_tech == tech_id and not player.has_tech(required_tech):
				var bonus = 20 * resources_in_borders[res_id]  # More copies = higher urgency
				score += min(bonus, 60)  # Cap at 60

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

	# Search in expanding rings — only consider explored tiles
	for radius in range(1, 15):
		var tiles = GridUtils.get_tiles_at_range(unit.grid_position, radius)
		for tile_pos in tiles:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null or not tile.is_passable() or tile.is_water():
				continue
			# Fog of war: only settle on explored tiles
			if tile.get_visibility_for_player(player.player_id) == 0:
				continue

			if _is_good_city_location(tile_pos, player):
				var score = _evaluate_city_location(tile_pos, growth_flavor, production_flavor, gold_flavor, player)
				if score > best_score:
					best_score = score
					best_pos = tile_pos

		if best_pos != Vector2i(-1, -1):
			break

	return best_pos

func _evaluate_city_location(pos: Vector2i, growth_flavor: int, prod_flavor: int, gold_flavor: int, player = null) -> int:
	var score = 0
	var food_count = 0
	var tiles = GridUtils.get_tiles_in_range(pos, 2)
	for tile_pos in tiles:
		var tile = GameManager.hex_grid.get_tile(tile_pos)
		if tile == null:
			continue
		var food = tile.get_food()
		score += food * growth_flavor
		score += tile.get_production() * prod_flavor
		score += tile.get_commerce() * gold_flavor
		if food >= 2:
			food_count += 1
		if tile.resource_id != "":
			var res = DataManager.get_resource(tile.resource_id)
			var res_type = res.get("type", "")
			# Strong bonus for resources the player doesn't already have
			var already_has = player != null and player.has_resource(tile.resource_id)
			if res_type == "strategic" and not already_has:
				score += 40  # Very high — settle for iron/horse/copper
			elif res_type == "luxury" and not already_has:
				score += 30  # High — new luxury = happiness
			elif not already_has:
				score += 15  # Bonus resource
			else:
				score += 8   # Already have it but still useful
		if tile.has_fresh_water():
			score += 5  # Fresh water for farms
	# Penalize locations with too little food (can't grow)
	if food_count < 2:
		score -= 50

	# Distance penalty: prefer settling near existing cities (lower maintenance,
	# easier to defend, road connections). Penalize distance from nearest own city.
	if player != null and not player.cities.is_empty():
		var min_dist = 999
		for city in player.cities:
			var d = GridUtils.chebyshev_distance(pos, city.grid_position)
			if d < min_dist:
				min_dist = d
		# Sweet spot: 5-8 tiles from nearest city. Closer = overlap, farther = costly
		if min_dist > 10:
			score -= (min_dist - 10) * 5  # Heavy penalty for far-flung settlements
		elif min_dist > 8:
			score -= (min_dist - 8) * 2   # Mild penalty

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

## Find best target for worker: resource improvement > tile improvement > road connection
func _find_best_worker_target(unit, player) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_score = -INF

	# Check owned tiles for improvements
	for city in player.cities:
		var city_needs_prod = _city_needs_production_rush(city)
		for tile_pos in city.territory:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null or tile.is_water():
				continue
			# Skip our own tile — if we couldn't do anything here, going back is pointless
			if tile_pos == unit.grid_position:
				continue

			var dist = GridUtils.chebyshev_distance(unit.grid_position, tile_pos)
			var score = -INF

			# Unimproved resource tile — TOP PRIORITY (connects resource to trade network)
			# BUT only if we can actually build the required improvement; otherwise the
			# worker would walk all the way there and just sit, looping forever.
			if tile.resource_id != "" and tile.improvement_id == "":
				var res = DataManager.get_resource(tile.resource_id)
				var required_imp = res.get("improvement", "")
				var can_improve_now = true
				if required_imp != "":
					var avail = ImprovementSystem.get_available_improvements(unit, tile)
					can_improve_now = required_imp in avail
				if can_improve_now:
					score = 200.0 - dist * 3.0
					if res.get("type", "") == "strategic":
						score += 30
					elif res.get("type", "") == "luxury":
						score += 20

			# Unimproved non-resource tile — only target if we can actually build something
			elif tile.improvement_id == "":
				var avail = ImprovementSystem.get_available_improvements(unit, tile)
				avail = avail.filter(func(i): return i != "fort")
				if not avail.is_empty():
					score = 100.0 - dist * 5.0
					if tile.feature_id == "forest":
						if city_needs_prod:
							score += 30
						if tile.has_fresh_water() or tile.terrain_id == "hills":
							score += 15
				# Fallback: no improvement available but can build road — low priority
				elif tile.road_level == 0 and ImprovementSystem.can_build_road(unit, tile):
					score = 30.0 - dist * 2.0

			# Road needed on improved/resource tile (to connect it to trade network)
			elif tile.road_level == 0:
				if ImprovementSystem.can_build_road(unit, tile):
					if tile.resource_id != "":
						score = 150.0 - dist * 3.0
					else:
						# Road on improved tile (connect improvements to network)
						score = 50.0 - dist * 2.0

			if score > best_score:
				best_score = score
				best_pos = tile_pos

	# Road connections between cities — high priority once improvements are done
	if player.cities.size() >= 2:
		var road_target = _find_road_connection_target(unit, player)
		if road_target != Vector2i(-1, -1):
			var dist = GridUtils.chebyshev_distance(unit.grid_position, road_target)
			# Roads are very important for trade — only below resource improvements
			var road_score = 160.0 - dist * 3.0
			if road_score > best_score:
				best_score = road_score
				best_pos = road_target

	return best_pos

## Check if a position is on a path between two cities that need road connection
func _is_on_road_path(pos: Vector2i, player) -> bool:
	# Simple check: is this tile between any two cities that aren't connected by road?
	for city_a in player.cities:
		for city_b in player.cities:
			if city_a == city_b:
				continue
			var dist_ab = GridUtils.chebyshev_distance(city_a.grid_position, city_b.grid_position)
			var dist_a = GridUtils.chebyshev_distance(pos, city_a.grid_position)
			var dist_b = GridUtils.chebyshev_distance(pos, city_b.grid_position)
			# On the path if pos is roughly between the two cities
			if dist_a + dist_b <= dist_ab + 2:
				return true
	return false

## Find next tile along a road connection path between unconnected cities
func _find_road_connection_target(unit, player) -> Vector2i:
	if player.cities.size() < 2 or GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	# Find capital
	var capital_pos = Vector2i(-1, -1)
	for city in player.cities:
		if "palace" in city.buildings:
			capital_pos = city.grid_position
			break
	if capital_pos == Vector2i(-1, -1) and not player.cities.is_empty():
		capital_pos = player.cities[0].grid_position

	# Find a city not road-connected to capital
	var target_city_pos = Vector2i(-1, -1)
	var best_dist = INF
	for city in player.cities:
		if city.grid_position == capital_pos:
			continue
		# Check if there's a continuous road path to capital
		if not _has_road_connection(city.grid_position, capital_pos):
			var dist = GridUtils.chebyshev_distance(unit.grid_position, city.grid_position)
			if dist < best_dist:
				best_dist = dist
				target_city_pos = city.grid_position

	if target_city_pos == Vector2i(-1, -1):
		return Vector2i(-1, -1)

	# Find the first tile without a road on the path from unit to the unconnected city
	var pathfinder = PathfindingClass.new(GameManager.hex_grid, unit)
	var path = pathfinder.find_path(unit.grid_position, target_city_pos)
	for pos in path:
		var tile = GameManager.hex_grid.get_tile(pos)
		if tile and tile.road_level == 0 and not tile.is_water() and tile.is_passable():
			return pos

	return Vector2i(-1, -1)

## Check if two positions are connected by a continuous road (BFS along roads)
func _has_road_connection(from_pos: Vector2i, to_pos: Vector2i) -> bool:
	if from_pos == to_pos:
		return true
	if GameManager.hex_grid == null:
		return false

	var visited = {}
	var queue = [from_pos]
	visited[from_pos] = true

	while not queue.is_empty():
		var current = queue.pop_front()
		for neighbor in GridUtils.get_neighbors(current):
			if neighbor in visited:
				continue
			var tile = GameManager.hex_grid.get_tile(neighbor)
			if tile == null or tile.road_level == 0:
				continue
			if neighbor == to_pos:
				return true
			visited[neighbor] = true
			# Limit search to reasonable distance
			if visited.size() > 200:
				return false
			queue.append(neighbor)

	return false

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
		# Fog of war: only detect enemies on visible tiles
		if tile.get_visibility_for_player(player.player_id) < 2:  # Not currently visible
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

## Find nearest visible goody hut (tribal village)
func _find_nearest_goody_hut(unit, player) -> Vector2i:
	if GameManager.hex_grid == null:
		return Vector2i(-1, -1)

	var best_pos = Vector2i(-1, -1)
	var best_dist = 999

	# Search in expanding rings (up to 15 tiles)
	for radius in range(1, 16):
		var tiles = GridUtils.get_tiles_at_range(unit.grid_position, radius)
		for tile_pos in tiles:
			var tile = GameManager.hex_grid.get_tile(tile_pos)
			if tile == null or not tile.has_goody_hut:
				continue
			# Must be visible (explored) to the player
			var visibility = tile.get_visibility_for_player(player.player_id)
			if visibility == 0:  # UNEXPLORED
				continue
			var dist = GridUtils.chebyshev_distance(unit.grid_position, tile_pos)
			if dist < best_dist:
				best_dist = dist
				best_pos = tile_pos
		if best_pos != Vector2i(-1, -1):
			break

	return best_pos

## Attack adjacent enemy if odds are good (helper for explore moves)
func _attack_adjacent_if_good_odds(unit, player) -> void:
	if not is_instance_valid(unit) or unit.movement_remaining <= 0:
		return
	var adj = _find_nearby_enemies(unit, player, 1)
	for e in adj:
		if is_instance_valid(e) and GridUtils.are_adjacent(unit.grid_position, e.grid_position):
			var odds = CombatSystem.calculate_odds(unit, e)
			if odds.win_chance >= 0.5:
				CombatSystem.resolve_combat(unit, e)
				return

## Random exploration move (fallback when no unexplored tiles in search range)
func _random_explore(unit) -> void:
	if GameManager.hex_grid == null or unit.movement_remaining <= 0:
		return
	var neighbors = GridUtils.get_neighbors(unit.grid_position)
	neighbors.shuffle()
	for n_pos in neighbors:
		if unit.can_move_to(n_pos):
			unit.move_to(n_pos)
			return

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
			# Fog of war: only target cities on explored tiles
			var tile = GameManager.hex_grid.get_tile(city.grid_position) if GameManager.hex_grid else null
			if tile and tile.get_visibility_for_player(player.player_id) == 0:
				continue  # Never seen this tile
			var dist = GridUtils.chebyshev_distance(unit.grid_position, city.grid_position)
			if dist <= search_range and dist < best_dist:
				best_dist = dist
				best_city = city

	return best_city

## Find the nearest known enemy city position
func _find_nearest_enemy_city(unit, player) -> Vector2i:
	var best_pos = Vector2i(-1, -1)
	var best_dist = INF
	for enemy_id in player.at_war_with:
		var enemy = GameManager.get_player(enemy_id)
		if enemy == null:
			continue
		for city in enemy.cities:
			# Fog of war: only target cities we've discovered
			var tile = GameManager.hex_grid.get_tile(city.grid_position) if GameManager.hex_grid else null
			if tile and tile.get_visibility_for_player(player.player_id) == 0:
				continue  # Never explored
			var dist = GridUtils.chebyshev_distance(unit.grid_position, city.grid_position)
			if dist < best_dist:
				best_dist = dist
				best_pos = city.grid_position
	return best_pos

## Check if player has siege units near a position
func _has_siege_units_near(pos: Vector2i, player, search_range: int) -> bool:
	for unit in player.units:
		var udata = DataManager.get_unit(unit.unit_id)
		if udata.get("unit_class", "") == "siege":
			if GridUtils.chebyshev_distance(pos, unit.grid_position) <= search_range:
				return true
	return false

func _get_best_military_unit(city, player, military_flavor: int, needs_siege: bool = false, prefer_cheap: bool = false) -> String:
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

		# Prefer higher-strength units (strength^2 makes axeman >> warrior decisively)
		var cost = unit_data.get("cost", 30)
		var score
		if prefer_cheap:
			# Bankruptcy mode: build the cheapest viable defender. Strength still
			# matters slightly so we'd take an archer over a warrior, but the
			# cubic cost penalty makes catapults a non-starter.
			score = strength * 10.0 / pow(max(cost, 10), 1.5)
		else:
			score = pow(strength, 2.0) * 5.0 / max(cost, 10)

		# Penalty for building weak units when better are available in same class
		var dominated = false
		for other_id in DataManager.units:
			if other_id == unit_id or not city.can_build_unit(other_id):
				continue
			var other_data = DataManager.get_unit(other_id)
			if other_data.get("unit_class", "") == unit_class:
				var other_str = DataManager.get_unit_strength(other_id)
				if other_str > strength:
					dominated = true
					break
		if dominated:
			score *= 0.1  # Heavily penalize obsolete units

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

	var best_project = ""
	var best_score = 0

	for project_id in ProjectsSystem.projects:
		var check = ProjectsSystem.can_build_project(project_id, player, city)
		if not check.can_build:
			continue

		var project = ProjectsSystem.projects[project_id]
		var score = 0

		# Spaceship parts get a flat bonus on top of any data-driven score.
		if project.get("spaceship_part", false):
			score = 100 + science_flavor * 10
		else:
			# Data-driven scoring: each project may carry an `ai_score` block in projects.json:
			#   {"base": 80, "flavor": "science", "flavor_weight": 8, "requires_global_project": "..."}
			# This replaces the per-project hardcoded if-elif chain that used to live here.
			var ai_score = project.get("ai_score", null)
			if ai_score is Dictionary:
				var required_global = ai_score.get("requires_global_project", "")
				if required_global == "" or ProjectsSystem.global_projects.has(required_global):
					score = int(ai_score.get("base", 0))
					var flavor_name = ai_score.get("flavor", "")
					var flavor_weight = int(ai_score.get("flavor_weight", 0))
					if flavor_weight > 0 and flavor_name != "":
						score += int(flavor.get(flavor_name, 0)) * flavor_weight

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
				if GridUtils.chebyshev_distance(city.grid_position, other_city.grid_position) < GameManager.scaled_distance(8):
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

			# Leaders with low wonder_construct_rand skip wonders sometimes
			var personality = _get_leader_personality(player)
			var wonder_rand = max(personality.get("wonder_construct_rand", 30), 50)
			if randi() % 100 >= wonder_rand:
				continue

		var effects = building.get("effects", {})
		var score = 0.0

		# Science
		if effects.has("science_percent"):
			var mod = spec_mods.get("science_percent", 1.0)
			score += effects.science_percent * science_flavor / 5 * mod
		if effects.has("science"):
			var mod = spec_mods.get("science", 1.0)
			score += effects.science * science_flavor * mod

		# Gold — boosted when running deficit (markets, banks, grocers)
		var deficit_gold_mult = 3.0 if player.gold_per_turn < 0 else 1.0
		if effects.has("gold_percent"):
			var mod = spec_mods.get("gold_percent", 1.0)
			score += effects.gold_percent * gold_flavor / 5 * mod * deficit_gold_mult
		if effects.has("gold"):
			var mod = spec_mods.get("gold", 1.0)
			score += effects.gold * gold_flavor * mod * deficit_gold_mult
		if effects.has("trade_routes") and player.gold_per_turn < 0:
			score += effects.trade_routes * 10  # Trade routes = gold when in deficit

		# Culture
		if effects.has("culture"):
			var mod = spec_mods.get("culture", 1.0)
			score += effects.culture * culture_flavor * mod

		# Military (barracks use "free_experience", also check "experience")
		if effects.has("free_experience"):
			var mod = spec_mods.get("experience", 1.0)
			score += effects.free_experience * military_flavor * mod
		if effects.has("experience"):
			var mod = spec_mods.get("experience", 1.0)
			score += effects.experience * military_flavor * 2 * mod
		if effects.has("happiness"):
			var mod = spec_mods.get("happiness", 1.0)
			score += effects.happiness * 5 * mod
		# Happiness from religion (temples) — valuable if city has state religion
		if effects.has("happiness_from_religion"):
			if city.player_owner and city.player_owner.state_religion in city.religions:
				score += effects.happiness_from_religion * 4
		# Happiness from resources (market)
		if effects.has("happiness_from_resource"):
			score += effects.happiness_from_resource * 3

		# Maintenance reduction (courthouse) — scales with city count
		# When running a deficit, courthouses become CRITICAL
		if effects.has("maintenance_reduction"):
			var num_cities_local = player.cities.size()
			var base_maint_score = effects.maintenance_reduction * num_cities_local * 3
			if player.gold_per_turn < 0:
				base_maint_score *= 3  # Triple priority when in deficit
			score += base_maint_score

		# Domain experience (barracks: land_experience, stable: mounted_experience)
		if effects.has("land_experience"):
			score += effects.land_experience * military_flavor
		if effects.has("mounted_experience"):
			score += effects.mounted_experience * military_flavor * 0.5

		# Sea food bonus (lighthouse)
		if effects.has("sea_food"):
			# Only valuable for coastal cities
			var has_water = false
			for tile_pos in city.worked_tiles:
				var tile = GameManager.hex_grid.get_tile(tile_pos) if GameManager.hex_grid else null
				if tile and tile.is_water():
					has_water = true
					break
			if has_water:
				score += effects.sea_food * growth_flavor * 3

		# Trade routes
		if effects.has("trade_routes"):
			score += effects.trade_routes * gold_flavor * 2

		# Defense bonus (for military cities)
		if effects.has("defense"):
			var mod = spec_mods.get("defense", 1.0)
			score += effects.defense * military_flavor * mod
		if effects.has("bombard_defense"):
			score += effects.bombard_defense * military_flavor * 0.5

		# Growth — granary's food_stored_on_growth is critical
		if effects.has("food"):
			var mod = spec_mods.get("food", 1.0)
			score += effects.food * growth_flavor * 2 * mod
		if effects.has("food_stored_on_growth"):
			# Granary is one of the best early buildings — high base score
			var mod = spec_mods.get("food", 1.0)
			score += effects.food_stored_on_growth * 20 * growth_flavor / 5 * mod
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

		# Culture percent (broadcast tower etc.)
		if effects.has("culture_percent"):
			var mod = spec_mods.get("culture", 1.0)
			score += effects.culture_percent * culture_flavor / 5 * mod

		# Great person points (valuable for culture/science cities)
		if effects.has("great_person_points"):
			var mod = spec_mods.get("great_person", 1.0)
			score += effects.great_person_points * mod * 3

		# Wonders get a strategic bonus based on AI's long-term goals
		if wonder_type == "world":
			score += 10  # Base bonus for world wonders

			# Strategy-aligned wonder bonuses (flavor as proxy for victory path)
			# Cultural victory: culture buildings/wonders
			if culture_flavor >= HIGH_FLAVOR:
				if effects.has("culture") or effects.has("culture_percent") or effects.has("culture_state_religion"):
					score += 15
				if effects.has("great_artist_points"):
					score += 8
				if effects.has("golden_age_length_modifier"):
					score += 10

			# Science/Space victory: science and production wonders
			if science_flavor >= HIGH_FLAVOR:
				if effects.has("science_percent") or effects.has("free_tech") or effects.has("free_scientists"):
					score += 15
				if effects.has("great_scientist_points"):
					score += 8
				if effects.has("spaceship_production_all_cities"):
					score += 20

			# Domination: military and expansion wonders
			if military_flavor >= HIGH_FLAVOR:
				if effects.has("free_experience_all_units") or effects.has("great_general_rate_modifier"):
					score += 15
				if effects.has("defense_all_cities") or effects.has("border_obstacle"):
					score += 10
				if effects.has("enemy_war_weariness"):
					score += 10

			# Economy: gold and trade wonders
			if gold_flavor >= HIGH_FLAVOR:
				if effects.has("gold_percent") or effects.has("trade_route_yield"):
					score += 12
				if effects.has("gold_state_religion_cities"):
					score += 10

			# Religious leaders: religion-related wonders
			if flavor.get("religion", 5) >= HIGH_FLAVOR:
				if effects.has("enables_apostolic_votes") or effects.has("any_religion_civic"):
					score += 15
				if effects.has("no_anarchy"):
					score += 10

		elif wonder_type == "national":
			score += 8

		# Reduce score by cost (prefer cheaper when scores are similar)
		# Wonders should be penalized less by cost since they're unique
		var cost = building.get("cost", 100)
		if wonder_type != "":
			score -= cost / 100  # Lighter penalty for wonders
		else:
			score -= cost / 50

		if score > best_score:
			best_score = score
			best_building = building_id

	return best_building

func _get_best_building(city, player, flavor: Dictionary) -> String:
	# Fallback version without specialization
	return _get_best_building_for_specialization(city, player, flavor, CitySpecialization.HYBRID)

## Pick a building that will fix a failing economy. Strongly prefers
## maintenance_reduction (courthouse), then gold (market/grocer/bank), then
## science (library — frees commerce by reducing the slider drop the AI
## otherwise has to apply). Returns "" if nothing buildable.
func _get_economic_rescue_building(city, player) -> String:
	var best_id = ""
	var best_score = -1.0
	for building_id in DataManager.buildings:
		if not city.can_build_building(building_id):
			continue
		var building = DataManager.get_building(building_id)
		# Skip wonders — too expensive to be a rescue
		if building.get("wonder_type", "") != "":
			continue
		# Skip special / great-person-only buildings (cost -1, e.g. academy, scotland yard)
		var bcost = building.get("cost", 0)
		if bcost <= 0:
			continue
		var effects = building.get("effects", {})
		var score = 0.0
		# Maintenance reduction is the single biggest lever — courthouse halves
		# distance maintenance which is the dominant cost on small maps.
		var maint_red = effects.get("maintenance_reduction", 0.0)
		if maint_red > 0:
			score += 200.0 * maint_red * max(player.cities.size(), 1)
		# Direct gold and gold_percent (percent values are 0..1, scale up heavily)
		score += effects.get("gold", 0) * 30
		score += effects.get("gold_percent", 0) * 100
		# Trade routes (markets/grocer adjacent)
		score += effects.get("trade_routes", 0) * 30
		# Science_percent — library frees commerce later
		score += effects.get("science_percent", 0) * 50
		# Granary helps growth → more workable tiles → more commerce
		if effects.has("food_stored_on_growth"):
			score += 20
		# Very light cost preference (not a hard penalty — courthouses cost a lot
		# but still pay back, so don't drown them out)
		score -= bcost * 0.05
		if score > best_score:
			best_score = score
			best_id = building_id
	return best_id if best_score > 0 else ""

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
	var border_range = GameManager.scaled_distance(6)
	for city in player.cities:
		for other in GameManager.players:
			if other == player:
				continue
			for other_city in other.cities:
				if GridUtils.chebyshev_distance(city.grid_position, other_city.grid_position) <= border_range:
					return city
	return null

func _get_holy_city(player):
	# Find a city that is a holy city for a religion
	for city in player.cities:
		if city.holy_city_of != "":
			return city
	return null
