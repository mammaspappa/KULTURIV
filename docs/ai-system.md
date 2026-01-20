# AI System

The AI system controls computer-controlled civilizations, making decisions about research, production, diplomacy, and warfare.

**File**: `scripts/ai/ai_controller.gd`
**Data File**: `data/handicaps.json` (difficulty settings)

## Overview

The AI in KulturIV is personality-driven, using leader flavor values to weight decisions. Each AI player has distinct preferences based on their leader's traits.

### Leader Flavors

Every leader has flavor values (0-10) that influence AI behavior:

| Flavor | Description |
|--------|-------------|
| `military` | Preference for military units and warfare |
| `gold` | Focus on economy and treasury |
| `science` | Prioritization of research |
| `culture` | Interest in cultural development |
| `religion` | Emphasis on religious spread |
| `expansion` | Desire to found new cities |
| `growth` | Focus on population growth |
| `production` | Preference for production buildings |

Example leader:
```json
{
  "julius_caesar": {
    "flavors": {
      "military": 8,
      "gold": 5,
      "science": 4,
      "expansion": 7,
      "production": 6
    }
  }
}
```

## AI Decision Making

### Research Selection

The AI chooses research based on:
1. Available technologies (prerequisites met)
2. Leader flavor weights
3. Current game state needs

```gdscript
func _select_research(player) -> String:
    var available = _get_available_techs(player)
    var scores = {}

    for tech_id in available:
        var tech = DataManager.get_tech(tech_id)
        var score = _evaluate_tech(player, tech)
        scores[tech_id] = score

    # Pick highest scored tech
    return _get_highest_scored(scores)

func _evaluate_tech(player, tech: Dictionary) -> float:
    var score = 0.0
    var flavors = player.leader_flavors

    # Military tech bonus
    if tech.enables_units.size() > 0:
        score += flavors.military * 10

    # Science building bonus
    if _has_science_building(tech):
        score += flavors.science * 8

    # Economic tech bonus
    if tech.get("commerce_bonus", 0) > 0:
        score += flavors.gold * 5

    # Urgency: at war, prioritize military
    if player.is_at_war():
        score += flavors.military * 5

    return score
```

### Production Selection

Cities choose what to build based on:
1. Current needs (defense, growth, production)
2. Leader preferences
3. Available options

```gdscript
func _select_production(city) -> String:
    var options = city.get_available_production()
    var scores = {}

    for item in options:
        scores[item] = _evaluate_production(city, item)

    return _get_highest_scored(scores)

func _evaluate_production(city, item: String) -> float:
    var score = 0.0
    var player = city.player_owner
    var flavors = player.leader_flavors

    # Unit evaluation
    if DataManager.is_unit(item):
        var unit_data = DataManager.get_unit(item)
        if unit_data.combat > 0:
            score += flavors.military * 5

            # Bonus if at war
            if player.is_at_war():
                score += 20

        # Settlers for expansion
        if item == "settler":
            score += flavors.expansion * 10

    # Building evaluation
    if DataManager.is_building(item):
        var building = DataManager.get_building(item)
        var effects = building.get("effects", {})

        if effects.has("production"):
            score += flavors.production * 3
        if effects.has("commerce"):
            score += flavors.gold * 3
        if effects.has("culture"):
            score += flavors.culture * 3

    return score
```

### Unit Movement

AI units follow these priorities:
1. Defend threatened cities
2. Attack weak enemy targets
3. Explore unknown territory
4. Garrison cities
5. Fortify in strategic positions

```gdscript
func _process_unit(unit: Unit) -> void:
    if unit.has_acted:
        return

    # Priority 1: City defense
    if _should_defend_city(unit):
        _move_to_threatened_city(unit)
        return

    # Priority 2: Attack opportunity
    var target = _find_attack_target(unit)
    if target and _should_attack(unit, target):
        _attack_target(unit, target)
        return

    # Priority 3: Explore
    if unit.has_ability("explore") or _should_explore(unit):
        _explore(unit)
        return

    # Priority 4: Garrison
    _move_to_garrison(unit)
```

### War Decisions

The AI decides to declare war based on:
1. Relative military power
2. Diplomatic relationships
3. Leader aggressiveness
4. Strategic opportunity

```gdscript
func _evaluate_war(player, target) -> bool:
    var our_power = _calculate_military_power(player)
    var their_power = _calculate_military_power(target)
    var power_ratio = our_power / max(1, their_power)

    # Base war score
    var war_score = 0.0

    # Power advantage
    if power_ratio > 1.5:
        war_score += 30
    elif power_ratio > 1.2:
        war_score += 15

    # Bad relationship
    var attitude = player.get_attitude(target.player_id)
    if attitude <= -8:  # Furious
        war_score += 25
    elif attitude <= -4:  # Annoyed
        war_score += 10

    # Leader aggressiveness
    war_score += player.leader_flavors.military * 3

    # Random factor
    war_score += randf_range(-10, 10)

    return war_score > 50
```

### Peace Decisions

The AI considers peace when:
1. Losing the war badly
2. Achieved war goals
3. Better opportunities elsewhere

```gdscript
func _should_make_peace(player, enemy) -> bool:
    var our_power = _calculate_military_power(player)
    var their_power = _calculate_military_power(enemy)

    # Losing badly
    if our_power < their_power * 0.5:
        return true

    # War exhaustion
    var war_length = _get_war_length(player, enemy)
    if war_length > 30:  # 30 turns of war
        return randf() < 0.3

    return false
```

## Difficulty Settings

AI advantages are controlled by handicaps.json:

```json
{
  "settler": {
    "name": "Settler",
    "ai_bonuses": {
      "starting_units": 0,
      "free_techs": 0,
      "production_bonus": 0,
      "research_bonus": 0,
      "gold_bonus": 0
    }
  },
  "prince": {
    "name": "Prince",
    "ai_bonuses": {
      "starting_units": 1,
      "free_techs": 0,
      "production_bonus": 0,
      "research_bonus": 0,
      "gold_bonus": 0
    }
  },
  "deity": {
    "name": "Deity",
    "ai_bonuses": {
      "starting_units": 4,
      "free_techs": 3,
      "production_bonus": 100,
      "research_bonus": 80,
      "gold_bonus": 100
    }
  }
}
```

### Difficulty Levels

| Level | AI Production | AI Research | Starting Units |
|-------|---------------|-------------|----------------|
| Settler | -50% | -50% | 0 |
| Chieftain | -25% | -25% | 0 |
| Warlord | 0% | 0% | 0 |
| Noble | 0% | 0% | 1 |
| Prince | 0% | 0% | 1 |
| Monarch | +25% | +25% | 2 |
| Emperor | +50% | +50% | 2 |
| Immortal | +75% | +75% | 3 |
| Deity | +100% | +80% | 4 |

## AI Diplomacy

### Trade Evaluation

The AI evaluates trades based on:
1. Relative value of items
2. Relationship with partner
3. Strategic needs

```gdscript
func _evaluate_trade(player, partner, offer, demand) -> bool:
    var offer_value = _calculate_trade_value(offer, player)
    var demand_value = _calculate_trade_value(demand, partner)

    # Relationship modifier
    var attitude = player.get_attitude(partner.player_id)
    var attitude_modifier = 1.0 + (attitude * 0.05)  # ±50% at extremes

    var adjusted_offer = offer_value * attitude_modifier

    return adjusted_offer >= demand_value * 0.9  # Accept if roughly fair
```

### Treaty Decisions

```gdscript
func _should_sign_treaty(player, partner, treaty_type: String) -> bool:
    var attitude = player.get_attitude(partner.player_id)

    match treaty_type:
        "open_borders":
            return attitude >= 0  # Cautious or better
        "defensive_pact":
            return attitude >= 4  # Pleased or better
        "peace":
            return _should_make_peace(player, partner)

    return false
```

## Worker Management

AI workers prioritize improvements based on:
1. Tile yield potential
2. City needs
3. Available resources

```gdscript
func _get_worker_priority(tile: GameTile, city: City) -> float:
    var score = 0.0

    # Unimproved resources are high priority
    if tile.resource != "" and tile.improvement == "":
        score += 100

    # Tiles near city center
    var distance = tile.grid_position.distance_to(city.grid_position)
    score += (5 - distance) * 10

    # Food tiles when growing
    if city.is_growing() and tile.get_food_yield() > 0:
        score += 20

    return score
```

## Known Limitations

The current AI doesn't handle:
- Naval warfare (planned)
- Air units (planned)
- Espionage operations (planned)
- City specialization (planned)
- Advanced diplomacy (vassals, etc.)

## Debugging AI

Enable AI debugging output:

```gdscript
# In ai_controller.gd
var debug_mode = true

func _log(message: String) -> void:
    if debug_mode:
        print("[AI] " + message)

func _select_research(player) -> String:
    _log("Selecting research for " + player.civ_name)
    # ...
    _log("Chose: " + selected_tech)
```

## Extending AI

### Add New Decision Type

```gdscript
func _process_turn(player) -> void:
    _process_research(player)
    _process_production(player)
    _process_diplomacy(player)
    _process_my_new_feature(player)  # Add new processing

func _process_my_new_feature(player) -> void:
    var flavors = player.leader_flavors
    # Use flavors to make personality-driven decisions
```

### Custom AI Personality

Create extreme personality by modifying flavors:

```json
{
  "warmonger_leader": {
    "flavors": {
      "military": 10,
      "gold": 2,
      "science": 2,
      "culture": 1,
      "expansion": 8,
      "growth": 3,
      "production": 7
    }
  }
}
```
