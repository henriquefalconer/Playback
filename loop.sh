#!/bin/bash
set -euo pipefail   # Exit on error, undefined vars, and pipe failures

# Usage: ./loop.sh [plan] [max_iterations] [--no-sandbox]
# Examples:
#   ./loop.sh                       # Build mode, unlimited, via docker sandbox
#   ./loop.sh --no-sandbox          # Build mode, unlimited, via claude CLI directly + confirmation
#   ./loop.sh plan 5                # Plan mode, max 5 iters, docker
#   ./loop.sh plan 5 --no-sandbox   # Plan mode, max 5 iters, claude CLI + confirmation
#   ./loop.sh 20 --no-sandbox       # Build mode, max 20, claude CLI + confirmation

# Color and style definitions
GREEN_BOLD="\033[1;38;2;40;254;20m"    # #28FE14 + bold
YELLOW_BOLD="\033[1;33m"
RED_BOLD="\033[1;31m"
RESET="\033[0m"

# ────────────────────────────────────────────────
# Parse flags & positional arguments
# ────────────────────────────────────────────────

USE_SANDBOX=true
POSITIONAL=()

for arg in "$@"; do
    case "$arg" in
        --no-sandbox)
            USE_SANDBOX=false
            shift
            ;;
        *)
            POSITIONAL+=("$arg")
            ;;
    esac
done

set -- "${POSITIONAL[@]:-}"   # restore positional parameters

# ────────────────────────────────────────────────
# Mode & prompt file
# ────────────────────────────────────────────────

if [ "${1:-}" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="PROMPT_plan.md"
    MAX_ITERATIONS=${2:-0}
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=$1
else
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=0
fi

# Select model
if [ "$MODE" = "build" ]; then
    MODEL="sonnet"   # for speed
else
    MODEL="opus"     # complex reasoning & planning
fi

# ────────────────────────────────────────────────
# Header
# ────────────────────────────────────────────────

ITERATION=0
CURRENT_BRANCH=$(git branch --show-current)

echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN_BOLD}Mode:         $MODE${RESET}"
echo -e "${GREEN_BOLD}Model:        $MODEL${RESET}"
echo -e "${GREEN_BOLD}Prompt:       $PROMPT_FILE${RESET}"
echo -e "${GREEN_BOLD}Branch:       $CURRENT_BRANCH${RESET}"
echo -e "${GREEN_BOLD}Execution:    $(if $USE_SANDBOX; then echo "docker sandbox"; else echo "claude CLI (direct / no sandbox)${RESET}"; fi)${RESET}"
[ $MAX_ITERATIONS -gt 0 ] && echo -e "${GREEN_BOLD}Max:          $MAX_ITERATIONS iterations${RESET}"
echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${GREEN_BOLD}Error: $PROMPT_FILE not found${RESET}"
    exit 1
fi

# ────────────────────────────────────────────────
# Confirmation when using --no-sandbox
# ────────────────────────────────────────────────

if ! $USE_SANDBOX; then
    echo -e ""
    echo -e "${YELLOW_BOLD}⚠️  WARNING: Running in DIRECT Claude CLI mode (--no-sandbox)${RESET}"
    echo -e "${YELLOW_BOLD}   • No sandbox isolation — Claude can run ANY shell command${RESET}"
    echo -e "${YELLOW_BOLD}   • --dangerously-skip-permissions is ON → all tool calls auto-approved${RESET}"
    echo -e "${YELLOW_BOLD}   • Model can read, write or delete files ANYWHERE your user has access${RESET}"
    echo -e "${YELLOW_BOLD}   • Only proceed if you accept full responsibility for the risk${RESET}"
    echo -e ""
    read -p "Continue without sandbox? (y/N) " -n 1 -r
    echo    # move to new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED_BOLD}Aborted by user.${RESET}"
        exit 1
    fi
    echo -e "${GREEN_BOLD}Confirmed — proceeding without sandbox.${RESET}\n"
fi

# ────────────────────────────────────────────────
# Main loop
# ────────────────────────────────────────────────

while true; do
    if [ $MAX_ITERATIONS -gt 0 ] && [ $ITERATION -ge $MAX_ITERATIONS ]; then
        echo -e "${GREEN_BOLD}Reached max iterations: $MAX_ITERATIONS${RESET}"
        break
    fi

    CURRENT_ITER=$((ITERATION + 1))

    START_TIME=$(date +%s)
    START_DISPLAY=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${GREEN_BOLD}Starting iteration ${CURRENT_ITER} at ${START_DISPLAY}${RESET}"

    if $USE_SANDBOX; then
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
    else
        # Run Ralph iteration without sandbox with selected prompt
        # -p: Headless mode (non-interactive, reads from stdin)
        # --dangerously-skip-permissions: Auto-approve all tool calls (YOLO mode)
        # --output-format=stream-json: Structured output for logging/monitoring
        # --model ...: selects the model
        #               Can use 'sonnet' in build mode for speed if plan is clear and tasks well-defined
        # --verbose: Detailed execution logging
        cat "$PROMPT_FILE" | claude -p \
            --output-format=stream-json \
            --model "$MODEL" \
            --verbose \
            --dangerously-skip-permissions
    fi

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    DURATION_MIN=$((DURATION / 60))
    DURATION_SEC=$((DURATION % 60))

    echo -e "${GREEN_BOLD}Iteration ${CURRENT_ITER} completed in ${DURATION_MIN}m ${DURATION_SEC}s${RESET}"

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
