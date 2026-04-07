#!/bin/bash
# KulturIV AI Simulation Batch Runner
# Runs multiple simulations with different configs to find balance issues,
# AI behavior gaps, and missing features.
#
# Usage: bash scripts/tools/run_sim_batch.sh
# Logs go to sim_output/

set -euo pipefail
cd "$(dirname "$0")/../.."

GODOT="./godot"
SCENE="scenes/tools/ai_simulation.tscn"
LOGDIR="sim_output"
mkdir -p "$LOGDIR"

SUMMARY="$LOGDIR/batch_summary_$(date +%Y%m%d_%H%M%S).txt"
echo "=== KulturIV Simulation Batch ===" | tee "$SUMMARY"
echo "Started: $(date)" | tee -a "$SUMMARY"
echo "" | tee -a "$SUMMARY"

run_sim() {
    local name="$1"; shift
    echo "------------------------------------------------------------" | tee -a "$SUMMARY"
    echo "[$name] Starting..." | tee -a "$SUMMARY"
    echo "  Params: $*" | tee -a "$SUMMARY"
    local start_time=$(date +%s)

    # Run and capture output
    local outfile="$LOGDIR/${name}_$(date +%Y%m%d_%H%M%S).log"
    env "$@" "$GODOT" --headless "$SCENE" > "$outfile" 2>&1 || true

    local end_time=$(date +%s)
    local elapsed=$(( end_time - start_time ))
    echo "  Duration: ${elapsed}s" | tee -a "$SUMMARY"

    # Extract key results
    grep -E "(Winner:|No winner|ANOMAL|Error|=== AI SIM)" "$outfile" | head -20 | tee -a "$SUMMARY"
    grep -E "Turn [0-9]+ \(" "$outfile" | tail -3 | tee -a "$SUMMARY"
    echo "  Full log: $outfile" | tee -a "$SUMMARY"
    echo "" | tee -a "$SUMMARY"
}

# ============================================================
# SIMULATION BATCH
# ============================================================

# --- 1. BASELINE: Standard 1v1 on small map (quick sanity check) ---
run_sim "01_baseline_1v1" \
    SIM_MAX_TURNS=150 SIM_MAP_W=40 SIM_MAP_H=25 SIM_PLAYERS=2 \
    SIM_DIFFICULTY=4 SIM_SPEED=0 SIM_MAP_TYPE=pangaea

# --- 2. LARGE MULTIPLAYER: 6 players on standard map (diplomacy/war stress) ---
run_sim "02_large_6p" \
    SIM_MAX_TURNS=200 SIM_MAP_W=80 SIM_MAP_H=50 SIM_PLAYERS=6 \
    SIM_DIFFICULTY=4 SIM_SPEED=0 SIM_MAP_TYPE=pangaea

# --- 3. CRAMPED MAP: 4 players on tiny map (early war & aggression test) ---
run_sim "03_cramped_4p" \
    SIM_MAX_TURNS=150 SIM_MAP_W=30 SIM_MAP_H=20 SIM_PLAYERS=4 \
    SIM_DIFFICULTY=4 SIM_SPEED=0 SIM_MAP_TYPE=pangaea

# --- 4. ARCHIPELAGO: Naval AI test (do AIs build navies? invade islands?) ---
run_sim "04_archipelago_4p" \
    SIM_MAX_TURNS=200 SIM_MAP_W=60 SIM_MAP_H=40 SIM_PLAYERS=4 \
    SIM_DIFFICULTY=4 SIM_SPEED=0 SIM_MAP_TYPE=archipelago

# --- 5. CONTINENTS: 4 players, cross-ocean expansion test ---
run_sim "05_continents_4p" \
    SIM_MAX_TURNS=200 SIM_MAP_W=60 SIM_MAP_H=40 SIM_PLAYERS=4 \
    SIM_DIFFICULTY=4 SIM_SPEED=0 SIM_MAP_TYPE=continents

# --- 6. HIGH DIFFICULTY: Deity AI bonuses (are they overwhelming?) ---
run_sim "06_deity_1v1" \
    SIM_MAX_TURNS=150 SIM_MAP_W=40 SIM_MAP_H=25 SIM_PLAYERS=2 \
    SIM_DIFFICULTY=8 SIM_SPEED=0 SIM_MAP_TYPE=pangaea

# --- 7. LOW DIFFICULTY: Settler (does AI still function at low bonuses?) ---
run_sim "07_settler_1v1" \
    SIM_MAX_TURNS=150 SIM_MAP_W=40 SIM_MAP_H=25 SIM_PLAYERS=2 \
    SIM_DIFFICULTY=0 SIM_SPEED=0 SIM_MAP_TYPE=pangaea

# --- 8. GAME SPEED: Quick (0) — fast production/research, do AIs rush? ---
run_sim "08_speed_quick" \
    SIM_MAX_TURNS=150 SIM_MAP_W=50 SIM_MAP_H=30 SIM_PLAYERS=3 \
    SIM_DIFFICULTY=4 SIM_SPEED=0 SIM_MAP_TYPE=pangaea

# --- 9. GAME SPEED: Normal (1) — standard pacing baseline ---
run_sim "09_speed_normal" \
    SIM_MAX_TURNS=200 SIM_MAP_W=50 SIM_MAP_H=30 SIM_PLAYERS=3 \
    SIM_DIFFICULTY=4 SIM_SPEED=1 SIM_MAP_TYPE=pangaea

# --- 10. GAME SPEED: Epic (2) — longer games, do AIs adapt build orders? ---
run_sim "10_speed_epic" \
    SIM_MAX_TURNS=300 SIM_MAP_W=50 SIM_MAP_H=30 SIM_PLAYERS=3 \
    SIM_DIFFICULTY=4 SIM_SPEED=2 SIM_MAP_TYPE=pangaea

# --- 11. GAME SPEED: Marathon (3) — very slow, late-game tech/victory test ---
run_sim "11_speed_marathon" \
    SIM_MAX_TURNS=400 SIM_MAP_W=50 SIM_MAP_H=30 SIM_PLAYERS=3 \
    SIM_DIFFICULTY=4 SIM_SPEED=3 SIM_MAP_TYPE=pangaea

# --- 12. EPIC BRAWL: 8 players on large fractal (max stress test) ---
run_sim "12_epic_8p_fractal" \
    SIM_MAX_TURNS=200 SIM_MAP_W=84 SIM_MAP_H=52 SIM_PLAYERS=8 \
    SIM_DIFFICULTY=4 SIM_SPEED=0 SIM_MAP_TYPE=fractal

# --- 13. AGGRESSIVE AI: Small map aggression test ---
run_sim "13_aggressive_2p" \
    SIM_MAX_TURNS=150 SIM_MAP_W=40 SIM_MAP_H=25 SIM_PLAYERS=2 \
    SIM_DIFFICULTY=6 SIM_SPEED=0 SIM_MAP_TYPE=pangaea \
    SIM_AGGRESSION=high

echo "============================================================" | tee -a "$SUMMARY"
echo "Batch complete: $(date)" | tee -a "$SUMMARY"
echo "Summary: $SUMMARY" | tee -a "$SUMMARY"
echo "JSONL logs: $LOGDIR/*.jsonl" | tee -a "$SUMMARY"
