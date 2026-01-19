# KulturIV Project Plan

A Civilization IV: Beyond the Sword clone built in Godot 4.2.

## Project Status Overview

| Category | Status | Progress |
|----------|--------|----------|
| Core Engine | Complete | 100% |
| Map System | Complete | 100% |
| Units | Partial | 70% |
| Cities | Partial | 85% |
| Combat | Complete | 100% |
| AI | Basic | 40% |
| UI | Partial | 50% |
| Diplomacy | Basic | 60% |
| Religion | Basic | 70% |
| Victory Conditions | Complete | 100% |
| Civics | Complete | 100% |
| Corporations | Not Started | 0% |
| Espionage | Not Started | 0% |
| Events | Not Started | 0% |
| Multiplayer | Not Started | 0% |

---

## Phase 1: Core Engine (COMPLETE)

### Implemented
- [x] Project structure with autoload singletons
- [x] Event-driven architecture via EventBus
- [x] JSON-based data loading (DataManager)
- [x] Game state management (GameManager)
- [x] Turn processing framework (TurnManager)
- [x] Save/Load system with JSON serialization

### Files
- `scripts/autoload/event_bus.gd`
- `scripts/autoload/data_manager.gd`
- `scripts/autoload/game_manager.gd`
- `scripts/autoload/turn_manager.gd`
- `scripts/systems/save_system.gd`
- `scripts/core/game_state.gd`

---

## Phase 2: Map System (COMPLETE)

### Implemented
- [x] Square grid with 8-directional movement
- [x] Noise-based terrain generation
- [x] Terrain types (grassland, plains, desert, tundra, snow, coast, ocean, hills, mountains)
- [x] Map features (forest, jungle, oasis, flood plains, ice)
- [x] Resources (strategic, luxury, bonus)
- [x] Tile improvements (farm, mine, cottage, road, railroad, etc.)
- [x] Fog of war and visibility system
- [x] Cylindrical map wrapping (X-axis)
- [x] A* pathfinding

### Files
- `scripts/map/grid_utils.gd`
- `scripts/map/game_grid.gd`
- `scripts/map/game_tile.gd`
- `scripts/map/pathfinding.gd`

### Data Files
- `data/terrains.json`
- `data/features.json`
- `data/resources.json`
- `data/improvements.json`

---

## Phase 3: Units (70% COMPLETE)

### Implemented
- [x] Unit class with movement, stats, abilities
- [x] Unit types across all eras (ancient to future)
- [x] Combat stats (strength, first strikes, withdraw chance)
- [x] Movement costs and terrain modifiers
- [x] Promotion system with prerequisites
- [x] Unit orders (fortify, sleep, sentry, heal, explore)
- [x] Great People units (Prophet, Artist, Scientist, Merchant, Engineer, General)
- [x] Special abilities (found_city, build_improvements, transport, bombard, etc.)
- [x] Unit upgrade paths
- [x] Experience and leveling

### Not Implemented
- [ ] Air units combat system (interception, air superiority, bombing runs)
- [ ] Naval transport loading/unloading
- [ ] Nuclear weapons effects (fallout, population kill)
- [ ] Unit formations and army groups
- [ ] Unique unit abilities per civilization
- [ ] Worker automation AI
- [ ] Explorer automation

### Files
- `scripts/entities/unit.gd`
- `data/units.json`
- `data/promotions.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/Units/CIV4UnitInfos.xml` - 150+ unit types
- `beyond/Beyond the Sword/Assets/XML/Units/CIV4PromotionInfos.xml` - 50+ promotions
- `beyond/Beyond the Sword/Assets/XML/Units/CIV4SpecialUnitInfos.xml` - Special unit categories

---

## Phase 4: Cities (75% COMPLETE)

### Implemented
- [x] City class with production, growth, buildings
- [x] Population and food mechanics
- [x] Production queue system
- [x] Building construction with effects
- [x] Culture generation and border expansion
- [x] Tile working radius
- [x] City health and happiness
- [x] Maintenance costs
- [x] Specialists (citizens, scientists, merchants, engineers, artists, priests, spies)
- [x] Specialist slots from buildings
- [x] Great People points per specialist
- [x] Specialist yields and commerces
- [x] Civic-based specialist bonuses (Representation, Caste System, Mercantilism)
- [x] Settled Great People specialists

### Not Implemented
- [ ] City governor automation
- [ ] Conscription
- [ ] City trading (culture flip risk)
- [ ] Wonder movies/effects
- [ ] National wonders vs World wonders limits

### Files
- `scripts/entities/city.gd`
- `data/buildings.json`
- `data/specialists.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/Buildings/CIV4BuildingInfos.xml` - 200+ buildings
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4SpecialistInfos.xml` - Specialist types

---

## Phase 5: Combat System (COMPLETE)

### Implemented
- [x] Attack resolution with odds calculation
- [x] Damage calculation based on strength ratio
- [x] Terrain defense bonuses
- [x] Fortification bonuses
- [x] First strike system
- [x] Withdraw mechanics
- [x] Experience gain from combat
- [x] Collateral damage (siege units)
- [x] City combat modifiers

### Files
- `scripts/systems/combat_system.gd`

---

## Phase 6: Technology (80% COMPLETE)

### Implemented
- [x] Tech tree with prerequisites (AND/OR logic)
- [x] Research points per turn
- [x] Tech costs by era
- [x] Tech unlocks (units, buildings, improvements)
- [x] Civilization starting techs
- [x] Tech trading framework

### Not Implemented
- [ ] Tech brokering rules
- [ ] "First to discover" bonuses
- [ ] Tech diffusion (slower research if others have it)
- [ ] Future techs (repeatable)

### Files
- `data/techs.json`
- `scripts/ui/tech_tree.gd`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/Technologies/CIV4TechInfos.xml` - 90+ technologies

---

## Phase 7: AI System (40% COMPLETE)

### Implemented
- [x] Basic AI controller framework
- [x] AI research selection
- [x] AI production selection
- [x] AI unit movement (exploration, attack)
- [x] AI city site evaluation
- [x] AI war/peace decisions (basic)

### Not Implemented
- [ ] Personality-based AI (aggressive, builder, diplomat, etc.)
- [ ] AI trade evaluation
- [ ] AI diplomacy negotiations
- [ ] AI worker management
- [ ] AI city specialization
- [ ] AI naval operations
- [ ] AI espionage
- [ ] Difficulty-based AI bonuses
- [ ] AI cheating (visibility, production bonuses at higher difficulties)

### Files
- `scripts/ai/ai_controller.gd`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/BasicInfos/CIV4UnitAIInfos.xml` - AI unit roles
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4HandicapInfo.xml` - Difficulty settings

---

## Phase 8: Diplomacy (60% COMPLETE)

### Implemented
- [x] Diplomacy screen UI
- [x] War/Peace declarations
- [x] Open Borders agreements
- [x] Defensive Pacts
- [x] First contact detection
- [x] Basic attitude calculation
- [x] Met players tracking

### Not Implemented
- [ ] Trade negotiations UI (full implementation)
- [ ] Permanent alliances
- [ ] Vassal states
- [ ] Tribute demands
- [ ] Technology trading
- [ ] Map trading
- [ ] City trading
- [ ] Resource trading (per-turn)
- [ ] Gold trading (lump sum and per-turn)
- [ ] Attitude modifiers (shared religion, shared enemy, etc.)
- [ ] "Worst enemy" tracking
- [ ] Diplomacy memory (broken promises, etc.)
- [ ] AI personality in negotiations

### Files
- `scripts/ui/diplomacy_screen.gd`
- `scripts/systems/trade_system.gd`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4DiplomacyInfos.xml` - Diplomacy options
- `beyond/Beyond the Sword/Assets/XML/BasicInfos/CIV4AttitudeInfos.xml` - Attitude levels
- `beyond/Beyond the Sword/Assets/XML/BasicInfos/CIV4MemoryInfos.xml` - Diplomacy memory
- `beyond/Beyond the Sword/Assets/XML/BasicInfos/CIV4DenialInfos.xml` - Trade denial reasons

---

## Phase 9: Religion (70% COMPLETE)

### Implemented
- [x] Religion founding via technology
- [x] Religion spread between cities
- [x] Holy cities with shrines
- [x] State religion adoption
- [x] Religious happiness bonuses
- [x] Missionary unit support

### Not Implemented
- [ ] Religious buildings per religion (temples, monasteries, cathedrals)
- [ ] Shrine income based on religion spread
- [ ] "No state religion" option
- [ ] Religious victory conditions
- [ ] Apostolic Palace voting
- [ ] Religious diplomacy modifiers (shared faith bonus)
- [ ] Inquisitor units

### Files
- `scripts/systems/religion_system.gd`
- `data/religions.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4ReligionInfo.xml` - 7 religions

---

## Phase 10: Victory Conditions (COMPLETE)

### Implemented
- [x] Domination Victory (control % of land and population)
- [x] Conquest Victory (eliminate all rivals)
- [x] Cultural Victory (3 legendary cities)
- [x] Space Race Victory (build spaceship)
- [x] Diplomatic Victory (UN vote)
- [x] Time Victory (highest score at end)
- [x] Religious Victory (optional)

### Files
- `scripts/systems/victory_system.gd`
- `data/victories.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4VictoryInfo.xml` - Victory conditions

---

## Phase 11: Great People (80% COMPLETE)

### Implemented
- [x] Great People point generation
- [x] GP type weighting based on buildings
- [x] GP birth in cities
- [x] GP abilities: settle, golden age, discover tech, trade mission, hurry production, culture bomb, spread religion

### Not Implemented
- [ ] Settled GP tile yield bonuses
- [ ] Great General attachment to units
- [ ] Great Spy unit
- [ ] Golden Age length calculation
- [ ] GP point display in city screen

### Files
- `scripts/systems/great_people_system.gd`

---

## Phase 12: UI System (50% COMPLETE)

### Implemented
- [x] Main menu
- [x] Game scene with map rendering
- [x] Unit selection and movement
- [x] City screen (basic)
- [x] Tech tree screen
- [x] Minimap with click-to-center
- [x] Diplomacy screen
- [x] Notification system (toasts)
- [x] Top bar (gold, science, turn)
- [x] Unit panel

### Not Implemented
- [ ] Full city screen with specialist management
- [ ] Civilopedia
- [ ] Demographics screen
- [ ] Military advisor
- [ ] Foreign advisor
- [ ] Domestic advisor
- [ ] Religion advisor
- [ ] Espionage advisor
- [ ] Victory progress screen
- [ ] Hall of Fame
- [ ] Replay system
- [ ] World Builder (map editor)
- [ ] Options/Settings menu
- [ ] Key bindings configuration

### Files
- `scripts/ui/game_ui.gd`
- `scripts/ui/city_screen.gd`
- `scripts/ui/tech_tree.gd`
- `scripts/ui/minimap.gd`
- `scripts/ui/diplomacy_screen.gd`
- `scripts/ui/victory_screen.gd`

---

## Phase 13: Civics System (COMPLETE)

### Implemented
- [x] Civic categories (Government, Legal, Labor, Economy, Religion)
- [x] All 25 civics defined with effects
- [x] Civic effects aggregation system
- [x] Anarchy during civic changes
- [x] Spiritual trait eliminates anarchy
- [x] Civic upkeep costs (none/low/medium/high)
- [x] Civic prerequisites (technologies)
- [x] Single and bulk civic changes
- [x] City yield modifiers from civics
- [x] Happiness modifiers (Hereditary Rule, Representation, Free Religion)
- [x] Health modifiers (Environmentalism)
- [x] Worker speed modifier (Serfdom)
- [x] Military production modifier (Police State)
- [x] Hurry production support (Slavery, Universal Suffrage)
- [x] Free specialists (Mercantilism, Free Religion)
- [x] Free unit experience (Vassalage, Theocracy)
- [x] Civics screen UI with category display
- [x] Keyboard shortcut (C key)
- [x] Effect descriptions and tooltips
- [x] Pending changes preview with anarchy warning

### Not Implemented (Minor)
- [ ] Favorite civics per leader (AI preference)
- [ ] Emancipation anger to other civs
- [ ] Corporation interactions (State Property)

### Files
- `scripts/systems/civics_system.gd`
- `scripts/ui/civics_screen.gd`
- `scenes/ui/civics_screen.tscn`
- `data/civics.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4CivicInfos.xml` - 25 civics across 5 categories

### Civic Categories (All Implemented):
1. **Government**: Despotism, Hereditary Rule, Representation, Police State, Universal Suffrage
2. **Legal**: Barbarism, Vassalage, Bureaucracy, Nationhood, Free Speech
3. **Labor**: Tribalism, Slavery, Serfdom, Caste System, Emancipation
4. **Economy**: Decentralization, Mercantilism, Free Market, State Property, Environmentalism
5. **Religion**: Paganism, Organized Religion, Theocracy, Pacifism, Free Religion

---

## Phase 14: Corporations (NOT STARTED)

### To Implement
- [ ] Corporation founding via Great People
- [ ] Corporation spread mechanics
- [ ] Corporation headquarters
- [ ] Resource consumption for bonuses
- [ ] Corporation maintenance costs
- [ ] Executive units for spreading
- [ ] Corporation screen UI
- [ ] Building requirements for corporations

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4CorporationInfo.xml` - 7 corporations

### Corporations from Civ4 BTS:
1. **Mining Inc** - Requires coal/iron/copper, produces production
2. **Sid's Sushi** - Requires rice/fish/clam/crab, produces food
3. **Cereal Mills** - Requires wheat/corn/rice, produces food
4. **Standard Ethanol** - Requires corn/sugar/wheat, produces production
5. **Creative Constructions** - Requires aluminum/iron/copper, produces production/culture
6. **Civilized Jewelers** - Requires gold/silver/gems, produces culture/gold
7. **Aluminum Co** - Requires coal/aluminum, produces production

---

## Phase 15: Espionage (NOT STARTED)

### To Implement
- [ ] Espionage points generation
- [ ] Espionage point distribution per rival
- [ ] Spy unit creation and movement
- [ ] Espionage missions:
  - [ ] See demographics
  - [ ] Investigate city
  - [ ] See research
  - [ ] Steal treasury
  - [ ] Sabotage production
  - [ ] Destroy building
  - [ ] Destroy improvement
  - [ ] City revolt
  - [ ] Poison water
  - [ ] Unhappiness
  - [ ] Counter-espionage
  - [ ] Steal technology
  - [ ] Switch civic
  - [ ] Switch religion
- [ ] Great Spy abilities
- [ ] Espionage screen UI

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4EspionageMissionInfo.xml` - 20+ missions

---

## Phase 16: Random Events (NOT STARTED)

### To Implement
- [ ] Event trigger system
- [ ] Random event selection
- [ ] Event choices with consequences
- [ ] Quest events (multi-turn)
- [ ] Global events
- [ ] Event text and UI popup

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/Events/CIV4EventInfos.xml` - 200+ events
- `beyond/Beyond the Sword/Assets/XML/Events/CIV4EventTriggerInfos.xml` - Event triggers

### Event Categories:
- Natural disasters (forest fire, earthquake, hurricane)
- Resource discovery
- Diplomatic incidents
- Religious events
- Cultural events
- Economic events
- Military events
- Quest chains

---

## Phase 17: Projects (NOT STARTED)

### To Implement
- [ ] National project system
- [ ] World project system (only one can exist)
- [ ] Space race projects (spaceship parts)
- [ ] Project prerequisites
- [ ] Project effects

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4ProjectInfo.xml` - 15+ projects

### Key Projects:
- Manhattan Project (enables nukes)
- The Internet (tech sharing)
- SDI (nuke interception)
- Apollo Program (enables space race)
- Spaceship parts (SS Cockpit, Thrusters, Engine, Casing, Life Support, Stasis Chamber)

---

## Phase 18: United Nations & Voting (NOT STARTED)

### To Implement
- [ ] UN building requirement
- [ ] Secretary General election
- [ ] UN resolutions
- [ ] Diplomatic victory voting
- [ ] Apostolic Palace (religious equivalent)

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4VoteInfo.xml` - Resolutions
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4VoteSourceInfos.xml` - Vote sources

### UN Resolutions:
- Diplomatic Victory
- Free Trade
- Open Borders
- Defensive Pact
- Force Peace
- Assign City
- Nuclear Non-Proliferation

---

## Phase 19: Sound & Music (NOT STARTED)

### To Implement
- [ ] Background music per era
- [ ] Combat sounds
- [ ] UI interaction sounds
- [ ] Ambient environmental sounds
- [ ] Leader voice clips
- [ ] Victory/defeat music
- [ ] Wonder completion movies/music

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/Audio/` - Audio configuration files

---

## Phase 20: Polish & Extras (NOT STARTED)

### To Implement
- [ ] Loading screens with tips
- [ ] Animated leaderheads
- [ ] Wonder splash screens
- [ ] Goody huts (tribal villages)
- [ ] Barbarian encampments
- [ ] Barbarian spawning system
- [ ] Score calculation refinement
- [ ] Hall of Fame
- [ ] Replay system
- [ ] Custom game options
- [ ] Advanced start (buying cities/units with points)
- [ ] Scenarios
- [ ] Mod support

---

## Data Files Comparison

### Currently Implemented (data/)
| File | Entries | Status |
|------|---------|--------|
| buildings.json | ~50 | Basic |
| civs.json | ~18 | Complete |
| features.json | ~10 | Complete |
| improvements.json | ~15 | Complete |
| leaders.json | ~26 | Complete |
| promotions.json | ~30 | Partial |
| religions.json | 7 | Complete |
| resources.json | ~30 | Complete |
| techs.json | ~80 | Complete |
| terrains.json | ~10 | Complete |
| units.json | ~70 | Partial |
| victories.json | 7 | Complete |

### Recently Added
| File | Entries | Status |
|------|---------|--------|
| civics.json | 25 | Complete |
| specialists.json | 15 | Complete |

### To Add
| File | Reference | Purpose |
|------|-----------|---------|
| corporations.json | CIV4CorporationInfo.xml | Corporation system |
| espionage.json | CIV4EspionageMissionInfo.xml | Espionage missions |
| events.json | CIV4EventInfos.xml | Random events |
| projects.json | CIV4ProjectInfo.xml | National/world projects |
| votes.json | CIV4VoteInfo.xml | UN resolutions |
| handicaps.json | CIV4HandicapInfo.xml | Difficulty levels |
| game_speeds.json | CIV4GameSpeedInfo.xml | Game speed modifiers |
| eras.json | CIV4EraInfos.xml | Era definitions |

---

## Development Priorities

### High Priority (Next Phase)
1. **Full Diplomacy** - Trade negotiations
2. **AI Improvements** - More competitive AI
3. **Espionage** - BTS signature feature
4. **Corporations** - BTS signature feature

### Medium Priority
5. **Projects** - Space race completion
7. **Projects** - Space race completion
8. **Random Events** - Adds variety

### Low Priority
9. **UN/Voting** - Diplomatic victory polish
10. **Sound/Music** - Polish
11. **Advanced UI** - Advisors, Civilopedia
12. **Multiplayer** - Major undertaking

---

## Technical Debt

### Code Quality
- [ ] Add unit tests for combat calculations
- [ ] Add unit tests for pathfinding
- [ ] Add integration tests for game flow
- [ ] Document all public APIs
- [ ] Optimize large map performance
- [ ] Profile and fix memory leaks

### Architecture
- [ ] Consider ECS for large entity counts
- [ ] Add mod loading system
- [ ] Add localization system
- [ ] Add configuration system for game rules

---

## Contributing

See CLAUDE.md for development guidelines and architecture overview.

### Key Files to Understand
1. `scripts/autoload/event_bus.gd` - All game events
2. `scripts/autoload/game_manager.gd` - Central game state
3. `scripts/entities/unit.gd` - Unit implementation
4. `scripts/entities/city.gd` - City implementation
5. `scripts/systems/combat_system.gd` - Combat mechanics

### Adding New Features
1. Define data in appropriate JSON file
2. Add loading logic to DataManager if needed
3. Create system script in `scripts/systems/`
4. Register as autoload if singleton
5. Connect to EventBus signals
6. Add UI components as needed

---

*Last updated: January 2026*
