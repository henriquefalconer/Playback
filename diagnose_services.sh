#!/bin/bash

echo "=== PLAYBACK SERVICE DIAGNOSTICS ==="
echo ""
echo "Date: $(date)"
echo ""

echo "=== ENVIRONMENT ==="
echo "User: $USER"
echo "Home: $HOME"
echo "Working Directory: $(pwd)"
echo ""

echo "=== SCRIPT LOCATIONS ==="
echo "Checking for Python scripts..."
echo ""

# Check project location
PROJECT_ROOT="/Users/henriquefalconer/Playback"
if [ -f "$PROJECT_ROOT/src/scripts/record_screen.py" ]; then
    echo "✓ Found in project: $PROJECT_ROOT/src/scripts/record_screen.py"
    ls -la "$PROJECT_ROOT/src/scripts/record_screen.py"
else
    echo "✗ NOT found in project: $PROJECT_ROOT/src/scripts/record_screen.py"
fi
echo ""

if [ -f "$PROJECT_ROOT/src/scripts/build_chunks_from_temp.py" ]; then
    echo "✓ Found in project: $PROJECT_ROOT/src/scripts/build_chunks_from_temp.py"
    ls -la "$PROJECT_ROOT/src/scripts/build_chunks_from_temp.py"
else
    echo "✗ NOT found in project: $PROJECT_ROOT/src/scripts/build_chunks_from_temp.py"
fi
echo ""

# Check Application Support
APP_SUPPORT="$HOME/Library/Application Support/Playback"
if [ -f "$APP_SUPPORT/src/scripts/record_screen.py" ]; then
    echo "✓ Found in App Support: $APP_SUPPORT/src/scripts/record_screen.py"
    ls -la "$APP_SUPPORT/src/scripts/record_screen.py"
else
    echo "✗ NOT found in App Support: $APP_SUPPORT/src/scripts/record_screen.py"
fi
echo ""

echo "=== LAUNCH AGENTS ==="
echo "Checking LaunchAgent plists..."
echo ""

LAUNCH_AGENTS="$HOME/Library/LaunchAgents"
echo "LaunchAgent directory: $LAUNCH_AGENTS"
ls -la "$LAUNCH_AGENTS" | grep playback || echo "No playback LaunchAgents found"
echo ""

# Check if any are loaded
echo "Loaded playback services:"
launchctl list | grep playback || echo "No playback services loaded"
echo ""

echo "=== APP BUNDLE ==="
echo "Looking for Playback.app..."
echo ""

# Find Playback.app in common locations
APP_LOCATIONS=(
    "/Applications/Playback.app"
    "$HOME/Applications/Playback.app"
    "$HOME/Library/Developer/Xcode/DerivedData/Playback-*/Build/Products/Debug/Playback.app"
    "$HOME/Library/Developer/Xcode/DerivedData/Playback-*/Build/Products/Release/Playback.app"
)

for app in "${APP_LOCATIONS[@]}"; do
    # Use glob expansion for DerivedData paths
    for expanded_path in $app; do
        if [ -d "$expanded_path" ]; then
            echo "✓ Found: $expanded_path"
            echo "  Contents/Resources/:"
            ls -la "$expanded_path/Contents/Resources/" 2>/dev/null | grep -E "\.py$|scripts" || echo "  No scripts found in Resources"
            echo ""
        fi
    done
done

echo "=== PERMISSIONS ==="
echo "Screen Recording permission:"
sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
    "SELECT client, auth_value FROM access WHERE service='kTCCServiceScreenCapture';" 2>/dev/null || \
    echo "Cannot check (requires Full Disk Access or SIP disabled)"
echo ""

echo "=== CONFIGURATION ==="
echo "Config files:"
if [ -f "$HOME/Library/Application Support/Playback/config.json" ]; then
    echo "✓ Production config exists:"
    echo "$HOME/Library/Application Support/Playback/config.json"
    cat "$HOME/Library/Application Support/Playback/config.json" | python3 -m json.tool 2>/dev/null || cat "$HOME/Library/Application Support/Playback/config.json"
else
    echo "✗ Production config NOT found"
fi
echo ""

if [ -f "$PROJECT_ROOT/dev_config.json" ]; then
    echo "✓ Dev config exists:"
    echo "$PROJECT_ROOT/dev_config.json"
    cat "$PROJECT_ROOT/dev_config.json" | python3 -m json.tool 2>/dev/null || cat "$PROJECT_ROOT/dev_config.json"
else
    echo "✗ Dev config NOT found"
fi
echo ""

echo "=== PYTHON & FFMPEG ==="
echo "Python version:"
python3 --version
echo ""
echo "Python path:"
which python3
echo ""
echo "FFmpeg version:"
ffmpeg -version 2>&1 | head -n 1
echo ""
echo "FFmpeg paths:"
which ffmpeg
ls -la /opt/homebrew/bin/ffmpeg 2>/dev/null || echo "Not in /opt/homebrew/bin/"
ls -la /usr/local/bin/ffmpeg 2>/dev/null || echo "Not in /usr/local/bin/"
echo ""

echo "=== LOGS ==="
echo "Recent log files:"
for log in recording processing cleanup; do
    LOG_PATH="$HOME/Library/Logs/Playback/${log}.log"
    DEV_LOG_PATH="$PROJECT_ROOT/dev_logs/${log}.log"

    if [ -f "$LOG_PATH" ]; then
        echo ""
        echo "=== $LOG_PATH (last 10 lines) ==="
        tail -10 "$LOG_PATH"
    fi

    if [ -f "$DEV_LOG_PATH" ]; then
        echo ""
        echo "=== $DEV_LOG_PATH (last 10 lines) ==="
        tail -10 "$DEV_LOG_PATH"
    fi
done
echo ""

echo "=== DIAGNOSTICS COMPLETE ==="
