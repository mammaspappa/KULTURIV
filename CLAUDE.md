# KulturIV - Project Context

A Civilization IV: Beyond the Sword clone built in Godot 4.2.

## Project Overview

**Goal**: Recreate the core gameplay of Civilization IV: Beyond the Sword as a standalone game using the Godot engine.

**Reference Files**: The original Civ4 BTS XML data files are located in `beyond/` directory for reference. These files should NOT be modified - they're only for understanding the original game's data structures and mechanics.

## Directory Structure

```
KULTURIV/
├── beyond/                  # Original Civ4 BTS files (REFERENCE ONLY)
├── data/                    # Game data in JSON format
│   ├── buildings.json       # Building definitions
│   ├── civs.json           # Civilization definitions
│   ├── features.json       # Map features (forest, jungle, etc.)
│   ├── improvements.json   # Tile improvements (farms, mines, etc.)
│   ├── leaders.json        # Leader definitions and traits
│   ├── promotions.json     # Unit promotion tree
│   ├── religions.json      # Religion definitions
│   ├── resources.json      # Strategic/luxury/bonus resources
│   ├── techs.json          # Technology tree
│   ├── terrains.json       # Terrain types
│   ├── units.json          # Unit definitions
│   └── victories.json      # Victory conditions
├── scenes/
│   └── main/
│       ├── main_menu.tscn  # Main menu scene
│       ├── main_menu.gd
│       ├── game.tscn       # Main game scene
│       └── game.gd
├── scripts/
│   ├── autoload/           # Singleton managers
│   │   ├── event_bus.gd    # Global signal bus
│   │   ├── data_manager.gd # Loads and provides game data
│   │   ├── game_manager.gd # Game state, players, settings
│   │   └── turn_manager.gd # Turn processing
│   ├── core/
│   │   ├── game_state.gd   # Serializable game state
│   │   ├── player.gd       # Player data and resources
│   │   ├── game_camera.gd  # Camera controls
│   │   └── game_world.gd   # World container
│   ├── map/
│   │   ├── grid_utils.gd   # Hex grid math utilities
│   │   ├── game_tile.gd    # Individual tile data
│   │   ├── game_grid.gd    # Map generation and management
│   │   └── pathfinding.gd  # A* pathfinding
│   ├── entities/
│   │   ├── unit.gd         # Unit class with movement, combat, promotions
│   │   └── city.gd         # City class with production, growth, buildings
│   ├── ui/
│   │   └── game_ui.gd      # In-game UI
│   ├── ai/                 # AI systems (to be implemented)
│   ├── data/               # Data classes
│   └── systems/            # Game systems
└── project.godot           # Godot project config
```

## Architecture

### Autoload Singletons (load order matters)
1. **EventBus** - Global signal bus for decoupled communication
2. **DataManager** - Loads JSON data, provides getters for game data
3. **GameManager** - Central game state, player management, settings
4. **TurnManager** - Handles turn processing for all players

### Key Classes

- **GameGrid** - Manages the hex map, noise-based terrain generation, tile storage
- **GameTile** - Individual tile with terrain, features, resources, improvements, visibility
- **Unit** - Movement, combat, promotions, orders, abilities
- **City** - Population, production queue, buildings, culture, territory
- **Player** - Resources (gold, science), tech tree, units, cities, diplomacy

### Coordinate System
- Uses offset coordinates (odd-r) for hex grid
- `GridUtils` provides conversion between grid and pixel coordinates
- Map wraps on X-axis (cylindrical world), not Y

## Current Implementation Status

### Implemented
- Project structure and autoload singletons
- JSON data loading for all game entities
- Hex grid map generation with noise-based terrain
- Terrain types, features, resources placement
- Unit class with movement, combat stats, promotions
- City class with production, growth, buildings, culture
- Player class with techs, diplomacy states
- Basic input mappings (WASD/arrows for camera, mouse for selection)
- Turn management framework
- Save/load serialization methods (to_dict/from_dict)

### Needs Implementation
- Combat system (attack resolution, damage calculation)
- AI players
- Full UI (city screen, tech tree, diplomacy screens)
- Map rendering (currently using placeholder _draw())
- Worker improvements
- Religion spread mechanics
- Great People
- Victory condition checking
- Sound and music
- Full save/load to files

## Game Settings

- **Map Size**: Configurable (default 80x50)
- **Difficulty**: 0-8 scale (4 = Prince)
- **Game Speed**: Quick/Normal/Epic/Marathon (affects production/research costs)

## Input Actions (defined in project.godot)
- `camera_pan_up/down/left/right` - WASD or Arrow keys
- `select` - Left mouse button
- `action` - Right mouse button
- `end_turn` - Enter key
- `zoom_in/out` - Mouse wheel
- `fortify` - F key
- `skip_turn` - Space bar

## Development Notes

- Using Godot 4.2 with Forward+ renderer
- Target resolution: 1920x1080, windowed mode
- All game data externalized to JSON for easy modding
- Following Civ4's mechanics closely for authenticity

## Implementation Plan

**IMPORTANT**: A detailed implementation plan exists at:
`/home/localuser/.claude/plans/twinkling-scribbling-coral.md`

This plan contains:
- 10 implementation phases with full code samples
- Phase status tracking
- Testing checklist
- Session recovery instructions

### Phase Summary
1. **Combat System** (CRITICAL) - Attack resolution, damage calculation
2. **Worker Improvements** (HIGH) - Tile improvement building
3. **City Screen UI** (HIGH) - City management interface
4. **Tech Tree UI** (HIGH) - Research interface
5. **Minimap** (MEDIUM) - Navigation aid
6. **AI System** (HIGH) - Computer opponent behavior
7. **Victory Conditions** (MEDIUM) - Win state checking
8. **Save/Load** (MEDIUM) - Game persistence
9. **Notifications** (LOW) - Event toasts
10. **Polish** (LOW) - Religion, great people, trade

### Progress Tracking
Check which phases are complete by looking for files:
- `scripts/systems/combat_system.gd` = Phase 1 done
- `scripts/systems/improvement_system.gd` = Phase 2 done
- `scenes/ui/city_screen.tscn` = Phase 3 done
- `scenes/ui/tech_tree.tscn` = Phase 4 done
- `scripts/ai/ai_controller.gd` = Phase 6 done
- `scripts/systems/victory_system.gd` = Phase 7 done
- `scripts/systems/save_system.gd` = Phase 8 done

---

## Common Tasks

### Adding a new unit type
1. Add entry to `data/units.json`
2. DataManager will auto-load it

### Adding a new building
1. Add entry to `data/buildings.json` with effects
2. DataManager handles loading

### Modifying terrain generation
- Edit `scripts/map/game_grid.gd`
- Adjust noise parameters or `_determine_terrain()` logic

### Adding UI elements
- Create scene in `scenes/` or script in `scripts/ui/`
- Connect to EventBus signals for updates

---

## Key Architecture Notes

### Coordinate System
- Uses **square grid** with 8-directional movement (not hex despite some naming)
- Tile size: 64x64 pixels
- Map wraps on X-axis (cylindrical), not Y-axis
- Conversion: `GridUtils.grid_to_pixel()` / `GridUtils.pixel_to_grid()`

### Event-Driven Architecture
All game events flow through `EventBus` singleton:
- UI subscribes to events for updates
- Systems emit events when state changes
- Decoupled communication between components

### Data-Driven Design
All game data in JSON files (`data/` directory):
- Units, buildings, techs defined externally
- Easy to mod without code changes
- DataManager provides typed accessors

### Turn Processing Order
1. `turn_started` signal emitted
2. Unit movement refreshed
3. Cities process: yields → growth → production → culture
4. Research progress updated
5. AI executes (if not human)
6. Player acts
7. `turn_ended` signal emitted
8. Units heal
9. Next player (or `all_turns_completed` if round done)
