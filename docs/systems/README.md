# Game Systems

This section documents all the game systems that handle specific mechanics in KulturIV.

## System Overview

| System | File | Purpose |
|--------|------|---------|
| [Combat](combat-system.md) | `combat_system.gd` | Attack resolution, damage calculation |
| [Improvement](improvement-system.md) | `improvement_system.gd` | Tile improvements (farms, mines, etc.) |
| [Religion](religion-system.md) | `religion_system.gd` | Religion founding and spreading |
| [Victory](victory-system.md) | `victory_system.gd` | Win condition checking |
| [Civics](civics-system.md) | `civics_system.gd` | Government and social policies |
| [Diplomacy](diplomacy-system.md) | `diplomacy_system.gd` | Relations, attitudes, memory |
| [Trade](trade-system.md) | `trade_system.gd` | Resource and tech trading |
| [Great People](great-people-system.md) | `great_people_system.gd` | Great Person generation and abilities |
| [Corporation](corporation-system.md) | `corporation_system.gd` | Corporate founding and spread |
| [Espionage](espionage-system.md) | `espionage_system.gd` | Spy missions and counter-espionage |
| [Projects](projects-system.md) | `projects_system.gd` | World wonders and space race |
| [Events](events-system.md) | `events_system.gd` | Random event triggering |
| [Voting](voting-system.md) | `voting_system.gd` | UN and Apostolic Palace votes |
| [Save](save-system.md) | `save_system.gd` | Game serialization |

## How Systems Work

All systems follow a consistent pattern:

```gdscript
extends Node
## Brief description of the system

# Data loaded from JSON
var data: Dictionary = {}

# Internal state
var state: Dictionary = {}

func _ready() -> void:
    _load_data()        # Load JSON configuration
    _connect_signals()  # Subscribe to EventBus

func _load_data() -> void:
    var path = "res://data/mydata.json"
    var file = FileAccess.open(path, FileAccess.READ)
    var json = JSON.new()
    json.parse(file.get_as_text())
    data = json.data

func _connect_signals() -> void:
    EventBus.turn_started.connect(_on_turn_started)

# Event handlers
func _on_turn_started(turn: int, player) -> void:
    pass

# Public API
func do_action(args) -> Result:
    # Perform action
    EventBus.action_completed.emit(result)
    return result

# Serialization
func to_dict() -> Dictionary:
    return state.duplicate(true)

func from_dict(d: Dictionary) -> void:
    state = d.duplicate(true)
```

## System Interactions

Systems interact through two mechanisms:

### 1. EventBus Signals

Used for notifications that multiple systems might care about:

```gdscript
# System A emits
EventBus.city_founded.emit(city, player)

# Systems B and C listen
EventBus.city_founded.connect(_on_city_founded)
```

### 2. Direct Calls

Used for specific queries or synchronous operations:

```gdscript
# Query another system
var damage = CombatSystem.calculate_damage(attacker, defender)

# Check game state
if VotingSystem.are_nukes_banned():
    return false
```

## Adding a New System

1. **Create the script** in `scripts/systems/`:
```gdscript
extends Node
## My new system description

func _ready() -> void:
    print("MySystem initialized")
```

2. **Register as autoload** in `project.godot`:
```ini
[autoload]
...
MySystem="*res://scripts/systems/my_system.gd"
```

3. **Add data file** (if needed) in `data/`:
```json
{
  "_metadata": {
    "description": "My system data"
  },
  "items": {
    "item_1": { ... }
  }
}
```

4. **Update DataManager** to load the data:
```gdscript
var my_data: Dictionary = {}

func _ready():
    # ... existing loads ...
    my_data = _load_json("res://data/my_data.json")

func get_my_item(id: String) -> Dictionary:
    return my_data.get(id, {})
```

5. **Add EventBus signals** (if needed):
```gdscript
signal my_event_happened(param1, param2)
```

6. **Document the system** in this folder

## Common Patterns

### Processing on Turn Start

Many systems do work at the start of each turn:

```gdscript
func _connect_signals() -> void:
    EventBus.turn_started.connect(_on_turn_started)

func _on_turn_started(turn: int, player) -> void:
    if player.is_human:
        _check_for_events(player)
        _process_timers()
```

### Checking Prerequisites

Many actions require tech or building prerequisites:

```gdscript
func can_do_action(player, action_id: String) -> bool:
    var action = data.get(action_id, {})

    # Check tech requirement
    var tech_req = action.get("tech_required", "")
    if tech_req != "" and not player.has_tech(tech_req):
        return false

    # Check building requirement
    var building_req = action.get("building_required", "")
    if building_req != "" and not player.has_building(building_req):
        return false

    return true
```

### Applying Effects

Effects are applied through standardized functions:

```gdscript
func _apply_effects(target, effects: Dictionary) -> void:
    for effect in effects:
        var value = effects[effect]
        match effect:
            "gold":
                target.add_gold(value)
            "happiness":
                target.add_happiness(value)
            "production":
                target.add_production(value)
            _:
                push_warning("Unknown effect: " + effect)
```

### Serialization

All mutable state must be serializable:

```gdscript
func to_dict() -> Dictionary:
    var d = {}
    d["timers"] = timers.duplicate()
    d["active_effects"] = []
    for effect in active_effects:
        d["active_effects"].append(effect.duplicate())
    return d

func from_dict(d: Dictionary) -> void:
    timers = d.get("timers", {})
    active_effects = []
    for effect_data in d.get("active_effects", []):
        active_effects.append(effect_data)
```

## Performance Tips

- **Batch operations** when processing many entities
- **Cache calculations** that are used repeatedly
- **Use signals** sparingly for high-frequency events
- **Profile first** before optimizing
