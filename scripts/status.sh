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

# 2. Check LaunchAgents
echo ""
echo "2. Loaded LaunchAgents:"
AGENTS=$(launchctl list | grep playback)
if [ -n "$AGENTS" ]; then
    echo "$AGENTS" | while read line; do
        STATUS=$(echo "$line" | awk '{print $1}')
        PID=$(echo "$line" | awk '{print $2}')
        NAME=$(echo "$line" | awk '{print $3}')
        if [ "$PID" = "-" ]; then
            echo "   ℹ️  $NAME (loaded but not running)"
        else
            echo "   ✅ $NAME (PID: $PID, exit: $STATUS)"
        fi
    done
else
    echo "   ℹ️  No LaunchAgents loaded"
fi

# 3. Check LaunchAgent plist files
echo ""
echo "3. LaunchAgent Plist Files:"
if ls ~/Library/LaunchAgents/com.playback* >/dev/null 2>&1; then
    for plist in ~/Library/LaunchAgents/com.playback*.plist; do
        NAME=$(basename "$plist" .plist)
        SIZE=$(ls -lh "$plist" | awk '{print $5}')
        echo "   📄 $NAME ($SIZE)"
    done
else
    echo "   ℹ️  No LaunchAgent plists found"
fi

# 4. Check signal files
echo ""
echo "4. Signal Files:"
if [ -f ~/Library/Application\ Support/Playback/data/.timeline_open ]; then
    echo "   ⚠️  Signal file exists (timeline open)"
else
    echo "   ✅ No signal file"
fi

# 5. Check recent screenshots
echo ""
echo "5. Recent Screenshots:"

PROD_RECENT=$(find ~/Library/Application\ Support/Playback/data/temp/$(date +%Y%m/%d) -name "*.png" -mmin -1 2>/dev/null | wc -l | xargs)
if [ "$PROD_RECENT" -gt 0 ]; then
    LATEST=$(ls -t ~/Library/Application\ Support/Playback/data/temp/$(date +%Y%m/%d)/*.png 2>/dev/null | head -1)
    AGE=$(stat -f "%Sm" -t "%H:%M:%S" "$LATEST" 2>/dev/null)
    echo "   ⚠️  $PROD_RECENT screenshots in last minute (latest: $AGE)"
else
    echo "   ✅ No recent screenshots"
fi

# 6. Summary
echo ""
echo "=== Summary ==="
if [ -z "$PLAYBACK_PROCS" ] && [ "$PROD_RECENT" -eq 0 ]; then
    echo "✅ All services stopped - no recording happening"
elif [ -n "$PLAYBACK_PROCS" ]; then
    echo "📱 Playback app is running"
    if [ "$PROD_RECENT" -gt 0 ]; then
        echo "📸 Recording is active"
    fi
fi

echo ""
echo "Quick commands:"
echo "  ./stop-prod.sh  - Stop all processes"
echo "  ./status.sh     - Show this status (refresh)"
