# Phase 5: Component extraction status

This directory holds helper classes peeled off the `Unit` and `City` god objects.
The plan called for full decomposition into multiple components per entity. To stay
within risk tolerance, the first pass extracted only the most cohesive, lowest-risk
pieces:

## Extracted (this pass)

- **`unit_combat_helper.gd`** — `get_combat_strength`, `get_first_strikes`,
  `get_withdraw_chance`, `direction_to_edge`. Pure functions of unit + opponent state.
  Removed ~100 lines from `unit.gd`.
- **`unit_serializer.gd`** — `to_dict` / `from_dict` data marshalling. The on-disk
  shape is unchanged; the wrapper methods on `Unit` delegate here.
- **`city_serializer.gd`** — same pattern for `City`.

`Unit` and `City` retain thin façade methods so call sites elsewhere in the codebase
do not need to change (`unit.get_combat_strength(...)`, `unit.to_dict()`, etc.).

## Still on the to-do list

These are deliberately deferred — they touch state ownership and lifecycle, so they
need their own focused PRs with combat/yield golden tests:

### Unit
- `UnitMovementComponent` — `can_move_to`, `move_to`, `_animate_move_to`,
  `move_along_path`, `_get_movement_cost_to`, `teleport_to`, animation tweens.
- `UnitPromotionComponent` — `_get_available_promotions`, `_check_level_up`,
  `_xp_for_next_level`, `add_promotion`, `gain_experience`.
- `UnitVisibilityComponent` — `get_visibility_range`, `_update_visibility`,
  `_check_first_contact_at`.
- `UnitCargoComponent` — transport / loaded units handling.
- `UnitUpgradeComponent` — `get_upgrade_target`, `can_upgrade`, `upgrade`,
  `get_upgrade_cost`.

### City
- `CityYieldsComponent` — `calculate_yields`, `_calculate_science`,
  `_calculate_culture`, `_calculate_trade_routes`, `_calculate_happiness`,
  `_calculate_health` (~200 lines, single largest cohesive block).
- `CityProductionComponent` — `set_production`, `complete_production`,
  `_produce_unit`, `_produce_building`, `can_build_*`.
- `CityGrowthComponent` — `food_needed_for_growth`, `grow`, `starve`,
  citizen assignment / focus scoring.
- `CityTerritoryComponent` — `_initialize_territory`, `_can_claim_tile`,
  `_expand_borders` (some of this lives in `border_system.gd` already).
- `CityHappinessComponent` — multi-factor happiness/health calculation.

## How to add another component

1. Pick a cohesive block of methods that all read/write a related slice of state.
2. Move them into a new `class_name FooComponent extends RefCounted` with the host
   entity (`unit` / `city`) passed as the first parameter.
3. Replace the body in `unit.gd` / `city.gd` with `return FooComponent.method(self, ...)`.
4. Run `./godot --headless --import` so Godot picks up the new `class_name`.
5. Run the GUT suite + a 30-turn AI sim. Both must be clean before the PR lands.
