# Espionage System

The Espionage System handles spy missions, espionage points, and counter-espionage operations. This is a signature Beyond the Sword feature.

**File**: `scripts/systems/espionage_system.gd`
**Data File**: `data/espionage_missions.json`

## Overview

Espionage allows players to:
- Gather intelligence on rival civilizations
- Steal technologies and gold
- Sabotage production and buildings
- Incite revolts and spread unrest
- Counter enemy espionage efforts

## Espionage Points

Espionage points (EP) are accumulated per rival civilization and used to fund missions.

### Accumulation

```gdscript
func _on_turn_started(turn: int, player) -> void:
    # Generate EP based on commerce allocation
    var ep_generated = player.get_espionage_output()

    # Distribute to rivals based on slider settings
    for rival_id in player.met_players:
        var weight = player.get_espionage_weight(rival_id)
        var points = ep_generated * weight
        add_espionage_points(player.player_id, rival_id, points)
```

### Spending

EP is spent when executing missions:

```gdscript
func execute_mission(mission_id: String, player, target, city = null) -> Dictionary:
    var cost = calculate_mission_cost(mission_id, player, target, city)

    if get_espionage_points(player.player_id, target.player_id) < cost:
        return {"success": false, "reason": "insufficient_ep"}

    # Deduct points
    spend_espionage_points(player.player_id, target.player_id, cost)

    # Execute mission...
```

## Key Functions

### `get_espionage_points(player_id: int, target_id: int) -> int`

Returns accumulated EP against a specific rival.

```gdscript
var ep = EspionageSystem.get_espionage_points(my_id, enemy_id)
print("We have %d EP against them" % ep)
```

### `calculate_mission_cost(mission_id, player, target, city) -> int`

Calculates the EP cost for a mission with all modifiers.

```gdscript
var cost = EspionageSystem.calculate_mission_cost(
    "steal_technology",
    my_player,
    enemy_player,
    enemy_city
)
```

**Cost Modifiers:**
- Distance from capital (+cost)
- Counter-espionage active (+50% cost)
- Having a spy in the city (-cost)
- Diplomatic relationship

### `execute_mission(mission_id, player, target, city, building) -> Dictionary`

Executes an espionage mission.

```gdscript
var result = EspionageSystem.execute_mission(
    "sabotage_production",
    my_player,
    enemy_player,
    enemy_city
)

if result.success:
    print("Mission successful!")
    print(result.message)
else:
    print("Mission failed: " + result.reason)
    if result.discovered:
        print("We were discovered!")
```

**Return Dictionary:**
```gdscript
{
    "success": bool,          # Did the mission succeed?
    "discovered": bool,       # Were we caught?
    "spy_captured": bool,     # Was our spy captured?
    "message": String,        # Result description
    "effects": Dictionary     # What happened
}
```

### `get_all_missions() -> Dictionary`

Returns all available mission types.

```gdscript
var missions = EspionageSystem.get_all_missions()
for mission_id in missions:
    var mission = missions[mission_id]
    print("%s - Cost: %d, Success: %d%%" % [
        mission.name,
        mission.base_cost,
        mission.success_chance_base
    ])
```

## Mission Types

### Intelligence Gathering

| Mission | Cost | Success | Discovery | Effect |
|---------|------|---------|-----------|--------|
| See Demographics | 50 | 100% | 0% | View rival's stats |
| Investigate City | 100 | 100% | 10% | See buildings, production |
| See Research | 75 | 100% | 5% | See current research |

### Theft

| Mission | Cost | Success | Discovery | Effect |
|---------|------|---------|-----------|--------|
| Steal Treasury | 200 | 70% | 30% | Take up to 25% gold (max 500) |
| Steal Technology | 600 | 35% | 70% | Acquire a tech |

### Sabotage

| Mission | Cost | Success | Discovery | Effect |
|---------|------|---------|-----------|--------|
| Sabotage Production | 300 | 60% | 40% | Destroy production progress |
| Destroy Building | 400 | 50% | 50% | Destroy a building |
| Destroy Improvement | 150 | 80% | 20% | Pillage a tile |
| Poison Water | 350 | 55% | 45% | -2 health for 5 turns |
| Spread Unhappiness | 300 | 60% | 35% | -2 happiness for 5 turns |

### Subversion

| Mission | Cost | Success | Discovery | Effect |
|---------|------|---------|-----------|--------|
| Incite Revolt | 500 | 40% | 60% | City revolts for 3 turns |
| Force Civic Change | 800 | 25% | 80% | Target adopts civic |
| Force Religion Change | 700 | 30% | 75% | Target changes religion |

### Counter-Espionage

| Mission | Cost | Success | Discovery | Effect |
|---------|------|---------|-----------|--------|
| Counter-Espionage | 100 | 100% | 0% | +50% defense for 10 turns |
| Expose Enemy Spy | 150 | 50% | 0% | Capture enemy spy |

## Spy Units

Some missions require a spy unit in the target city.

### Placing Spies

```gdscript
func place_spy(spy_unit: Unit, city: City) -> bool:
    if not can_place_spy(spy_unit, city):
        return false

    spy_unit.set_hidden(true)
    spy_placements[city.get_id()] = spy_unit

    EventBus.spy_placed.emit(spy_unit, city)
    return true
```

### Spy Capture

When discovered, spies may be captured:

```gdscript
func _check_spy_capture(mission_result: Dictionary, city: City) -> void:
    if not mission_result.discovered:
        return

    var capture_chance = 0.5  # Base 50%
    if randf() < capture_chance:
        var spy = spy_placements.get(city.get_id())
        if spy:
            spy.queue_free()
            spy_placements.erase(city.get_id())
            mission_result.spy_captured = true
            EventBus.spy_captured.emit(spy, city)
```

## Counter-Espionage

Players can defend against espionage:

### Active Counter-Espionage

The Counter-Espionage mission increases defense:

```gdscript
var counter_esp: Dictionary = {}  # player_id -> { end_turn, bonus }

func is_counter_espionage_active(player_id: int) -> bool:
    if not counter_esp.has(player_id):
        return false
    return counter_esp[player_id].end_turn > TurnManager.current_turn

func get_counter_espionage_bonus(player_id: int) -> float:
    if is_counter_espionage_active(player_id):
        return counter_esp[player_id].bonus
    return 0.0
```

### Buildings

Certain buildings boost espionage defense:
- **Intelligence Agency**: +50% espionage defense
- **Security Bureau**: +25% espionage defense

## Success Calculation

Mission success depends on multiple factors:

```gdscript
func calculate_success_chance(mission_id: String, player, target, city) -> float:
    var mission = missions.get(mission_id, {})
    var base_chance = mission.get("success_chance_base", 50) / 100.0

    # Spy in city bonus
    if city and has_spy_in_city(player.player_id, city):
        base_chance += 0.15

    # Counter-espionage penalty
    if is_counter_espionage_active(target.player_id):
        base_chance *= 0.5

    # Relationship modifier
    var relations = target.get_relationship(player.player_id)
    if relations == "friendly":
        base_chance -= 0.1  # Harder against friends
    elif relations == "furious":
        base_chance += 0.1  # Easier against enemies

    return clamp(base_chance, 0.05, 0.95)
```

## Discovery Consequences

When discovered:

1. **Diplomatic Penalty**: Relationship worsens
2. **Spy Risk**: Spy may be captured
3. **War Risk**: Target may declare war

```gdscript
func _apply_discovery_consequences(player, target, mission_id: String) -> void:
    # Diplomatic hit
    DiplomacySystem.add_memory(target.player_id, player.player_id,
        "espionage", -15, 20)  # -15 attitude for 20 turns

    # Chance of war declaration (AI only)
    if not target.is_human:
        var war_chance = 0.1 * (1 + target.get_personality("aggressiveness"))
        if randf() < war_chance:
            target.declare_war_on(player.player_id)
```

## Events Emitted

| Signal | When |
|--------|------|
| `espionage_points_changed` | EP accumulated or spent |
| `espionage_mission_executed` | Mission completed |
| `espionage_discovered` | Mission was detected |
| `spy_placed` | Spy entered a city |
| `spy_captured` | Spy was caught |
| `spy_escaped` | Spy evaded capture |

## Example Usage

```gdscript
# Check if we can afford a mission
var cost = EspionageSystem.calculate_mission_cost(
    "steal_technology", my_player, rival, rival_capital
)
var available = EspionageSystem.get_espionage_points(my_id, rival_id)

if available >= cost:
    # Execute the mission
    var result = EspionageSystem.execute_mission(
        "steal_technology", my_player, rival, rival_capital
    )

    if result.success:
        EventBus.notification_added.emit(
            "Stole %s from %s!" % [result.tech_stolen, rival.civ_name],
            "espionage"
        )
    else:
        if result.discovered:
            EventBus.notification_added.emit(
                "Our spy was discovered!",
                "warning"
            )
```

## Serialization

The espionage system saves:
- Espionage points per player pair
- Active spies and their locations
- Counter-espionage timers
- Mission cooldowns

```gdscript
func to_dict() -> Dictionary:
    return {
        "espionage_points": espionage_points.duplicate(true),
        "spy_placements": _serialize_spies(),
        "counter_esp": counter_esp.duplicate(true),
        "cooldowns": cooldowns.duplicate(true)
    }
```
