#!/usr/bin/env python3
"""
Evolutionary AI parameter tuner for KulturIV.

Evolves AI strategy parameters through head-to-head simulation. Can run in two
modes:

  1. SINGLE mode (default): Evolves one unified parameter set across all
     strategies. Fast convergence, but all archetypes share the same tuning.

  2. PER-STRATEGY mode (--per-strategy): Runs a separate evolution for each
     strategy archetype (wide, tall, warmonger, builder, science). Civs are
     force-locked into the target strategy during eval so variants compete
     on equal strategic footing. Produces a best variant per strategy, which
     can be merged back into ai.json.

Fitness = final_score + 5*techs + 10*cities + 3*pop + 50*win_bonus - 50*elim

Usage:
    # Single-strategy (default):
    python3 scripts/tools/ai_tuner.py --generations 5 --pool-size 6

    # Per-strategy (much slower, one evolution per archetype):
    python3 scripts/tools/ai_tuner.py --per-strategy --generations 4 \
                                      --output per_strategy.json
"""

import argparse
import copy
import json
import os
import random
import subprocess
import sys
import time
from pathlib import Path

# Paths — resolve relative to this script so it works from anywhere
SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent.parent  # KULTURIV/
GODOT_BIN = PROJECT_ROOT / "godot"
SIM_SCENE = "scenes/tools/ai_simulation.tscn"
AI_TUNABLES = PROJECT_ROOT / "data" / "tunables" / "ai.json"

# Civs available in the eval pool — we round-robin between them so variants
# don't get stuck on one civ's bonuses
EVAL_CIVS = [
    "rome", "persia", "india", "china", "france", "germany",
    "russia", "greece", "egypt", "aztec", "mongolia", "japan",
]

# Parameters that we'll mutate. Each entry: (path, min, max, type)
# The path matches the dot-notation key used in GameManager.get_ai_tunable.
# Ranges are intentionally broad — per-strategy hard bounds are enforced
# by STRATEGY_CONSTRAINTS below so the evolution can't drift away from
# the strategy's core identity (e.g. "wide" can't evolve to have
# max_cities_hard_max=5, which is less wide than baseline).
MUTABLE_PARAMS = [
    # Expansion
    ("expansion.max_cities_divisor", 80, 250, int),
    ("expansion.max_cities_expansion_divisor", 2, 8, int),
    ("expansion.max_cities_hard_min", 2, 5, int),
    ("expansion.max_cities_hard_max", 4, 12, int),
    ("expansion.max_inflight_settlers", 1, 4, int),
    ("expansion.freeze_max_cities_at_gpt", -30, -5, int),
    ("expansion.soft_brake_gpt", -10, 0, int),
    ("expansion.soft_brake_science_rate", 0.2, 0.8, float),
    # Military
    ("military.desired_per_city_base", 0, 3, int),
    ("military.desired_per_city_flavor_divisor", 3, 8, int),
    ("military.max_per_city_mult", 2, 6, int),
    ("military.max_military_base", 2, 6, int),
    ("military.late_game_floor_per_city_1", 1, 4, int),
    ("military.late_game_floor_per_city_2", 2, 5, int),
    ("military.build_unit_prob_default", 20, 60, int),
    ("military.comfort_garrison_per_city", 1, 4, int),
]

# Per-strategy hard floors/ceilings. Each entry is (path, min_or_None, max_or_None).
# After mutation, if the value falls outside this range for the target strategy,
# it gets clamped. Prevents strategies from evolving AWAY from their core identity.
STRATEGY_CONSTRAINTS = {
    "wide": {
        "expansion.max_cities_hard_max": (7, None),     # must stay wide
        "expansion.max_inflight_settlers": (2, None),   # parallel expansion
        "military.comfort_garrison_per_city": (None, 2), # don't over-garrison
    },
    "tall": {
        "expansion.max_cities_hard_max": (None, 5),     # cap low
        "expansion.max_inflight_settlers": (None, 2),   # slow expansion
        "military.max_military_base": (None, 4),        # modest military
    },
    "warmonger": {
        "military.desired_per_city_base": (2, None),    # lots of units
        "military.late_game_floor_per_city_2": (3, None),
        "military.build_unit_prob_default": (40, None), # high unit prob
        "military.max_per_city_mult": (3, None),
    },
    "builder": {
        "military.build_unit_prob_default": (None, 35), # low unit prob
        "military.desired_per_city_base": (None, 1),    # modest military
        "expansion.max_inflight_settlers": (None, 2),
    },
    "science": {
        "expansion.max_cities_hard_max": (None, 6),     # stay compact
        "military.desired_per_city_base": (None, 1),    # minimal mil
        "military.build_unit_prob_default": (None, 35),
    },
    "cultural": {
        # BTS cultural victory needs 6-9 cities (3 legendary + supporting)
        "expansion.max_cities_hard_min": (4, None),     # at least 4 cities
        "expansion.max_cities_hard_max": (6, 10),       # wider to support culture cities
        "military.build_unit_prob_default": (None, 35), # prefer buildings
        "military.desired_per_city_base": (None, 1),    # low military
        "military.max_per_city_mult": (None, 3),        # no military bloat
    },
}

# Cultural strategy needs a longer evaluation window — culture accumulates slowly
# and short sims can't tell if a variant will actually reach legendary cities.
# Fitness also rewards total culture yield.
FITNESS_CULTURE_BONUS_WEIGHT = 0.5  # per total culture point across all cities


def apply_strategy_constraints(variant, strategy):
    """Clamp variant parameters to strategy-specific ranges."""
    if not strategy or strategy not in STRATEGY_CONSTRAINTS:
        return variant
    out = dict(variant)
    for path, (lo, hi) in STRATEGY_CONSTRAINTS[strategy].items():
        if path not in out:
            continue
        v = out[path]
        if lo is not None and v < lo:
            v = lo
        if hi is not None and v > hi:
            v = hi
        out[path] = v
    return out

# Fitness weights
FITNESS_SCORE_WEIGHT = 1.0
FITNESS_TECH_WEIGHT = 5.0
FITNESS_CITY_WEIGHT = 10.0
FITNESS_POP_WEIGHT = 3.0
FITNESS_WIN_BONUS = 50.0
FITNESS_ELIMINATED_PENALTY = 50.0


def load_baseline():
    """Load current ai.json as the starting point."""
    with open(AI_TUNABLES) as f:
        data = json.load(f)
    # Flatten to dot-notation dict
    flat = {}
    def walk(d, prefix=""):
        for k, v in d.items():
            if k.startswith("_"):
                continue
            key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                walk(v, key)
            else:
                flat[key] = v
    walk(data)
    return flat


def mutate(variant, mutation_rate=0.3, step=0.15):
    """Return a new variant with some parameters mutated."""
    new = dict(variant)
    for path, lo, hi, typ in MUTABLE_PARAMS:
        if random.random() > mutation_rate:
            continue
        current = new.get(path, (lo + hi) / 2)
        if typ is int:
            # ±step * range, round to int, clamp
            delta = int(round((hi - lo) * step * random.uniform(-1.5, 1.5)))
            if delta == 0 and random.random() < 0.5:
                delta = random.choice([-1, 1])
            new[path] = max(lo, min(hi, int(current) + delta))
        else:
            delta = (hi - lo) * step * random.uniform(-1.5, 1.5)
            new[path] = max(lo, min(hi, float(current) + delta))
    return new


def crossover(parent_a, parent_b):
    """Uniform crossover — each parameter taken randomly from one parent."""
    child = dict(parent_a)
    for path, *_ in MUTABLE_PARAMS:
        if random.random() < 0.5:
            child[path] = parent_b.get(path, child.get(path))
    return child


def variant_to_overrides(variant, force_strategy=None):
    """Return the subset of variant in MUTABLE_PARAMS, clamped to strategy
    constraints. If force_strategy is set, also include a __force_strategy
    marker that locks the civ into that archetype during eval."""
    out = {path: variant[path] for path, *_ in MUTABLE_PARAMS if path in variant}
    out = apply_strategy_constraints(out, force_strategy)
    if force_strategy:
        out["__force_strategy"] = force_strategy
    return out


def run_sim(civ_overrides, civs, seed, max_turns=200, map_w=24, map_h=16,
            speed=0, timeout=300):
    """Run a single sim and return the results dict, or None on error."""
    tmpdir = Path("/tmp") / f"kulturiv_tuner_{os.getpid()}_{seed}"
    tmpdir.mkdir(exist_ok=True)
    overrides_path = tmpdir / "overrides.json"
    results_path = tmpdir / "results.json"
    with open(overrides_path, "w") as f:
        json.dump(civ_overrides, f)

    env = os.environ.copy()
    env.update({
        "SIM_MAX_TURNS": str(max_turns),
        "SIM_MAP_W": str(map_w),
        "SIM_MAP_H": str(map_h),
        "SIM_PLAYERS": str(len(civs)),
        "SIM_SPEED": str(speed),
        "SIM_SEED": str(seed),
        "SIM_CIVS": ",".join(civs),
        "SIM_AI_OVERRIDES": str(overrides_path),
        "SIM_RESULTS_OUT": str(results_path),
        "SIM_NO_BARBARIANS": "1",  # deterministic eval
    })
    try:
        subprocess.run(
            [str(GODOT_BIN), "--headless", SIM_SCENE],
            cwd=str(PROJECT_ROOT),
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        return None
    except Exception as e:
        print(f"  sim error: {e}", file=sys.stderr)
        return None

    if not results_path.exists():
        return None
    with open(results_path) as f:
        return json.load(f)


def fitness(result, civ_id, strategy=None):
    """Compute fitness for a single civ in a single sim.
    When evolving the cultural strategy, adds a culture-yield bonus so
    variants that actually accumulate culture (toward the 3 legendary
    cities goal) rank higher than ones that just score on tech/cities."""
    if result is None:
        return -500  # penalty for failed sim
    for p in result.get("players", []):
        if p["civ"] != civ_id:
            continue
        score = p["score"] * FITNESS_SCORE_WEIGHT
        score += p["techs"] * FITNESS_TECH_WEIGHT
        score += p["cities"] * FITNESS_CITY_WEIGHT
        score += p["pop"] * FITNESS_POP_WEIGHT
        if p["eliminated"]:
            score -= FITNESS_ELIMINATED_PENALTY
        if result.get("winner") == civ_id:
            score += FITNESS_WIN_BONUS
        # Cultural strategy: heavy bonus for total culture + huge bonus per
        # legendary city. Without this, "cultural" would just evolve toward
        # the same score-maximizing params as "tall".
        if strategy == "cultural":
            total_culture = p.get("total_culture", 0)
            legendary = p.get("legendary_cities", 0)
            score += total_culture * 0.01  # 100 culture → 1 fitness
            score += legendary * 200       # 200 per legendary city
        return score
    return -500  # civ not found in results


def evaluate_pool(pool, sims_per_eval, base_seed, max_turns, civs_per_sim,
                  force_strategy=None):
    """Run head-to-head sims pitting pool variants against each other.

    Each variant is assigned to one civ per sim. We rotate pairings so every
    variant plays against several others. Returns a list of (variant_idx, fitness).
    Ensures every variant is sampled at least once per evaluation.

    If force_strategy is set, all civs are locked into that strategy archetype
    so variants compete on equal strategic footing — used in per-strategy mode.
    """
    fitness_totals = [0.0] * len(pool)
    fitness_counts = [0] * len(pool)

    # Build an assignment schedule — round-robin to guarantee coverage
    assignments = []  # list of lists of variant indices per sim
    pending = list(range(len(pool)))
    random.shuffle(pending)
    for sim_i in range(sims_per_eval):
        picks = []
        for _ in range(civs_per_sim):
            if not pending:
                pending = list(range(len(pool)))
                random.shuffle(pending)
            # Try to avoid duplicates within a single sim
            for candidate in list(pending):
                if candidate not in picks:
                    picks.append(candidate)
                    pending.remove(candidate)
                    break
            else:
                picks.append(random.randrange(len(pool)))
        assignments.append(picks)

    for sim_i, picks in enumerate(assignments):
        civs = random.sample(EVAL_CIVS, civs_per_sim)
        overrides = {}
        for variant_idx, civ_id in zip(picks, civs):
            overrides[civ_id] = variant_to_overrides(pool[variant_idx], force_strategy)
        seed = base_seed + sim_i * 1000
        t0 = time.time()
        result = run_sim(overrides, civs, seed, max_turns=max_turns)
        dt = time.time() - t0
        for variant_idx, civ_id in zip(picks, civs):
            f = fitness(result, civ_id, force_strategy)
            fitness_totals[variant_idx] += f
            fitness_counts[variant_idx] += 1
        winner = result.get("winner", "-") if result else "ERR"
        print(f"    sim {sim_i+1}/{sims_per_eval}: civs={civs}, winner={winner}, dt={dt:.1f}s")

    scores = []
    for i in range(len(pool)):
        if fitness_counts[i] == 0:
            # Force-run one more sim for any unsampled variants
            civ_id = random.choice(EVAL_CIVS)
            overrides = {civ_id: variant_to_overrides(pool[i], force_strategy)}
            result = run_sim(overrides, [civ_id] + random.sample(
                [c for c in EVAL_CIVS if c != civ_id], min(civs_per_sim - 1, len(EVAL_CIVS) - 1)
            ), base_seed + 999999, max_turns=max_turns)
            f = fitness(result, civ_id, force_strategy)
            scores.append((i, f))
        else:
            scores.append((i, fitness_totals[i] / fitness_counts[i]))
    return scores


def evolve_single(args, baseline, force_strategy=None):
    """Run one evolutionary loop, optionally locked to a single strategy.
    Returns (history, final_best_variant)."""
    # Seed pool with baseline clamped to strategy, plus mutated variants.
    pool = [apply_strategy_constraints(dict(baseline), force_strategy)]
    for _ in range(args.pool_size - 1):
        m = mutate(baseline, mutation_rate=args.mutation_rate, step=args.mutation_step)
        pool.append(apply_strategy_constraints(m, force_strategy))

    history = []
    for gen in range(args.generations):
        label = f"[{force_strategy}] " if force_strategy else ""
        print(f"\n=== {label}Generation {gen + 1}/{args.generations} ===")
        t0 = time.time()
        scores = evaluate_pool(pool, args.sims_per_eval,
                               args.base_seed + gen * 100000,
                               args.max_turns, args.civs_per_sim,
                               force_strategy=force_strategy)
        scores.sort(key=lambda x: -x[1])
        gen_time = time.time() - t0
        print(f"  Generation scores (gen took {gen_time:.0f}s):")
        for rank, (idx, fit) in enumerate(scores):
            marker = " <- BASELINE" if idx == 0 and gen == 0 else ""
            print(f"    #{rank+1} variant[{idx}]: fitness={fit:.1f}{marker}")
        history.append({
            "generation": gen + 1,
            "best_fitness": scores[0][1],
            "avg_fitness": sum(f for _, f in scores) / len(scores),
            "best_variant": variant_to_overrides(pool[scores[0][0]]),
        })

        # Select top half, crossover + mutate the rest
        keep = max(2, args.pool_size // 2)
        parents = [pool[idx] for idx, _ in scores[:keep]]
        new_pool = list(parents)
        while len(new_pool) < args.pool_size:
            a, b = random.sample(parents, 2)
            child = crossover(a, b)
            child = mutate(child, mutation_rate=args.mutation_rate, step=args.mutation_step)
            child = apply_strategy_constraints(child, force_strategy)
            new_pool.append(child)
        pool = new_pool

    # Best variant after final gen
    final_scores = evaluate_pool(pool, args.sims_per_eval,
                                 args.base_seed + 777777,
                                 args.max_turns, args.civs_per_sim,
                                 force_strategy=force_strategy)
    final_scores.sort(key=lambda x: -x[1])
    best = variant_to_overrides(pool[final_scores[0][0]])
    return history, best


STRATEGIES = ["wide", "tall", "warmonger", "builder", "science", "cultural"]


def print_best(label, best, baseline):
    print(f"\n=== {label} best variant ===")
    for k, v in best.items():
        if k.startswith("__"):
            continue
        baseline_v = baseline.get(k, "?")
        marker = "  (changed)" if v != baseline_v else ""
        print(f"  {k}: {baseline_v} -> {v}{marker}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--generations", type=int, default=5)
    ap.add_argument("--pool-size", type=int, default=6)
    ap.add_argument("--sims-per-eval", type=int, default=4)
    ap.add_argument("--civs-per-sim", type=int, default=3)
    ap.add_argument("--max-turns", type=int, default=150)
    ap.add_argument("--mutation-rate", type=float, default=0.3)
    ap.add_argument("--mutation-step", type=float, default=0.15)
    ap.add_argument("--output", type=str, default="tuner_results.json")
    ap.add_argument("--base-seed", type=int, default=10000)
    ap.add_argument("--per-strategy", action="store_true",
                    help="Run separate evolution per strategy archetype")
    ap.add_argument("--strategies", type=str, default=",".join(STRATEGIES),
                    help="Comma-separated list of strategies to evolve (per-strategy mode only)")
    args = ap.parse_args()

    print(f"Loading baseline from {AI_TUNABLES}")
    baseline = load_baseline()
    print(f"  {len(baseline)} baseline parameters, {len(MUTABLE_PARAMS)} mutable")

    results = {
        "mode": "per-strategy" if args.per_strategy else "single",
        "generations": args.generations,
        "pool_size": args.pool_size,
        "sims_per_eval": args.sims_per_eval,
        "runs": {},
    }

    if args.per_strategy:
        strats = [s.strip() for s in args.strategies.split(",") if s.strip()]
        print(f"\nEvolving per-strategy for: {strats}")
        for strat in strats:
            print(f"\n{'='*60}\nStrategy: {strat}\n{'='*60}")
            history, best = evolve_single(args, baseline, force_strategy=strat)
            results["runs"][strat] = {"history": history, "final_best": best}
            print_best(strat, best, baseline)
    else:
        history, best = evolve_single(args, baseline, force_strategy=None)
        results["runs"]["single"] = {"history": history, "final_best": best}
        print_best("single", best, baseline)

    out_path = Path(args.output)
    with open(out_path, "w") as f:
        json.dump(results, f, indent=2)
    print(f"\nAll results written to {out_path}")


if __name__ == "__main__":
    main()
