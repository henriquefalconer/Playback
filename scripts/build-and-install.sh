#!/bin/bash
# Build Playback Release and install to /Applications

set -e

echo "=== Build and Install Playback to /Applications ==="
echo ""

# 1. Stop any running instances
echo "1. Stopping any running Playback instances..."
pkill -9 Playback 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.playback.*.plist 2>/dev/null || true
sleep 1

# 2. Build Release configuration
echo ""
echo "2. Building Release configuration..."
cd src/Playback

xcodebuild \
    -scheme Playback \
    -configuration Release \
    clean build \
    -quiet \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_ENTITLEMENTS="Playback/Playback.entitlements"

# 3. Find the built app
echo ""
echo "3. Finding built app..."
BUILD_DIR=$(xcodebuild -scheme Playback -configuration Release -showBuildSettings 2>/dev/null | grep "BUILD_DIR" | head -1 | awk '{print $3}')
BUILT_APP="$BUILD_DIR/Release/Playback.app"

if [ ! -d "$BUILT_APP" ]; then
    echo "❌ Built app not found at: $BUILT_APP"
    echo ""
    echo "Searching for app..."
    find "$BUILD_DIR" -name "Playback.app" -type d 2>/dev/null || true
    exit 1
fi

echo "✅ Found: $BUILT_APP"

# 4. Copy to /Applications
echo ""
echo "4. Installing to /Applications..."
if [ -d "/Applications/Playback.app" ]; then
    echo "   Removing existing app..."
    sudo rm -rf /Applications/Playback.app
fi

echo "   Copying app..."
sudo cp -R "$BUILT_APP" /Applications/

# 5. Install Python scripts to app bundle
echo ""
echo "5. Installing Python scripts..."
REPO_ROOT="$(cd ../.. && pwd)"
sudo mkdir -p /Applications/Playback.app/Contents/Resources/scripts
sudo mkdir -p /Applications/Playback.app/Contents/Resources/lib

sudo cp "$REPO_ROOT/src/scripts"/*.py /Applications/Playback.app/Contents/Resources/scripts/
sudo cp "$REPO_ROOT/src/lib"/*.py /Applications/Playback.app/Contents/Resources/lib/

sudo chmod -R 755 /Applications/Playback.app/Contents/Resources/scripts
sudo chmod -R 755 /Applications/Playback.app/Contents/Resources/lib

# 6. Verify installation
echo ""
echo "6. Verifying installation..."
if [ -f "/Applications/Playback.app/Contents/Resources/scripts/build_chunks_from_temp.py" ]; then
    echo "   ✅ Scripts installed correctly"
else
    echo "   ❌ Scripts missing!"
    exit 1
fi

# 7. Show next steps
echo ""
echo "=== Installation Complete ==="
echo ""
echo "App installed at: /Applications/Playback.app"
echo ""
echo "Next steps:"
echo "  1. Launch app: open /Applications/Playback.app"
echo "  2. Grant permissions when prompted"
echo "  3. Enable recording from menu bar"
echo ""
echo "Verify processing service:"
echo "  launchctl list | grep com.playback.processing"
echo "  ./diagnose-processing.sh"
