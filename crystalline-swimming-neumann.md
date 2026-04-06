# KulturIV - Continuation Plan & Authenticity Audit

## Context

KulturIV is a Civ4 BTS clone in Godot at ~95% completion. This plan covers: (1) removing non-authentic mechanics, (2) prioritizing remaining work to reach completion, and (3) tracking known simplifications.

---

## Part 1: Non-Civ4 BTS Mechanic Audit

### Issue Found: Standalone Religious Victory

**File:** `data/victories.json` (lines 61-68)

The `"religious"` victory condition ("Spread your religion to 75% of all cities") is a **Civ6 mechanic**, not Civ4 BTS. It should be removed.

**Note:** The Apostolic Palace "Religious Unity" vote in `data/votes.json` (line 183) IS authentic Civ4 BTS — the AP can call a diplomatic-style victory vote. This stays.

**What's correct:** `victory_system.gd` never checks for religious victory, so it's already dead data. But it should be removed to avoid confusion.

**Action:**
- Remove the `"religious"` entry from `data/victories.json`
- Update `CLAUDE.md` to list 6 victory types instead of 7 (remove "Religious" from victory list)

**Everything else is authentic.** The audit confirmed: square grid, unit stacking, happiness/health (not amenities), permanent workers, proper civics categories, no city-states, no districts, no tourism, no builder charges, no policy cards. The codebase is very faithful to Civ4 BTS.

---

## Part 2: Remaining Work Priorities

### Tier 1: High Impact — Core Gameplay Gaps

#### 1. Diplomatic Victory Check Missing
- `victory_system.gd` checks conquest, domination, cultural, space_race, and score — but NOT diplomatic
- `voting_system.gd:478` calls `VictorySystem.check_diplomatic_victory(secretary_id)` — but that method doesn't exist in `victory_system.gd`
- **This is a runtime error** if a UN diplomatic victory vote passes
- **Fix:** Add `check_diplomatic_victory(player_id)` method to `scripts/systems/victory_system.gd`

#### 2. Wonder Special Effects Not Applied
- `scripts/systems/civics_system.gd:151` has `# TODO: Add wonder effects`
- Wonder buildings exist in `data/buildings.json` with `"wonder_type": "world"` but their unique abilities aren't executed
- Examples of missing effects: Oracle (free tech), Great Wall (free promotions in borders), Statue of Liberty (free specialist slots), etc.
- **Fix:** Implement wonder effect application — either in a new `wonder_system.gd` or by extending `civics_system.gd` / `city.gd`

#### 3. Promotion Selection UI Missing
- Units can earn promotions (`unit.gd:493` `can_level_up()`, `unit.gd:495` `_get_available_promotions()`, `unit.gd:524` `add_promotion()`)
- **`add_promotion()` is never called from any UI code** — players have no way to choose or apply promotions
- This is a significant gameplay gap: promotions are core to Civ4 combat strategy
- **Fix:** Add a promotion selection popup in `scripts/ui/game_ui.gd` that appears when a unit levels up, showing available promotions from the promotion tree

### Tier 2: Save System Completeness

#### 4. Wire Existing Save/Load Methods into SaveSystem
Five subsystems already implement `to_dict()` / `from_dict()` but **none are called by `save_system.gd`**:

| System | File | `to_dict()` | `from_dict()` | Status |
|--------|------|-------------|----------------|--------|
| Espionage | `espionage_system.gd:517` | Working | Working (line 524) | Not wired |
| Voting | `voting_system.gd:733` | Working | Working (line 742) | Not wired |
| Barbarians | `barbarian_system.gd:432` | Working | Working (line 441) | Not wired |
| Events | `events_system.gd:743` | Working | Working (line 750) | Not wired |
| Corporations | `corporation_system.gd:352` | Working | **Empty** (line 371-374) | Not wired; `from_dict()` is `pass` |

- **Fix:** Add calls to each system's `to_dict()` in `save_system.gd:_collect_save_data()` and `from_dict()` in the restore function
- **Fix:** Implement `corporation_system.gd:from_dict()` (currently just `pass` — noted as requiring cities to be loaded first, so restore order matters)

### Tier 3: AI Refinements

The AI (`scripts/ai/ai_controller.gd`, 1536 lines) is already moderately sophisticated with personality-driven decisions via 8 flavor values, 7 city specialization types, multi-layered production logic, espionage/diplomacy/civic evaluation, and naval operations. Specific areas for improvement:

#### 5. Unit Type Selection & Countering
- `_get_best_military_unit()` (line 797) only picks strongest unit by raw strength
- No consideration of unit type matchups, promotions, or countering enemy compositions
- **Fix:** Score units based on opponent's army composition (e.g., build spearmen if enemy has cavalry)

#### 6. Build Queue Planning
- Each city commits to the next item immediately with no lookahead
- No coordination between cities (e.g., avoiding duplicate wonders)
- **Fix:** Add basic wonder duplication avoidance; consider queue depth of 2-3 items

#### 7. Adaptive Expansion Limits
- City cap is fixed at `4 + expansion_flavor` (line 537) regardless of map size
- **Fix:** Scale city cap with map dimensions (e.g., `max(4, map_tiles / 200) + expansion_flavor`)

### Tier 4: UI Polish

#### 8. City Focus / Manual Tile Assignment
- Citizens are only auto-assigned via `city.gd:383` `_auto_assign_citizen()`
- No UI for manual tile-to-citizen assignment in `city_screen.gd`
- No city focus options (production focus, science focus, gold focus, etc.)
- **Fix:** Add clickable worked-tile indicators on city screen + focus dropdown (Food/Production/Commerce/Science/Culture/GPP)

### Tier 5: Code Cleanup

#### 9. Stale TODO in game_world.gd
- `scripts/core/game_world.gd:480` has `# TODO: Create proper build menu UI`
- This is **already implemented** in `scripts/ui/game_ui.gd:411-548` (`_update_worker_actions()`) with improvement buttons, road/railroad, keyboard shortcuts (R/M/I/O/A), and automate
- **Fix:** Remove or update the stale TODO comment; the `_try_build_improvement()` fallback in game_world.gd may be dead code

---

## Part 3: Known Simplifications (Low Priority)

These are documented inline in the code and are minor:

| Simplification | File | Line | Notes |
|----------------|------|------|-------|
| River system not modeled | `game_tile.gd` | 240-243 | `has_fresh_water()` only checks oasis, not rivers |
| Building river requirement | `city.gd` | 668-670 | `requires_river` check simplified |
| Espionage civic switching | `espionage_system.gd` | 417-418 | "switch_civic" mission not implemented (needs UI) |
| Corporation HQ benefits | `corporation_system.gd` | 349 | Only adds gold, not culture |

---

## Suggested Implementation Order

1. **Remove religious victory** from `data/victories.json` — dead data cleanup (5 min)
2. **Add diplomatic victory check** to `victory_system.gd` — fixes runtime error on UN vote (30 min)
3. **Promotion selection UI** — core gameplay feature, high impact (1-2 hrs)
4. **Wonder effects system** — major missing mechanic (2-3 hrs)
5. **Wire save/load for 5 subsystems** — mostly plumbing, systems already have serialization (1-2 hrs)
6. **Implement `corporation_system.from_dict()`** — complete corporation save/load (30 min)
7. **City focus / tile assignment UI** — quality-of-life for city management (2-3 hrs)
8. **Clean up stale TODO** in game_world.gd (5 min)
9. **AI refinements** — unit countering, build queue planning, expansion scaling (ongoing)

---

## Verification

- After removing religious victory: confirm `data/victories.json` has exactly 6 entries, game still runs
- After adding diplomatic victory: trigger UN vote, verify victory fires correctly
- After promotion UI: level up a unit in combat, verify promotion popup appears with valid choices
- After wonder effects: build Oracle, verify free tech granted; build Great Wall, verify border promotions
- After save/load wiring: save game with active spies + barbarian camps + ongoing votes, reload, verify state restored
- After each change: run the game via `godot project.godot` and test the affected system
