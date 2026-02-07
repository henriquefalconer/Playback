#!/bin/bash
# Usage: ./loop.sh [plan] [max_iterations]
# Examples:
#   ./loop.sh              # Build mode, unlimited iterations
#   ./loop.sh 20           # Build mode, max 20 iterations
#   ./loop.sh plan         # Plan mode, unlimited iterations
#   ./loop.sh plan 5       # Plan mode, max 5 iterations

# Color and style definitions
GREEN_BOLD="\033[1;38;2;40;254;20m"    # #28FE14 + bold
RESET="\033[0m"

# Parse arguments
if [ "$1" = "plan" ]; then
    # Plan mode
    MODE="plan"
    PROMPT_FILE="PROMPT_plan.md"
    MAX_ITERATIONS=${2:-0}
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    # Build mode with max iterations
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=$1
else
    # Build mode, unlimited (no arguments or invalid input)
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=0
fi

# Select model
if [ "$MODE" = "build" ]; then
    MODEL="sonnet" # for speed
else
    MODEL="opus" # complex reasoning & planning
fi

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)

# Diagnostics setup
mkdir -p claude_logs

echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN_BOLD}Mode:   $MODE${RESET}"
echo -e "${GREEN_BOLD}Model:  $MODEL${RESET}"
echo -e "${GREEN_BOLD}Prompt: $PROMPT_FILE${RESET}"
echo -e "${GREEN_BOLD}Branch: $CURRENT_BRANCH${RESET}"
[ $MAX_ITERATIONS -gt 0 ] && echo -e "${GREEN_BOLD}Max:    $MAX_ITERATIONS iterations${RESET}"
echo -e "${GREEN_BOLD}Logs:   claude_logs/ (per-iteration + summary)${RESET}"
echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${GREEN_BOLD}Error: $PROMPT_FILE not found${RESET}"
    exit 1
fi

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo -e "${GREEN_BOLD}Reached max iterations: $MAX_ITERATIONS${RESET}"
        break
    fi

    CURRENT_ITER=$((ITERATION + 1))
    LOG_FILE="claude_logs/iteration_${CURRENT_ITER}.log"
    SUMMARY_LOG="claude_logs/diagnostics_summary.log"

    START_TIME=$(date +%s)
    START_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN_BOLD}Starting iteration ${CURRENT_ITER} at ${START_DISPLAY}${RESET}"
    echo -e "${GREEN_BOLD}Log: $LOG_FILE${RESET}"
    echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    # Run Ralph iteration via Docker sandbox (prompt passed directly)
    # -p: headless/non-interactive mode
    # --output-format=stream-json: structured streaming output
    # --model ...: selects the model
    # --verbose: detailed logging
    # Note: --dangerously-skip-permissions is automatic in sandbox
    docker sandbox run claude . -- \
        -p \
        --output-format=stream-json \
        --model "$MODEL" \
        --verbose \
        "$(cat "$PROMPT_FILE")" 2>&1 | tee "$LOG_FILE"

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    DURATION_MIN=$((DURATION / 60))
    DURATION_SEC=$((DURATION % 60))

    echo -e "${GREEN_BOLD}Iteration ${CURRENT_ITER} completed in ${DURATION_MIN}m ${DURATION_SEC}s${RESET}"

    # === Diagnostics extraction ===
    echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${GREEN_BOLD}Diagnostics for iteration ${CURRENT_ITER}${RESET}"
    echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    # Context usage estimate from last usage block
    LAST_USAGE_JSON=$(grep -o '{.*"usage":.*}' "$LOG_FILE" | tail -1)

    if command -v jq >/dev/null; then
        INPUT_TOKENS=$(echo "$LAST_USAGE_JSON" | jq -r '.usage.input_tokens // 0')
        OUTPUT_TOKENS=$(echo "$LAST_USAGE_JSON" | jq -r '.usage.output_tokens // 0')
        CACHE_READ=$(echo "$LAST_USAGE_JSON" | jq -r '.usage.cache_read_input_tokens // 0')
        TOTAL_USED=$((INPUT_TOKENS + OUTPUT_TOKENS + CACHE_READ))
        CONTEXT_LIMIT=200000  # 200k standard; change to 1000000 for 1M-beta models
        PERCENT_USED=$(( (TOTAL_USED * 100) / CONTEXT_LIMIT ))
        echo -e "${GREEN_BOLD}Estimated context used: ~${PERCENT_USED}% (tokens: ${TOTAL_USED}/${CONTEXT_LIMIT})${RESET}"
        if [ $PERCENT_USED -gt 90 ]; then
            echo -e "${GREEN_BOLD}⚠️  VERY HIGH – nearing compaction risk${RESET}"
        elif [ $PERCENT_USED -gt 75 ]; then
            echo -e "${GREEN_BOLD}⚠️  Approaching compaction – watch performance${RESET}"
        else
            echo -e "${GREEN_BOLD}Context usage looks healthy${RESET}"
        fi
    else
        # Simple fallback without jq
        TOTAL_TOKENS=$(grep -o '"input_tokens":[0-9]*\|"output_tokens":[0-9]*\|"cache_read_input_tokens":[0-9]*' "$LOG_FILE" | cut -d: -f2 | awk '{sum += $1} END {print sum}')
        [ -n "$TOTAL_TOKENS" ] && echo -e "${GREEN_BOLD}Rough total tokens seen: ${TOTAL_TOKENS}${RESET}"
    fi

    # Compaction detection
    if grep -q '"subtype":"compact_boundary"' "$LOG_FILE"; then
        echo -e "${GREEN_BOLD}🗜️  Compaction occurred this iteration${RESET}"
        echo -e "${GREEN_BOLD}   → Trigger: $(grep -o '"trigger":"[^"]*"' "$LOG_FILE" | tail -1 | cut -d'"' -f4)${RESET}"
        echo -e "${GREEN_BOLD}   → Pre-tokens: $(grep -o '"pre_tokens":[0-9]*' "$LOG_FILE" | tail -1 | cut -d: -f2)${RESET}"
    else
        echo -e "${GREEN_BOLD}No compaction this iteration${RESET}"
    fi

    # Token/cost tail
    echo -e "${GREEN_BOLD}Recent token usage lines:${RESET}"
    grep -E '"input_tokens"|"output_tokens"|"total_cost"' "$LOG_FILE" | tail -8 || echo "  (none found)"

    # Summary append
    {
        echo "=== Iteration ${CURRENT_ITER} @ ${START_DISPLAY} (${DURATION}s) ==="
        echo "Context estimate: ~${PERCENT_USED}% (${TOTAL_USED}/${CONTEXT_LIMIT})"
        echo "Compaction: $(grep -q '"subtype":"compact_boundary"' "$LOG_FILE" && echo "YES" || echo "no")"
        echo "Log size: $(wc -c < "$LOG_FILE") bytes"
        echo "--------------------------------------------------"
    } >> "$SUMMARY_LOG"

    # Completion check
    if [ -f .agent_complete ]; then
        echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo -e "${GREEN_BOLD}Agent signaled: COMPLETION${RESET}"
        echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        rm -f .agent_complete
        break
    fi

    # Push changes after each iteration
    git push origin "$CURRENT_BRANCH" || {
        echo -e "${GREEN_BOLD}Failed to push. Creating remote branch...${RESET}"
        git push -u origin "$CURRENT_BRANCH"
    }

    ITERATION=$((ITERATION + 1))
    echo -e "${GREEN_BOLD}\n\n======================== LOOP $ITERATION ========================${RESET}\n"
done

echo -e "${GREEN_BOLD}Loop finished. Full diagnostics in claude_logs/ (summary: diagnostics_summary.log)${RESET}"
