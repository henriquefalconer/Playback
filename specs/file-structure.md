# File Structure Specification

**Component:** File System Organization
**Version:** 2.0
**Last Updated:** 2026-02-07

## Overview

Playback organizes files into three distinct environments: **development** (source code, isolated data), **production** (installed app, user data), and **distribution** (installer packages). This separation ensures clean development workflows without affecting user installations.

## Development File Structure

**Location:** Project source directory (e.g., `~/Projects/playback/`)

```
playback/                                 # Project root
├── .git/                                 # Git repository
├── .gitignore
├── README.md
├── LICENSE
│
├── Playback/                             # Xcode project
│   ├── Playback.xcodeproj/
│   ├── Playback/                         # Main app target
│   │   ├── PlaybackApp.swift            # App entry point (menu bar + timeline)
│   │   ├── MenuBar/
│   │   │   ├── MenuBarView.swift
│   │   │   ├── StatusBarController.swift
│   │   │   └── MenuBarMenu.swift
│   │   ├── Timeline/
│   │   │   ├── TimelineView.swift
│   │   │   ├── VideoPlayer.swift
│   │   │   ├── PlaybackController.swift
│   │   │   └── DateTimePicker.swift
│   │   ├── Settings/
│   │   │   ├── SettingsWindow.swift
│   │   │   ├── GeneralTab.swift
│   │   │   ├── RecordingTab.swift
│   │   │   ├── ProcessingTab.swift
│   │   │   ├── StorageTab.swift
│   │   │   ├── PrivacyTab.swift
│   │   │   ├── AdvancedTab.swift
│   │   │   └── UninstallView.swift       # Uninstall UI (in settings)
│   │   ├── Diagnostics/
│   │   │   ├── DiagnosticsWindow.swift
│   │   │   ├── LogViewer.swift
│   │   │   └── ResourceCharts.swift
│   │   ├── Services/
│   │   │   ├── RecordingService.swift
│   │   │   ├── ProcessingService.swift
│   │   │   └── LaunchAgentManager.swift
│   │   ├── Search/
│   │   │   ├── SearchController.swift
│   │   │   ├── SearchBar.swift
│   │   │   └── OCRService.swift
│   │   ├── Config/
│   │   │   ├── ConfigManager.swift
│   │   │   ├── Environment.swift
│   │   │   └── Paths.swift
│   │   ├── Database/
│   │   │   ├── Database.swift
│   │   │   ├── Segment.swift
│   │   │   └── AppSegment.swift
│   │   └── Resources/
│   │       ├── Assets.xcassets
│   │       ├── Info.plist
│   │       └── embedded_scripts/         # Python scripts (copied at build)
│   ├── PlaybackTests/                    # Unit tests
│   └── PlaybackUITests/                  # UI tests
│
├── scripts/                              # Python scripts (source)
│   ├── record_screen.py                  # Screenshot capture
│   ├── build_chunks_from_temp.py         # Video processing
│   ├── validate_config.py                # Config validation
│   ├── tests/                            # Python tests
│   │   ├── test_recording.py
│   │   └── test_processing.py
│   └── pkg/                              # Installer scripts
│       ├── postinstall
│       └── preinstall
│
├── dev_data/                             # Development data (gitignored)
│   ├── temp/
│   │   └── YYYYMM/DD/
│   ├── chunks/
│   │   └── YYYYMM/DD/
│   └── meta.sqlite3
│
├── dev_logs/                             # Development logs (gitignored)
│   ├── recording.log
│   ├── processing.log
│   └── app.log
│
├── dev_config.json                       # Development config (gitignored)
│
├── specs/                                # This documentation
│   ├── README.md
│   ├── 01-architecture.md
│   ├── ...
│   └── 14-build-process.md
│
├── scripts/                              # Build scripts
│   ├── build_release.sh                  # Production build
│   ├── install_dev_launchagents.sh       # Dev LaunchAgents
│   └── validate_config.py                # Config validator
│
├── exportOptions.plist                   # Xcode export config
├── .swiftlint.yml                        # Swift linting rules
└── .pre-commit-config.yaml               # Pre-commit hooks
```

## Production File Structure

**Location:** User's Mac after installation

```
/
├── Applications/
│   └── Playback.app                      # Single unified app
│       └── Contents/
│           ├── MacOS/
│           │   └── Playback              # Single executable
│           ├── Resources/
│           │   ├── Assets.car
│           │   ├── scripts/              # Embedded Python scripts
│           │   │   ├── record_screen.py
│           │   │   └── build_chunks_from_temp.py
│           │   └── ...
│           ├── Frameworks/               # Embedded frameworks
│           └── Info.plist
│
└── Users/<username>/
    │
    ├── Library/
    │   │
    │   ├── Application Support/
    │   │   └── Playback/
    │   │       ├── config.json           # User configuration
    │   │       ├── config.json.backup.1  # Config backups
    │   │       └── data/                 # User recordings
    │   │           ├── temp/             # Raw screenshots
    │   │           │   └── YYYYMM/DD/
    │   │           ├── chunks/           # Video segments
    │   │           │   └── YYYYMM/DD/
    │   │           └── meta.sqlite3      # Metadata DB
    │   │
    │   ├── LaunchAgents/
    │   │   ├── com.playback.recording.plist
    │   │   └── com.playback.processing.plist
    │   │
    │   └── Logs/
    │       └── Playback/
    │           ├── recording.log
    │           ├── recording.log.1
    │           ├── processing.log
    │           ├── processing.log.1
    │           └── app.log
    │
    └── (no other user-visible files)
```

## Key Differences: Dev vs Production

### Data Directory

**Development:**
- Location: `<project>/dev_data/`
- Gitignored
- Isolated from production
- Can be deleted/recreated freely

**Production:**
- Location: `~/Library/Application Support/Playback/data/`
- Permanent user data
- Backed up by Time Machine
- Never automatically deleted

### Configuration

**Development:**
- File: `<project>/dev_config.json`
- Hot-reloaded on changes
- Debug settings enabled
- Mock data options available

**Production:**
- File: `~/Library/Application Support/Playback/config.json`
- Standard macOS location
- Production settings
- User-configured via Settings UI

### Python Scripts

**Development:**
- Location: `<project>/scripts/`
- Run directly from source
- Changes take effect immediately
- Can edit and test without rebuilding

**Production:**
- Location: Embedded in `Playback.app/Contents/Resources/scripts/`
- Copied at build time
- Immutable (part of signed app bundle)
- Changes require full rebuild

### LaunchAgents

**Development:**
- Label: `com.playback.dev.recording`, `com.playback.dev.processing`
- Point to source scripts
- Environment: `PLAYBACK_DEV_MODE=1`
- Don't interfere with production LaunchAgents

**Production:**
- Label: `com.playback.recording`, `com.playback.processing`
- Point to embedded scripts
- Environment: Standard
- Managed by app

## App Bundle Structure

### Single Unified App

**Playback.app** contains everything:

```
Playback.app/
└── Contents/
    ├── Info.plist
    │
    ├── MacOS/
    │   └── Playback                      # Main executable
    │
    ├── Resources/
    │   ├── Assets.car                    # Compiled assets
    │   ├── AppIcon.icns                  # Play button icon
    │   ├── scripts/                      # Python scripts
    │   │   ├── record_screen.py
    │   │   └── build_chunks_from_temp.py
    │   └── launchagents/                 # LaunchAgent templates
    │       ├── recording.plist.template
    │       └── processing.plist.template
    │
    ├── Frameworks/                       # Embedded frameworks (if any)
    │
    └── _CodeSignature/                   # Code signature
```

**Entry Point:** Single `PlaybackApp.swift` that:
1. Shows menu bar icon on launch
2. Registers global hotkey (Option+Shift+Space) for timeline
3. Manages LaunchAgents for background services
4. Provides settings window (including uninstall)

### No Separate Apps

**Removed:**
- ❌ `Playback Menu.app` (now part of main app)
- ❌ `Uninstall Playback.app` (now button in settings)

**Simplified:**
- ✅ Single icon in Applications folder
- ✅ Single process to manage
- ✅ Cleaner uninstall (just delete one app)

## File Naming Conventions

### Screenshots (temp/)

**Format:** `YYYYMMDD-HHMMSS-<uuid>-<app_id>`

**Examples:**
- `20251222-143050-a1b2c3d4-com.apple.Safari`
- `20251222-143052-e5f6g7h8-com.google.Chrome`

**No Extension:** Raw PNG data without `.png` extension

### Video Segments (chunks/)

**Format:** `<segment_id>.mp4`

**Examples:**
- `a3f8b29c4d1e5f67890a.mp4`
- `b4f9c30d1e2a5f678901.mp4`

**ID Generation:** `os.urandom(10).hex()` (20 hex chars)

### Log Files

**Format:** `<component>.log[.N]`

**Examples:**
- `recording.log` (current)
- `recording.log.1` (most recent rotation)
- `processing.log`
- `app.log` (main app logs)

## File Permissions

### Application Bundle

**Playback.app:** `0755` (executable by all)
```bash
drwxr-xr-x  Playback.app/
-rwxr-xr-x  Playback.app/Contents/MacOS/Playback
```

### User Data

**Sensitive files:** `0600` (user read/write only)
```bash
-rw-------  temp/20251222-143050-a1b2c3d4-com.apple.Safari
-rw-------  chunks/a3f8b29c.mp4
-rw-------  meta.sqlite3
```

**Config and logs:** `0644` (user read/write, others read)
```bash
-rw-r--r--  config.json
-rw-r--r--  recording.log
```

## Storage Estimates

### Per-Day Storage

**Assumptions:**
- 24-hour continuous recording
- 2-second interval
- 3840×2160 resolution (4K)

**Temp Files (before processing):**
- Screenshots: 43,200 per day
- Size: ~20-50 GB per day

**Video Files (after processing):**
- Segments: ~17,000 per day
- Size: ~5-20 GB per day (70-90% compression)

**Database:**
- Growth: ~3 MB per day

### Long-Term Storage

**30 days:** ~600 GB - 1.5 TB
**90 days:** ~1.8 TB - 4.5 TB
**365 days:** ~7 TB - 18 TB

**Recommendation:** External drive for long-term storage

## Gitignore

**`.gitignore`:**
```gitignore
# Development data
dev_data/
dev_logs/
dev_config.json

# Xcode
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/

# Python
__pycache__/
*.pyc
.pytest_cache/

# macOS
.DS_Store
*.swp

# Build artifacts
*.xcarchive
*.pkg
*.dmg

# Logs
*.log
```

## Distribution Structure

**Release Package:** `Playback-1.0.pkg`

**Contents:**
```
Playback-1.0.pkg
├── Playback.app                          # Signed, notarized
├── Scripts/
│   ├── postinstall                       # Setup LaunchAgents, create directories
│   └── preinstall                        # Check dependencies
└── Distribution.xml                      # Installer configuration
```

## Path Conventions

### Generic Paths (No User-Specific References)

**✅ Good (Generic):**
```swift
// Use standard macOS locations
let appSupport = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Playback")

let dataDir = appSupport.appendingPathComponent("data")
```

**❌ Bad (User-Specific):**
```swift
// Don't hardcode user paths
let dataDir = URL(fileURLWithPath: "/Users/someuser/Documents/...")
```

**Environment-Aware:**
```swift
func dataDirectory() -> URL {
    #if DEVELOPMENT
    // Development: relative to project
    return Bundle.main.resourceURL!
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("dev_data")
    #else
    // Production: standard location
    return FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Playback/data")
    #endif
}
```

## Backup and Portability

### What to Backup

**Essential:**
- `~/Library/Application Support/Playback/data/chunks/` (videos)
- `~/Library/Application Support/Playback/data/meta.sqlite3` (metadata)
- `~/Library/Application Support/Playback/config.json` (settings)

**Optional:**
- `data/temp/` (can be regenerated)
- Logs (for troubleshooting only)

**Not Needed:**
- `Playback.app` (reinstallable)
- LaunchAgent plists (regenerated by app)

### Backup Script

```bash
#!/bin/bash
# backup_playback_data.sh

BACKUP_DIR="$HOME/Backups/Playback-$(date +%Y%m%d)"
DATA_DIR="$HOME/Library/Application Support/Playback/data"

mkdir -p "$BACKUP_DIR"

# Backup recordings
echo "Backing up recordings..."
rsync -av "$DATA_DIR/chunks" "$BACKUP_DIR/"

# Backup database
echo "Backing up database..."
cp "$DATA_DIR/meta.sqlite3" "$BACKUP_DIR/"

# Backup config
echo "Backing up configuration..."
cp "$HOME/Library/Application Support/Playback/config.json" "$BACKUP_DIR/"

echo "✓ Backup complete: $BACKUP_DIR"
```

## Migration from Old Structure

**If user has old separate apps:**

```bash
#!/bin/bash
# migrate_to_unified_app.sh

echo "Migrating to unified Playback.app..."

# Remove old separate apps
rm -rf "/Applications/Playback Menu.app"
rm -rf "/Applications/Uninstall Playback.app"

# Update LaunchAgents to point to new unified app
sed -i '' 's|/Applications/Playback Menu.app|/Applications/Playback.app|g' \
    ~/Library/LaunchAgents/com.playback.menubar.plist

# Reload LaunchAgents
launchctl unload ~/Library/LaunchAgents/com.playback.*.plist
launchctl load ~/Library/LaunchAgents/com.playback.*.plist

echo "✓ Migration complete"
```

## Testing File Structure

### Test Data

**Location:** `<project>/test_data/` (gitignored)

```
test_data/
├── fixtures/                             # Test fixtures
│   ├── sample_screenshots/
│   ├── sample_videos/
│   └── sample_db.sqlite3
├── temp/                                 # Test temp files
└── chunks/                               # Test video output
```

**Cleanup:** Deleted after tests complete

## Future Enhancements

1. **iCloud Sync** - Optional sync of chunks/ to iCloud Drive
2. **External Storage** - Support for recordings on external drives
3. **Shared Recordings** - Multiple users, separate data dirs
4. **Compression** - HEVC encoding for smaller files
5. **Cloud Backup** - Automatic backup to cloud storage
