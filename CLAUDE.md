# KulturIV - Project Context

A Civilization IV: Beyond the Sword clone built in Godot 4.5.1.

## Project Overview

**Goal**: Recreate the core gameplay of Civilization IV: Beyond the Sword as a standalone game using the Godot engine.

**Status**: ~95% complete. Most core systems implemented including combat, diplomacy, espionage, corporations, religion, and victory conditions. Recent additions include unit focus cycling (auto-cycle to next unit after action), "No State Religion" option, AI visibility bonuses at higher difficulties, Great General attachment to military units (+20% combat, +50% XP), goody huts, barbarian spawning, AI naval operations, and favorite civics per leader.

**Reference Files**: The original Civ4 BTS XML data files are located in `beyond/` directory for reference. These files should NOT be modified - they're only for understanding the original game's data structures and mechanics.

## Directory Structure

```
KULTURIV/
├── beyond/                  # Original Civ4 BTS files (REFERENCE ONLY)
├── data/                    # Game data in JSON format
│   ├── buildings.json       # Building definitions (~120 buildings incl. wonders, unique buildings)
│   ├── civs.json           # Civilization definitions (18 civs)
│   ├── civics.json         # Civic system (25 civics in 5 categories)
│   ├── corporations.json   # Corporation mechanics (7 corporations)
│   ├── eras.json           # Era definitions (7 eras)
│   ├── espionage_missions.json  # Spy missions (15 missions)
│   ├── events.json         # Random events (20 events)
│   ├── features.json       # Map features (forest, jungle, etc.)
│   ├── game_speeds.json    # Game speed modifiers (4 speeds)
│   ├── handicaps.json      # Difficulty settings (9 levels)
│   ├── improvements.json   # Tile improvements (farms, mines, etc.)
│   ├── leaders.json        # Leader definitions and traits (26 leaders)
│   ├── projects.json       # World/national projects (11 projects)
│   ├── promotions.json     # Unit promotion tree (30+ promotions)
│   ├── religions.json      # Religion definitions (7 religions)
│   ├── resources.json      # Strategic/luxury/bonus resources (30 resources)
│   ├── specialists.json    # City specialists (15 types)
│   ├── techs.json          # Technology tree (80+ techs)
│   ├── terrains.json       # Terrain types (10 types)
│   ├── units.json          # Unit definitions (90+ units, incl. 16 unique units)
│   ├── victories.json      # Victory conditions (7 types)
│   └── votes.json          # UN/Apostolic Palace resolutions (22 resolutions)
├── scenes/
│   └── main/
│       ├── main_menu.tscn  # Main menu scene
│       ├── game.tscn       # Main game scene
│   └── ui/
│       ├── city_screen.tscn
│       ├── tech_tree.tscn
│       ├── diplomacy_screen.tscn
│       ├── civics_screen.tscn
│       └── ... (many more UI screens)
├── scripts/
│   ├── autoload/           # Singleton managers
│   │   ├── event_bus.gd    # Global signal bus (100+ signals)
│   │   ├── data_manager.gd # Loads and provides game data
│   │   ├── game_manager.gd # Game state, players, settings
│   │   └── turn_manager.gd # Turn processing
│   ├── core/
│   │   ├── game_state.gd   # Serializable game state
│   │   ├── player.gd       # Player data and resources
│   │   ├── game_camera.gd  # Camera controls
│   │   └── game_world.gd   # World container
│   ├── map/
│   │   ├── grid_utils.gd   # Grid math utilities
│   │   ├── game_tile.gd    # Individual tile data
│   │   ├── game_grid.gd    # Map generation and management
│   │   └── pathfinding.gd  # A* pathfinding with border checks
│   ├── entities/
│   │   ├── unit.gd         # Unit class (movement, combat, automation)
│   │   └── city.gd         # City class (production, growth, specialists)
│   ├── ai/
│   │   └── ai_controller.gd # AI player behavior
│   ├── ui/                 # UI scripts
│   │   ├── game_ui.gd
│   │   ├── city_screen.gd
│   │   ├── tech_tree.gd
│   │   ├── diplomacy_screen.gd
│   │   └── ... (many more)
│   └── systems/            # Game systems
│       ├── combat_system.gd      # Ground, air, and nuclear combat
│       ├── improvement_system.gd # Tile improvements
│       ├── religion_system.gd    # Religion mechanics
│       ├── civics_system.gd      # Civic effects
│       ├── corporation_system.gd # Corporation mechanics
│       ├── espionage_system.gd   # Spy missions
│       ├── great_people_system.gd # Great person mechanics
│       ├── victory_system.gd     # Victory conditions
│       ├── voting_system.gd      # UN/Apostolic Palace
│       ├── events_system.gd      # Random events
│       ├── projects_system.gd    # World/national projects
│       ├── border_system.gd      # Border permissions
│       ├── diplomacy_system.gd   # Diplomacy calculations
│       ├── trade_system.gd       # Trade agreements
│       ├── save_system.gd        # Save/load
│       ├── goody_huts_system.gd  # Tribal villages with rewards
│       └── barbarian_system.gd   # Barbarian camps and spawning
└── project.godot           # Godot project config
```

## Architecture

### Autoload Singletons (load order matters)
1. **EventBus** - Global signal bus for decoupled communication (100+ signals)
2. **DataManager** - Loads JSON data, provides typed getters for game data
3. **GameManager** - Central game state, player management, settings
4. **TurnManager** - Handles turn processing for all players

### Key Classes

- **GameGrid** - Manages the map, noise-based terrain generation, tile storage
- **GameTile** - Individual tile with terrain, features, resources, improvements, visibility
- **Unit** - Movement, combat, promotions, orders, abilities, automation
- **City** - Population, production queue, buildings, culture, territory, specialists
- **Player** - Resources (gold, science), tech tree, units, cities, diplomacy, civics

### Coordinate System
- Uses **square grid** with 8-directional movement
- Tile size: 64x64 pixels
- Map wraps on X-axis (cylindrical), not Y-axis
- Conversion: `GridUtils.grid_to_pixel()` / `GridUtils.pixel_to_grid()`

## Implemented Systems

### Core (100%)
- [x] Map generation with terrain, features, resources
- [x] Unit movement with pathfinding and border checks
- [x] City founding, growth, production
- [x] Technology research with prerequisites
- [x] Save/load system

### Combat (100%)
- [x] Ground combat with strength, first strikes, withdraw
- [x] Terrain and fortification bonuses
- [x] Collateral damage (siege units)
- [x] Air combat (bombing, interception, air superiority)
- [x] Nuclear weapons (fallout, population kill, SDI)

### Diplomacy (95%)
- [x] War/peace declarations
- [x] Open borders, defensive pacts
- [x] Trade agreements (gold, resources, techs)
- [x] Attitude calculation with modifiers
- [x] Memory system for events
- [x] Border crossing restrictions

### Religion (100%)
- [x] Religion founding via technology
- [x] Religion spread via missionaries
- [x] Holy cities and shrines
- [x] State religion and happiness
- [x] "No State Religion" option (religious freedom)
- [x] Religion-specific buildings (21 total)
- [x] Inquisitor unit (removes non-state religions)

### Civics (100%)
- [x] 25 civics in 5 categories
- [x] Civic effects (happiness, production, etc.)
- [x] Anarchy during changes
- [x] Spiritual trait

### Victory Conditions (100%)
- [x] Domination, Conquest, Cultural, Space Race
- [x] Diplomatic, Time, Religious

### AI (95%)
- [x] Research, production, movement decisions
- [x] War/peace evaluation
- [x] Trade and diplomacy
- [x] Worker management
- [x] Espionage operations
- [x] Random event handling (evaluates choices by flavor)
- [x] City specialization (production, science, gold, military, culture, food)
- [x] Naval operations (transports, combat ships, blockades, coastal patrol)
- [x] Civics adoption based on favorite civics per leader
- [x] Visibility bonuses at higher difficulties (Emperor 25%, Immortal 50%, Deity 100%)

### Other Systems
- [x] Great People (birth, abilities, golden ages)
- [x] Great General attachment to units (+20% combat, +50% XP)
- [x] Corporations (founding, spreading, effects, HQ buildings)
- [x] Espionage (15 missions, spy mechanics)
- [x] Random Events (20 events with choices, AI handling)
- [x] UN/Apostolic Palace voting (22 resolutions)
- [x] Projects (Manhattan, Apollo, spaceship)
- [x] Tech diffusion (cost reduction if others know tech)
- [x] Conscription (draft units with Nationalism + Nationhood)
- [x] Emancipation civic anger
- [x] Unique units per civilization (16 total, with civ restrictions)
- [x] Unique buildings per civilization (9 total, with civ restrictions)
- [x] Worker border restrictions (improvements only in own territory, except roads/forts)
- [x] City founding places road on tile automatically
- [x] Pasture improvement (cattle, sheep, horses, pig)
- [x] Camp improvement (deer, furs, ivory)
- [x] Goody huts (tribal villages with 8 reward types: gold, tech, map, XP, unit, settler, population, barbarians)
- [x] Barbarian system (camps, spawning, pillaging AI, unit scaling by era)
- [x] Unit focus cycling (auto-cycle to next unit after action, TAB/PERIOD keys)

## Game Settings

- **Map Size**: Configurable (default 80x50)
- **Difficulty**: 0-8 scale (4 = Prince)
- **Game Speed**: Quick/Normal/Epic/Marathon

## Input Actions (defined in project.godot)
- `camera_pan_up/down/left/right` - WASD or Arrow keys
- `select` - Left mouse button
- `action` - Right mouse button
- `end_turn` - Enter key
- `zoom_in/out` - Mouse wheel
- `fortify` - F key
- `skip_turn` - Space bar
- `diplomacy` - D key
- `civics` - C key
- `cycle_unit` - TAB key (cycle to next unit needing orders)
- `skip_and_cycle` - PERIOD key (skip current unit and cycle to next)

## Common Tasks

### Adding a new unit type
1. Add entry to `data/units.json`
2. DataManager will auto-load it

### Adding a new building
1. Add entry to `data/buildings.json` with effects
2. DataManager handles loading

### Adding a new system
1. Create script in `scripts/systems/`
2. Connect to EventBus signals in `_ready()`
3. Emit events when state changes
4. Register as autoload if singleton

### Adding UI elements
1. Create scene in `scenes/ui/`
2. Create script in `scripts/ui/`
3. Connect to EventBus signals for updates

## Event-Driven Architecture

All game events flow through `EventBus` singleton:
- UI subscribes to events for updates
- Systems emit events when state changes
- Decoupled communication between components

Key event patterns:
```gdscript
# Emit an event
EventBus.unit_moved.emit(unit, from_pos, to_pos)

# Subscribe to an event
func _ready():
    EventBus.unit_moved.connect(_on_unit_moved)
```

## Data-Driven Design

All game data in JSON files (`data/` directory):
- Units, buildings, techs defined externally
- Easy to mod without code changes
- DataManager provides typed accessors

Example accessor:
```gdscript
var unit_data = DataManager.get_unit("warrior")
var strength = DataManager.get_unit_strength("warrior")
var abilities = DataManager.get_unit_abilities("warrior")
```

## Turn Processing Order
1. `turn_started` signal emitted
2. Unit movement refreshed
3. Cities process: yields → growth → production → culture
4. Research progress updated
5. Great People points accumulated
6. AI executes (if not human)
7. Player acts
8. `turn_ended` signal emitted
9. Units heal
10. Fallout decay processed
11. Next player (or `all_turns_completed` if round done)

## Not Yet Implemented
- Sound and music
- Multiplayer
- Civilopedia
- Advisor screens
- Hall of Fame
- Replay system
- World Builder (map editor)

## Development Notes

- Using Godot 4.5.1 with Forward+ renderer
- Target resolution: 1920x1080, windowed mode
- All game data externalized to JSON for easy modding
- Following Civ4's mechanics closely for authenticity

---

*Last updated: January 28, 2026*
