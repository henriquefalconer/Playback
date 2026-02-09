#!/bin/bash
# Show status of all Playback processes and services

echo "=== Playback Status Check ==="
echo ""

# 1. Check Playback app processes
echo "1. Playback App Processes:"
PLAYBACK_PROCS=$(ps aux | grep -i "Playback.app" | grep -v grep)
if [ -n "$PLAYBACK_PROCS" ]; then
    echo "$PLAYBACK_PROCS" | while read line; do
        PID=$(echo "$line" | awk '{print $2}')
        CMD=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')
        echo "   ✅ PID $PID: $CMD"
    done
else
    echo "   ℹ️  No Playback app running"
fi

# 2. Check Python services
echo ""
echo "2. Python Services:"
PYTHON_PROCS=$(ps aux | grep -E "record_screen|build_chunks|cleanup_old" | grep -v grep)
if [ -n "$PYTHON_PROCS" ]; then
    echo "$PYTHON_PROCS" | while read line; do
        PID=$(echo "$line" | awk '{print $2}')
        CMD=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i; print ""}')
        echo "   ⚠️  PID $PID: $CMD"
    done
else
    echo "   ✅ No Python services running"
fi

# 3. Check LaunchAgents
echo ""
echo "3. Loaded LaunchAgents:"
AGENTS=$(launchctl list | grep playback)
if [ -n "$AGENTS" ]; then
    echo "$AGENTS" | while read line; do
        STATUS=$(echo "$line" | awk '{print $1}')
        PID=$(echo "$line" | awk '{print $2}')
        NAME=$(echo "$line" | awk '{print $3}')
        if [[ "$NAME" == *".dev."* ]]; then
            MODE="DEV"
        else
            MODE="PROD"
        fi
        if [ "$PID" = "-" ]; then
            echo "   ℹ️  [$MODE] $NAME (loaded but not running)"
        else
            echo "   ✅ [$MODE] $NAME (PID: $PID, exit: $STATUS)"
        fi
    done
else
    echo "   ℹ️  No LaunchAgents loaded"
fi

# 4. Check LaunchAgent plist files
echo ""
echo "4. LaunchAgent Plist Files:"
if ls ~/Library/LaunchAgents/com.playback* >/dev/null 2>&1; then
    for plist in ~/Library/LaunchAgents/com.playback*.plist; do
        NAME=$(basename "$plist" .plist)
        SIZE=$(ls -lh "$plist" | awk '{print $5}')
        if [[ "$NAME" == *".dev."* ]]; then
            MODE="DEV"
        else
            MODE="PROD"
        fi
        echo "   📄 [$MODE] $NAME ($SIZE)"
    done
else
    echo "   ℹ️  No LaunchAgent plists found"
fi

# 5. Check signal files
echo ""
echo "5. Signal Files:"
if [ -f ~/Playback/dev_data/.timeline_open ]; then
    echo "   ⚠️  DEV signal file exists (timeline open)"
else
    echo "   ✅ No DEV signal file"
fi

if [ -f ~/Library/Application\ Support/Playback/data/.timeline_open ]; then
    echo "   ⚠️  PROD signal file exists (timeline open)"
else
    echo "   ✅ No PROD signal file"
fi

# 6. Check recent screenshots
echo ""
echo "6. Recent Screenshots:"

# Dev screenshots
DEV_RECENT=$(find ~/Playback/dev_data/temp/$(date +%Y%m/%d) -name "*.png" -mmin -1 2>/dev/null | wc -l | xargs)
if [ "$DEV_RECENT" -gt 0 ]; then
    LATEST=$(ls -t ~/Playback/dev_data/temp/$(date +%Y%m/%d)/*.png 2>/dev/null | head -1)
    AGE=$(stat -f "%Sm" -t "%H:%M:%S" "$LATEST" 2>/dev/null)
    echo "   ⚠️  DEV: $DEV_RECENT screenshots in last minute (latest: $AGE)"
else
    echo "   ✅ DEV: No recent screenshots"
fi

# Prod screenshots
PROD_RECENT=$(find ~/Library/Application\ Support/Playback/data/temp/$(date +%Y%m/%d) -name "*.png" -mmin -1 2>/dev/null | wc -l | xargs)
if [ "$PROD_RECENT" -gt 0 ]; then
    LATEST=$(ls -t ~/Library/Application\ Support/Playback/data/temp/$(date +%Y%m/%d)/*.png 2>/dev/null | head -1)
    AGE=$(stat -f "%Sm" -t "%H:%M:%S" "$LATEST" 2>/dev/null)
    echo "   ⚠️  PROD: $PROD_RECENT screenshots in last minute (latest: $AGE)"
else
    echo "   ✅ PROD: No recent screenshots"
fi

# 7. Summary
echo ""
echo "=== Summary ==="
if [ -z "$PLAYBACK_PROCS" ] && [ -z "$PYTHON_PROCS" ] && [ "$DEV_RECENT" -eq 0 ] && [ "$PROD_RECENT" -eq 0 ]; then
    echo "✅ All services stopped - no recording happening"
elif [ -n "$PLAYBACK_PROCS" ]; then
    echo "📱 Playback app is running"
    if [ "$DEV_RECENT" -gt 0 ] || [ "$PROD_RECENT" -gt 0 ]; then
        echo "📸 Recording is active"
    fi
else
    echo "⚠️  Background services are running - use ./stop-dev.sh or ./stop-prod.sh"
fi

echo ""
echo "Quick commands:"
echo "  ./stop-dev.sh   - Stop all dev processes"
echo "  ./stop-prod.sh  - Stop all prod processes"
echo "  ./status.sh     - Show this status (refresh)"
