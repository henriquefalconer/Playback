#!/bin/bash
#
# Playback - 5-Second Smoke Test
#
# This script builds the Debug configuration and runs the app for 5 seconds
# to detect crashes during initialization. Used for pre-commit validation.
#
# Exit codes:
#   0 - Test passed (no crashes detected)
#   1 - Build failed or crashes detected
#   2 - Not on macOS or xcodebuild not available

# Exit immediately if any command returns non-zero
set -e
# A pipeline fails if any command in it fails
set -o pipefail

# Get the project root directory (where this script lives)
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

# Check if on macOS
if [ "$(uname -s)" != "Darwin" ]; then
    echo "⏭️  Skipping smoke test (not on macOS)"
    exit 2
fi

# Check if xcodebuild is available
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "⏭️  Skipping smoke test (xcodebuild not found)"
    exit 2
fi

echo "🔨 Building Debug configuration..."
cd "$PROJECT_ROOT/src/Playback"

if ! xcodebuild -scheme Playback -configuration Debug CODE_SIGN_IDENTITY="macos-codesigning" build 2>&1 | tail -20; then
    echo ""
    echo "❌ Build failed"
    exit 1
fi

echo ""
echo "✅ Build succeeded"
echo ""
echo "🧪 Running 5-second smoke test..."
echo ""

# Find the most recently built debug app
app=$(find ~/Library/Developer/Xcode/DerivedData -type f -path "*/Build/Products/Debug/Playback.app/Contents/MacOS/Playback" -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -n1)

if [ -z "$app" ] || [ ! -x "$app" ]; then
    echo "❌ Could not find built Playback.app"
    exit 1
fi

# Create temp log file
TEMP_LOG=$(mktemp "${TMPDIR:-/tmp}/smoke-test.XXXXXX.log")
trap "rm -f '$TEMP_LOG'" EXIT

# Run the app with crash backtraces enabled, capturing output
SWIFT_BACKTRACE=enable=yes,interactive=no "$app" > "$TEMP_LOG" 2>&1 & app_pid=$!

# Kill after 5 seconds
( sleep 5; kill -9 "$app_pid" 2>/dev/null || true ) &

# Wait for the app to exit (either naturally or via kill)
wait "$app_pid" 2>/dev/null || true

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if crash detected
if grep -q "Program crashed\|SIGABRT\|SIGSEGV\|SIGBUS" "$TEMP_LOG"; then
    echo "❌ SMOKE TEST FAILED - Crash detected:"
    echo ""
    cat "$TEMP_LOG"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "The app crashed during initialization. See crash log above."
    echo ""
    exit 1
else
    echo "✅ SMOKE TEST PASSED"
    echo ""
    echo "The app ran for 5 seconds without crashing."
    echo ""
fi
