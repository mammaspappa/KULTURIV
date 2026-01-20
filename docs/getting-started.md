# Getting Started

This guide will help you set up the KulturIV development environment and understand the basics of the codebase.

## Prerequisites

- **Godot 4.2** or later (download from [godotengine.org](https://godotengine.org))
- **Git** for version control
- A code editor (VS Code with Godot extensions recommended)

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/mammaspappa/KULTURIV.git
cd KULTURIV
```

### 2. Open in Godot

1. Launch Godot 4.2+
2. Click "Import" in the Project Manager
3. Navigate to the KULTURIV folder and select `project.godot`
4. Click "Import & Edit"

### 3. Run the Game

Press F5 or click the Play button to run the game. The main menu will appear.

## Project Layout

```
KULTURIV/
├── data/                    # JSON game data files
│   ├── units.json          # Unit definitions
│   ├── buildings.json      # Building definitions
│   ├── techs.json          # Technology tree
│   └── ...                 # Other data files
├── scenes/
│   ├── main/
│   │   ├── main_menu.tscn  # Main menu scene
│   │   ├── main_menu.gd    # Main menu script
│   │   ├── game.tscn       # Main game scene
│   │   └── game.gd         # Main game script
│   └── ui/                 # UI component scenes
├── scripts/
│   ├── autoload/           # Singleton managers
│   ├── core/               # Core game classes
│   ├── entities/           # Unit, City, Player classes
│   ├── map/                # Grid and pathfinding
│   ├── systems/            # Game systems
│   ├── ui/                 # UI scripts
│   └── ai/                 # AI controller
└── beyond/                 # Civ4 reference files (read-only)
```

## Understanding the Code

### Entry Points

1. **Main Menu**: `scenes/main/main_menu.tscn`
   - Handles new game setup, load game, settings

2. **Game Scene**: `scenes/main/game.tscn`
   - Contains the game world and UI
   - Entry point for gameplay

### Key Files to Read First

1. **EventBus** (`scripts/autoload/event_bus.gd`)
   - All game events are defined here
   - Read this to understand what events exist

2. **GameManager** (`scripts/autoload/game_manager.gd`)
   - Central game state
   - Player management

3. **Unit** (`scripts/entities/unit.gd`)
   - How units work (movement, combat, abilities)

4. **City** (`scripts/entities/city.gd`)
   - How cities work (production, growth, buildings)

## Making Changes

### Adding a New Unit

1. Open `data/units.json`
2. Add a new entry:
```json
{
  "my_unit": {
    "name": "My Custom Unit",
    "combat": 5,
    "moves": 2,
    "cost": 40,
    "tech_required": "bronze_working"
  }
}
```
3. The unit is now available in the game!

### Adding a New Building

1. Open `data/buildings.json`
2. Add a new entry:
```json
{
  "my_building": {
    "name": "My Building",
    "cost": 100,
    "effects": {
      "happiness": 2,
      "culture_per_turn": 3
    },
    "tech_required": "writing"
  }
}
```

### Modifying Game Logic

1. Find the relevant system in `scripts/systems/`
2. Make your changes
3. Test thoroughly

### Creating a New System

1. Create a new file in `scripts/systems/`:
```gdscript
extends Node
## Description of your system

func _ready() -> void:
    _load_data()
    _connect_signals()

func _load_data() -> void:
    # Load JSON data if needed
    pass

func _connect_signals() -> void:
    # Connect to EventBus signals
    EventBus.turn_started.connect(_on_turn_started)

func _on_turn_started(turn: int, player) -> void:
    # Handle turn start
    pass

# Serialization for save/load
func to_dict() -> Dictionary:
    return {}

func from_dict(data: Dictionary) -> void:
    pass
```

2. Register it as an autoload in `project.godot`:
```ini
[autoload]
...
MySystem="*res://scripts/systems/my_system.gd"
```

## Common Tasks

### Running the Game from Command Line

```bash
godot --path /path/to/KULTURIV --main-scene scenes/main/main_menu.tscn
```

### Exporting the Game

1. Go to Project → Export
2. Add a preset for your platform
3. Configure export settings
4. Click Export Project

### Finding Code

Use Godot's built-in search (Ctrl+Shift+F) or your editor's search:

- **Find a function**: Search for `func function_name`
- **Find a signal**: Look in `scripts/autoload/event_bus.gd`
- **Find data**: Check the appropriate JSON file in `data/`

## Debugging

### Print Debugging

```gdscript
print("Variable value: ", variable)
push_warning("This might be a problem")
push_error("This is definitely wrong")
```

### Godot Debugger

1. Set breakpoints by clicking in the gutter
2. Run with F5
3. Use the Debugger panel to inspect variables

### Common Issues

**"Class not found" errors**
- Check the autoload order in project.godot
- Ensure the class_name is defined

**UI not showing**
- Check that `visible = true` is set
- Verify EventBus signal connections

**Data not loading**
- Check JSON syntax (use a validator)
- Check file paths are correct

## Testing Your Changes

1. Run the game (F5)
2. Start a new game
3. Test your changes manually
4. Check the Output panel for errors

## Next Steps

- Read the [Architecture Overview](architecture.md) for deeper understanding
- Check the [Systems Documentation](systems/README.md) for specific systems
- Review the [Modding Guide](modding-guide.md) for customization
- See the [API Reference](api-reference.md) for function documentation
