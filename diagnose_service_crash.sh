#!/bin/bash

echo "=== SERVICE CRASH DIAGNOSTICS ==="
echo ""
echo "Date: $(date)"
echo ""

PROJECT_ROOT="/Users/henriquefalconer/Playback"
cd "$PROJECT_ROOT"

echo "=== 1. Check Installed LaunchAgent Plists ==="
echo ""

for label in com.playback.dev.recording com.playback.dev.processing; do
    plist="$HOME/Library/LaunchAgents/${label}.plist"
    if [ -f "$plist" ]; then
        echo "✓ Found: $plist"
        echo ""
        echo "Contents:"
        cat "$plist"
        echo ""
        echo "---"
        echo ""
    else
        echo "✗ Not found: $plist"
        echo ""
    fi
done

echo "=== 2. Check LaunchAgent Status ==="
echo ""

for label in com.playback.dev.recording com.playback.dev.processing; do
    echo "Status for $label:"
    launchctl list | grep "$label" || echo "  Not loaded"
    echo ""

    # Try to get more details
    launchctl print "gui/$(id -u)/$label" 2>&1 | head -20
    echo ""
    echo "---"
    echo ""
done

echo "=== 3. Check Log Files ==="
echo ""

LOG_PATHS=(
    "$PROJECT_ROOT/dev_logs/recording.log"
    "$PROJECT_ROOT/dev_logs/processing.log"
    "$HOME/Library/Logs/Playback/recording.log"
    "$HOME/Library/Logs/Playback/processing.log"
)

for log in "${LOG_PATHS[@]}"; do
    if [ -f "$log" ]; then
        echo "✓ Found: $log"
        echo "  Last modified: $(date -r "$log" "+%Y-%m-%d %H:%M:%S")"
        echo "  Size: $(wc -c < "$log") bytes"
        echo ""
        echo "Last 20 lines:"
        tail -20 "$log"
        echo ""
    else
        echo "✗ Not found: $log"
        echo ""
    fi
    echo "---"
    echo ""
done

echo "=== 4. Try Running Scripts Manually ==="
echo ""

# Set environment for dev mode
export PLAYBACK_DEV_MODE=1

echo "Attempting to run record_screen.py manually..."
echo ""
cd "$PROJECT_ROOT"
python3 src/scripts/record_screen.py 2>&1 | head -50 &
RECORD_PID=$!
sleep 3
kill $RECORD_PID 2>/dev/null
echo ""
echo "---"
echo ""

echo "Attempting to run build_chunks_from_temp.py manually..."
echo ""
python3 src/scripts/build_chunks_from_temp.py --auto 2>&1 | head -50
echo ""
echo "---"
echo ""

echo "=== 5. Check Python Dependencies ==="
echo ""

echo "Python version:"
python3 --version
echo ""

echo "Python location:"
which python3
echo ""

echo "Checking required packages..."
echo ""

for package in Quartz Foundation Cocoa PIL pytesseract opencv-python; do
    echo -n "  $package: "
    python3 -c "import $package; print('✓ installed')" 2>/dev/null || echo "✗ NOT installed"
done
echo ""

echo "All installed packages:"
python3 -m pip list 2>/dev/null | head -30
echo ""

echo "=== 6. Check Environment Variables ==="
echo ""

echo "Environment variables that will be passed to LaunchAgent:"
echo "  HOME: $HOME"
echo "  USER: $USER"
echo "  PATH: $PATH"
echo ""

echo "=== 7. Check File Permissions ==="
echo ""

echo "dev_logs/ permissions:"
ls -la "$PROJECT_ROOT/dev_logs/"
echo ""

echo "dev_data/ permissions:"
ls -la "$PROJECT_ROOT/dev_data/"
echo ""

echo "=== DIAGNOSTICS COMPLETE ==="
