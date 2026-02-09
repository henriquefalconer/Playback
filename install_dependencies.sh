#!/bin/bash

echo "=== Installing Playback Python Dependencies ==="
echo ""

# Get project root
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$PROJECT_ROOT"

# Use the system Python (the one LaunchAgents will use)
PYTHON="/opt/homebrew/bin/python3"

# Fall back to python3 in PATH if Homebrew python not found
if [ ! -f "$PYTHON" ]; then
    PYTHON="python3"
fi

echo "Using Python: $PYTHON"
$PYTHON --version
echo ""

if [ ! -f "src/scripts/requirements.txt" ]; then
    echo "✗ requirements.txt not found!"
    echo "Expected at: src/scripts/requirements.txt"
    exit 1
fi

echo "Installing from requirements.txt..."
echo ""
$PYTHON -m pip install --user -r src/scripts/requirements.txt

echo ""
echo "=== Verifying Installation ==="
echo ""

for package in Quartz Foundation Cocoa PIL; do
    echo -n "  $package: "
    $PYTHON -c "import $package; print('✓ installed')" 2>/dev/null || echo "✗ FAILED"
done

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "Next: Restart the services by clicking 'Force Run Services' again"
echo ""
