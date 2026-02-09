#!/bin/bash

set -e

echo "=========================================="
echo "Playback Development Environment Setup"
echo "=========================================="
echo ""

# Get project root (script is in scripts/)
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Project root: $PROJECT_ROOT"
echo ""

# 1. Create dev_config.json
echo "Step 1: Creating dev_config.json..."
if [ -f "dev_config.json" ]; then
    echo "  ⚠️  dev_config.json already exists, skipping"
else
    cat > dev_config.json << 'EOF'
{
  "version": "1.0.0",
  "processing_interval_minutes": 5,
  "temp_retention_policy": "1_week",
  "recording_retention_policy": "never",
  "exclusion_mode": "skip",
  "excluded_apps": [],
  "ffmpeg_crf": 28,
  "video_fps": 30,
  "timeline_shortcut": "Option+Shift+Space",
  "pause_when_timeline_open": true,
  "recording_enabled": true,
  "launch_at_login": true,
  "notifications": {
    "processing_complete": true,
    "processing_errors": true,
    "disk_space_warnings": true,
    "recording_status": true
  }
}
EOF
    echo "  ✓ Created dev_config.json"
fi
echo ""

# 2. Create dev directories
echo "Step 2: Creating development directories..."
mkdir -p dev_data/temp dev_data/chunks dev_logs
echo "  ✓ Created dev_data/temp/"
echo "  ✓ Created dev_data/chunks/"
echo "  ✓ Created dev_logs/"
echo ""

# 3. Update .gitignore
echo "Step 3: Updating .gitignore..."
GITIGNORE_ENTRIES=("dev_data/" "dev_logs/" "dev_config.json")
for entry in "${GITIGNORE_ENTRIES[@]}"; do
    if grep -q "^${entry}$" .gitignore 2>/dev/null; then
        echo "  ✓ ${entry} already in .gitignore"
    else
        echo "${entry}" >> .gitignore
        echo "  ✓ Added ${entry} to .gitignore"
    fi
done
echo ""

# 4. Verify Python scripts exist
echo "Step 4: Verifying Python scripts..."
SCRIPTS=("record_screen.py" "build_chunks_from_temp.py" "cleanup_old_chunks.py")
ALL_SCRIPTS_EXIST=true
for script in "${SCRIPTS[@]}"; do
    if [ -f "src/scripts/${script}" ]; then
        echo "  ✓ src/scripts/${script}"
    else
        echo "  ✗ MISSING: src/scripts/${script}"
        ALL_SCRIPTS_EXIST=false
    fi
done
echo ""

# 5. Check Python and FFmpeg
echo "Step 5: Checking dependencies..."
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    echo "  ✓ Python: ${PYTHON_VERSION}"
else
    echo "  ✗ Python 3 not found in PATH"
fi

if command -v ffmpeg &> /dev/null; then
    FFMPEG_VERSION=$(ffmpeg -version 2>&1 | head -n 1)
    echo "  ✓ FFmpeg: ${FFMPEG_VERSION}"
else
    echo "  ✗ FFmpeg not found in PATH"
fi
echo ""

# 6. Final verification
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""

if [ "$ALL_SCRIPTS_EXIST" = true ]; then
    echo "✓ All Python scripts found"
else
    echo "⚠️  Some Python scripts are missing"
fi

echo ""
echo "Next steps:"
echo ""
echo "1. Open Xcode:"
echo "   cd src/Playback && open Playback.xcodeproj"
echo ""
echo "2. Set TWO environment variables in Xcode:"
echo "   - Click scheme dropdown → 'Edit Scheme...'"
echo "   - Select 'Run' → 'Arguments' tab"
echo "   - Add TWO Environment Variables:"
echo ""
echo "     Variable 1:"
echo "       Name:  PLAYBACK_DEV_MODE"
echo "       Value: 1"
echo ""
echo "     Variable 2 (REQUIRED):"
echo "       Name:  SRCROOT"
echo "       Value: $PROJECT_ROOT"
echo "       (or use: ~/Playback if that's your path)"
echo ""
echo "3. Build and run the app (Cmd+R)"
echo ""
echo "4. Verify development mode in app:"
echo "   Settings → Advanced → Force Run Services"
echo "   Should see: 'Development Mode: true'"
echo "   Should see: 'SRCROOT: $PROJECT_ROOT'"
echo ""
echo "⚠️  IMPORTANT: SRCROOT is REQUIRED for script detection!"
echo ""
echo "See DEVELOPMENT_SETUP.md for detailed instructions."
echo ""
