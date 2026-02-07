#!/bin/bash

# Playback Uninstall Script
# Safely removes Playback applications and optionally deletes user data
# Default behavior: PRESERVE data (non-destructive)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Data directories
PRODUCTION_DATA_DIR="$HOME/Library/Application Support/Playback"
DEV_DATA_DIR="$HOME/dev_data"
PRODUCTION_LOGS_DIR="$HOME/Library/Logs/Playback"
DEV_LOGS_DIR="$HOME/dev_logs"

# LaunchAgent labels (both production and development)
LAUNCH_AGENTS=(
    "com.playback.recording"
    "com.playback.processing"
    "com.playback.cleanup"
    "com.playback.dev.recording"
    "com.playback.dev.processing"
    "com.playback.dev.cleanup"
)

# Application paths
APP_PATHS=(
    "/Applications/Playback.app"
    "/Applications/PlaybackMenuBar.app"
    "$HOME/Applications/Playback.app"
    "$HOME/Applications/PlaybackMenuBar.app"
)

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}    Playback Uninstall Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Function to check if LaunchAgent exists and is loaded
check_agent() {
    local label=$1
    local plist_path="$HOME/Library/LaunchAgents/${label}.plist"

    if [ -f "$plist_path" ]; then
        return 0
    fi
    return 1
}

# Function to stop and unload LaunchAgent
stop_agent() {
    local label=$1
    local plist_path="$HOME/Library/LaunchAgents/${label}.plist"

    if check_agent "$label"; then
        echo -e "${YELLOW}Stopping LaunchAgent: ${label}${NC}"

        # Try to stop the agent (may fail if not running, that's OK)
        launchctl stop "$label" 2>/dev/null || true

        # Unload the agent
        if launchctl list | grep -q "$label"; then
            launchctl unload "$plist_path" 2>/dev/null || true
        fi

        # Remove the plist file
        rm -f "$plist_path"
        echo -e "${GREEN}✓ Stopped and removed ${label}${NC}"
    fi
}

# Function to remove application
remove_app() {
    local app_path=$1

    if [ -d "$app_path" ]; then
        echo -e "${YELLOW}Removing application: ${app_path}${NC}"
        rm -rf "$app_path"
        echo -e "${GREEN}✓ Removed ${app_path}${NC}"
    fi
}

# Function to calculate directory size
get_dir_size() {
    local dir=$1
    if [ -d "$dir" ]; then
        du -sh "$dir" 2>/dev/null | awk '{print $1}'
    else
        echo "0B"
    fi
}

# Function to count files in directory
count_files() {
    local dir=$1
    if [ -d "$dir" ]; then
        find "$dir" -type f 2>/dev/null | wc -l | tr -d ' '
    else
        echo "0"
    fi
}

# Function to show data summary
show_data_summary() {
    echo ""
    echo -e "${BLUE}Data Summary:${NC}"
    echo -e "${BLUE}----------------------------------------${NC}"

    if [ -d "$PRODUCTION_DATA_DIR" ]; then
        local prod_size=$(get_dir_size "$PRODUCTION_DATA_DIR")
        local prod_files=$(count_files "$PRODUCTION_DATA_DIR")
        echo -e "Production data: ${YELLOW}${prod_size}${NC} (${prod_files} files)"
        echo -e "  Location: ${PRODUCTION_DATA_DIR}"
    else
        echo -e "Production data: ${GREEN}Not found${NC}"
    fi

    if [ -d "$DEV_DATA_DIR" ]; then
        local dev_size=$(get_dir_size "$DEV_DATA_DIR")
        local dev_files=$(count_files "$DEV_DATA_DIR")
        echo -e "Development data: ${YELLOW}${dev_size}${NC} (${dev_files} files)"
        echo -e "  Location: ${DEV_DATA_DIR}"
    else
        echo -e "Development data: ${GREEN}Not found${NC}"
    fi

    echo -e "${BLUE}----------------------------------------${NC}"
    echo ""
}

# Step 1: Stop all LaunchAgents
echo -e "${BLUE}Step 1: Stopping LaunchAgents...${NC}"
echo ""

any_agents_found=false
for label in "${LAUNCH_AGENTS[@]}"; do
    if check_agent "$label"; then
        any_agents_found=true
        stop_agent "$label"
    fi
done

if [ "$any_agents_found" = false ]; then
    echo -e "${GREEN}No LaunchAgents found${NC}"
fi

echo ""

# Step 2: Remove applications
echo -e "${BLUE}Step 2: Removing applications...${NC}"
echo ""

any_apps_found=false
for app_path in "${APP_PATHS[@]}"; do
    if [ -d "$app_path" ]; then
        any_apps_found=true
        remove_app "$app_path"
    fi
done

if [ "$any_apps_found" = false ]; then
    echo -e "${GREEN}No applications found${NC}"
fi

echo ""

# Step 3: Handle data deletion
show_data_summary

has_data=false
if [ -d "$PRODUCTION_DATA_DIR" ] || [ -d "$DEV_DATA_DIR" ]; then
    has_data=true
fi

if [ "$has_data" = true ]; then
    echo -e "${YELLOW}⚠️  WARNING: You have recorded data on this system${NC}"
    echo ""
    echo -e "By default, your data will be ${GREEN}PRESERVED${NC}."
    echo -e "You can delete it manually later if desired."
    echo ""
    echo -e "${RED}Do you want to DELETE all recordings and data? (y/N):${NC} "
    read -r response

    echo ""

    if [[ "$response" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deleting all data...${NC}"
        echo ""

        if [ -d "$PRODUCTION_DATA_DIR" ]; then
            echo -e "${YELLOW}Deleting production data...${NC}"
            rm -rf "$PRODUCTION_DATA_DIR"
            echo -e "${GREEN}✓ Deleted ${PRODUCTION_DATA_DIR}${NC}"
        fi

        if [ -d "$DEV_DATA_DIR" ]; then
            echo -e "${YELLOW}Deleting development data...${NC}"
            rm -rf "$DEV_DATA_DIR"
            echo -e "${GREEN}✓ Deleted ${DEV_DATA_DIR}${NC}"
        fi

        if [ -d "$PRODUCTION_LOGS_DIR" ]; then
            echo -e "${YELLOW}Deleting production logs...${NC}"
            rm -rf "$PRODUCTION_LOGS_DIR"
            echo -e "${GREEN}✓ Deleted ${PRODUCTION_LOGS_DIR}${NC}"
        fi

        if [ -d "$DEV_LOGS_DIR" ]; then
            echo -e "${YELLOW}Deleting development logs...${NC}"
            rm -rf "$DEV_LOGS_DIR"
            echo -e "${GREEN}✓ Deleted ${DEV_LOGS_DIR}${NC}"
        fi

        echo ""
        echo -e "${GREEN}✓ All data deleted${NC}"
    else
        echo -e "${GREEN}Data preserved.${NC}"
        echo ""
        echo -e "${BLUE}Your recordings are stored at:${NC}"

        if [ -d "$PRODUCTION_DATA_DIR" ]; then
            echo -e "  • ${PRODUCTION_DATA_DIR}"
        fi

        if [ -d "$DEV_DATA_DIR" ]; then
            echo -e "  • ${DEV_DATA_DIR}"
        fi

        echo ""
        echo -e "${BLUE}To delete manually later, run:${NC}"

        if [ -d "$PRODUCTION_DATA_DIR" ]; then
            echo -e "  rm -rf \"${PRODUCTION_DATA_DIR}\""
        fi

        if [ -d "$DEV_DATA_DIR" ]; then
            echo -e "  rm -rf \"${DEV_DATA_DIR}\""
        fi

        if [ -d "$PRODUCTION_LOGS_DIR" ]; then
            echo -e "  rm -rf \"${PRODUCTION_LOGS_DIR}\""
        fi

        if [ -d "$DEV_LOGS_DIR" ]; then
            echo -e "  rm -rf \"${DEV_LOGS_DIR}\""
        fi
    fi
else
    echo -e "${GREEN}No data directories found${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${GREEN}✓ Playback uninstalled successfully${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Note about permissions (optional cleanup)
echo -e "${BLUE}Note:${NC} Playback's permissions (Screen Recording, Accessibility)"
echo -e "can be manually removed in: System Settings → Privacy & Security"
echo ""

exit 0
