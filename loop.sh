#!/bin/bash
set -euo pipefail   # Exit on error, undefined vars, and pipe failures

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
if [ "${1:-}" = "plan" ]; then
    # Plan mode
    MODE="plan"
    PROMPT_FILE="PROMPT_plan.md"
    MAX_ITERATIONS=${2:-0}
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
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

echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN_BOLD}Mode:   $MODE${RESET}"
echo -e "${GREEN_BOLD}Model:  $MODEL${RESET}"
echo -e "${GREEN_BOLD}Prompt: $PROMPT_FILE${RESET}"
echo -e "${GREEN_BOLD}Branch: $CURRENT_BRANCH${RESET}"
[ $MAX_ITERATIONS -gt 0 ] && echo -e "${GREEN_BOLD}Max:    $MAX_ITERATIONS iterations${RESET}"
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

    START_TIME=$(date +%s)
    START_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${GREEN_BOLD}Starting iteration ${CURRENT_ITER} at ${START_DISPLAY}${RESET}"

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
        "$(cat "$PROMPT_FILE")"

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    DURATION_MIN=$((DURATION / 60))
    DURATION_SEC=$((DURATION % 60))

    echo -e "${GREEN_BOLD}Iteration ${CURRENT_ITER} completed in ${DURATION_MIN}m ${DURATION_SEC}s${RESET}"

    # TODO: add back any per-iteration checks / credit detection / custom status here if needed later

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

echo -e "${GREEN_BOLD}Loop finished${RESET}"
