#!/bin/bash
# Stop all Playback development processes and services

echo "=== Stopping Playback Development Processes ==="

# 1. Kill all Playback app processes
echo "1. Killing Playback app processes..."
pkill -9 Playback 2>/dev/null && echo "   ✅ Killed Playback app" || echo "   ℹ️  No Playback app running"

# 2. Kill Python recording service
echo "2. Killing Python recording service..."
pkill -9 -f record_screen.py 2>/dev/null && echo "   ✅ Killed record_screen.py" || echo "   ℹ️  No recording service running"

# 3. Kill Python processing service
echo "3. Killing Python processing service..."
pkill -9 -f build_chunks_from_temp.py 2>/dev/null && echo "   ✅ Killed build_chunks_from_temp.py" || echo "   ℹ️  No processing service running"

# 4. Kill Python cleanup service
echo "4. Killing Python cleanup service..."
pkill -9 -f cleanup_old_chunks.py 2>/dev/null && echo "   ✅ Killed cleanup_old_chunks.py" || echo "   ℹ️  No cleanup service running"

# 5. Unload dev LaunchAgents
echo "5. Unloading dev LaunchAgents..."
launchctl unload ~/Library/LaunchAgents/com.playback.dev.recording.plist 2>/dev/null && echo "   ✅ Unloaded dev recording agent" || echo "   ℹ️  Dev recording agent not loaded"
launchctl unload ~/Library/LaunchAgents/com.playback.dev.processing.plist 2>/dev/null && echo "   ✅ Unloaded dev processing agent" || echo "   ℹ️  Dev processing agent not loaded"
launchctl unload ~/Library/LaunchAgents/com.playback.dev.cleanup.plist 2>/dev/null && echo "   ✅ Unloaded dev cleanup agent" || echo "   ℹ️  Dev cleanup agent not loaded"

# 6. Remove signal file
echo "6. Removing signal file..."
rm -f ~/Playback/dev_data/.timeline_open 2>/dev/null && echo "   ✅ Removed signal file" || echo "   ℹ️  No signal file"

# 7. Verify everything is stopped
echo ""
echo "=== Verification ==="
PLAYBACK_PROCS=$(ps aux | grep -i playback | grep -v grep | grep -v stop-dev)
PYTHON_PROCS=$(ps aux | grep -E "record_screen|build_chunks|cleanup_old" | grep -v grep)
AGENTS=$(launchctl list | grep playback.dev)

if [ -z "$PLAYBACK_PROCS" ] && [ -z "$PYTHON_PROCS" ] && [ -z "$AGENTS" ]; then
    echo "✅ All dev processes stopped"
else
    echo "⚠️  Some processes still running:"
    [ -n "$PLAYBACK_PROCS" ] && echo "   App processes: $PLAYBACK_PROCS"
    [ -n "$PYTHON_PROCS" ] && echo "   Python processes: $PYTHON_PROCS"
    [ -n "$AGENTS" ] && echo "   LaunchAgents: $AGENTS"
fi

echo ""
echo "To verify screenshots stopped:"
echo "  sleep 5 && ls -lt ~/Playback/dev_data/temp/\$(date +%Y%m/%d)/ | head -3"
