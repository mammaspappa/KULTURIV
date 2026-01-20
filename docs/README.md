# KulturIV Documentation

Welcome to the KulturIV documentation. This guide covers the architecture, systems, and implementation details of this Civilization IV: Beyond the Sword clone built in Godot 4.2.

## Table of Contents

1. [Getting Started](getting-started.md)
2. [Architecture Overview](architecture.md)
3. [Core Systems](systems/README.md)
4. [Game Data](data-files.md)
5. [User Interface](ui-components.md)
6. [AI System](ai-system.md)
7. [Modding Guide](modding-guide.md)
8. [API Reference](api-reference.md)

## Quick Overview

KulturIV is a turn-based 4X strategy game that faithfully recreates the mechanics of Civilization IV: Beyond the Sword. Players lead a civilization from ancient times to the space age, competing against AI opponents through military conquest, cultural dominance, scientific achievement, or diplomatic victory.

### Key Features

- **18 Civilizations** with unique leaders and traits
- **90+ Technologies** across 7 eras
- **150+ Units** from Warriors to Modern Armor
- **200+ Buildings** including World Wonders
- **7 Religions** with spreading mechanics
- **25 Civics** across 5 categories
- **7 Corporations** (Beyond the Sword feature)
- **Full Espionage System** with 15 missions
- **Random Events** that add variety
- **UN/Apostolic Palace Voting** for diplomatic victory
- **Space Race** victory condition

### Technology Stack

- **Engine**: Godot 4.2 with GDScript
- **Renderer**: Forward Plus
- **Data Format**: JSON for all game configuration
- **Architecture**: Event-driven with autoload singletons

## Project Structure

```
KULTURIV/
├── data/                    # Game data (JSON files)
├── docs/                    # Documentation (you are here)
├── scenes/                  # Godot scene files (.tscn)
│   ├── main/               # Main menu and game scenes
│   └── ui/                 # UI component scenes
├── scripts/                 # GDScript source files
│   ├── autoload/           # Singleton managers
│   ├── core/               # Core game classes
│   ├── entities/           # Game entities (Unit, City)
│   ├── map/                # Map and grid utilities
│   ├── systems/            # Game systems
│   ├── ui/                 # UI scripts
│   └── ai/                 # AI controller
├── beyond/                  # Original Civ4 reference files (read-only)
├── CLAUDE.md               # Development guidelines
└── PROJECT_PLAN.md         # Implementation roadmap
```

## Design Philosophy

KulturIV follows several key design principles:

1. **Data-Driven Design**: All game content is defined in JSON files, making it easy to modify without touching code.

2. **Event-Driven Architecture**: Game systems communicate through a central EventBus, keeping components decoupled and maintainable.

3. **Faithful Recreation**: We aim to match Civilization IV's mechanics as closely as possible, using the original XML files as reference.

4. **Extensibility**: The architecture supports modding and customization through JSON data files and the event system.

## Getting Help

- Check the [Getting Started](getting-started.md) guide for setup instructions
- Read the [Architecture Overview](architecture.md) to understand the codebase
- See the [Modding Guide](modding-guide.md) for customization options
- Review the [API Reference](api-reference.md) for function documentation

## Contributing

See `CLAUDE.md` in the project root for development guidelines and coding standards.
