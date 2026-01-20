# Modding Guide

KulturIV is designed to be highly moddable. This guide covers how to customize and extend the game.

## Modding Overview

### What Can Be Modded

| Category | Difficulty | Method |
|----------|------------|--------|
| Units, buildings, techs | Easy | Edit JSON files |
| Civilizations, leaders | Easy | Edit JSON files |
| Game rules, balance | Medium | Edit JSON + scripts |
| New systems | Advanced | GDScript coding |
| UI changes | Advanced | GDScript + scenes |

### No-Code Modding

The easiest mods require only editing JSON files in the `data/` directory:
- Add new units, buildings, technologies
- Modify stats and costs
- Create new civilizations
- Add random events

---

## Quick Start: Your First Mod

Let's add a custom unit in 5 minutes.

### Step 1: Open units.json

Find `data/units.json` and open it in a text editor.

### Step 2: Add Your Unit

Add a new entry at the end (before the closing `}`):

```json
{
  "existing_unit": { ... },

  "my_custom_knight": {
    "name": "Elite Knight",
    "type": "mounted",
    "combat": 15,
    "moves": 2,
    "cost": 120,
    "tech_required": "guilds",
    "resource_required": "horses",
    "abilities": ["flanking", "charge"],
    "domain": "land"
  }
}
```

### Step 3: Test It

1. Save the file
2. Run the game
3. Research Guilds and build your unit!

---

## JSON Modding

### Adding Content

#### New Unit

```json
{
  "super_tank": {
    "name": "Super Tank",
    "type": "armor",
    "combat": 40,
    "moves": 2,
    "cost": 200,
    "tech_required": "composites",
    "resource_required": "oil",
    "abilities": ["blitz", "city_raider"],
    "domain": "land",
    "upgrade_to": ""
  }
}
```

#### New Building

```json
{
  "research_lab": {
    "name": "Research Laboratory",
    "cost": 250,
    "maintenance": 3,
    "tech_required": "computers",
    "building_required": "university",
    "effects": {
      "science_percent": 50,
      "great_scientist_points": 3
    },
    "is_wonder": false
  }
}
```

#### New Technology

```json
{
  "quantum_computing": {
    "name": "Quantum Computing",
    "era": "future",
    "cost": 6000,
    "prerequisites": ["computers", "superconductors"],
    "enables_buildings": ["quantum_lab"],
    "enables_units": []
  }
}
```

#### New Civilization

```json
{
  "atlantis": {
    "name": "Atlantean Empire",
    "adjective": "Atlantean",
    "leaders": ["poseidon"],
    "starting_techs": ["fishing", "sailing"],
    "unique_unit": "triton",
    "unique_building": "sea_shrine",
    "city_names": ["Atlantis", "Poseidonia", "Oceanus", "Nereid"]
  }
}
```

#### New Leader

```json
{
  "poseidon": {
    "name": "Poseidon",
    "civilization": "atlantis",
    "traits": ["expansive", "charismatic"],
    "favorite_civic": "free_market",
    "flavors": {
      "military": 5,
      "gold": 7,
      "science": 4,
      "culture": 6,
      "religion": 3,
      "expansion": 8,
      "growth": 5,
      "production": 4
    }
  }
}
```

### Modifying Existing Content

#### Change Unit Stats

Find the unit in `units.json` and modify:

```json
{
  "warrior": {
    "combat": 3,      // Was 2
    "moves": 2,       // Was 1
    "cost": 10        // Was 15
  }
}
```

#### Adjust Building Effects

```json
{
  "library": {
    "effects": {
      "science_percent": 30,  // Was 25
      "great_scientist_points": 2  // Added
    }
  }
}
```

#### Rebalance Technologies

```json
{
  "writing": {
    "cost": 60  // Was 90, now faster to research
  }
}
```

---

## Creating New Events

Random events add variety to gameplay.

### Event Structure

```json
{
  "meteor_strike": {
    "name": "Meteor Strike",
    "category": "disaster",
    "description": "A meteor has struck near one of our cities!",
    "weight": 50,
    "triggers": {
      "min_turn": 50,
      "min_cities": 3
    },
    "choices": [
      {
        "text": "Study the meteor for science",
        "effects": {
          "research_bonus": 50,
          "great_scientist_points": 5
        }
      },
      {
        "text": "Sell meteor fragments",
        "effects": {
          "gold": 200
        }
      },
      {
        "text": "Build a monument",
        "effects": {
          "culture": 100,
          "happiness": 1
        }
      }
    ],
    "can_repeat": false
  }
}
```

### Event Categories

Use these for appropriate styling:
- `natural_disaster` - Orange Red
- `disaster` - Red
- `discovery` - Gold
- `economic` - Green
- `cultural` - Purple
- `science` - Cyan
- `military` - Dark Red
- `diplomatic` - Medium Purple
- `growth` - Light Green
- `unrest` - Dark Orange
- `religious` - Medium Aquamarine
- `prosperity` - Yellow

### Trigger Conditions

| Trigger | Type | Description |
|---------|------|-------------|
| `min_turn` | int | Minimum game turn |
| `max_turn` | int | Maximum game turn |
| `min_cities` | int | Minimum cities owned |
| `min_population` | int | Minimum total population |
| `has_tech` | string | Required technology |
| `has_resource` | string | Required resource |
| `has_improvement` | string | Tile with improvement |
| `has_building` | string | City with building |
| `at_war` | bool | Currently at war |
| `at_peace` | bool | Currently at peace |

---

## Advanced Modding

### Creating a New System

For complex mods, you may need to add a new game system.

#### Step 1: Create Data File

`data/my_feature.json`:
```json
{
  "_metadata": {
    "description": "My custom feature data"
  },
  "items": {
    "item_1": {
      "name": "Item One",
      "effect": 10
    }
  }
}
```

#### Step 2: Create System Script

`scripts/systems/my_system.gd`:
```gdscript
extends Node
## My custom system

var data: Dictionary = {}
var state: Dictionary = {}

func _ready() -> void:
    _load_data()
    EventBus.turn_started.connect(_on_turn_started)

func _load_data() -> void:
    var file = FileAccess.open("res://data/my_feature.json", FileAccess.READ)
    var json = JSON.new()
    json.parse(file.get_as_text())
    data = json.data.get("items", {})

func _on_turn_started(turn: int, player) -> void:
    # Process each turn
    pass

func do_action(player_id: int, item_id: String) -> bool:
    var item = data.get(item_id, {})
    if item.is_empty():
        return false

    # Apply effect
    var effect = item.get("effect", 0)
    # ... do something ...

    return true

func to_dict() -> Dictionary:
    return state.duplicate(true)

func from_dict(d: Dictionary) -> void:
    state = d.duplicate(true)
```

#### Step 3: Register as Autoload

In `project.godot`:
```ini
[autoload]
...
MySystem="*res://scripts/systems/my_system.gd"
```

#### Step 4: Add EventBus Signals

```gdscript
# In event_bus.gd
signal my_action_completed(player_id, item_id, result)
```

---

## Mod Compatibility

### Best Practices

1. **Use Unique IDs**: Prefix your content with a mod identifier
   ```json
   "mymod_super_unit": { ... }
   ```

2. **Don't Delete Base Content**: Add new items instead of removing

3. **Document Your Changes**: Create a README for your mod

4. **Test Thoroughly**: Check for conflicts and edge cases

### Mod Folders (Planned)

Future versions will support mod folders:
```
mods/
├── my_mod/
│   ├── mod.json          # Mod metadata
│   ├── data/
│   │   ├── units.json    # Additions/overrides
│   │   └── events.json
│   └── scripts/
│       └── my_system.gd
```

---

## Debugging Mods

### Common Issues

#### JSON Parse Errors

Check for:
- Missing commas between entries
- Unquoted strings
- Trailing commas (not allowed in JSON)

Use a JSON validator like [jsonlint.com](https://jsonlint.com/).

#### Missing References

Error: "Unknown tech: my_tech"
- Check that referenced items exist
- Verify spelling matches exactly

#### Effects Not Applying

- Check effect names match expected keys
- Verify the system processes that effect type
- Add print statements for debugging

### Debug Mode

Add debug output to your systems:
```gdscript
func _ready() -> void:
    print("MySystem loaded with %d items" % data.size())

func do_action(player_id: int, item_id: String) -> bool:
    print("MySystem.do_action(%d, %s)" % [player_id, item_id])
    # ...
```

---

## Examples

### Total Conversion: Fantasy Theme

Replace all civilizations with fantasy races:

`data/civs.json`:
```json
{
  "elves": {
    "name": "Elven Kingdom",
    "adjective": "Elven",
    "starting_techs": ["archery", "mysticism"],
    "unique_unit": "elven_archer",
    "city_names": ["Rivendell", "Lothlorien", "Mirkwood"]
  },
  "dwarves": {
    "name": "Dwarven Clans",
    "adjective": "Dwarven",
    "starting_techs": ["mining", "masonry"],
    "unique_unit": "dwarven_warrior",
    "city_names": ["Erebor", "Moria", "Khazad-dum"]
  }
}
```

### Difficulty Mod: Harder AI

`data/handicaps.json`:
```json
{
  "deity": {
    "name": "Deity",
    "ai_bonuses": {
      "starting_units": 4,
      "free_techs": 3,
      "production_bonus": 100,
      "research_bonus": 80,
      "gold_bonus": 100
    },
    "player_penalties": {
      "maintenance_percent": 150
    }
  }
}
```

### New Victory Condition

Add to `data/victories.json`:
```json
{
  "economic": {
    "name": "Economic Victory",
    "description": "Accumulate 100,000 gold in treasury",
    "conditions": {
      "gold_threshold": 100000
    },
    "tech_required": "economics"
  }
}
```

Then implement in `victory_system.gd`:
```gdscript
func _check_economic_victory(player) -> bool:
    return player.gold >= 100000
```

---

## Resources

- **Original Civ4 Data**: `beyond/` directory has reference XML files
- **Community**: Share mods and get help on the project GitHub
- **Documentation**: This docs folder covers all systems
