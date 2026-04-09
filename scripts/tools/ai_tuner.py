#!/usr/bin/env python3
"""
Evolutionary AI parameter tuner for KulturIV.

Runs generations of simulations where each civ uses a different variant of
AI thresholds. Top performers are selected and mutated to produce the next
generation. Over time, the tuner converges on parameter sets that perform
better than the baseline.

Usage:
    python3 scripts/tools/ai_tuner.py [--generations N] [--pool-size N]
                                      [--sims-per-eval N] [--output file.json]

The script calls the Godot binary directly and reads structured JSON results
emitted by the sim (via SIM_RESULTS_OUT). Each variant is tested by running
several sims with different seeds and averaging its fitness.

Fitness is a weighted score: final_score + 5*techs + 10*cities + 3*pop
                               + 50*win_bonus - 50*eliminated_penalty

Variants are mutated by adjusting numeric parameters by ±10% (configurable)
with some probability of larger jumps. Non-numeric values are left alone.
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
MUTABLE_PARAMS = [
    # Expansion
    ("expansion.max_cities_divisor", 80, 250, int),
    ("expansion.max_cities_expansion_divisor", 2, 8, int),
    ("expansion.max_cities_hard_min", 2, 5, int),
    ("expansion.max_cities_hard_max", 5, 12, int),
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


def variant_to_overrides(variant):
    """Return the subset of variant that's actually in MUTABLE_PARAMS."""
    return {path: variant[path] for path, *_ in MUTABLE_PARAMS if path in variant}


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


def fitness(result, civ_id):
    """Compute fitness for a single civ in a single sim."""
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
        return score
    return -500  # civ not found in results


def evaluate_pool(pool, sims_per_eval, base_seed, max_turns, civs_per_sim):
    """Run head-to-head sims pitting pool variants against each other.

    Each variant is assigned to one civ per sim. We rotate pairings so every
    variant plays against several others. Returns a list of (variant_idx, fitness).
    """
    fitness_totals = [0.0] * len(pool)
    fitness_counts = [0] * len(pool)

    # For each sim, pick civs_per_sim variants at random and run them
    for sim_i in range(sims_per_eval):
        picks = random.sample(range(len(pool)), civs_per_sim)
        civs = random.sample(EVAL_CIVS, civs_per_sim)
        overrides = {}
        for variant_idx, civ_id in zip(picks, civs):
            overrides[civ_id] = variant_to_overrides(pool[variant_idx])
        seed = base_seed + sim_i * 1000
        t0 = time.time()
        result = run_sim(overrides, civs, seed, max_turns=max_turns)
        dt = time.time() - t0
        for variant_idx, civ_id in zip(picks, civs):
            f = fitness(result, civ_id)
            fitness_totals[variant_idx] += f
            fitness_counts[variant_idx] += 1
        winner = result.get("winner", "-") if result else "ERR"
        print(f"    sim {sim_i+1}/{sims_per_eval}: civs={civs}, winner={winner}, dt={dt:.1f}s")

    return [(i, fitness_totals[i] / max(1, fitness_counts[i])) for i in range(len(pool))]


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
    args = ap.parse_args()

    print(f"Loading baseline from {AI_TUNABLES}")
    baseline = load_baseline()
    print(f"  {len(baseline)} baseline parameters, {len(MUTABLE_PARAMS)} mutable")

    # Initial pool: baseline + mutants
    pool = [dict(baseline)]
    for _ in range(args.pool_size - 1):
        pool.append(mutate(baseline, mutation_rate=args.mutation_rate, step=args.mutation_step))

    history = []
    for gen in range(args.generations):
        print(f"\n=== Generation {gen + 1}/{args.generations} ===")
        t0 = time.time()
        scores = evaluate_pool(pool, args.sims_per_eval, args.base_seed + gen * 100000,
                               args.max_turns, args.civs_per_sim)
        scores.sort(key=lambda x: -x[1])
        gen_time = time.time() - t0
        print(f"  Generation scores (gen took {gen_time:.0f}s):")
        for rank, (idx, fit) in enumerate(scores):
            marker = " <- BASELINE" if idx == 0 and gen == 0 else ""
            print(f"    #{rank+1} variant[{idx}]: fitness={fit:.1f}{marker}")

        # Record history
        history.append({
            "generation": gen + 1,
            "best_fitness": scores[0][1],
            "avg_fitness": sum(f for _, f in scores) / len(scores),
            "best_variant": variant_to_overrides(pool[scores[0][0]]),
        })

        # Select top half as parents for next gen
        keep = max(2, args.pool_size // 2)
        parents = [pool[idx] for idx, _ in scores[:keep]]

        # Next generation: keep parents, fill rest with crossover + mutation
        new_pool = list(parents)
        while len(new_pool) < args.pool_size:
            a, b = random.sample(parents, 2)
            child = crossover(a, b)
            child = mutate(child, mutation_rate=args.mutation_rate, step=args.mutation_step)
            new_pool.append(child)
        pool = new_pool

    # Save final results
    final = {
        "generations": args.generations,
        "pool_size": args.pool_size,
        "sims_per_eval": args.sims_per_eval,
        "history": history,
        "final_best": variant_to_overrides(pool[0]),
    }
    out_path = Path(args.output)
    with open(out_path, "w") as f:
        json.dump(final, f, indent=2)
    print(f"\nResults written to {out_path}")
    print("\n=== Best variant ===")
    for k, v in final["final_best"].items():
        baseline_v = baseline.get(k, "?")
        marker = "  (changed)" if v != baseline_v else ""
        print(f"  {k}: {baseline_v} -> {v}{marker}")


if __name__ == "__main__":
    main()
