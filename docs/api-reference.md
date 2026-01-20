# API Reference

This document provides a reference for the key classes and functions in KulturIV.

---

## Autoload Singletons

### EventBus

**File**: `scripts/autoload/event_bus.gd`

Global signal hub for event-driven communication.

#### Signals

**Turn Events**
```gdscript
signal turn_started(turn_number: int, player: Player)
signal turn_ended(turn_number: int, player: Player)
signal all_turns_completed(turn_number: int)
```

**Unit Events**
```gdscript
signal unit_created(unit: Unit)
signal unit_destroyed(unit: Unit)
signal unit_selected(unit: Unit)
signal unit_deselected(unit: Unit)
signal unit_moved(unit: Unit, from_hex: Vector2i, to_hex: Vector2i)
signal unit_attacked(attacker: Unit, defender: Unit)
signal unit_promoted(unit: Unit, promotion: String)
```

**City Events**
```gdscript
signal city_founded(city: City, founder: Player)
signal city_captured(city: City, old_owner: Player, new_owner: Player)
signal city_grew(city: City, new_population: int)
signal city_production_completed(city: City, item: String)
signal city_building_constructed(city: City, building: String)
```

**Combat Events**
```gdscript
signal combat_started(attacker: Unit, defender: Unit)
signal combat_ended(winner: Unit, loser: Unit)
signal first_strike(attacker: Unit, defender: Unit, damage: int)
```

**Research Events**
```gdscript
signal research_started(player: Player, tech: String)
signal research_completed(player: Player, tech: String)
```

**UI Events**
```gdscript
signal show_city_screen(city: City)
signal show_tech_tree()
signal show_diplomacy_screen()
signal show_civics_screen()
signal show_espionage_screen()
signal show_voting_screen()
signal show_spaceship_screen()
signal notification_added(message: String, type: String)
```

---

### DataManager

**File**: `scripts/autoload/data_manager.gd`

Loads and provides access to game data from JSON files.

#### Methods

```gdscript
# Unit data
func get_unit(unit_id: String) -> Dictionary
func get_all_units() -> Dictionary

# Building data
func get_building(building_id: String) -> Dictionary
func get_all_buildings() -> Dictionary

# Technology data
func get_tech(tech_id: String) -> Dictionary
func get_all_techs() -> Dictionary
func get_tech_cost(tech_id: String) -> int

# Civilization data
func get_civ(civ_id: String) -> Dictionary
func get_leader(leader_id: String) -> Dictionary

# Map data
func get_terrain(terrain_id: String) -> Dictionary
func get_feature(feature_id: String) -> Dictionary
func get_resource(resource_id: String) -> Dictionary
func get_improvement(improvement_id: String) -> Dictionary

# Other data
func get_religion(religion_id: String) -> Dictionary
func get_civic(civic_id: String) -> Dictionary
func get_promotion(promotion_id: String) -> Dictionary
func get_corporation(corp_id: String) -> Dictionary
func get_espionage_mission(mission_id: String) -> Dictionary
func get_project(project_id: String) -> Dictionary
func get_event(event_id: String) -> Dictionary
func get_vote_resolution(resolution_id: String) -> Dictionary
```

---

### GameManager

**File**: `scripts/autoload/game_manager.gd`

Central game state management.

#### Properties

```gdscript
var human_player: Player          # The human-controlled player
var hex_grid: GameGrid            # The map
var map_width: int                # Map width in tiles
var map_height: int               # Map height in tiles
var difficulty: int               # Difficulty level (0-8)
var game_speed: String            # "quick", "normal", "epic", "marathon"
var nukes_banned: bool            # Whether nuclear weapons are banned
```

#### Methods

```gdscript
func get_player(player_id: int) -> Player
func get_all_players() -> Array[Player]
func get_speed_multiplier() -> float
func is_tile_visible(pos: Vector2i, player: Player) -> bool
```

---

### TurnManager

**File**: `scripts/autoload/turn_manager.gd`

Handles turn-based game flow.

#### Properties

```gdscript
var current_turn: int             # Current turn number
var current_player: Player        # Whose turn it is
var year: int                     # Current game year
```

#### Methods

```gdscript
func end_turn() -> void           # End current player's turn
func get_year_string() -> String  # Returns "4000 BC", "1990 AD", etc.
func get_era() -> String          # Returns current era
```

---

## Game Entities

### Player

**File**: `scripts/core/player.gd`

Represents a civilization.

#### Properties

```gdscript
var player_id: int
var civilization_id: String
var leader_id: String
var is_human: bool
var gold: int
var gold_per_turn: int
var research_progress: int
var current_research: String
var cities: Array[City]
var units: Array[Unit]
var known_techs: Array[String]
var met_players: Array[int]
var state_religion: String
```

#### Methods

```gdscript
func has_tech(tech_id: String) -> bool
func add_tech(tech_id: String) -> void
func get_relationship(other_player_id: int) -> String
func set_relationship(other_player_id: int, state: String) -> void
func is_at_war_with(other_player_id: int) -> bool
func declare_war_on(other_player_id: int) -> void
func make_peace_with(other_player_id: int) -> void
func add_gold(amount: int) -> void
func can_afford(amount: int) -> bool
```

---

### Unit

**File**: `scripts/entities/unit.gd`

Represents a military or civilian unit.

#### Properties

```gdscript
var unit_id: String
var player_owner: Player
var grid_position: Vector2i
var health: int
var max_health: int
var movement_remaining: float
var experience: int
var has_acted: bool
var is_fortified: bool
var promotions: Array[String]
```

#### Methods

```gdscript
func get_strength() -> float
func get_base_movement() -> int
func can_move_to(pos: Vector2i) -> bool
func move_to(pos: Vector2i) -> bool
func attack(target: Unit) -> Dictionary
func fortify() -> void
func skip_turn() -> void
func heal(amount: int) -> void
func add_experience(xp: int) -> void
func add_promotion(promotion_id: String) -> void
func has_ability(ability: String) -> bool
func has_promotion(promotion_id: String) -> bool
func get_first_strikes() -> int
func get_withdraw_chance() -> float
func get_fortification_bonus() -> float
```

---

### City

**File**: `scripts/entities/city.gd`

Represents a city.

#### Properties

```gdscript
var city_name: String
var player_owner: Player
var grid_position: Vector2i
var population: int
var food_stored: float
var production_queue: Array[String]
var production_progress: float
var culture_total: int
var culture_level: int
var buildings: Array[String]
var religions: Array[String]
var specialists: Dictionary
```

#### Methods

```gdscript
func get_food_yield() -> int
func get_production_yield() -> int
func get_commerce_yield() -> int
func get_culture_per_turn() -> int
func get_happiness() -> int
func get_health() -> int
func has_building(building_id: String) -> bool
func add_building(building_id: String) -> void
func has_religion(religion_id: String) -> bool
func add_religion(religion_id: String) -> void
func set_production(item: String) -> void
func get_production_turns(item: String) -> int
func buy_current_production() -> bool
func can_produce(item: String) -> bool
```

---

### GameTile

**File**: `scripts/map/game_tile.gd`

Represents a map tile.

#### Properties

```gdscript
var grid_position: Vector2i
var terrain_type: String
var feature: String
var resource: String
var improvement: String
var road_level: int                # 0=none, 1=road, 2=railroad
var tile_owner: Player
var worked_by_city: City
```

#### Methods

```gdscript
func get_movement_cost(unit: Unit) -> float
func get_defense_bonus() -> float
func get_food_yield() -> int
func get_production_yield() -> int
func get_commerce_yield() -> int
func can_have_improvement(improvement: String) -> bool
func set_improvement(improvement: String) -> void
func is_visible_to(player: Player) -> bool
func is_revealed_to(player: Player) -> bool
```

---

## Game Systems

### CombatSystem

**File**: `scripts/systems/combat_system.gd`

```gdscript
func can_attack(attacker: Unit, defender: Unit) -> bool
func calculate_combat_odds(attacker: Unit, defender: Unit) -> Dictionary
func attack(attacker: Unit, defender: Unit) -> Dictionary
func calculate_damage(attacker: Unit, defender: Unit) -> Dictionary
```

---

### ImprovementSystem

**File**: `scripts/systems/improvement_system.gd`

```gdscript
func can_build(worker: Unit, improvement: String, tile: GameTile) -> bool
func start_build(worker: Unit, improvement: String) -> void
func get_build_time(improvement: String, worker: Unit) -> int
func complete_improvement(tile: GameTile, improvement: String) -> void
```

---

### ReligionSystem

**File**: `scripts/systems/religion_system.gd`

```gdscript
func found_religion(religion_id: String, city: City, player: Player) -> void
func spread_religion(religion_id: String, city: City) -> bool
func get_holy_city(religion_id: String) -> City
func set_state_religion(player: Player, religion_id: String) -> void
```

---

### CivicsSystem

**File**: `scripts/systems/civics_system.gd`

```gdscript
func get_current_civic(player: Player, category: String) -> String
func can_adopt_civic(player: Player, civic_id: String) -> bool
func change_civic(player_id: int, category: String, civic_id: String) -> void
func get_civic_effects(player: Player) -> Dictionary
func get_anarchy_turns(player: Player, changes: Array) -> int
```

---

### DiplomacySystem

**File**: `scripts/systems/diplomacy_system.gd`

```gdscript
func get_attitude(from_player: Player, to_player_id: int) -> int
func get_attitude_breakdown(from: Player, to: Player) -> Dictionary
func add_memory(player_id: int, target_id: int, type: String, amount: int, duration: int) -> void
func get_memories(player_id: int, target_id: int) -> Array
```

---

### TradeSystem

**File**: `scripts/systems/trade_system.gd`

```gdscript
func propose_trade(from: Player, to: Player, offer: Dictionary, demand: Dictionary) -> bool
func evaluate_trade(evaluator: Player, offer: Dictionary, demand: Dictionary) -> float
func execute_trade(from: Player, to: Player, offer: Dictionary, demand: Dictionary) -> void
```

---

### EspionageSystem

**File**: `scripts/systems/espionage_system.gd`

```gdscript
func get_espionage_points(player_id: int, target_id: int) -> int
func calculate_mission_cost(mission_id: String, player, target, city) -> int
func execute_mission(mission_id: String, player, target, city, building: String = "") -> Dictionary
func get_all_missions() -> Dictionary
func is_counter_espionage_active(player_id: int) -> bool
```

---

### ProjectsSystem

**File**: `scripts/systems/projects_system.gd`

```gdscript
func can_build_project(player: Player, project_id: String) -> bool
func complete_project(player_id: int, project_id: String, city: City) -> void
func get_spaceship_status(player_id: int) -> Dictionary
func launch_spaceship(player_id: int) -> bool
func is_project_completed(project_id: String) -> bool
```

---

### EventsSystem

**File**: `scripts/systems/events_system.gd`

```gdscript
func trigger_event(player: Player, event_id: String) -> void
func process_event_choice(event_data: Dictionary, choice_index: int) -> Dictionary
func get_available_events(player: Player) -> Array
```

---

### VotingSystem

**File**: `scripts/systems/voting_system.gd`

```gdscript
func is_vote_source_active(source_id: String) -> bool
func get_vote_power(player_id: int, source_id: String) -> int
func get_total_votes(source_id: String) -> int
func get_vote_leader(source_id: String) -> int
func start_vote(source_id: String, resolution_id: String, proposer_id: int, target = null) -> void
func cast_vote(player_id: int, vote_for: bool) -> void
func get_available_resolutions(source_id: String) -> Array
func get_active_resolutions(source_id: String) -> Array
```

---

### VictorySystem

**File**: `scripts/systems/victory_system.gd`

```gdscript
func check_victory_conditions() -> Dictionary
func check_domination_victory(player: Player) -> bool
func check_conquest_victory(player: Player) -> bool
func check_cultural_victory(player: Player) -> bool
func check_space_victory(player: Player) -> bool
func check_diplomatic_victory(player_id: int) -> bool
func check_time_victory() -> Player
func get_player_score(player: Player) -> int
```

---

### SaveSystem

**File**: `scripts/systems/save_system.gd`

```gdscript
func save_game(slot: String) -> bool
func load_game(slot: String) -> bool
func get_save_slots() -> Array
func delete_save(slot: String) -> bool
func get_save_info(slot: String) -> Dictionary
```

---

## Utility Classes

### GridUtils

**File**: `scripts/map/grid_utils.gd`

```gdscript
const TILE_SIZE: int = 64

static func grid_to_pixel(grid_pos: Vector2i) -> Vector2
static func pixel_to_grid(pixel_pos: Vector2) -> Vector2i
static func get_neighbors(pos: Vector2i) -> Array[Vector2i]
static func get_distance(from: Vector2i, to: Vector2i) -> int
static func wrap_x(x: int, map_width: int) -> int
```

---

### Pathfinding

**File**: `scripts/map/pathfinding.gd`

```gdscript
func find_path(from: Vector2i, to: Vector2i, unit: Unit) -> Array[Vector2i]
func get_reachable_tiles(unit: Unit, range: float) -> Array[Vector2i]
func get_movement_cost(from: Vector2i, to: Vector2i, unit: Unit) -> float
```

---

## Serialization

All major classes implement:

```gdscript
func to_dict() -> Dictionary    # Convert to serializable dictionary
func from_dict(data: Dictionary) -> void  # Restore from dictionary
```

Example:
```gdscript
# Saving
var unit_data = unit.to_dict()
var json_string = JSON.stringify(unit_data)

# Loading
var data = JSON.parse_string(json_string)
unit.from_dict(data)
```
