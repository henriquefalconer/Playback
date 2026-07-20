#!/bin/bash
# Build Playback Release and install to /Applications
#
# Usage: ./build-and-install.sh [--no-self-signing]
#
# Options:
#   --no-self-signing  Use Xcode automatic signing instead of
#                   the "macos-codesigning" self-signed certificate

set -e

# Parse arguments
AUTO_SIGNING=false
for arg in "$@"; do
    case "$arg" in
        --no-self-signing)
            AUTO_SIGNING=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--no-self-signing]"
            exit 1
            ;;
    esac
done

echo "=== Build and Install Playback to /Applications ==="
echo ""

# 1. Stop any running instances
echo "1. Stopping any running Playback instances..."
pkill -9 Playback 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.playback.*.plist 2>/dev/null || true
sleep 1

# 1b. Ensure the self-signed macos-codesigning cert is trusted for code signing.
#
# The app stores the OCR search-index encryption key in the login keychain. A
# keychain "Always Allow" grant only sticks across rebuilds if the signing cert
# is trusted: then the grant binds to the app's stable designated requirement
# (identifier + cert leaf). If the cert is untrusted (CSSMERR_TP_NOT_TRUSTED),
# the grant instead binds to the per-build cdhash, so every rebuild re-triggers
# the "Playback wants to access com.falconer.Playback.search" prompt.
#
# Idempotent: only prompts for authorization the first time.
if [ "$AUTO_SIGNING" = false ]; then
    # Silent when already trusted; only speaks up when it changes state or fails.
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "macos-codesigning"; then
        TRUST_CERT=$(mktemp -t macos-codesigning).pem
        if security find-certificate -c "macos-codesigning" -p > "$TRUST_CERT" 2>/dev/null && [ -s "$TRUST_CERT" ]; then
            if security add-trusted-cert -r trustRoot -p codeSign \
                -k "$HOME/Library/Keychains/login.keychain-db" "$TRUST_CERT" 2>/dev/null; then
                echo ""
                echo "✅ Certificate marked as trusted. The keychain prompt will appear one"
                echo "   last time on next launch — click Always Allow, and it will persist"
                echo "   across all future rebuilds."
            else
                echo ""
                echo "⚠️  Could not add trust automatically. Run manually:"
                echo "   security add-trusted-cert -r trustRoot -p codeSign \\"
                echo "     -k ~/Library/Keychains/login.keychain-db <cert.pem>"
            fi
        else
            echo ""
            echo "⚠️  macos-codesigning certificate not found in keychain; skipping trust."
        fi
        rm -f "$TRUST_CERT"
    fi
fi

# 2. Build Release configuration
echo ""
echo "2. Building Release configuration..."
cd src/Playback

if [ "$AUTO_SIGNING" = true ]; then
    echo "   Using automatic signing..."
    xcodebuild \
        -scheme Playback \
        -configuration Release \
        clean build \
        -quiet \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_ALLOWED=YES
else
    xcodebuild \
        -scheme Playback \
        -configuration Release \
        clean build \
        -quiet \
        CODE_SIGN_IDENTITY="macos-codesigning"
fi

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

# 3b. Re-sign with entitlements and hardened runtime
echo ""
if [ "$AUTO_SIGNING" = true ]; then
    echo "3b. Ad-hoc signing with entitlements..."
    codesign --force --sign "-" --entitlements Playback/Playback.entitlements --options runtime "$BUILT_APP"
else
    echo "3b. Signing with macos-codesigning certificate..."
    codesign --force --sign "macos-codesigning" --entitlements Playback/Playback.entitlements --options runtime "$BUILT_APP"
fi

# 3c. Verify code signature
echo "3c. Verifying code signature..."
codesign --verify --deep --strict "$BUILT_APP"
echo "✅ Code signature valid"

# 4. Copy to /Applications
echo ""
echo "4. Installing to /Applications..."
if [ -d "/Applications/Playback.app" ]; then
    echo "   Removing existing app..."
    rm -rf /Applications/Playback.app
fi

echo "   Copying app..."
cp -R "$BUILT_APP" /Applications/

# 5. Verify installation
echo ""
echo "5. Verifying installation..."
if [ -d "/Applications/Playback.app" ]; then
    echo "   ✅ App installed correctly"
else
    echo "   ❌ App not found in /Applications!"
    exit 1
fi

# 6. Show next steps
echo ""
echo "=== Installation Complete ==="
echo ""
echo "App installed at: /Applications/Playback.app"
echo ""
echo "Next steps:"
echo "  1. Launch app: open /Applications/Playback.app"
echo "  2. Grant permissions when prompted"
echo "  3. Enable recording from menu bar"
