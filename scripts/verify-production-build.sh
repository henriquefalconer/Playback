#!/bin/bash
# Production Build Verification Script
# Checks that Playback.app is properly configured for production use

set -e

# Find the most recent Release build
echo "=== Playback Production Build Verification ==="
echo ""
echo "Searching for Release build..."

APP_EXECUTABLE=$(find ~/Library/Developer/Xcode/DerivedData -type f -path "*/Build/Products/Release/Playback.app/Contents/MacOS/Playback" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n1)

if [ -z "$APP_EXECUTABLE" ]; then
    echo "❌ No Release build found in DerivedData"
    echo ""
    echo "Please build first:"
    echo "  cd ~/Playback/src/Playback"
    echo "  xcodebuild -scheme Playback -configuration Release build"
    exit 1
fi

# Get the .app bundle path from the executable
APP_PATH="$(dirname "$(dirname "$(dirname "$APP_EXECUTABLE")")")"

echo "✅ Found Release build at:"
echo "   $APP_PATH"
echo ""

# 1. Check app exists
echo "1. Checking app exists..."
if [ -d "$APP_PATH" ]; then
    echo "   ✅ App bundle is valid"
else
    echo "   ❌ App bundle is invalid"
    exit 1
fi

# 2. Check code signature
echo ""
echo "2. Checking code signature..."
if codesign --verify --deep --strict "$APP_PATH" 2>/dev/null; then
    echo "   ✅ Code signature valid"
    codesign -dvv "$APP_PATH" 2>&1 | grep "Authority" | head -3
else
    echo "   ⚠️  Code signature invalid (expected for local debug builds)"
fi

# 3. Check entitlements
echo ""
echo "3. Checking entitlements..."
ENTITLEMENTS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null || echo "")
if echo "$ENTITLEMENTS" | grep -q "com.apple.security.personal-information.screen-capture"; then
    echo "   ✅ Screen Recording entitlement present"
else
    echo "   ❌ Screen Recording entitlement MISSING"
fi

if echo "$ENTITLEMENTS" | grep -q "com.apple.security.device.camera"; then
    echo "   ✅ Camera entitlement present"
else
    echo "   ⚠️  Camera entitlement missing"
fi

# 4. Check bundle structure
echo ""
echo "4. Checking bundle structure..."
if [ -f "$APP_PATH/Contents/Info.plist" ]; then
    echo "   ✅ Info.plist exists"
else
    echo "   ❌ Info.plist MISSING"
fi

if [ -f "$APP_PATH/Contents/MacOS/Playback" ]; then
    echo "   ✅ Executable exists"
else
    echo "   ❌ Executable MISSING"
fi

if [ -d "$APP_PATH/Contents/Resources" ]; then
    echo "   ✅ Resources directory exists"
else
    echo "   ❌ Resources directory MISSING"
fi

# 5. Check LaunchAgent templates
echo ""
echo "5. Checking LaunchAgent templates..."
TEMPLATES=("processing.plist.template" "cleanup.plist.template")
for template in "${TEMPLATES[@]}"; do
    if [ -f "$APP_PATH/Contents/Resources/$template" ]; then
        echo "   ✅ $template exists"
    else
        echo "   ❌ $template MISSING"
    fi
done

# 6. Check bundle identifier
echo ""
echo "6. Checking bundle identifier..."
BUNDLE_ID=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "")
if [ "$BUNDLE_ID" = "com.falconer.Playback" ]; then
    echo "   ✅ Bundle ID: $BUNDLE_ID"
else
    echo "   ❌ Unexpected Bundle ID: $BUNDLE_ID (expected: com.falconer.Playback)"
fi

# 7. Check version info
echo ""
echo "7. Checking version info..."
VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
BUILD=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo "unknown")
echo "   Version: $VERSION (Build $BUILD)"

# 8. Test launch (5 second smoke test)
echo ""
echo "8. Running 5-second smoke test..."
open "$APP_PATH"
sleep 5

# Check if app is running
if pgrep -x "Playback" > /dev/null; then
    echo "   ✅ App launched successfully and is running"

    # Check for crashes
    CRASH_LOG=$(ls -t ~/Library/Logs/DiagnosticReports/Playback_*.crash 2>/dev/null | head -1)
    if [ -n "$CRASH_LOG" ]; then
        CRASH_TIME=$(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$CRASH_LOG")
        CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
        # Check if crash is recent (within last minute)
        if [[ "$CRASH_TIME" > "$(date -v-1M "+%Y-%m-%d %H:%M:%S")" ]]; then
            echo "   ❌ Recent crash detected at: $CRASH_TIME"
            echo "      Log: $CRASH_LOG"
        else
            echo "   ✅ No recent crashes"
        fi
    else
        echo "   ✅ No crashes detected"
    fi
else
    echo "   ❌ App failed to launch or crashed immediately"
    exit 1
fi

# 9. Check if recording is working
echo ""
echo "9. Checking recording service..."
sleep 2  # Wait for service to start
if pgrep -x "Playback" > /dev/null; then
    # Check if screenshots are being created (look for recent files)
    TEMP_DIR="$HOME/Library/Application Support/Playback/data/temp/$(date +%Y%m/%d)"
    RECENT_SCREENSHOT=$(find "$TEMP_DIR" -name "*.png" -mmin -1 2>/dev/null | head -1)

    if [ -n "$RECENT_SCREENSHOT" ]; then
        echo "   ✅ Recording service working (found recent screenshot)"
        echo "      Latest: $(basename "$RECENT_SCREENSHOT")"
    else
        echo "   ⚠️  No recent screenshots found (recording may be disabled or paused)"
        echo "      Expected location: $TEMP_DIR"
    fi
else
    echo "   ⚠️  App not running, skipping recording check"
fi

# 10. Summary
echo ""
echo "=== Verification Complete ==="
echo ""
echo "App Location:"
echo "  $APP_PATH"
echo ""
echo "To run the app without Xcode:"
echo "  open \"$APP_PATH\""
echo ""
echo "To copy to Applications folder:"
echo "  cp -r \"$APP_PATH\" /Applications/"
echo "  open /Applications/Playback.app"
echo ""
echo "To check LaunchAgents:"
echo "  launchctl list | grep playback"
echo ""
echo "To view logs:"
echo "  tail -f ~/Library/Logs/Playback/recording.log"
echo "  tail -f ~/Library/Logs/Playback/processing.log"
echo ""
echo "To remove old dev LaunchAgents:"
echo "  launchctl unload ~/Library/LaunchAgents/com.playback.dev.recording.plist 2>/dev/null"
echo "  rm ~/Library/LaunchAgents/com.playback.dev.recording.plist 2>/dev/null"
