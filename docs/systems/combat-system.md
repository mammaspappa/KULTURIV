# Combat System

The Combat System handles all attack resolution, damage calculation, and combat-related mechanics.

**File**: `scripts/systems/combat_system.gd`

## Overview

Combat in KulturIV follows Civilization IV's mechanics closely:
- Combat is deterministic with some randomness
- Damage is based on strength ratios
- Terrain and promotions provide modifiers
- First strikes deal damage before normal combat rounds

## Key Functions

### `can_attack(attacker: Unit, defender: Unit) -> bool`

Checks if an attack is valid.

```gdscript
var can = CombatSystem.can_attack(my_unit, enemy_unit)
if can:
    # Proceed with attack
```

**Conditions checked:**
- Attacker has movement remaining
- Attacker has combat strength > 0
- Defender is an enemy unit
- Units are adjacent (or attacker has range)

### `calculate_combat_odds(attacker: Unit, defender: Unit) -> Dictionary`

Calculates the probability of winning.

```gdscript
var odds = CombatSystem.calculate_combat_odds(attacker, defender)
# odds = {
#   "attacker_win_chance": 0.65,
#   "defender_win_chance": 0.35,
#   "attacker_strength": 4.5,
#   "defender_strength": 3.0
# }
```

### `attack(attacker: Unit, defender: Unit) -> Dictionary`

Executes an attack and returns the result.

```gdscript
var result = CombatSystem.attack(my_unit, enemy_unit)
# result = {
#   "winner": attacker,
#   "loser": defender,
#   "attacker_damage": 25,
#   "defender_damage": 100,
#   "experience_gained": 4
# }
```

### `calculate_damage(attacker: Unit, defender: Unit) -> Dictionary`

Calculates expected damage without executing combat.

```gdscript
var damage = CombatSystem.calculate_damage(attacker, defender)
# damage = {
#   "attacker_expected": 30,
#   "defender_expected": 70
# }
```

## Combat Mechanics

### Strength Calculation

Effective strength is calculated with modifiers:

```gdscript
func get_effective_strength(unit: Unit, is_attacker: bool, terrain: GameTile) -> float:
    var base = unit.get_strength()

    # Health modifier (linear reduction)
    base *= (unit.health / 100.0)

    # Terrain defense (defender only)
    if not is_attacker:
        base *= (1.0 + terrain.get_defense_bonus())

    # Fortification bonus (defender only)
    if not is_attacker and unit.is_fortified:
        base *= (1.0 + unit.get_fortification_bonus())

    # Promotion modifiers
    for promo in unit.promotions:
        base *= (1.0 + get_promo_modifier(promo, is_attacker))

    return base
```

### Damage Calculation

Damage per round is based on strength ratio:

```gdscript
func calculate_round_damage(attacker_str: float, defender_str: float) -> Dictionary:
    var ratio = attacker_str / max(0.01, defender_str)

    # Base damage ranges
    var base_damage = 20

    # Higher ratio = more damage to defender
    var defender_damage = base_damage * ratio
    var attacker_damage = base_damage / ratio

    # Clamp and randomize
    defender_damage = clamp(defender_damage + randf_range(-5, 5), 5, 60)
    attacker_damage = clamp(attacker_damage + randf_range(-5, 5), 5, 60)

    return {
        "attacker_takes": attacker_damage,
        "defender_takes": defender_damage
    }
```

### Combat Rounds

Combat proceeds in rounds until one unit is destroyed:

```gdscript
func execute_combat(attacker: Unit, defender: Unit) -> Dictionary:
    var rounds = []

    while attacker.health > 0 and defender.health > 0:
        var round_result = execute_round(attacker, defender)
        rounds.append(round_result)

        attacker.health -= round_result.attacker_takes
        defender.health -= round_result.defender_takes

        EventBus.combat_round.emit(attacker, defender,
            round_result.attacker_takes, round_result.defender_takes)

    return {
        "winner": attacker if defender.health <= 0 else defender,
        "loser": attacker if attacker.health <= 0 else defender,
        "rounds": rounds
    }
```

### First Strikes

First strikes deal damage before normal combat:

```gdscript
func apply_first_strikes(attacker: Unit, defender: Unit) -> void:
    var att_fs = attacker.get_first_strikes()
    var def_fs = defender.get_first_strikes()
    var net_fs = att_fs - def_fs

    if net_fs > 0:
        # Attacker gets free damage
        for i in range(net_fs):
            var damage = calculate_first_strike_damage(attacker, defender)
            defender.health -= damage
            EventBus.first_strike.emit(attacker, defender, damage)
    elif net_fs < 0:
        # Defender gets free damage
        for i in range(abs(net_fs)):
            var damage = calculate_first_strike_damage(defender, attacker)
            attacker.health -= damage
            EventBus.first_strike.emit(defender, attacker, damage)
```

### Withdrawal

Some units can withdraw from losing combat:

```gdscript
func check_withdrawal(unit: Unit, opponent: Unit) -> bool:
    var withdraw_chance = unit.get_withdraw_chance()
    if withdraw_chance <= 0:
        return false

    # Can't withdraw if opponent is faster
    if opponent.get_base_movement() > unit.get_base_movement():
        withdraw_chance *= 0.5

    return randf() < withdraw_chance
```

### Collateral Damage

Siege units deal collateral damage to stacked units:

```gdscript
func apply_collateral_damage(attacker: Unit, primary_target: Unit) -> void:
    if not attacker.has_ability("collateral"):
        return

    var collateral_percent = attacker.get_collateral_damage()
    var max_units = attacker.get_collateral_limit()

    var targets = get_stacked_units(primary_target.grid_position)
    targets.erase(primary_target)
    targets = targets.slice(0, max_units)

    for target in targets:
        var damage = target.max_health * collateral_percent
        damage = min(damage, target.health - 1)  # Can't kill with collateral
        target.health -= damage
```

## Modifiers

### Terrain Modifiers

| Terrain | Defense Bonus |
|---------|---------------|
| Grassland | 0% |
| Plains | 0% |
| Hills | +25% |
| Forest | +50% |
| Jungle | +50% |
| City | +50% to +100% |

### Promotion Modifiers

| Promotion | Effect |
|-----------|--------|
| Combat I-V | +10% to +50% strength |
| City Raider I-III | +20% to +50% vs cities |
| City Garrison I-III | +20% to +50% defending city |
| Drill I-IV | +1 to +4 first strikes |
| Shock | +25% vs melee |
| Cover | +25% vs ranged |

### Fortification

| Turns Fortified | Bonus |
|-----------------|-------|
| 1 | +5% |
| 2 | +10% |
| 3+ | +25% |

## Experience

Experience is gained from combat:

```gdscript
func calculate_experience(winner: Unit, loser: Unit) -> int:
    var base_xp = 2

    # More XP for defeating stronger units
    var strength_ratio = loser.get_strength() / max(1, winner.get_strength())
    if strength_ratio > 1:
        base_xp += int(strength_ratio * 2)

    # Barbarians give less XP
    if loser.player_owner.is_barbarian:
        base_xp = max(1, base_xp / 2)

    return base_xp
```

## Events Emitted

| Signal | When |
|--------|------|
| `combat_started` | Attack initiated |
| `combat_round` | Each round of damage |
| `first_strike` | First strike damage dealt |
| `combat_ended` | Combat resolved |
| `unit_withdrew` | Unit successfully withdrew |
| `unit_destroyed` | Unit killed in combat |

## Example Usage

```gdscript
# Check if attack is possible
if CombatSystem.can_attack(my_warrior, enemy_archer):
    # Show odds to player
    var odds = CombatSystem.calculate_combat_odds(my_warrior, enemy_archer)
    print("Win chance: %d%%" % (odds.attacker_win_chance * 100))

    # Execute attack
    var result = CombatSystem.attack(my_warrior, enemy_archer)

    if result.winner == my_warrior:
        print("Victory! Gained %d XP" % result.experience_gained)
    else:
        print("Defeat!")
```
