# KulturIV - Continuation Plan & Authenticity Audit

## Context

KulturIV is a Civ4 BTS clone in Godot at ~95% completion. This plan covers: (1) removing non-authentic mechanics, and (2) prioritizing remaining work to reach completion.

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

#### 1. Diplomatic Victory Check Missing from `victory_system.gd`
- `victory_system.gd` checks conquest, domination, cultural, space, and time — but NOT diplomatic
- Diplomatic victory is triggered via `voting_system.gd` line 478 calling `VictorySystem.check_diplomatic_victory()` — but that method doesn't exist in `victory_system.gd`
- **Fix:** Add `check_diplomatic_victory()` method to `victory_system.gd`

#### 2. Wonder Special Effects Not Applied
- `civics_system.gd:151` has `# TODO: Add wonder effects`
- Wonder buildings exist in `buildings.json` but their unique abilities aren't executed
- **Fix:** Implement wonder effect application (Oracle, Great Wall, etc.)

#### 3. Build Menu UI Missing
- `game_world.gd:480` has `# TODO: Create proper build menu UI`
- Workers auto-build first available improvement rather than showing choices
- **Fix:** Add improvement selection popup when worker activates build

### Tier 2: AI Improvements

#### 4. AI City Production Decisions
- AI city production logic needs refinement — strategic build choices (wonders, military, infrastructure)

#### 5. AI Worker Tile Improvement Strategy
- Workers need smarter tile improvement prioritization (resources first, then high-yield tiles)

#### 6. AI Defense/Expansion Strategy
- Tactical positioning when threatened
- Expansion site evaluation for settlers

### Tier 3: Save System Completeness

#### 7. Persist Missing System States
- Espionage points and spy placements
- Active project progress
- Voting system state (active resolutions, timers)
- Corporation HQ/spread state
- Barbarian camp positions (restore properly)
- Event system active effects

### Tier 4: UI Polish

#### 8. Promotion Selection UI
- Players can't view or choose promotions when multiple are available
- Need promotion tree display

#### 9. Citizen/Tile Assignment UI
- No manual tile working — only auto-assign
- Need city focus options (production, science, gold, etc.)

#### 10. Missing Notifications
- Several events emit signals but UI doesn't show notifications (tech discovered, wonder built, etc.)

### Tier 5: Not Yet Implemented Features

These are listed as not implemented and have zero code:

| Feature | Effort | Priority |
|---------|--------|----------|
| Sound/Music | Medium | Nice-to-have (audio stubs exist in options_screen) |
| Civilopedia | Large | Nice-to-have |
| Advisor Screens | Medium | Nice-to-have |
| Hall of Fame | Small | Nice-to-have |
| Replay System | Medium | Nice-to-have |
| World Builder | Large | Nice-to-have |
| Multiplayer | Very Large | Out of scope |

---

## Suggested Implementation Order

1. **Remove religious victory** from `data/victories.json` (5 min)
2. **Add diplomatic victory check** to `victory_system.gd` (30 min)
3. **Build menu UI** for workers (1-2 hrs)
4. **Wonder effects system** (2-3 hrs)
5. **Save system gaps** — persist espionage, projects, voting, corporations (2-3 hrs)
6. **Promotion selection UI** (1-2 hrs)
7. **AI improvements** — city production, workers, defense (ongoing)
8. **Notification system** for game events (1-2 hrs)
9. **City focus / tile assignment UI** (2-3 hrs)

---

## Verification

- After removing religious victory: confirm `data/victories.json` has exactly 6 entries, game still runs
- After adding diplomatic victory: trigger UN vote, verify victory fires correctly
- After each change: run the game via `godot project.godot` and test the affected system
