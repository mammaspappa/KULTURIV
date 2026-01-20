# Game Data Files

All game content in KulturIV is defined in JSON files located in the `data/` directory. This makes the game highly moddable without changing any code.

## Data Files Overview

| File | Purpose | Entries |
|------|---------|---------|
| `units.json` | Unit definitions | ~70 |
| `buildings.json` | Building definitions | ~50 |
| `techs.json` | Technology tree | ~80 |
| `terrains.json` | Terrain types | ~10 |
| `features.json` | Map features | ~10 |
| `resources.json` | Resources | ~30 |
| `improvements.json` | Tile improvements | ~15 |
| `civs.json` | Civilizations | ~18 |
| `leaders.json` | Leaders | ~26 |
| `promotions.json` | Unit promotions | ~30 |
| `religions.json` | Religions | 7 |
| `civics.json` | Government civics | 25 |
| `specialists.json` | City specialists | 15 |
| `corporations.json` | Corporations | 7 |
| `espionage_missions.json` | Spy missions | 15 |
| `projects.json` | World projects | 11 |
| `events.json` | Random events | 20 |
| `votes.json` | UN resolutions | 22 |
| `victories.json` | Victory conditions | 7 |
| `handicaps.json` | Difficulty levels | 9 |

## File Structure

All data files follow a consistent structure:

```json
{
  "_metadata": {
    "version": "1.0",
    "description": "Description of this data file",
    "count": 42
  },
  "item_id": {
    "name": "Display Name",
    "property1": "value1",
    "property2": 123
  }
}
```

The `_metadata` section is optional and ignored during loading.

---

## Units (`units.json`)

Defines all military and civilian units.

### Structure

```json
{
  "warrior": {
    "name": "Warrior",
    "type": "melee",
    "combat": 2,
    "moves": 1,
    "cost": 15,
    "tech_required": "",
    "obsolete_tech": "steel",
    "resource_required": "",
    "upgrade_to": "swordsman",
    "abilities": ["can_attack"],
    "domain": "land",
    "special_abilities": []
  }
}
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | Display name |
| `type` | String | Unit class (melee, ranged, mounted, siege, naval, air) |
| `combat` | int | Base combat strength |
| `moves` | int | Movement points per turn |
| `cost` | int | Production cost |
| `tech_required` | String | Technology needed to build |
| `obsolete_tech` | String | Technology that makes unit obsolete |
| `resource_required` | String | Strategic resource needed |
| `upgrade_to` | String | Unit this can upgrade to |
| `abilities` | Array | Combat abilities |
| `domain` | String | Movement domain (land, sea, air) |
| `special_abilities` | Array | Special actions (found_city, build_improvements, etc.) |

### Special Abilities

| Ability | Description |
|---------|-------------|
| `found_city` | Can found new cities (Settler) |
| `build_improvements` | Can build tile improvements (Worker) |
| `spread_religion` | Can spread religion (Missionary) |
| `great_person` | Great Person abilities |
| `transport` | Can carry other units |
| `bombard` | Can attack cities without dying |
| `airlift` | Can move between airports |

---

## Buildings (`buildings.json`)

Defines city buildings and wonders.

### Structure

```json
{
  "granary": {
    "name": "Granary",
    "cost": 60,
    "maintenance": 1,
    "tech_required": "pottery",
    "building_required": "",
    "effects": {
      "food_stored_on_growth": 50,
      "health": 1
    },
    "yields": {},
    "specialist_slots": {},
    "is_wonder": false,
    "is_national_wonder": false
  }
}
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | Display name |
| `cost` | int | Production cost (hammers) |
| `maintenance` | int | Gold cost per turn |
| `tech_required` | String | Required technology |
| `building_required` | String | Required building |
| `effects` | Dictionary | Bonus effects |
| `yields` | Dictionary | Tile yield bonuses |
| `specialist_slots` | Dictionary | Specialist capacity |
| `is_wonder` | bool | World wonder (only one globally) |
| `is_national_wonder` | bool | National wonder (one per civ) |

### Effect Types

| Effect | Type | Description |
|--------|------|-------------|
| `food` | int | Extra food per turn |
| `production` | int | Extra production per turn |
| `commerce` | int | Extra commerce per turn |
| `culture` | int | Culture per turn |
| `happiness` | int | Happiness bonus |
| `health` | int | Health bonus |
| `defense` | int | City defense percentage |
| `food_stored_on_growth` | int | % food kept on growth |
| `great_people_points` | int | GP points per turn |
| `experience` | int | Free XP for new units |

---

## Technologies (`techs.json`)

Defines the technology tree.

### Structure

```json
{
  "writing": {
    "name": "Writing",
    "era": "ancient",
    "cost": 90,
    "prerequisites": ["alphabet"],
    "leads_to": ["literature", "code_of_laws"],
    "enables_units": [],
    "enables_buildings": ["library"],
    "enables_improvements": [],
    "unlocks_features": [],
    "quotes": ["The pen is mightier than the sword. - Edward Bulwer-Lytton"]
  }
}
```

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `name` | String | Display name |
| `era` | String | Technology era |
| `cost` | int | Base research cost |
| `prerequisites` | Array | Required technologies (AND logic) |
| `or_prerequisites` | Array | Alternative requirements (OR logic) |
| `leads_to` | Array | Technologies this unlocks |
| `enables_units` | Array | Units unlocked |
| `enables_buildings` | Array | Buildings unlocked |
| `enables_improvements` | Array | Improvements unlocked |
| `founds_religion` | String | Religion founded (first discoverer) |

### Eras

1. `ancient` - 4000 BC to 1000 BC
2. `classical` - 1000 BC to 500 AD
3. `medieval` - 500 AD to 1400 AD
4. `renaissance` - 1400 AD to 1700 AD
5. `industrial` - 1700 AD to 1900 AD
6. `modern` - 1900 AD to 1980 AD
7. `future` - 1980 AD and beyond

---

## Civilizations (`civs.json`)

Defines playable civilizations.

### Structure

```json
{
  "rome": {
    "name": "Roman Empire",
    "adjective": "Roman",
    "leaders": ["julius_caesar", "augustus"],
    "starting_techs": ["mining", "fishing"],
    "unique_unit": "praetorian",
    "unique_building": "forum",
    "city_names": ["Rome", "Antium", "Cumae", "Neapolis"]
  }
}
```

---

## Leaders (`leaders.json`)

Defines civilization leaders and their traits.

### Structure

```json
{
  "julius_caesar": {
    "name": "Julius Caesar",
    "civilization": "rome",
    "traits": ["organized", "imperialistic"],
    "favorite_civic": "hereditary_rule",
    "flavors": {
      "military": 8,
      "gold": 5,
      "science": 4,
      "culture": 3,
      "religion": 2,
      "expansion": 7,
      "growth": 4,
      "production": 6
    }
  }
}
```

### Traits

| Trait | Effect |
|-------|--------|
| `aggressive` | Free Combat I, +100% Great General birth |
| `charismatic` | +1 happiness, -25% XP needed |
| `creative` | +2 culture per city, free borders |
| `expansive` | +50% worker speed, +2 health |
| `financial` | +1 commerce on 2+ commerce tiles |
| `imperialistic` | +50% Great General, +100% settler production |
| `industrious` | +50% wonder production |
| `organized` | -50% civic upkeep |
| `philosophical` | +100% Great People |
| `protective` | Free Drill I, +100% city defense |
| `spiritual` | No anarchy |

---

## Civics (`civics.json`)

Defines government and social policies.

### Structure

```json
{
  "slavery": {
    "name": "Slavery",
    "category": "labor",
    "tech_required": "bronze_working",
    "upkeep": "low",
    "effects": {
      "can_hurry": true,
      "hurry_type": "population"
    }
  }
}
```

### Categories

1. `government` - Rule type
2. `legal` - Legal system
3. `labor` - Worker policies
4. `economy` - Economic system
5. `religion` - Religious policies

---

## Religions (`religions.json`)

Defines the seven religions.

### Structure

```json
{
  "buddhism": {
    "name": "Buddhism",
    "tech_required": "meditation",
    "holy_shrine": "mahabodhi",
    "missionary_unit": "buddhist_missionary",
    "temple": "buddhist_temple",
    "monastery": "buddhist_monastery",
    "cathedral": "buddhist_cathedral"
  }
}
```

---

## Resources (`resources.json`)

Defines strategic, luxury, and bonus resources.

### Structure

```json
{
  "iron": {
    "name": "Iron",
    "type": "strategic",
    "tech_required": "iron_working",
    "terrain_types": ["grassland", "plains", "tundra", "hills"],
    "yields": { "production": 1 },
    "improvement_yields": { "mine": { "production": 1 } },
    "happiness": 0,
    "health": 0
  }
}
```

### Resource Types

| Type | Purpose |
|------|---------|
| `strategic` | Required for certain units (iron, horses, oil) |
| `luxury` | Provides happiness (gems, silk, wine) |
| `bonus` | Provides yields (wheat, fish, deer) |

---

## Improvements (`improvements.json`)

Defines tile improvements built by workers.

### Structure

```json
{
  "farm": {
    "name": "Farm",
    "tech_required": "agriculture",
    "valid_terrains": ["grassland", "plains", "flood_plains"],
    "valid_features": [],
    "build_time": 4,
    "yields": { "food": 1 },
    "with_tech": {
      "civil_service": { "food": 1 }
    }
  }
}
```

---

## Random Events (`events.json`)

Defines random events that can occur during gameplay.

### Structure

```json
{
  "gold_discovery": {
    "name": "Gold Discovery",
    "category": "discovery",
    "description": "Prospectors have found gold deposits!",
    "weight": 100,
    "triggers": {
      "has_improvement": "mine",
      "min_turn": 20
    },
    "choices": [
      {
        "text": "Wonderful! Commence mining immediately!",
        "effects": { "gold": 100 }
      },
      {
        "text": "Create a mining company",
        "effects": { "gold_per_turn": 5 }
      }
    ],
    "can_repeat": true
  }
}
```

---

## Modifying Data Files

### Adding New Content

1. Open the appropriate JSON file
2. Add a new entry with a unique ID
3. Fill in all required properties
4. Restart the game to load changes

### Example: Adding a New Unit

```json
{
  "heavy_cavalry": {
    "name": "Heavy Cavalry",
    "type": "mounted",
    "combat": 12,
    "moves": 2,
    "cost": 100,
    "tech_required": "military_tradition",
    "resource_required": "horses",
    "abilities": ["flanking"]
  }
}
```

### Validation

Before editing:
1. Backup the original file
2. Use a JSON validator
3. Check for duplicate IDs
4. Test in-game

### Common Mistakes

- Missing commas between entries
- Misspelled property names
- Invalid references (e.g., non-existent techs)
- Wrong data types (string vs number)

## Loading Process

DataManager loads all JSON files during `_ready()`:

```gdscript
func _ready() -> void:
    units = _load_json("res://data/units.json")
    buildings = _load_json("res://data/buildings.json")
    techs = _load_json("res://data/techs.json")
    # ... etc
```

Data is accessed through getter functions:

```gdscript
var unit_data = DataManager.get_unit("warrior")
var building_data = DataManager.get_building("granary")
```
