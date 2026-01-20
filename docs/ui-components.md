# User Interface Components

This document covers all UI screens and components in KulturIV.

## UI Architecture

### Design Principles

1. **Programmatic UI**: Most UI is built in code using `_build_ui()` rather than scene files
2. **Event-Driven**: UI responds to EventBus signals
3. **Overlay Pattern**: Modal screens use semi-transparent overlays
4. **Consistent Styling**: Common StyleBoxFlat patterns for panels

### Standard UI Pattern

All major UI screens follow this pattern:

```gdscript
extends Control

# UI element references
var panel: PanelContainer
var close_button: Button

func _ready() -> void:
    _build_ui()           # Create UI elements
    visible = false       # Start hidden
    _connect_signals()    # Subscribe to EventBus

func _build_ui() -> void:
    # Create overlay
    var overlay = ColorRect.new()
    overlay.color = Color(0, 0, 0, 0.6)
    overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(overlay)

    # Create centered panel
    var center = CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    panel = PanelContainer.new()
    panel.custom_minimum_size = Vector2(800, 600)
    # ... style and content ...
    center.add_child(panel)

func _connect_signals() -> void:
    EventBus.show_my_screen.connect(_on_show)

func _on_show() -> void:
    _refresh_display()
    visible = true

func _on_close() -> void:
    visible = false

func _input(event: InputEvent) -> void:
    if visible and event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            _on_close()
            get_viewport().set_input_as_handled()
```

---

## Main UI Screens

### Game UI (`game_ui.gd`)

The persistent in-game interface showing vital information.

**Location**: `scripts/ui/game_ui.gd`

**Components**:
- **Top Bar**: Turn, gold, science, research progress
- **Unit Panel**: Selected unit info and actions
- **End Turn Button**: Advances the game
- **Notification Area**: Toast messages

**Key Signals**:
```gdscript
EventBus.turn_started.connect(_on_turn_started)
EventBus.unit_selected.connect(_on_unit_selected)
EventBus.notification_added.connect(_on_notification_added)
```

**Notification Types**:
| Type | Color |
|------|-------|
| `tech` | Cyan |
| `city` | Green |
| `production` | Yellow |
| `combat` | Orange Red |
| `diplomacy` | Medium Purple |
| `espionage` | Slate Gray |
| `event` | Orange |
| `victory` | Gold |

---

### City Screen (`city_screen.gd`)

Manages city production, buildings, and citizens.

**Location**: `scripts/ui/city_screen.gd`
**Scene**: `scenes/ui/city_screen.tscn`

**Features**:
- City stats (population, food, production, commerce)
- Production queue management
- Building list
- Citizen assignment (worked tiles, specialists)

**Opening**:
```gdscript
EventBus.show_city_screen.emit(city)
```

**Key Elements**:
```
┌────────────────────────────────────────────────────┐
│  [City Name]                              [Close]  │
├─────────────────────┬──────────────────────────────┤
│                     │  Production Queue            │
│   City Tile View    │  ─────────────────           │
│   (worked tiles)    │  [Building units...]         │
│                     │                              │
├─────────────────────┼──────────────────────────────┤
│  Stats:             │  Buildings:                  │
│  Pop: 5             │  • Granary                   │
│  Food: +3           │  • Library                   │
│  Prod: 8            │  • Barracks                  │
│  Comm: 12           │                              │
├─────────────────────┴──────────────────────────────┤
│  [Change Production]  [Buy]  [Specialists]         │
└────────────────────────────────────────────────────┘
```

---

### Tech Tree (`tech_tree.gd`)

Displays the technology tree and current research.

**Location**: `scripts/ui/tech_tree.gd`
**Scene**: `scenes/ui/tech_tree.tscn`

**Features**:
- Visual tech tree with connections
- Era grouping
- Research selection
- Tech prerequisites highlighting

**Opening**:
```gdscript
EventBus.show_tech_tree.emit()
# or press 'T' key
```

**Tech Node Colors**:
| State | Color |
|-------|-------|
| Researched | Green |
| Available | White |
| Locked | Gray |
| Researching | Yellow |

---

### Diplomacy Screen (`diplomacy_screen.gd`)

Manages relations with other civilizations.

**Location**: `scripts/ui/diplomacy_screen.gd`
**Scene**: `scenes/ui/diplomacy_screen.tscn`

**Features**:
- Leader list with attitudes
- Relationship breakdown
- Treaty management
- Trade proposal button

**Opening**:
```gdscript
EventBus.show_diplomacy_screen.emit()
# or press 'D' key
```

**Attitude Levels**:
| Level | Color |
|-------|-------|
| Friendly | Green |
| Pleased | Light Green |
| Cautious | Yellow |
| Annoyed | Orange |
| Furious | Red |

---

### Trade Screen (`trade_screen.gd`)

Handles resource and technology trading.

**Location**: `scripts/ui/trade_screen.gd`
**Scene**: `scenes/ui/trade_screen.tscn`

**Features**:
- Two-column offer/demand layout
- Gold, gold per turn trading
- Resource trading
- Technology trading
- Deal evaluation

**Layout**:
```
┌────────────────────────────────────────────────────┐
│              Trade with [Civilization]             │
├───────────────────────┬────────────────────────────┤
│    We Offer:          │     They Offer:            │
│    ───────────        │     ────────────           │
│    □ 100 Gold         │     □ Iron                 │
│    □ 10 Gold/turn     │     □ Writing Tech         │
│    □ Horses           │     □ 5 Gold/turn          │
│                       │                            │
├───────────────────────┴────────────────────────────┤
│  [Clear]  [Propose]  [Cancel]                      │
└────────────────────────────────────────────────────┘
```

---

### Civics Screen (`civics_screen.gd`)

Manages government policies.

**Location**: `scripts/ui/civics_screen.gd`
**Scene**: `scenes/ui/civics_screen.tscn`

**Features**:
- Five civic categories
- Current and available civics
- Effect descriptions
- Anarchy preview

**Opening**:
```gdscript
EventBus.show_civics_screen.emit()
# or press 'C' key
```

---

### Event Popup (`event_popup.gd`)

Displays random events with choices.

**Location**: `scripts/ui/event_popup.gd`

**Features**:
- Category-colored header
- Event description
- Choice buttons with effect tooltips
- Number keys for quick selection

**Triggering**:
```gdscript
EventBus.random_event_triggered.emit(event_data)
```

**Event Data Structure**:
```gdscript
{
    "name": "Gold Discovery",
    "category": "discovery",
    "description": "Prospectors found gold!",
    "choices": [
        {
            "text": "Mine it!",
            "effects": { "gold": 100 }
        }
    ]
}
```

---

### Espionage Screen (`espionage_screen.gd`)

Manages spy missions against rivals.

**Location**: `scripts/ui/espionage_screen.gd`

**Features**:
- Target civilization list with EP
- Mission panels with stats
- Cost/success/discovery display
- Execute button

**Opening**:
```gdscript
EventBus.show_espionage_screen.emit()
```

**Layout**:
```
┌────────────────────────────────────────────────────┐
│  Espionage                                [Close]  │
├─────────────────────┬──────────────────────────────┤
│  Target Civs        │  Available Missions          │
│  ───────────        │  ─────────────────           │
│  • Rome (150 EP)    │  ┌──────────────────────┐    │
│  • Egypt (80 EP)    │  │ Steal Technology     │    │
│  • China (45 EP)    │  │ Cost: 600  Success: 35%   │
│                     │  │ Discovery: 70%       │    │
│  Total EP: 275      │  │ [Execute]            │    │
│                     │  └──────────────────────┘    │
└─────────────────────┴──────────────────────────────┘
```

---

### Spaceship Screen (`spaceship_screen.gd`)

Shows space race progress.

**Location**: `scripts/ui/spaceship_screen.gd`

**Features**:
- Visual ship representation
- Part completion status
- Launch button (when ready)
- Travel time estimate

**Opening**:
```gdscript
EventBus.show_spaceship_screen.emit()
```

**Part Display**:
| Part | Icon | Color |
|------|------|-------|
| Cockpit | C | Cyan |
| Life Support | L | Green |
| Stasis Chamber | S | Purple |
| Docking Bay | D | Orange |
| Engine | E | Red |
| Casing | H | Silver |
| Thrusters | T | Yellow |

---

### Voting Screen (`voting_screen.gd`)

Handles UN and Apostolic Palace voting.

**Location**: `scripts/ui/voting_screen.gd`

**Features**:
- Tabbed interface (UN / Apostolic Palace)
- Secretary General / Resident info
- Available resolutions
- Active resolutions list
- Voting interface

**Opening**:
```gdscript
EventBus.show_voting_screen.emit()
```

---

### Victory Screen (`victory_screen.gd`)

Displays victory or defeat.

**Location**: `scripts/ui/victory_screen.gd`
**Scene**: `scenes/ui/victory_screen.tscn`

**Features**:
- Victory type announcement
- Final score
- Game statistics
- Replay option (planned)

---

## UI Styling Guide

### Panel Style

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

### Button Style

```gdscript
var btn_style = StyleBoxFlat.new()
btn_style.bg_color = Color(0.25, 0.25, 0.3)
btn_style.corner_radius_top_left = 4
btn_style.corner_radius_top_right = 4
btn_style.corner_radius_bottom_left = 4
btn_style.corner_radius_bottom_right = 4
button.add_theme_stylebox_override("normal", btn_style)

var hover_style = btn_style.duplicate()
hover_style.bg_color = Color(0.35, 0.35, 0.45)
button.add_theme_stylebox_override("hover", hover_style)
```

### Font Sizes

| Usage | Size |
|-------|------|
| Title | 24-26 |
| Header | 16-18 |
| Body | 14 |
| Small | 11-12 |

### Colors

| Purpose | Color |
|---------|-------|
| Title | `Color.LIGHT_BLUE` |
| Positive | `Color.LIGHT_GREEN` |
| Negative | `Color.RED` |
| Warning | `Color.YELLOW` |
| Disabled | `Color.GRAY` |

---

## Creating New UI Screens

### Step 1: Create the Script

```gdscript
extends Control
## Description of the screen

signal some_action(data)

var panel: PanelContainer
var close_button: Button

func _ready() -> void:
    _build_ui()
    visible = false
    EventBus.show_my_screen.connect(_on_show)

func _build_ui() -> void:
    # Build UI programmatically
    pass

func _on_show(data = null) -> void:
    _refresh_display(data)
    visible = true

func _on_close() -> void:
    visible = false

func _input(event: InputEvent) -> void:
    if visible and event is InputEventKey and event.pressed:
        if event.keycode == KEY_ESCAPE:
            _on_close()
            get_viewport().set_input_as_handled()
```

### Step 2: Add EventBus Signal

```gdscript
# In event_bus.gd
signal show_my_screen(optional_data)
signal hide_my_screen()
```

### Step 3: Register in Game Scene

```gdscript
# In game.gd
func _setup_ui_screens() -> void:
    var MyScreenScript = load("res://scripts/ui/my_screen.gd")
    if MyScreenScript:
        var screen = Control.new()
        screen.set_script(MyScreenScript)
        screen.name = "MyScreen"
        add_child(screen)
```

### Step 4: Add Button (Optional)

```gdscript
# In game_ui.gd
@onready var my_button: Button = $TopBar/HBoxContainer/MyButton

func _ready() -> void:
    if my_button:
        my_button.pressed.connect(_on_my_button_pressed)

func _on_my_button_pressed() -> void:
    EventBus.show_my_screen.emit()
```
