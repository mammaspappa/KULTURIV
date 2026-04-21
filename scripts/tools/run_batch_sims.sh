#!/bin/bash
# Batch AI simulation runner — runs multiple scenarios and collects results
GODOT="./Godot_v4.5.1-stable_linux.x86_64"
SCENE="scenes/tools/ai_simulation.tscn"
RESULTS_FILE="sim_output/batch_results.txt"

mkdir -p sim_output

echo "=== BATCH AI SIMULATION ===" | tee "$RESULTS_FILE"
echo "Started: $(date)" | tee -a "$RESULTS_FILE"
echo "" | tee -a "$RESULTS_FILE"

run_sim() {
    local label="$1"
    local map_w="$2"
    local map_h="$3"
    local players="$4"
    local map_type="$5"
    local difficulty="$6"
    local aggro="$7"
    local max_turns="${8:-300}"

    echo "--- Running: $label ---" | tee -a "$RESULTS_FILE"
    echo "  Map: ${map_w}x${map_h} ($map_type), Players: $players, Diff: $difficulty, Aggro: $aggro" | tee -a "$RESULTS_FILE"

    local output
    output=$(timeout 180 env \
        SIM_MAP_W="$map_w" SIM_MAP_H="$map_h" SIM_PLAYERS="$players" \
        SIM_MAP_TYPE="$map_type" SIM_DIFFICULTY="$difficulty" SIM_SPEED="0" \
        SIM_AGGRO="$aggro" SIM_MAX_TURNS="$max_turns" \
        "$GODOT" --headless "$SCENE" 2>&1)

    local exit_code=$?

    # Extract key info from output
    local winner=$(echo "$output" | grep "Winner:" | head -1)
    local duration=$(echo "$output" | grep "Duration:" | head -1)
    local anomalies=$(echo "$output" | grep "Anomalies:" | head -1)
    local errors=$(echo "$output" | grep "^Errors:" | head -1)
    local log_file=$(echo "$output" | grep "Log file:" | head -1)

    # Get final snapshot from latest log
    local latest_log=$(ls -t sim_output/*.jsonl 2>/dev/null | head -1)
    local final_state=""
    if [ -n "$latest_log" ]; then
        final_state=$(grep '"state_snapshot"' "$latest_log" | tail -1 | python3 -c "
import sys, json
for line in sys.stdin:
    d = json.loads(line)
    for p in d.get('players',[]):
        if p.get('civ') != 'barbarian':
            print(f\"    {p['name']}: {p['cities']}c/{p['units']}u/{p['military']}m, score={p['score']}, gold={p['gold']}\")
" 2>/dev/null)
        # Count cities founded
        local cities_founded=$(grep -c '"city_founded"' "$latest_log" 2>/dev/null)
        local wars=$(grep -c '"war_declared"' "$latest_log" 2>/dev/null)
        echo "  Cities founded: $cities_founded, Wars: $wars" | tee -a "$RESULTS_FILE"
    fi

    if [ $exit_code -eq 124 ]; then
        echo "  TIMEOUT (180s)" | tee -a "$RESULTS_FILE"
    fi

    [ -n "$duration" ] && echo "  $duration" | tee -a "$RESULTS_FILE"
    [ -n "$anomalies" ] && echo "  $anomalies" | tee -a "$RESULTS_FILE"
    [ -n "$errors" ] && echo "  $errors" | tee -a "$RESULTS_FILE"
    [ -n "$final_state" ] && echo "  Final state:" | tee -a "$RESULTS_FILE" && echo "$final_state" | tee -a "$RESULTS_FILE"

    echo "" | tee -a "$RESULTS_FILE"
}

# Scenario 1: Small Pangaea, 2 players — basic expansion test
run_sim "Small Pangaea 2P" 52 32 2 pangaea 4 normal

# Scenario 2: Standard Pangaea, 4 players — normal game
run_sim "Standard Pangaea 4P" 84 52 4 pangaea 4 normal

# Scenario 3: Small Fractal, 4 players — cramped islands
run_sim "Small Fractal 4P" 52 32 4 fractal 4 normal

# Scenario 4: Large Pangaea, 6 players — crowded continent
run_sim "Large Pangaea 6P" 104 64 6 pangaea 4 normal

# Scenario 5: Aggressive AI, 4 players — war stress test
run_sim "Aggressive 4P" 64 40 4 pangaea 4 aggressive

# Scenario 6: Peaceful AI, 2 players — economy/expansion focus
run_sim "Peaceful 2P" 64 40 2 pangaea 4 peaceful

# Scenario 7: High difficulty (Deity), 4 players
run_sim "Deity 4P" 64 40 4 pangaea 8 normal

# Scenario 8: Continents map, 4 players — naval test
run_sim "Continents 4P" 84 52 4 continents 4 normal

echo "=== BATCH COMPLETE ===" | tee -a "$RESULTS_FILE"
echo "Finished: $(date)" | tee -a "$RESULTS_FILE"
echo "Results saved to: $RESULTS_FILE"
