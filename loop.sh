#!/bin/bash
set -euo pipefail   # Exit on error, undefined vars, and pipe failures

# Usage: ./loop.sh [plan] [max_iterations] [--goal <text> | -g <text> | ...]
# Examples:
#   ./loop.sh plan --goal "a beautiful dark-mode todo app with offline sync"
#   ./loop.sh plan 8 -g "a minimal blog engine with RSS and markdown editor"
#   ./loop.sh --goal "a CLI password manager in Rust" 10
#   ./loop.sh plan                                      # ← will ask you interactively

# Color and style definitions
GREEN_BOLD="\033[1;38;2;40;254;20m"    # #28FE14 + bold
YELLOW_BOLD="\033[1;33m"
RED_BOLD="\033[1;31m"
RESET="\033[0m"

# ────────────────────────────────────────────────
# Parse flags & positional arguments
# ────────────────────────────────────────────────

USE_SANDBOX=true
GOAL_TEXT=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-sandbox)
            USE_SANDBOX=false
            shift
            ;;
        --goal|--project-goal|-g|--project_specific_goal)
            shift
            [[ $# -eq 0 ]] && { echo -e "${RED_BOLD}Error: --goal requires a value${RESET}"; exit 1; }
            GOAL_TEXT="$1"
            shift
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

set -- "${POSITIONAL[@]:-}"   # restore positional parameters

# ────────────────────────────────────────────────
# Mode, iterations, prompt file
# ────────────────────────────────────────────────

if [ "${1:-}" = "plan" ]; then
    MODE="plan"
    PROMPT_FILE="PROMPT_plan.md"
    shift
    MAX_ITERATIONS="${1:-0}"
    [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]] && shift || MAX_ITERATIONS=0
elif [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS="$1"
    shift
else
    MODE="build"
    PROMPT_FILE="PROMPT_build.md"
    MAX_ITERATIONS=0
fi

# Last positional argument can be the goal (legacy style)
if [ -z "$GOAL_TEXT" ] && [ $# -ge 1 ]; then
    GOAL_TEXT="$1"
    shift
fi

# Project-specific goal (only interactive in plan mode if missing)
# ────────────────────────────────────────────────
# Project-specific goal – interactive only in plan mode if missing
# ────────────────────────────────────────────────

if [ "$MODE" = "plan" ] && [ -z "$GOAL_TEXT" ]; then
    echo -e "${YELLOW_BOLD}PLAN mode – let's define the goal${RESET}"
    echo -e ""
    echo -e "The prompt will complete this sentence:"
    echo -e "   ${GREEN_BOLD}ULTIMATE GOAL: We want to achieve …${RESET}"
    echo -e ""

    # Default starting text (user can edit from here)
    GOAL_TEXT="a "

    while true; do
        # Clear screen to simulate "live preview" (works almost everywhere)
        clear 2>/dev/null || printf "\033c"  # fallback for very old terminals

        echo -e "${GREEN_BOLD}Define your project goal${RESET}"
        echo -e "────────────────────────────────────────────────────────────"
        echo -e "ULTIMATE GOAL: We want to achieve ${YELLOW_BOLD}${GOAL_TEXT}${RESET}."
        echo -e "Consider missing elements and plan accordingly."
        echo -e "If an element is missing, search first to confirm it doesn't exist,"
        echo -e "then if needed author the specification at specs/FILENAME.md ..."
        echo -e "────────────────────────────────────────────────────────────"
        echo -e ""
        echo -e "${YELLOW_BOLD}Examples:${RESET}"
        echo -e "  • a beautiful dark mode to this application"
        echo -e "  • a detailed analytics system based on specs/analytics.md"
        echo -e "  • a great working ui and ux"
        echo -e "  • an AI-powered data import system based on specs/data-import.md"
        echo -e ""
        echo -en "${GREEN_BOLD}Your goal (edit and press Enter when done): ${RESET}"

        # Read new value – no -i, no -e → compatible with bash 3.2
        read -r input

        # User pressed Enter without typing anything new → keep previous
        if [ -z "$input" ]; then
            input="$GOAL_TEXT"
        fi

        # Trim leading/trailing whitespace (POSIX compatible)
        GOAL_TEXT=$(echo "$input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

        if [ -z "$GOAL_TEXT" ]; then
            echo -e "\n${RED_BOLD}Goal cannot be empty. Please try again.${RESET}"
            echo -e "Press Enter to continue..."
            read -r dummy
            continue
        fi

        # Show confirmation with preview
        clear 2>/dev/null || printf "\033c"

        echo -e "${GREEN_BOLD}Confirm this goal?${RESET}"
        echo -e "────────────────────────────────────────────────────────────"
        echo -e "ULTIMATE GOAL: We want to achieve ${YELLOW_BOLD}${GOAL_TEXT}${RESET}."
        echo -e "────────────────────────────────────────────────────────────"
        echo -e ""
        echo -en "${GREEN_BOLD}Looks good? [Y/n] ${RESET}"
        read -n 1 -r confirm
        echo

        if [ -z "$confirm" ] || [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        else
            echo -e "${YELLOW_BOLD}Let's edit it again...${RESET}"
            echo ""
        fi
    done

    echo -e "${GREEN_BOLD}Goal locked in:${RESET} ${YELLOW_BOLD}${GOAL_TEXT}${RESET}\n"
fi

# Prepare final prompt
if [ ! -f "$PROMPT_FILE" ]; then
    echo -e "${RED_BOLD}Error: $PROMPT_FILE not found${RESET}"
    exit 1
fi

PROMPT_CONTENT=$(cat "$PROMPT_FILE")

if [ -n "$GOAL_TEXT" ]; then
    # Simple literal replacement – safe and exact
    FINAL_PROMPT="${PROMPT_CONTENT//\[project-specific goal\]/$GOAL_TEXT}"
    echo -e "${GREEN_BOLD}Goal injected:${RESET} $GOAL_TEXT"
else
    FINAL_PROMPT="$PROMPT_CONTENT"
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
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")

echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN_BOLD}Mode:         $MODE${RESET}"
echo -e "${GREEN_BOLD}Model:        $MODEL${RESET}"
echo -e "${GREEN_BOLD}Prompt:       $PROMPT_FILE${RESET}"
[ -n "$GOAL_TEXT" ] && echo -e "${GREEN_BOLD}Goal:         $GOAL_TEXT${RESET}"
echo -e "${GREEN_BOLD}Branch:       $CURRENT_BRANCH${RESET}"
echo -e "${GREEN_BOLD}Execution:    $(if $USE_SANDBOX; then echo "docker sandbox"; else echo "claude CLI (direct)${RESET}"; fi)${RESET}"
[ $MAX_ITERATIONS -gt 0 ] && echo -e "${GREEN_BOLD}Max:          $MAX_ITERATIONS iterations${RESET}"
echo -e "${GREEN_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

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
            "$FINAL_PROMPT"
    else
        # Run Ralph iteration without sandbox with selected prompt
        # -p: Headless mode (non-interactive, reads from stdin)
        # --dangerously-skip-permissions: Auto-approve all tool calls (YOLO mode)
        # --output-format=stream-json: Structured output for logging/monitoring
        # --model ...: selects the model
        #               Can use 'sonnet' in build mode for speed if plan is clear and tasks well-defined
        # --verbose: Detailed execution logging
        echo "$FINAL_PROMPT" | claude -p \
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
