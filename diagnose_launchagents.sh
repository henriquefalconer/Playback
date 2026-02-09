#!/bin/bash

echo "=== LAUNCHAGENT TEMPLATE DIAGNOSTICS ==="
echo ""
echo "Date: $(date)"
echo ""

PROJECT_ROOT="/Users/henriquefalconer/Playback"
cd "$PROJECT_ROOT"

echo "=== 1. Check Template Files in Source ==="
echo ""
TEMPLATES_DIR="$PROJECT_ROOT/src/Playback/Playback/Resources/launchagents"
echo "Templates directory: $TEMPLATES_DIR"
echo ""

if [ -d "$TEMPLATES_DIR" ]; then
    echo "✓ Directory exists"
    echo ""
    echo "Contents:"
    ls -la "$TEMPLATES_DIR"
    echo ""

    # Check for specific templates
    for template in recording.plist.template processing.plist.template cleanup.plist.template; do
        if [ -f "$TEMPLATES_DIR/$template" ]; then
            echo "✓ $template exists"
            echo "  Size: $(wc -c < "$TEMPLATES_DIR/$template") bytes"
            echo "  First 5 lines:"
            head -5 "$TEMPLATES_DIR/$template" | sed 's/^/    /'
            echo ""
        else
            echo "✗ $template MISSING"
            echo ""
        fi
    done
else
    echo "✗ Templates directory DOES NOT EXIST"
    echo ""
    echo "Creating it now..."
    mkdir -p "$TEMPLATES_DIR"
    echo "✓ Created $TEMPLATES_DIR"
    echo ""
fi

echo "=== 2. Check App Bundle Resources ==="
echo ""

# Find the app bundle
APP_BUNDLE=$(find ~/Library/Developer/Xcode/DerivedData/Playback-*/Build/Products/Debug/Playback.app -maxdepth 0 2>/dev/null | head -1)

if [ -n "$APP_BUNDLE" ]; then
    echo "Found app bundle: $APP_BUNDLE"
    echo ""

    RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
    echo "Resources directory: $RESOURCES_DIR"
    echo ""

    if [ -d "$RESOURCES_DIR/launchagents" ]; then
        echo "✓ launchagents/ exists in Resources"
        echo ""
        echo "Contents:"
        ls -la "$RESOURCES_DIR/launchagents"
        echo ""
    else
        echo "✗ launchagents/ NOT FOUND in Resources"
        echo ""
        echo "Resources directory contains:"
        ls -la "$RESOURCES_DIR" | head -20
        echo ""
    fi
else
    echo "✗ App bundle not found in DerivedData"
    echo ""
fi

echo "=== 3. Check Xcode Project Build Phase ==="
echo ""

XCODEPROJ="$PROJECT_ROOT/src/Playback/Playback.xcodeproj"
PBXPROJ="$XCODEPROJ/project.pbxproj"

if [ -f "$PBXPROJ" ]; then
    echo "Checking if launchagents templates are in 'Copy Bundle Resources' phase..."
    echo ""

    if grep -q "launchagents" "$PBXPROJ"; then
        echo "✓ 'launchagents' mentioned in project.pbxproj"
        echo ""
        echo "Matching lines:"
        grep -n "launchagents" "$PBXPROJ" | head -10
        echo ""
    else
        echo "✗ 'launchagents' NOT found in project.pbxproj"
        echo ""
        echo "This means the templates are not added to the Xcode project!"
        echo ""
    fi

    # Check for plist.template files
    if grep -q "plist.template" "$PBXPROJ"; then
        echo "✓ '.plist.template' files found in project"
        echo ""
        echo "Template files in project:"
        grep "plist.template" "$PBXPROJ" | grep -o '[a-z_]*\.plist\.template' | sort -u
        echo ""
    else
        echo "✗ No .plist.template files in project.pbxproj"
        echo ""
    fi
else
    echo "✗ project.pbxproj not found"
    echo ""
fi

echo "=== 4. Check Existing LaunchAgents ==="
echo ""

LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
echo "LaunchAgents directory: $LAUNCH_AGENTS_DIR"
echo ""

if ls "$LAUNCH_AGENTS_DIR"/*playback* 2>/dev/null; then
    echo ""
    echo "Existing Playback LaunchAgents:"
    for plist in "$LAUNCH_AGENTS_DIR"/*playback*.plist; do
        if [ -f "$plist" ]; then
            echo ""
            echo "File: $(basename "$plist")"
            echo "Size: $(wc -c < "$plist") bytes"
            echo "Content preview:"
            head -10 "$plist" | sed 's/^/  /'
        fi
    done
else
    echo "✓ No existing Playback LaunchAgents found (clean state)"
fi
echo ""

echo "=== 5. Check Python Scripts Permissions ==="
echo ""

for script in record_screen.py build_chunks_from_temp.py cleanup_old_chunks.py; do
    SCRIPT_PATH="$PROJECT_ROOT/src/scripts/$script"
    if [ -f "$SCRIPT_PATH" ]; then
        echo "✓ $script"
        ls -la "$SCRIPT_PATH"

        # Check if executable
        if [ -x "$SCRIPT_PATH" ]; then
            echo "  Status: Executable ✓"
        else
            echo "  Status: Not executable (might need chmod +x)"
        fi

        # Check shebang
        SHEBANG=$(head -1 "$SCRIPT_PATH")
        echo "  Shebang: $SHEBANG"
        echo ""
    else
        echo "✗ $script NOT FOUND"
        echo ""
    fi
done

echo "=== DIAGNOSTICS COMPLETE ==="
echo ""
echo "=== SUMMARY ==="
echo ""
echo "If templates are MISSING from app bundle Resources:"
echo "  → You need to add them to Xcode project 'Copy Bundle Resources' phase"
echo ""
echo "If templates are in source but not in project.pbxproj:"
echo "  → Open Xcode, right-click Resources folder → Add Files"
echo "  → Select launchagents/ folder, ensure 'Copy items' is checked"
echo ""
