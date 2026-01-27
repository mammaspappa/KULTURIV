# KulturIV Project Plan

A Civilization IV: Beyond the Sword clone built in Godot 4.5.1

## Project Status Overview

| Category | Status | Progress |
|----------|--------|----------|
| Core Engine | Complete | 100% |
| Map System | Complete | 100% |
| Units | Partial | 75% |
| Cities | Partial | 85% |
| Combat | Complete | 100% |
| AI | Enhanced | 75% |
| UI | Partial | 70% |
| Diplomacy | Complete | 95% |
| Religion | Basic | 70% |
| Victory Conditions | Complete | 100% |
| Civics | Complete | 100% |
| Corporations | Basic | 70% |
| Espionage | Basic | 80% |
| Projects | Basic | 85% |
| Events | Basic | 80% |
| UN/Voting | Basic | 85% |
| Borders | Complete | 100% |
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
- [x] Road-to-road movement bonus (1/3 movement cost)
- [x] Railroad-to-railroad movement bonus (0.1 movement cost)

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

### Recently Added
- [x] Worker keyboard shortcuts (R=road, M=mine, I=farm, O=cottage)
- [x] Worker action buttons with availability check per tile
- [x] Border permission checking for unit movement
- [x] Road-to-road movement cost calculation

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
- [x] Attacking triggers war declaration automatically
- [x] Cannot attack across closed borders (must have permission to enter)

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

## Phase 7: AI System (75% COMPLETE)

### Implemented
- [x] Basic AI controller framework
- [x] AI research selection (personality-weighted tech evaluation)
- [x] AI production selection (flavor-based building/unit choices)
- [x] AI unit movement (exploration, attack, garrison)
- [x] AI city site evaluation (weighted by leader flavor)
- [x] AI war/peace decisions (based on power ratio and personality)
- [x] Personality-based AI using leader flavor values (military, gold, science, culture, religion, expansion, growth, production)
- [x] AI trade evaluation and tech trading
- [x] AI diplomacy negotiations (treaties, open borders, defensive pacts)
- [x] AI worker management with improvement selection based on flavor
- [x] Difficulty-based AI bonuses (handicaps.json with 9 difficulty levels)
- [x] AI target selection in combat (weighted by win chance and aggressiveness)

### Not Implemented
- [ ] AI city specialization (production vs science cities)
- [ ] AI naval operations
- [ ] AI espionage
- [ ] AI cheating (visibility at higher difficulties)

### Files
- `scripts/ai/ai_controller.gd`
- `data/handicaps.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/BasicInfos/CIV4UnitAIInfos.xml` - AI unit roles
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4HandicapInfo.xml` - Difficulty settings

---

## Phase 8: Diplomacy (95% COMPLETE)

### Implemented
- [x] Diplomacy screen UI with attitude breakdown
- [x] War/Peace declarations
- [x] Open Borders agreements
- [x] Defensive Pacts
- [x] First contact detection
- [x] Full attitude calculation with multiple modifiers
- [x] Met players tracking
- [x] Trade negotiations UI (full implementation)
- [x] Technology trading
- [x] Resource trading (per-turn)
- [x] Gold trading (lump sum and per-turn)
- [x] Attitude modifiers (shared religion, shared enemy, treaties, civics, power ratio)
- [x] "Worst enemy" tracking
- [x] Diplomacy memory system (events decay over time)
- [x] Memory types: declared war, made peace, signed treaties, shared tech, helped in war, etc.
- [x] AI trade evaluation and acceptance
- [x] Peace demands calculation based on power ratio
- [x] Trade screen with gold, gold/turn, resources, technologies
- [x] Keyboard shortcut (D key)

### Not Implemented
- [ ] Permanent alliances
- [ ] Tribute demands
- [ ] Map trading
- [ ] City trading
- [ ] AI personality in negotiations

### Recently Added
- [x] Border crossing restrictions (own borders, at war, open borders, vassal)
- [x] Forced unit expulsion when borders close or war declared
- [x] Tech trading requires Alphabet technology
- [x] Vassal state framework (vassals array, master_id tracking)
- [x] Border permission checks in pathfinding

### Files
- `scripts/ui/diplomacy_screen.gd`
- `scripts/ui/trade_screen.gd`
- `scripts/systems/trade_system.gd`
- `scripts/systems/diplomacy_system.gd`
- `scripts/systems/border_system.gd`
- `scenes/ui/diplomacy_screen.tscn`
- `scenes/ui/trade_screen.tscn`

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

## Phase 12: UI System (70% COMPLETE)

### Implemented
- [x] Main menu
- [x] Game scene with map rendering
- [x] Unit selection and movement
- [x] City screen (basic)
- [x] Tech tree screen
- [x] Minimap with click-to-center
- [x] Diplomacy screen
- [x] Trade screen
- [x] Civics screen
- [x] Victory screen
- [x] Notification system (toasts)
- [x] Top bar (gold, science, turn)
- [x] Unit panel with worker actions
- [x] Worker action buttons (context-sensitive per tile)
- [x] Event popup (random events with choices)
- [x] Espionage screen (missions, targets)
- [x] Spaceship screen (space race progress)
- [x] UN/Voting screen (resolutions, elections)

### Not Implemented
- [ ] Full city screen with specialist management
- [ ] Civilopedia
- [ ] Demographics screen
- [ ] Military advisor
- [ ] Foreign advisor
- [ ] Domestic advisor
- [ ] Religion advisor
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
- `scripts/ui/civics_screen.gd`
- `scripts/ui/trade_screen.gd`
- `scripts/ui/event_popup.gd`
- `scripts/ui/espionage_screen.gd`
- `scripts/ui/spaceship_screen.gd`
- `scripts/ui/voting_screen.gd`

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

## Phase 14: Corporations (70% COMPLETE)

### Implemented
- [x] Corporation data with all 7 BTS corporations
- [x] Corporation founding via Great People (Great Merchant/Engineer)
- [x] Corporation spread mechanics via executive units
- [x] Corporation headquarters tracking
- [x] Resource consumption for city bonuses (food, production, culture, gold, happiness)
- [x] Corporation maintenance costs per city and per resource
- [x] Headquarters income from foreign cities
- [x] Tech requirements for corporations
- [x] Corporation serialization

### Not Implemented
- [ ] Executive units for spreading (unit data needed)
- [ ] Corporation screen UI
- [ ] State Property civic disabling corporations
- [ ] Corporation buildings in cities

### Files
- `scripts/systems/corporation_system.gd`
- `data/corporations.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4CorporationInfo.xml` - 7 corporations

### Corporations Implemented:
1. **Mining Inc** - Great Engineer, consumes coal/iron/copper/silver/gold, +production
2. **Sid's Sushi** - Great Merchant, consumes fish/rice/clam/crab, +food/culture
3. **Cereal Mills** - Great Merchant, consumes wheat/corn/rice, +food
4. **Standard Ethanol** - Great Engineer, consumes corn/sugar/wheat, +production
5. **Creative Constructions** - Great Engineer, consumes aluminum/iron/copper/marble/stone, +production/culture
6. **Civilized Jewelers** - Great Merchant, consumes gold/silver/gems/ivory, +culture/gold/happiness
7. **Aluminum Co** - Great Engineer, consumes coal/aluminum/iron, +production

---

## Phase 15: Espionage (80% COMPLETE)

### Implemented
- [x] Espionage points generation per turn
- [x] Espionage point accumulation per rival
- [x] Spy placement in enemy cities
- [x] 15 espionage missions with full mechanics:
  - [x] See Demographics (100% success, no discovery)
  - [x] Investigate City (reveals buildings, production)
  - [x] See Research (reveals current research)
  - [x] Steal Treasury (up to 25% / 500 gold)
  - [x] Sabotage Production (destroys production progress)
  - [x] Destroy Building (50% success, 50% discovery)
  - [x] Destroy Improvement (80% success, 20% discovery)
  - [x] Incite City Revolt (3 turns of revolt)
  - [x] Poison Water (health penalty for 5 turns)
  - [x] Spread Unhappiness (happiness penalty for 5 turns)
  - [x] Counter-Espionage (+50% defense for 10 turns)
  - [x] Steal Technology (35% success, 70% discovery)
  - [x] Force Civic Change (25% success)
  - [x] Force Religion Change (30% success)
  - [x] Expose Enemy Spy (capture spies in own territory)
- [x] Mission success/failure calculation with modifiers
- [x] Discovery chance calculation
- [x] Spy capture on discovery
- [x] Mission cooldowns
- [x] Counter-espionage defense system
- [x] Tech requirements for missions
- [x] Distance-based cost modifiers
- [x] Diplomatic penalty on discovery
- [x] Full serialization support

### Not Implemented
- [ ] Espionage point slider for distribution
- [ ] Great Spy unit and abilities
- [ ] AI espionage operations
- [ ] Buildings that boost espionage (Intelligence Agency, Security Bureau)

### Files
- `scripts/systems/espionage_system.gd`
- `data/espionage_missions.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4EspionageMissionInfo.xml` - 20+ missions

### Espionage Missions Implemented:
| Mission | Base Cost | Success % | Discovery % | Requires Spy |
|---------|-----------|-----------|-------------|--------------|
| See Demographics | 50 | 100% | 0% | No |
| Investigate City | 100 | 100% | 10% | Yes |
| See Research | 75 | 100% | 5% | No |
| Steal Treasury | 200 | 70% | 30% | Yes |
| Sabotage Production | 300 | 60% | 40% | Yes |
| Destroy Building | 400 | 50% | 50% | Yes |
| Destroy Improvement | 150 | 80% | 20% | No |
| Incite Revolt | 500 | 40% | 60% | Yes |
| Poison Water | 350 | 55% | 45% | Yes |
| Spread Unhappiness | 300 | 60% | 35% | Yes |
| Counter-Espionage | 100 | 100% | 0% | No |
| Steal Technology | 600 | 35% | 70% | Yes |
| Force Civic Change | 800 | 25% | 80% | Yes |
| Force Religion Change | 700 | 30% | 75% | Yes |
| Expose Enemy Spy | 150 | 50% | 0% | No |

---

## Phase 16: Random Events (80% COMPLETE)

### Implemented
- [x] Event trigger system with multiple conditions
- [x] Weight-based random event selection
- [x] Event choices with various consequences
- [x] Temporary effects with duration tracking
- [x] Event cooldowns to prevent spam
- [x] Non-recurring events tracking
- [x] 20 diverse events across multiple categories
- [x] Full serialization support

### Events Implemented:
| Category | Events |
|----------|--------|
| Natural Disaster | Forest Fire, Earthquake, Flood |
| Disaster | Plague, Mine Collapse |
| Discovery | Gold Discovery, Ancient Ruins |
| Economic | Merchant Caravan, Trade Opportunity |
| Cultural | Religious Festival, Great Artist Born |
| Science | Scientific Breakthrough |
| Military | Barbarian Raiders |
| Diplomatic | Diplomatic Incident, Spy Discovered |
| Growth | Population Boom, Skilled Immigrants |
| Unrest | Rebellion Brewing |
| Religious | Wandering Prophet |
| Prosperity | Bountiful Harvest |

### Event Effects Supported:
- Gold changes (immediate or per-turn)
- Population changes
- Food/Production/Research bonuses
- Happiness/Health modifiers (temporary)
- Culture gains
- Feature/Improvement changes
- Diplomatic modifiers
- Espionage effects
- Religion spreading
- City revolt chances

### Not Implemented
- [ ] Quest events (multi-turn chains)
- [ ] Global events (affect all players)
- [ ] AI event handling

### Files
- `scripts/systems/events_system.gd`
- `data/events.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/Events/CIV4EventInfos.xml` - 200+ events
- `beyond/Beyond the Sword/Assets/XML/Events/CIV4EventTriggerInfos.xml` - Event triggers

---

## Phase 17: Projects (85% COMPLETE)

### Implemented
- [x] World project system (unique global wonders)
- [x] National project system (per-player limits)
- [x] Space race projects with all spaceship parts
- [x] Project prerequisites (tech, other projects)
- [x] Production bonuses from resources
- [x] Project effects (nukes, tech share, nuke interception)
- [x] Spaceship assembly tracking
- [x] Spaceship launch with success/failure based on components
- [x] Travel time calculation based on engines/thrusters
- [x] Full serialization support

### Projects Implemented:
| Project | Type | Cost | Tech Required | Effect |
|---------|------|------|---------------|--------|
| Manhattan Project | World | 1500 | Fission | Enables nukes globally |
| The Internet | World | 2000 | Computers | Grants techs known by 2+ civs |
| SDI | National | 1000 | Laser | 75% nuke interception |
| Apollo Program | National | 1600 | Rocketry | Enables spaceship parts |
| SS Cockpit | Spaceship | 1000 | Fiber Optics | Required x1 |
| SS Life Support | Spaceship | 1000 | Ecology | Required x1 |
| SS Stasis Chamber | Spaceship | 1200 | Genetics | Required x1 |
| SS Docking Bay | Spaceship | 2000 | Satellites | Required x1 |
| SS Engine | Spaceship | 1600 | Fusion | 1-2 (faster travel) |
| SS Casing | Spaceship | 1200 | Composites | 1-5 (launch success) |
| SS Thrusters | Spaceship | 1200 | Superconductors | 1-5 (faster travel) |

### Not Implemented
- [ ] Spaceship viewer/animation (basic screen exists)
- [ ] AI project prioritization
- [ ] Team projects (multiplayer)

### Files
- `scripts/systems/projects_system.gd`
- `data/projects.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4ProjectInfo.xml` - 15+ projects

---

## Phase 18: United Nations & Voting (85% COMPLETE)

### Implemented
- [x] Two vote sources: United Nations and Apostolic Palace
- [x] Secretary General / Resident elections
- [x] Population-based voting (UN)
- [x] Religion-based voting (Apostolic Palace)
- [x] Vote power calculation
- [x] Diplomatic Victory voting
- [x] 22 total resolutions implemented
- [x] AI voting logic based on relationships
- [x] Resolution effects system
- [x] Vote history tracking
- [x] Full serialization support

### Vote Sources:
| Source | Building | Vote Type | Interval |
|--------|----------|-----------|----------|
| United Nations | united_nations | Population | 5 turns |
| Apostolic Palace | apostolic_palace | Religion | 9 turns |

### UN Resolutions Implemented:
| Resolution | Threshold | Effect |
|------------|-----------|--------|
| Elect Secretary General | 40% | Elects leader |
| Diplomatic Victory | 62% | Grants victory |
| Single Currency | 51% | +1 trade route |
| Free Trade | 51% | Open markets |
| Nuclear Non-Proliferation | 51% | Bans nukes |
| Universal Suffrage | 51% | Force civic |
| Free Speech | 51% | Force civic |
| Emancipation | 51% | Force civic |
| Environmentalism | 51% | Force civic |
| Free Religion | 51% | Force civic |
| Stop the War | 62% | Force peace |
| Trade Embargo | 62% | Force no trade |
| Declare War | 62% | Force war |
| Assign City | 62% | Transfer city |

### Apostolic Palace Resolutions:
| Resolution | Threshold | Effect |
|------------|-----------|--------|
| Elect Resident | 40% | Elects leader |
| Religious Victory | 75% | Grants victory |
| Open Borders | 62% | Force borders |
| Defensive Pact | 62% | Force alliance |
| Stop the Holy War | 62% | Force peace |
| Trade Embargo | 62% | Force no trade |
| Holy War | 62% | Force war |
| Assign Holy City | 62% | Transfer city |

### Not Implemented
- [ ] Defying resolutions (penalties)
- [ ] Vassal voting
- [ ] Team voting

### Files
- `scripts/systems/voting_system.gd`
- `data/votes.json`

### Reference (beyond/)
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4VoteInfo.xml` - Resolutions
- `beyond/Beyond the Sword/Assets/XML/GameInfo/CIV4VoteSourceInfos.xml` - Vote sources

---

## Phase 18.5: Border System (COMPLETE)

### Implemented
- [x] Border crossing permission system
- [x] Units can only enter tiles if: own territory, at war, open borders, or vassal relationship
- [x] Forced unit expulsion when diplomatic status changes
- [x] Unit expulsion on war declaration (both sides)
- [x] Unit expulsion when open borders ends
- [x] Unit expulsion when borders expand into occupied tiles
- [x] Pathfinding respects border permissions
- [x] Combat restricted to valid border crossings
- [x] Vassal state tracking (vassals array, master_id)

### Border Permission Rules:
| Condition | Can Enter |
|-----------|-----------|
| Own territory | Yes |
| At war with owner | Yes |
| Open borders agreement | Yes |
| Vassal of tile owner | Yes |
| Master of tile owner | Yes |
| No relationship | No |

### Files
- `scripts/systems/border_system.gd`
- `scripts/core/player.gd` (can_enter_borders_of, vassal tracking)
- `scripts/entities/unit.gd` (can_enter_tile)
- `scripts/map/pathfinding.gd` (border checks)

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
| handicaps.json | 9 | Complete |
| corporations.json | 7 | Complete |
| espionage_missions.json | 15 | Complete |
| projects.json | 11 | Complete |
| events.json | 20 | Complete |
| votes.json | 22 | Complete |

### To Add
| File | Reference | Purpose |
|------|-----------|---------|
| game_speeds.json | CIV4GameSpeedInfo.xml | Game speed modifiers |
| eras.json | CIV4EraInfos.xml | Era definitions |

---

## Development Priorities

### High Priority (Next Phase)
1. ~~**Full Diplomacy** - Trade negotiations~~ (COMPLETE)
2. ~~**AI Improvements** - More competitive AI~~ (75% COMPLETE)
3. ~~**Espionage** - BTS signature feature~~ (75% COMPLETE)
4. ~~**Corporations** - BTS signature feature~~ (70% COMPLETE)

### Medium Priority
5. ~~**Projects** - Space race completion~~ (80% COMPLETE)
6. ~~**Random Events** - Adds variety~~ (75% COMPLETE)

### Low Priority
9. ~~**UN/Voting** - Diplomatic victory polish~~ (80% COMPLETE)
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
6. `scripts/systems/border_system.gd` - Border permissions and unit expulsion
7. `scripts/map/pathfinding.gd` - Movement and pathfinding

### Adding New Features
1. Define data in appropriate JSON file
2. Add loading logic to DataManager if needed
3. Create system script in `scripts/systems/`
4. Register as autoload if singleton
5. Connect to EventBus signals
6. Add UI components as needed

---

*Last updated: January 27, 2026*
