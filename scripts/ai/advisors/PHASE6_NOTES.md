# Phase 6: AI controller decomposition status

`ai_controller.gd` is the largest file in the project (~3,500 lines, 85+ methods).
The plan is to split it along decision domains so each can be tuned and tested
independently. This pass installed the supporting infrastructure but left the
mechanical extractions for incremental follow-up PRs.

## In place

- **`scripts/ui/base_ui_screen.gd`** — common base class for all screens with a
  standard `show_screen / hide_screen / refresh` lifecycle and `_on_show / _on_hide`
  hooks. New screens should inherit from this; existing screens can be migrated one
  at a time without coordinated changes.

## To split out

Each item below is a single follow-up PR. Run `./godot --headless -s addons/gut/gut_cmdln.gd
-gdir=res://tests/unit -gexit` plus a 50-turn AI sim before and after each.

### `AIResearchAdvisor`
Move `_process_research`, `_evaluate_tech`, `_manage_science_rate`, and the
research-side helpers (`_get_research_speed`, etc.). The controller calls
`AIResearchAdvisor.tick(player, flavor, sim_logger)` once per turn.

### `AIEconomyAdvisor`
City production decisions: `_process_city_ai`, `_get_best_unit`, `_get_best_building`,
`_get_best_project`, `_determine_city_specialization`, worker tasking. This is the
biggest single block (~700 lines).

### `AIMilitaryAdvisor`
Unit-level orders: `_process_unit_ai`, escort assignment, threat scoring, attack
target selection, fortify / heal / pillage decisions.

### `AINavalAdvisor`
`_process_naval_strategy`, `_process_naval_unit_ai`, `_calculate_naval_need`,
`_get_best_naval_unit`. Already cohesive (~150 lines) and easy to extract first.

### `AIDiplomacyAdvisor`
`_process_diplomacy`, war/peace decisions, deal evaluation.

### `AIEspionageAdvisor`
`_process_espionage`, spy placement, mission selection.

### `AICivicsAdvisor`
`_process_civics`, civic adoption logic.

### `AIPersonality`
Leader flavor lookup, caching, personality modifiers. Currently spread across
`_get_leader_flavor`, `_cached_flavor`, `_cached_personality`. This is a *value*
provider, not a tick handler — it should expose `get_flavor(player)` and
`get_personality(player)` to all the advisors above.

### `GameState` expansion
The current `game_state.gd` is a hollow 56-line container. Persistent metadata
(turn number, active player index, game settings) should move into it, and
`SaveSystem._collect_save_data` should serialize through `GameState.to_dict()`
instead of building the dict ad-hoc.

This change requires bumping `SAVE_VERSION` to 3 and adding `migrate_2_to_3` to
`save_migrator.gd`. The existing migrator framework (Phase 3) makes this safe.

## Why it isn't done yet

Each extraction touches code that runs on every turn for every AI player. A bug
in any one of them can corrupt the AI sim or freeze cities. The right approach is
one PR per advisor, with the test suite + golden-seed AI sim required to be green
before landing. That work is appropriately scoped per-PR but does not fit in a
single batched session.

The `BaseUIScreen` and `advisors/` directory exist now so the next PRs can land
incrementally without further plumbing work.
