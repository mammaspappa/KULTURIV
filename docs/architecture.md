# Architecture Overview

This document explains the high-level architecture of KulturIV, including how different systems interact and the design patterns used throughout the codebase.

## Core Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         GODOT ENGINE                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    AUTOLOAD SINGLETONS                    │   │
│  │  ┌─────────┐ ┌─────────────┐ ┌─────────────┐             │   │
│  │  │EventBus │ │DataManager  │ │GameManager  │             │   │
│  │  └────┬────┘ └──────┬──────┘ └──────┬──────┘             │   │
│  │       │             │               │                     │   │
│  │  ┌────┴────┐ ┌──────┴──────┐ ┌──────┴──────┐             │   │
│  │  │TurnMgr  │ │GridUtils    │ │AIController │             │   │
│  │  └─────────┘ └─────────────┘ └─────────────┘             │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      GAME SYSTEMS                         │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │   │
│  │  │Combat    │ │Religion  │ │Diplomacy │ │Victory   │     │   │
│  │  │System    │ │System    │ │System    │ │System    │     │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │   │
│  │  │Civics    │ │Trade     │ │Espionage │ │Projects  │     │   │
│  │  │System    │ │System    │ │System    │ │System    │     │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │   │
│  │  │Events    │ │Voting    │ │GreatPpl  │ │Corpor.   │     │   │
│  │  │System    │ │System    │ │System    │ │System    │     │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      GAME ENTITIES                        │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │   │
│  │  │ Player   │ │  Unit    │ │  City    │ │ GameTile │     │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              │                                   │
│                              ▼                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                      USER INTERFACE                       │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐     │   │
│  │  │ GameUI   │ │CityScreen│ │TechTree  │ │Diplomacy │     │   │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘     │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Autoload Singletons

Autoload singletons are globally accessible nodes that persist across scene changes. They form the backbone of KulturIV's architecture.

### Load Order

The order of autoloads in `project.godot` matters because later autoloads may depend on earlier ones:

```gdscript
# project.godot [autoload] section
GridUtils     = "*res://scripts/map/grid_utils.gd"      # 1. Pure utility functions
EventBus      = "*res://scripts/autoload/event_bus.gd"  # 2. Signal hub (no dependencies)
DataManager   = "*res://scripts/autoload/data_manager.gd" # 3. Loads JSON data
GameManager   = "*res://scripts/autoload/game_manager.gd" # 4. Game state
TurnManager   = "*res://scripts/autoload/turn_manager.gd" # 5. Turn processing
# ... Game systems follow ...
```

### EventBus

The EventBus is the central communication hub. All game events are defined as signals here, allowing systems to communicate without direct references.

**File**: `scripts/autoload/event_bus.gd`

```gdscript
# Example signals
signal turn_started(turn_number, player)
signal unit_moved(unit, from_hex, to_hex)
signal city_founded(city, founder)
signal research_completed(player, tech)
```

**Why use EventBus?**
- **Decoupling**: Systems don't need direct references to each other
- **Flexibility**: Easy to add new listeners without modifying emitters
- **Debugging**: Central location to trace all game events
- **Modding**: Modders can hook into events without changing core code

### DataManager

DataManager loads and provides access to all JSON game data.

**File**: `scripts/autoload/data_manager.gd`

```gdscript
# Loading data
func _load_json(path: String) -> Dictionary:
    var file = FileAccess.open(path, FileAccess.READ)
    var json = JSON.new()
    json.parse(file.get_as_text())
    return json.data

# Accessing data
func get_unit(unit_id: String) -> Dictionary:
    return units.get(unit_id, {})

func get_building(building_id: String) -> Dictionary:
    return buildings.get(building_id, {})
```

### GameManager

GameManager holds the current game state including players, map, and settings.

**File**: `scripts/autoload/game_manager.gd`

**Key Responsibilities:**
- Store game settings (map size, difficulty, game speed)
- Manage player list and human player reference
- Hold reference to the game grid (map)
- Track game-wide state (nukes banned, etc.)

```gdscript
# Key properties
var human_player: Player
var all_players: Array[Player]
var hex_grid: GameGrid
var map_width: int = 80
var map_height: int = 50
var difficulty: int = 4  # Prince
var game_speed: String = "normal"
```

### TurnManager

TurnManager handles the turn-based flow of the game.

**File**: `scripts/autoload/turn_manager.gd`

**Turn Processing Order:**
1. Emit `turn_started` signal
2. Refresh unit movement points
3. Process cities (yields → growth → production → culture)
4. Update research progress
5. AI executes decisions
6. Wait for human input
7. Emit `turn_ended` signal
8. Heal units
9. Advance to next player (or `all_turns_completed` if round done)

```gdscript
func end_turn() -> void:
    EventBus.turn_ended.emit(current_turn, current_player)
    _process_end_of_turn()
    _advance_to_next_player()
```

## Game Systems

Game systems are autoloaded singletons that handle specific game mechanics. Each system:
- Loads its own data from JSON files
- Connects to relevant EventBus signals
- Exposes functions for other systems to call
- Implements serialization for save/load

### System Pattern

```gdscript
extends Node
## System description

# Data loaded from JSON
var data: Dictionary = {}

func _ready() -> void:
    _load_data()
    _connect_signals()

func _load_data() -> void:
    var path = "res://data/system_data.json"
    # ... load JSON ...

func _connect_signals() -> void:
    EventBus.turn_started.connect(_on_turn_started)
    # ... connect other signals ...

# Public API
func do_something(args) -> Result:
    # Implementation
    pass

# Serialization
func to_dict() -> Dictionary:
    return { "key": value }

func from_dict(data: Dictionary) -> void:
    value = data.get("key", default)
```

### System Communication

Systems communicate through two mechanisms:

1. **EventBus Signals**: For notifications that multiple systems might care about
   ```gdscript
   # Emitting
   EventBus.city_founded.emit(city, player)

   # Listening
   EventBus.city_founded.connect(_on_city_founded)
   ```

2. **Direct Calls**: For specific queries or actions
   ```gdscript
   # Direct call to another system
   var cost = CombatSystem.calculate_damage(attacker, defender)
   ```

## Game Entities

Entities are the objects that exist in the game world.

### Player

Represents a civilization in the game.

**File**: `scripts/core/player.gd`

```gdscript
class_name Player

# Identity
var player_id: int
var civilization_id: String
var leader_id: String
var is_human: bool

# Resources
var gold: int = 0
var gold_per_turn: int = 0
var research_progress: int = 0
var current_research: String = ""

# Collections
var cities: Array[City] = []
var units: Array[Unit] = []
var known_techs: Array[String] = []
var met_players: Array[int] = []

# Diplomacy
var relationships: Dictionary = {}  # player_id -> state
var state_religion: String = ""
```

### Unit

A military or civilian unit on the map.

**File**: `scripts/entities/unit.gd`

```gdscript
class_name Unit

# Identity
var unit_id: String
var player_owner: Player

# Position
var grid_position: Vector2i
var facing: int

# Stats (from data + modifiers)
var health: int = 100
var max_health: int = 100
var movement_remaining: float = 0.0
var experience: int = 0

# State
var has_acted: bool = false
var is_fortified: bool = false
var promotions: Array[String] = []
```

### City

A city that produces units, buildings, and generates yields.

**File**: `scripts/entities/city.gd`

```gdscript
class_name City

# Identity
var city_name: String
var player_owner: Player
var grid_position: Vector2i

# Population
var population: int = 1
var food_stored: float = 0.0

# Production
var production_queue: Array[String] = []
var production_progress: float = 0.0

# Culture
var culture_total: int = 0
var culture_level: int = 1

# Buildings and Religion
var buildings: Array[String] = []
var religions: Array[String] = []
```

### GameTile

A single tile on the map.

**File**: `scripts/map/game_tile.gd`

```gdscript
class_name GameTile

# Position
var grid_position: Vector2i

# Terrain
var terrain_type: String = "grassland"
var feature: String = ""        # forest, jungle, etc.
var resource: String = ""       # iron, wheat, etc.
var improvement: String = ""    # farm, mine, etc.
var road_level: int = 0         # 0=none, 1=road, 2=railroad

# Ownership
var tile_owner: Player = null
var worked_by_city: City = null

# Visibility
var visibility: Dictionary = {} # player_id -> VisibilityState
```

## Map System

### Coordinate System

KulturIV uses a square grid with 8-directional movement (not hexagonal despite some naming conventions).

```
   NW  N  NE
     \ | /
   W - * - E
     / | \
   SW  S  SE
```

**GridUtils** provides conversion functions:

```gdscript
# Grid to pixel conversion
func grid_to_pixel(grid_pos: Vector2i) -> Vector2:
    return Vector2(grid_pos.x * TILE_SIZE, grid_pos.y * TILE_SIZE)

# Pixel to grid conversion
func pixel_to_grid(pixel_pos: Vector2) -> Vector2i:
    return Vector2i(int(pixel_pos.x / TILE_SIZE), int(pixel_pos.y / TILE_SIZE))

# Get neighbors
func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
    # Returns 8 adjacent tiles
```

### Map Wrapping

The map wraps horizontally (cylindrical world) but not vertically:

```gdscript
func wrap_x(x: int) -> int:
    return posmod(x, map_width)

func is_valid_position(pos: Vector2i) -> bool:
    var wrapped = Vector2i(wrap_x(pos.x), pos.y)
    return wrapped.y >= 0 and wrapped.y < map_height
```

### Pathfinding

A* pathfinding is used for unit movement.

**File**: `scripts/map/pathfinding.gd`

```gdscript
func find_path(from: Vector2i, to: Vector2i, unit: Unit) -> Array[Vector2i]:
    # A* implementation considering:
    # - Terrain movement costs
    # - Unit movement type (land, sea, air)
    # - Enemy units and borders
    # - Road bonuses
```

## UI Architecture

UI components follow a consistent pattern:

```gdscript
extends Control

# UI element references
var panel: PanelContainer
var close_button: Button
# ...

func _ready() -> void:
    _build_ui()           # Create UI programmatically
    visible = false       # Start hidden
    _connect_signals()    # Connect to EventBus

func _build_ui() -> void:
    # Create overlay, panels, buttons, etc.
    pass

func _on_show() -> void:
    _refresh_display()
    visible = true

func _on_close() -> void:
    visible = false

func _input(event: InputEvent) -> void:
    if visible and event is InputEventKey:
        if event.keycode == KEY_ESCAPE:
            _on_close()
            get_viewport().set_input_as_handled()
```

### UI Styling

UI uses `StyleBoxFlat` for consistent panel styling:

```gdscript
var style = StyleBoxFlat.new()
style.bg_color = Color(0.1, 0.1, 0.15, 0.98)
style.border_color = Color(0.3, 0.4, 0.5)
style.border_width_top = 2
style.border_width_bottom = 2
style.border_width_left = 2
style.border_width_right = 2
style.corner_radius_top_left = 8
style.corner_radius_top_right = 8
style.corner_radius_bottom_left = 8
style.corner_radius_bottom_right = 8
panel.add_theme_stylebox_override("panel", style)
```

## Serialization

All game state can be serialized for save/load functionality.

### Pattern

Every class that holds game state implements:

```gdscript
func to_dict() -> Dictionary:
    return {
        "property_a": property_a,
        "property_b": property_b,
        "nested": nested_object.to_dict()
    }

func from_dict(data: Dictionary) -> void:
    property_a = data.get("property_a", default_a)
    property_b = data.get("property_b", default_b)
    nested_object.from_dict(data.get("nested", {}))
```

### SaveSystem

**File**: `scripts/systems/save_system.gd`

```gdscript
func save_game(slot: String) -> bool:
    var save_data = {
        "version": SAVE_VERSION,
        "turn": TurnManager.current_turn,
        "players": _serialize_players(),
        "map": hex_grid.to_dict(),
        "systems": _serialize_systems()
    }
    # Write to file

func load_game(slot: String) -> bool:
    # Read file
    # Restore all state
```

## Performance Considerations

### Large Maps

For maps with many tiles (100x60 = 6000 tiles):
- Tiles are stored in a Dictionary for O(1) lookup
- Only visible tiles are rendered
- Fog of war uses bitflags for memory efficiency

### Many Units

- Unit processing is batched by player
- AI units use simplified pathfinding for distant moves
- Combat calculations are cached when possible

### Memory Management

- `queue_free()` is used for proper node cleanup
- Dictionaries are duplicated with `duplicate(true)` for deep copies
- Large data structures use references, not copies

## Error Handling

### Defensive Coding

All external references are checked:

```gdscript
if GameManager and GameManager.human_player:
    # Safe to use

var data = DataManager.get_unit(unit_id) if DataManager else {}
if data.is_empty():
    push_warning("Unknown unit: " + unit_id)
    return
```

### Debug Output

Use Godot's built-in logging:

```gdscript
print("Debug info")           # General output
push_warning("Warning message")  # Non-critical issues
push_error("Error message")      # Critical problems
```
