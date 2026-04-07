# KulturIV - Project Context

A Civilization IV: Beyond the Sword clone built in Godot 4.6.2.

## Commands

```bash
# Open project in Godot editor
godot --editor project.godot

# Run the game directly
godot project.godot

# Export (presets defined in export_presets.cfg)
godot --headless --export-debug "Linux" build/kulturiv.x86_64
```

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
│   │   ├── game_camera.gd  # Camera controls (2D)
│   │   ├── game_camera_3d.gd # Camera controls (3D)
│   │   └── game_world.gd   # World container
│   ├── map/
│   │   ├── grid_utils.gd   # Grid math utilities
│   │   ├── game_tile.gd    # Individual tile data
│   │   ├── game_grid.gd    # Map generation and management
│   │   ├── pathfinding.gd  # A* pathfinding with border checks
│   │   ├── cylinder_map.gd # Cylindrical map projection
│   │   └── input_raycast.gd # Mouse/input raycasting on map
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
│       ├── barbarian_system.gd   # Barbarian camps and spawning
│       └── visibility_system.gd  # Fog of war and tile visibility
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
- Map does not wrap (flat map with clamped edges)
- Conversion: `GridUtils.grid_to_pixel()` / `GridUtils.pixel_to_grid()`

## Implemented Systems

**Complete (100%):** Core (map, units, cities, tech, save/load), Combat (ground, air, nuclear, collateral, terrain bonuses), Religion (founding, spread, holy cities, shrines, inquisitors, "No State Religion"), Civics (25 civics, 5 categories, anarchy, Spiritual trait), Victory (Domination, Conquest, Cultural, Space Race, Diplomatic, Time, Religious), Great People, Corporations, Espionage (15 missions), Random Events (20 events), UN/Apostolic Palace voting (22 resolutions), Projects, Goody Huts, Barbarians, Visibility/Fog of War

**Near-complete (95%):** Diplomacy (war/peace, trade, borders, attitudes, memory — minor gaps), AI (research, production, combat, naval ops, city specialization, civics, espionage, difficulty-scaled visibility bonuses)

**Notable mechanics:** Tech diffusion, conscription, emancipation anger, Great General attachment (+20% combat, +50% XP), worker border restrictions, unit focus cycling (TAB/PERIOD), 16 unique units, 9 unique buildings

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

- Using Godot 4.6.2 with Forward+ renderer
- Target resolution: 1920x1080, windowed mode
- All game data externalized to JSON for easy modding
- Following Civ4's mechanics closely for authenticity
- Make sure that features from other Civilization games (Civ V, VI, VII) do NOT leak into this project — stay faithful to Civ4 BTS mechanics.

---

*Last updated: April 6, 2026*
