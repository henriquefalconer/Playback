# File Structure Implementation Plan

**Component:** File System Organization
**Version:** 2.1
**Last Updated:** 2026-02-09

## Implementation Checklist

### Development Directory Structure
- [ ] Set up project root structure
  - Create `.gitignore` with development data exclusions
  - Create `README.md` and `LICENSE` files
  - Initialize Git repository if not already present

- [ ] Create source directory structure
  - Root: `src/` - All source code
  - Swift app: `src/Playback/` - Xcode project and Swift source
  - Python services: `src/scripts/` - Recording and processing services
  - Shared utilities: `src/lib/` - Shared Python modules (planned)

- [ ] Create Xcode project hierarchy
  - Directory: `src/Playback/Playback.xcodeproj`
  - Main target: `src/Playback/Playback/`
  - Test targets: `src/Playback/PlaybackTests/` and `src/Playback/PlaybackUITests/`
  - Minimum deployment: macOS 26.0 (Tahoe)
  - Architecture: Apple Silicon only

- [ ] Set up Swift source directory organization
  - `src/Playback/Playback/PlaybackApp.swift` - Single app entry point
  - `src/Playback/Playback/MenuBar/` - Menu bar component
  - `src/Playback/Playback/Timeline/` - Timeline viewer component
  - `src/Playback/Playback/Settings/` - Settings window with UninstallView
  - `src/Playback/Playback/Diagnostics/` - Diagnostics and logging
  - `src/Playback/Playback/Services/` - Recording, processing, LaunchAgent management
  - `src/Playback/Playback/Search/` - Search controller and OCR service
  - `src/Playback/Playback/Config/` - ConfigManager, Environment, Paths
  - `src/Playback/Playback/Database/` - Database access layer
  - `src/Playback/Playback/Resources/` - Assets, Info.plist, embedded_scripts/

- [x] Create Python scripts directory
  - `src/scripts/record_screen.py` - Screenshot capture service (implemented)
  - `src/scripts/build_chunks_from_temp.py` - Video processing service (implemented)
  - `src/scripts/cleanup_old_chunks.py` - Retention policy enforcement (implemented)
  - `src/scripts/requirements.txt` - Python dependencies (PyObjC, Pillow, psutil)
  - `src/lib/test_*.py` - Python unit tests (280 tests passing)

- [x] Create shared Python library directory (implemented)
  - `src/lib/` - Shared utilities (9 modules, 280 tests passing)
  - Implemented modules: paths.py, database.py, video.py, macos.py, timestamps.py, config.py, logging_config.py, security.py, network.py

- [ ] Create development data directories (gitignored)
  - `dev_data/temp/` - Development screenshots with date structure
  - `dev_data/chunks/` - Development video segments with date structure
  - `dev_data/meta.sqlite3` - Development metadata database

- [ ] Create development logs directory (gitignored)
  - `dev_logs/recording.log` - Recording service logs
  - `dev_logs/processing.log` - Processing service logs
  - `dev_logs/app.log` - Main application logs

- [ ] Create specs directory structure
  - `specs/README.md` - Specification index
  - `specs/*.md` - Implementation plans for all components

- [ ] Create build scripts directory
  - `src/scripts/build_release.sh` - Production build automation
  - `src/scripts/install_dev_launchagents.sh` - Dev LaunchAgent setup
  - `src/scripts/validate_config.py` - Config validation

- [ ] Create build configuration files
  - `exportOptions.plist` - Xcode export configuration
  - `.swiftlint.yml` - Swift linting rules
  - `.pre-commit-config.yaml` - Pre-commit hooks

### Production Directory Structure
- [ ] Configure application bundle structure
  - Single app: `Playback.app` (no separate menu/uninstall apps)
  - Executable: `Contents/MacOS/Playback`
  - Resources: `Contents/Resources/scripts/` for Python scripts
  - Templates: `Contents/Resources/launchagents/*.plist.template`
  - Frameworks: `Contents/Frameworks/` for embedded dependencies
  - Signature: `Contents/_CodeSignature/` for code signing

- [ ] Set up user data directories
  - Base: `~/Library/Application Support/Playback/`
  - Config: `~/Library/Application Support/Playback/config.json`
  - Backups: `~/Library/Application Support/Playback/config.json.backup.N`
  - Data root: `~/Library/Application Support/Playback/data/`
  - Temp: `~/Library/Application Support/Playback/data/temp/YYYYMM/DD/`
  - Chunks: `~/Library/Application Support/Playback/data/chunks/YYYYMM/DD/`
  - Database: `~/Library/Application Support/Playback/data/meta.sqlite3`

- [ ] Configure LaunchAgents directory
  - Recording: `~/Library/LaunchAgents/com.playback.recording.plist`
  - Processing: `~/Library/LaunchAgents/com.playback.processing.plist`

- [ ] Set up logs directory
  - Base: `~/Library/Logs/Playback/`
  - Recording: `~/Library/Logs/Playback/recording.log` (with rotation)
  - Processing: `~/Library/Logs/Playback/processing.log` (with rotation)
  - App: `~/Library/Logs/Playback/app.log`

### Path Resolution (Dev vs Prod)
- [x] Implement Environment detection in Paths.swift
  - Source: `src/Playback/Playback/Paths.swift`
  - Detection: Check for `PLAYBACK_DEV_MODE=1` environment variable
  - **REQUIRED:** `SRCROOT` environment variable must be set in development mode
  - See: "Key Differences: Development vs Production" section below

- [x] Implement Paths.swift
  - Source: `src/Playback/Playback/Paths.swift`
  - Properties: baseDataDirectory, databasePath, chunksDirectory, configPath()
  - Dev paths: Use SRCROOT environment variable (mandatory)
  - Prod paths: Standard macOS locations (FileManager API)
  - See: "Path Resolution Examples" section below

- [x] Create path resolution helpers
  - Generic paths only (no hardcoded usernames)
  - Use FileManager.default.urls(for:in:) for standard locations
  - Handle both environments transparently
  - **CRITICAL:** All development path resolution requires SRCROOT environment variable

### Environment Detection
- [x] Implement development mode detection
  - Check: `ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"]`
  - Build flag: Inject `PLAYBACK_DEV_MODE=1` in Debug scheme
  - **REQUIRED:** `SRCROOT` environment variable must be set in Xcode scheme
  - LaunchAgents: Use separate labels (com.playback.dev.*)

- [x] Configure development vs production behavior
  - Dev: Hot-reload config changes, verbose logging
  - Prod: Stable config, production settings only
  - Dev: Scripts run from source directory (via SRCROOT)
  - Prod: Scripts run from app bundle

- [x] Set up development isolation
  - Dev data completely separate from production
  - Dev LaunchAgents don't interfere with production
  - Can run both simultaneously without conflict

- [x] **CRITICAL: SRCROOT Environment Variable**
  - **Mandatory for development mode** - app will crash with `fatalError` if not set
  - Set in Xcode: Edit Scheme → Run → Arguments → Environment Variables
  - Name: `SRCROOT`
  - Value: `/Users/YOUR_USERNAME/Playback` (or `~/Playback`)
  - Used by: `Paths.swift`, `LaunchAgentManager.swift`, `DiagnosticsController.swift`, `SettingsView.swift`
  - Why: Bundle path resolution from DerivedData is unreliable, SRCROOT provides explicit project root

### File Naming Conventions
- [ ] Implement screenshot naming
  - Format: `YYYYMMDD-HHMMSS-<uuid>-<app_id>`
  - Example: `20251222-143050-a1b2c3d4-com.apple.Safari`
  - No extension (raw PNG data)
  - Source: `src/scripts/record_screen.py`

- [ ] Implement video segment naming
  - Format: `<segment_id>.mp4`
  - ID generation: `os.urandom(10).hex()` (20 hex characters)
  - Example: `a3f8b29c4d1e5f67890a.mp4`
  - Source: `src/scripts/build_chunks_from_temp.py`

- [ ] Implement log file naming
  - Format: `<component>.log[.N]`
  - Current: `recording.log`
  - Rotated: `recording.log.1`, `recording.log.2`, etc.
  - Components: recording, processing, app

- [ ] Create date-based directory structure
  - Pattern: `YYYYMM/DD/`
  - Example: `202512/22/` for December 22, 2025
  - Used for both temp/ and chunks/ directories

### App Bundle Structure
- [ ] Configure build phase for script embedding
  - Copy Phase: `src/scripts/*.py` → `Resources/scripts/`
  - Timing: Build time (immutable in production)
  - Preserve permissions: Executable scripts
  - See: "Scripts Embedding in Bundle" section below

- [x] Create LaunchAgent templates
  - Recording template: `Resources/recording.plist.template` (directly in Resources/)
  - Processing template: `Resources/processing.plist.template` (directly in Resources/)
  - Cleanup template: `Resources/cleanup.plist.template` (directly in Resources/)
  - Variables: `{{LABEL}}`, `{{SCRIPT_PATH}}`, `{{LOG_PATH}}`, `{{CONFIG_PATH}}`, `{{DATA_DIR}}`, `{{DEV_MODE}}`
  - Instantiation: At app first launch or via Force Run Services in settings

- [ ] Set up single app architecture
  - Remove: Separate `Playback Menu.app` and `Uninstall Playback.app`
  - Unified: Single `PlaybackApp.swift` with MenuBarExtra + Window
  - Uninstall: Button in Settings window (UninstallView.swift)

### Scripts Embedding in Bundle
- [ ] Configure Xcode build phases
  - Add "Copy Files" phase for Python scripts
  - Destination: Resources
  - Subpath: `scripts/`
  - Files: `record_screen.py`, `build_chunks_from_temp.py`

- [ ] Set up script path resolution
  - Production: `Bundle.main.resourceURL/scripts/`
  - Development: Project source `src/scripts/` directory
  - Environment-aware: Switch based on PLAYBACK_DEV_MODE

- [ ] Handle script permissions
  - Ensure executable bit set in copy phase
  - Verify Python shebang: `#!/usr/bin/env python3`

### Gitignore Setup
- [ ] Create .gitignore file
  - Development data: `dev_data/`, `dev_logs/`, `dev_config.json`
  - Xcode: `*.xcodeproj/xcuserdata/`, `DerivedData/`, `build/`
  - Python: `__pycache__/`, `*.pyc`, `.pytest_cache/`
  - macOS: `.DS_Store`, `*.swp`
  - Build artifacts: `*.xcarchive`, `*.pkg`, `*.dmg`
  - Logs: `*.log`
  - See: "Gitignore Configuration" section below

### Backup Script Creation
- [ ] Create backup_playback_data.sh
  - Location: `src/scripts/backup_playback_data.sh`
  - Backup target: Date-stamped directory (`~/Backups/Playback-YYYYMMDD`)
  - Essential data: chunks/, meta.sqlite3, config.json
  - Method: rsync for chunks (efficient), cp for config/database
  - See: "Backup Script Details" section below

- [ ] Implement backup functionality in app
  - Settings UI: "Backup Data" button
  - Destination picker: Allow user to select backup location
  - Progress indicator: Show backup progress
  - Notification: Completion with size and location

### Migration from Old Structure
- [ ] Create migration script
  - Location: `src/scripts/migrate_to_unified_app.sh`
  - Remove: Old separate apps (`Playback Menu.app`, `Uninstall Playback.app`)
  - Update: LaunchAgent plists to point to unified app
  - Reload: LaunchAgents with new configuration
  - See: "Migration Procedures" section below

- [ ] Implement migration detection
  - Check: Presence of old app bundles in /Applications/
  - Prompt: Ask user to migrate on first launch
  - Automatic: Offer to run migration script
  - Backup: Create backup before migration

- [ ] Handle data directory migration
  - Old location: Check if different from current standard
  - Move: Copy data to new location if needed
  - Cleanup: Remove old data after successful migration
  - Verify: Ensure all data copied correctly

### Development Tools
- [x] Force Run Services diagnostic tool
  - Location: Settings → Advanced → Force Run Services button
  - 7-step diagnostic: Enable recording, check permissions, verify scripts, install agents, start services, verify status, show environment
  - Export: Saves full diagnostic report to Desktop
  - Error handling: Shows concise summary in alert, full details in export
  - Status check: 3-second wait for launchd to register processes

### File Permissions
- [ ] Set application bundle permissions
  - App bundle: `0755` (drwxr-xr-x)
  - Executable: `0755` (-rwxr-xr-x)
  - Resources: `0644` (-rw-r--r--)

- [ ] Set user data permissions
  - Screenshots: `0600` (-rw------) - user only
  - Videos: `0600` (-rw------) - user only
  - Database: `0600` (-rw------) - user only
  - Config: `0644` (-rw-r--r--) - readable by others
  - Logs: `0644` (-rw-r--r--) - readable by others

- [ ] Implement permission checks
  - Verify: Screen Recording permission at launch
  - Verify: Accessibility permission for app detection
  - Create: Directories with correct permissions
  - Warn: If permissions incorrect or missing

### Distribution Structure
- [ ] Configure installer package
  - Format: `Playback-1.0.pkg`
  - Contents: Signed, notarized Playback.app
  - Scripts: preinstall, postinstall
  - Configuration: Distribution.xml

- [ ] Create postinstall script
  - Create: Application Support and Logs directories
  - Install: LaunchAgent plists from app bundle templates
  - Set: Correct file permissions
  - Start: LaunchAgents if requested

- [ ] Create preinstall script
  - Check: macOS version (26.0+)
  - Check: Available disk space (minimum 100GB recommended)
  - Stop: Running LaunchAgents if present
  - Backup: Existing configuration if present

## File Structure Details

### Complete Directory Trees

#### Development Directory Tree
```
.
├── src/                                     # All source code
│   ├── Playback/                           # Swift app
│   │   ├── Playback.xcodeproj/
│   │   │   ├── project.pbxproj
│   │   │   └── project.xcworkspace/
│   │   ├── Playback/
│   │   │   ├── PlaybackApp.swift          # Single unified app entry point
│   │   │   ├── MenuBar/
│   │   │   │   ├── MenuBarView.swift
│   │   │   │   ├── MenuBarController.swift
│   │   │   │   └── StatusItemManager.swift
│   │   │   ├── Timeline/
│   │   │   │   ├── TimelineView.swift
│   │   │   │   ├── TimelineController.swift
│   │   │   │   ├── VideoPlayer.swift
│   │   │   │   └── TimelineScrollView.swift
│   │   │   ├── Settings/
│   │   │   │   ├── SettingsView.swift
│   │   │   │   ├── SettingsController.swift
│   │   │   │   ├── UninstallView.swift    # Uninstall UI (no separate app)
│   │   │   │   └── PrivacySettingsView.swift
│   │   │   ├── Diagnostics/
│   │   │   │   ├── DiagnosticsView.swift
│   │   │   │   ├── LogViewer.swift
│   │   │   │   └── SystemInfoCollector.swift
│   │   │   ├── Services/
│   │   │   │   ├── RecordingService.swift
│   │   │   │   ├── ProcessingService.swift
│   │   │   │   ├── LaunchAgentManager.swift
│   │   │   │   └── PermissionsManager.swift
│   │   │   ├── Search/
│   │   │   │   ├── SearchController.swift
│   │   │   │   ├── OCRService.swift
│   │   │   │   └── SearchResultsView.swift
│   │   │   ├── Config/
│   │   │   │   ├── ConfigManager.swift
│   │   │   │   ├── Environment.swift      # Dev vs Prod detection
│   │   │   │   └── Paths.swift            # Path resolution
│   │   │   ├── Database/
│   │   │   │   ├── DatabaseManager.swift
│   │   │   │   ├── SchemaManager.swift
│   │   │   │   └── Queries/
│   │   │   └── Resources/
│   │   │       ├── Assets.xcassets/
│   │   │       ├── Info.plist
│   │   │       └── embedded_scripts/
│   │   ├── PlaybackTests/
│   │   │   ├── ConfigTests.swift
│   │   │   ├── PathsTests.swift
│   │   │   └── ServicesTests.swift
│   │   └── PlaybackUITests/
│   │       ├── TimelineUITests.swift
│   │       └── SettingsUITests.swift
│   ├── scripts/                            # Python services
│   │   ├── record_screen.py               # Screenshot capture service
│   │   ├── build_chunks_from_temp.py      # Video processing service
│   │   ├── validate_config.py             # Config validation utility
│   │   ├── build_release.sh               # Production build automation
│   │   ├── install_dev_launchagents.sh    # Dev LaunchAgent setup
│   │   ├── backup_playback_data.sh        # User data backup utility
│   │   ├── migrate_to_unified_app.sh      # Migration script
│   │   ├── tests/
│   │   │   ├── test_record_screen.py
│   │   │   └── test_build_chunks.py
│   │   └── pkg/
│   │       ├── postinstall                # Installer post-install
│   │       └── preinstall                 # Installer pre-install
│   └── lib/                                # Shared Python utilities (planned)
│       └── .gitkeep                       # Placeholder for future modules
├── specs/                                 # Implementation plans
│   ├── README.md                         # Specification index
│   ├── file-structure.md                 # This document
│   └── *.md                              # Component specifications
├── dev_data/                              # GITIGNORED
│   ├── temp/                              # Development screenshots
│   │   ├── 202512/
│   │   │   ├── 22/
│   │   │   │   ├── 20251222-143050-a1b2c3d4-com.apple.Safari
│   │   │   │   ├── 20251222-143051-b2c3d4e5-com.apple.Mail
│   │   │   │   └── ...
│   │   │   └── 23/
│   │   └── 202601/
│   ├── chunks/                            # Development video segments
│   │   ├── 202512/
│   │   │   ├── 22/
│   │   │   │   ├── a3f8b29c4d1e5f67890a.mp4
│   │   │   │   ├── b4c9d3ae5f2g6h78901b.mp4
│   │   │   │   └── ...
│   │   │   └── 23/
│   │   └── 202601/
│   └── meta.sqlite3                       # Development database
├── dev_logs/                              # GITIGNORED
│   ├── recording.log
│   ├── recording.log.1
│   ├── processing.log
│   ├── processing.log.1
│   └── app.log
├── dev_config.json                        # GITIGNORED
├── .gitignore
├── .swiftlint.yml
├── .pre-commit-config.yaml
├── exportOptions.plist
├── README.md
└── LICENSE
```

#### Production Directory Tree
```
/Applications/
└── Playback.app/                            # Single unified app
    ├── Contents/
    │   ├── Info.plist
    │   ├── MacOS/
    │   │   └── Playback                     # Main executable
    │   ├── Resources/
    │   │   ├── Assets.car
    │   │   ├── recording.plist.template     # LaunchAgent templates (root level)
    │   │   ├── processing.plist.template
    │   │   ├── cleanup.plist.template
    │   │   └── scripts/                     # Embedded Python scripts
    │   │       ├── record_screen.py
    │   │       ├── build_chunks_from_temp.py
    │   │       └── cleanup_old_chunks.py
    │   ├── Frameworks/                      # Embedded dependencies
    │   │   └── [Any required frameworks]
    │   └── _CodeSignature/
    │       └── CodeResources

~/Library/Application Support/Playback/
├── config.json                              # User configuration
├── config.json.backup.1                     # Config backup (rotating)
├── config.json.backup.2
├── config.json.backup.3
└── data/
    ├── temp/                                # Screenshots
    │   ├── 202512/
    │   │   ├── 22/
    │   │   │   ├── 20251222-143050-a1b2c3d4-com.apple.Safari
    │   │   │   ├── 20251222-143051-b2c3d4e5-com.apple.Mail
    │   │   │   └── ... (~28,800 files/day)
    │   │   └── 23/
    │   └── 202601/
    ├── chunks/                              # Video segments (MP4)
    │   ├── 202512/
    │   │   ├── 22/
    │   │   │   ├── a3f8b29c4d1e5f67890a.mp4  # 5-minute segment
    │   │   │   ├── b4c9d3ae5f2g6h78901b.mp4
    │   │   │   └── ... (~288 files/day)
    │   │   └── 23/
    │   └── 202601/
    └── meta.sqlite3                         # Metadata database

~/Library/LaunchAgents/
├── com.playback.recording.plist             # Recording service
└── com.playback.processing.plist            # Processing service

~/Library/Logs/Playback/
├── recording.log                            # Current recording log
├── recording.log.1                          # Rotated log
├── recording.log.2
├── processing.log                           # Current processing log
├── processing.log.1
├── processing.log.2
└── app.log                                  # Main app log
```

### Shared Python Utilities (src/lib/)

**Status:** ✅ Implemented (280 tests passing, 100% test coverage)

The `src/lib/` directory contains shared Python utilities that consolidate common functionality across recording and processing services. All modules are production-ready with comprehensive test coverage.

#### Implemented Modules

**`src/lib/paths.py`** - Centralized path resolution
- `PROJECT_ROOT` - Auto-detect project root from script location
- `resolve_data_dir()` - Return dev_data/ or ~/Library/Application Support/Playback/data/
- `resolve_config_path()` - Return dev_config.json or ~/Library/Application Support/Playback/config.json
- `CHUNKS_ROOT`, `TEMP_ROOT`, `META_DB_PATH` - Path constants for data directories
- Environment-aware resolution based on `PLAYBACK_DEV_MODE` environment variable

**`src/lib/database.py`** - SQLite operations for meta.sqlite3
- `init_meta_db(db_path)` - Initialize database schema and tables
- `insert_segment_meta(db_path, segment_data)` - Insert video segment metadata
- `insert_appsegment_meta(db_path, app_data)` - Insert app activity segment
- `query_segments(db_path, start_time, end_time)` - Query helper for segments table
- Connection pooling and transaction management

**`src/lib/video.py`** - FFmpeg wrappers and video processing
- `get_image_size(image_path)` - Get PNG dimensions via ffprobe
- `run_ffmpeg_make_segment(input_pattern, output_path, fps, crf)` - Generate video from image sequence
- FFmpeg command builders with standard parameters (H.264, CRF 28, veryfast preset)
- Error handling and logging for video generation failures

**`src/lib/macos.py`** - macOS-specific utilities
- `_load_coregraphics()` - CoreGraphics framework loader via ctypes
- `_check_display_active()` - Check if display is powered on
- `_get_active_display_index()` - Detect active monitor index
- `_get_frontmost_app_bundle_id()` - Get active app bundle ID via AppleScript
- `is_screen_unavailable()` - Combined check for screen lock, sleep, or screensaver
- macOS system integration utilities

**`src/lib/timestamps.py`** - Timestamp parsing and formatting
- `DATE_RE` - Regex pattern for YYYYMMDD-HHMMSS format
- `parse_timestamp_from_name(filename)` - Extract timestamp from screenshot filename
- `parse_app_from_name(filename)` - Extract app bundle ID from screenshot filename
- `generate_chunk_name()` - Create standardized video segment filename
- Timestamp conversion utilities (Unix epoch ↔ YYYYMMDD-HHMMSS)

#### Integration with Services

Recording and processing services will migrate duplicated logic to these shared utilities:

**Recording Service (`src/scripts/record_screen.py`):**
- Use `src/lib/paths.py` for data directory resolution
- Use `src/lib/macos.py` for screen availability checks and app detection
- Use `src/lib/timestamps.py` for screenshot filename generation

**Processing Service (`src/scripts/build_chunks_from_temp.py`):**
- Use `src/lib/paths.py` for data directory resolution
- Use `src/lib/database.py` for segment metadata insertion
- Use `src/lib/video.py` for FFmpeg operations
- Use `src/lib/timestamps.py` for parsing screenshot timestamps

#### Implementation Notes

- Modules designed to be **stateless** and **side-effect free** where possible
- All path resolution uses environment variables (`PLAYBACK_DEV_MODE`) for dev/prod detection
- Error handling with structured logging (JSON format for machine readability)
- Type hints on all public functions for better IDE support and documentation
- Comprehensive unit tests with 280 passing tests across 9 modules

**Status:** ✅ **Implemented and Production-Ready** - All modules are fully implemented with 100% test coverage.

**Additional Implemented Modules:**
- `src/lib/config.py` - Configuration loading with validation and defaults
- `src/lib/logging_config.py` - Structured JSON logging with rotation
- `src/lib/security.py` - Permission checking and validation
- `src/lib/network.py` - Network availability detection

### File Naming Patterns

#### Screenshots (temp/)
**Format:** `YYYYMMDD-HHMMSS-<uuid>-<app_id>`

**Components:**
- `YYYYMMDD`: Date (e.g., `20251222`)
- `HHMMSS`: Time (e.g., `143050` for 2:30:50 PM)
- `<uuid>`: 8-character hex UUID (e.g., `a1b2c3d4`)
- `<app_id>`: Bundle identifier of active app (e.g., `com.apple.Safari`)

**Examples:**
```
20251222-143050-a1b2c3d4-com.apple.Safari
20251222-143051-b2c3d4e5-com.apple.Mail
20251222-143052-c3d4e5f6-com.microsoft.VSCode
20251222-143053-d4e5f6g7-com.google.Chrome
```

**Properties:**
- No file extension (raw PNG data)
- Chronologically sortable by name
- Unique per second (UUID prevents collision)
- App context preserved in filename

**Generation:** Python `src/scripts/record_screen.py`

#### Video Segments (chunks/)
**Format:** `<segment_id>.mp4`

**Components:**
- `<segment_id>`: 20-character hex string (from `os.urandom(10).hex()`)
- Extension: `.mp4` (H.264/AAC encoding)

**Examples:**
```
a3f8b29c4d1e5f67890a.mp4
b4c9d3ae5f2g6h78901b.mp4
c5e0f4bg6j3k7m89012c.mp4
```

**Properties:**
- Random, collision-resistant IDs
- 5-minute duration per segment
- ~500-750 MB per file
- Database stores: chunk_id, start_time, end_time, file_path

**Generation:** Python `src/scripts/build_chunks_from_temp.py`

#### Log Files
**Format:** `<component>.log[.N]`

**Components:**
- `<component>`: Service name (recording, processing, app)
- `.N`: Rotation number (1, 2, 3...)

**Examples:**
```
recording.log         # Current log
recording.log.1       # Previous rotation
recording.log.2       # Older rotation
processing.log
processing.log.1
app.log
```

**Rotation Policy:**
- Max size: 10 MB per log file
- Max rotations: 5 files retained
- Total per service: ~50 MB maximum
- Rotation: Automatic on size threshold

#### Date-Based Directories
**Format:** `YYYYMM/DD/`

**Examples:**
```
202512/22/    # December 22, 2025
202512/23/    # December 23, 2025
202601/01/    # January 1, 2026
```

**Properties:**
- Two-level hierarchy (month/day)
- Efficient for date-range queries
- Simplifies cleanup (delete old month directories)
- Standard across temp/ and chunks/

### Storage Estimates

> **Note:** Screenshot storage estimates are pending real-world usage data and will be updated after 1 month of production use. Estimates below focus on processed video segments.

#### Per-Day Storage
**Screenshots (temp/):**
- *Storage estimates pending - will be updated after 1 month of usage data*
- Temporary storage only (deleted after processing)
- Expected to be significantly less than video segment storage

**Video Segments (chunks/):**
- Segment duration: 5 seconds video (represents 5 minutes real-time)
- File size: **~7.5 MB per segment** (H.264, CRF 28, 30fps)
- Recording pattern: Varies by user activity (4-5 hours typical usage)
- Typical segments per day: 48-60 segments (4-5 hours of recording)
- Daily total: 48-60 × 7.5 MB = **~360-450 MB/day**

**Combined Daily:**
- Screenshots: *TBD after usage data collection*
- Videos: 360-450 MB
- **Total: ~360-450 MB/day** (videos only, screenshots TBD)

#### Long-Term Storage
**30 Days (1 month):**
- Videos: 30 × 405 MB = **~12.2 GB/month**
- Expected range: **10-14 GB/month** (based on typical usage patterns)
- Screenshots: *TBD*

**90 Days (3 months):**
- Videos: 90 × 405 MB = **~36.5 GB**
- Expected range: 30-42 GB

**365 Days (1 year):**
- Videos: 365 × 405 MB = **~148 GB**
- Expected range: 120-170 GB (depending on usage patterns)

**Recommended Minimum:**
- System drive: 100 GB free for 6 months of recordings
- External drive: 500 GB for extended retention (2+ years)
- Cloud backup: Optional, ~12 GB/month upload

**Usage Pattern Notes:**
- Estimates assume 4-5 hours of active recording per day
- Actual usage varies significantly by user:
  - Light users (2-3 hours/day): ~6-8 GB/month
  - Typical users (4-5 hours/day): ~10-14 GB/month
  - Heavy users (8+ hours/day): ~20-28 GB/month
- Recording pauses during screen lock, screensaver, and excluded apps

#### Database Growth
**Records Per Day:**
- Segments: 48-60 records (per typical usage)
- OCR results: Varies by screenshot count (TBD)

**Database Size:**
- Per day: ~5-10 MB (with indexes and metadata)
- Per month: ~150-300 MB
- Per year: ~1.8-3.6 GB

**Total Storage (1 Year, Typical Usage):**
- Video segments: ~148 GB
- Database: ~2.5 GB
- Logs: ~2 GB
- **Total: ~152.5 GB**

### Path Resolution Examples

#### Environment Detection
**Development Mode:**
```swift
// Environment.swift
static var isDevelopment: Bool {
    #if DEVELOPMENT
    return true
    #else
    return ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"] == "1"
    #endif
}
```

**Usage:**
```swift
if Environment.isDevelopment {
    print("Running in development mode")
    // Use dev_data/, dev_config.json, dev_logs/
} else {
    print("Running in production mode")
    // Use ~/Library/Application Support/Playback/
}
```

#### Path Resolution
**Paths.swift Implementation:**
```swift
// src/Playback/Playback/Config/Paths.swift
import Foundation

struct Paths {
    /// Checks if the app is running in development mode
    static var isDevelopment: Bool {
        ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"] == "1"
    }

    /// Returns the base data directory
    static func dataDirectory() -> URL {
        if isDevelopment {
            // Development: Use SRCROOT environment variable (REQUIRED)
            guard let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] else {
                fatalError("SRCROOT environment variable not set - required in development mode")
            }
            let expandedPath = NSString(string: srcRoot).expandingTildeInPath
            let projectRoot = URL(fileURLWithPath: expandedPath)
            return projectRoot.appendingPathComponent("dev_data")
        } else {
            // Production: ~/Library/Application Support/Playback/data/
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            return appSupport
                .appendingPathComponent("Playback")
                .appendingPathComponent("data")
        }
    }

    /// Returns the screenshots directory
    static func tempDirectory() -> URL {
        return dataDirectory().appendingPathComponent("temp")
    }

    /// Returns the video segments directory
    static func chunksDirectory() -> URL {
        return dataDirectory().appendingPathComponent("chunks")
    }

    /// Returns the database file path
    static func databasePath() -> URL {
        return dataDirectory().appendingPathComponent("meta.sqlite3")
    }

    /// Returns the config file path
    static func configPath() -> URL {
        if isDevelopment {
            // Development: Use SRCROOT environment variable (REQUIRED)
            guard let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] else {
                fatalError("SRCROOT environment variable not set - required in development mode")
            }
            let expandedPath = NSString(string: srcRoot).expandingTildeInPath
            let projectRoot = URL(fileURLWithPath: expandedPath)
            return projectRoot.appendingPathComponent("dev_config.json")
        } else {
            // Production: ~/Library/Application Support/Playback/config.json
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
            return appSupport
                .appendingPathComponent("Playback")
                .appendingPathComponent("config.json")
        }
    }

    /// Returns the logs directory
    static func logsDirectory() -> URL {
        if isDevelopment {
            // Development: Use SRCROOT environment variable (REQUIRED)
            guard let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] else {
                fatalError("SRCROOT environment variable not set - required in development mode")
            }
            let expandedPath = NSString(string: srcRoot).expandingTildeInPath
            let projectRoot = URL(fileURLWithPath: expandedPath)
            return projectRoot.appendingPathComponent("dev_logs")
        } else {
            // Production: ~/Library/Logs/Playback/
            let logs = FileManager.default.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            ).first!
            return logs
                .appendingPathComponent("Logs")
                .appendingPathComponent("Playback")
        }
    }

    /// Returns the embedded scripts directory
    static func scriptsDirectory() -> URL {
        if isDevelopment {
            // Development: Use SRCROOT environment variable (REQUIRED)
            guard let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] else {
                fatalError("SRCROOT environment variable not set - required in development mode")
            }
            let expandedPath = NSString(string: srcRoot).expandingTildeInPath
            let projectRoot = URL(fileURLWithPath: expandedPath)
            return projectRoot
                .appendingPathComponent("src")
                .appendingPathComponent("scripts")
        } else {
            // Production: Playback.app/Contents/Resources/scripts/
            return Bundle.main.resourceURL!
                .appendingPathComponent("scripts")
        }
    }
}
```

**Usage Examples:**
```swift
// Get paths (works in both dev and prod)
let tempDir = Paths.tempDirectory()
let configPath = Paths.configPath()
let dbPath = Paths.databasePath()

// Create date-based subdirectory
let dateFormatter = DateFormatter()
dateFormatter.dateFormat = "yyyyMM"
let monthDir = tempDir.appendingPathComponent(dateFormatter.string(from: Date()))

dateFormatter.dateFormat = "dd"
let dayDir = monthDir.appendingPathComponent(dateFormatter.string(from: Date()))

// Create directory if needed
try? FileManager.default.createDirectory(
    at: dayDir,
    withIntermediateDirectories: true,
    attributes: nil
)
```

### Permission Details

#### File Permissions
**Application Bundle:**
```bash
drwxr-xr-x  /Applications/Playback.app/           # 0755
-rwxr-xr-x  Contents/MacOS/Playback               # 0755
-rw-r--r--  Contents/Info.plist                   # 0644
-rw-r--r--  Contents/Resources/scripts/*.py       # 0644 (but executed via python3)
```

**User Data (Production):**
```bash
drwx------  ~/Library/Application Support/Playback/       # 0700
-rw-------  ~/Library/Application Support/Playback/config.json  # 0600
drwx------  ~/Library/Application Support/Playback/data/  # 0700
-rw-------  ~/Library/Application Support/Playback/data/temp/*/*  # 0600
-rw-------  ~/Library/Application Support/Playback/data/chunks/*/*/*.mp4  # 0600
-rw-------  ~/Library/Application Support/Playback/data/meta.sqlite3  # 0600
```

**LaunchAgents:**
```bash
-rw-r--r--  ~/Library/LaunchAgents/com.playback.recording.plist  # 0644
-rw-r--r--  ~/Library/LaunchAgents/com.playback.processing.plist  # 0644
```

**Logs:**
```bash
drwxr-xr-x  ~/Library/Logs/Playback/      # 0755
-rw-r--r--  ~/Library/Logs/Playback/*.log  # 0644
```

#### macOS Permissions Required
**Screen Recording:**
- Required for: Screenshot capture
- Request at: First launch
- Location: System Settings > Privacy & Security > Screen Recording
- Check: `CGPreflightScreenCaptureAccess()`

**Accessibility:**
- Required for: Active app detection
- Request at: First launch
- Location: System Settings > Privacy & Security > Accessibility
- Check: `AXIsProcessTrusted()`

**Full Disk Access:**
- Required for: None (app uses standard directories)
- Optional: For backup to external drives

#### Permission Checking Code
```swift
// src/Playback/Playback/Services/PermissionsManager.swift
import Foundation
import ApplicationServices

class PermissionsManager {
    /// Check if Screen Recording permission is granted
    static func hasScreenRecordingPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission
    static func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
    }

    /// Check if Accessibility permission is granted
    static func hasAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }

    /// Request Accessibility permission
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Check all required permissions
    static func hasAllPermissions() -> Bool {
        return hasScreenRecordingPermission() && hasAccessibilityPermission()
    }
}
```

### Migration Procedures

#### Migration from Old Structure
**Scenario:** User has old separate apps (Playback Menu.app, Uninstall Playback.app)

**Migration Script:** `src/scripts/migrate_to_unified_app.sh`
```bash
#!/bin/bash
# Migrate from old separate apps to unified Playback.app

set -e

echo "Playback Migration Tool"
echo "======================="
echo ""

# Check if running as user (not sudo)
if [ "$EUID" -eq 0 ]; then
    echo "ERROR: Do not run this script as root"
    exit 1
fi

# 1. Stop old LaunchAgents
echo "Step 1: Stopping old LaunchAgents..."
launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist 2>/dev/null || true
echo "  ✓ LaunchAgents stopped"

# 2. Backup current configuration
echo ""
echo "Step 2: Backing up configuration..."
BACKUP_DIR=~/Desktop/Playback-Migration-Backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUP_DIR"
cp -r ~/Library/Application\ Support/Playback/ "$BACKUP_DIR/" 2>/dev/null || true
cp ~/Library/LaunchAgents/com.playback.*.plist "$BACKUP_DIR/" 2>/dev/null || true
echo "  ✓ Backup created at: $BACKUP_DIR"

# 3. Remove old apps
echo ""
echo "Step 3: Removing old apps..."
OLD_APPS=(
    "/Applications/Playback Menu.app"
    "/Applications/Uninstall Playback.app"
)
for app in "${OLD_APPS[@]}"; do
    if [ -d "$app" ]; then
        rm -rf "$app"
        echo "  ✓ Removed: $app"
    fi
done

# 4. Update LaunchAgent plists
echo ""
echo "Step 4: Updating LaunchAgent plists..."
NEW_APP_PATH="/Applications/Playback.app/Contents/MacOS/Playback"
RECORDING_PLIST=~/Library/LaunchAgents/com.playback.recording.plist
PROCESSING_PLIST=~/Library/LaunchAgents/com.playback.processing.plist

if [ -f "$RECORDING_PLIST" ]; then
    # Update ProgramArguments to point to new app
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /usr/bin/python3" "$RECORDING_PLIST"
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:1 /Applications/Playback.app/Contents/Resources/scripts/record_screen.py" "$RECORDING_PLIST"
    echo "  ✓ Updated recording LaunchAgent"
fi

if [ -f "$PROCESSING_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 /usr/bin/python3" "$PROCESSING_PLIST"
    /usr/libexec/PlistBuddy -c "Set :ProgramArguments:1 /Applications/Playback.app/Contents/Resources/scripts/build_chunks_from_temp.py" "$PROCESSING_PLIST"
    echo "  ✓ Updated processing LaunchAgent"
fi

# 5. Reload LaunchAgents
echo ""
echo "Step 5: Reloading LaunchAgents..."
launchctl load ~/Library/LaunchAgents/com.playback.recording.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.playback.processing.plist 2>/dev/null || true
echo "  ✓ LaunchAgents reloaded"

# 6. Verify data integrity
echo ""
echo "Step 6: Verifying data integrity..."
DATA_DIR=~/Library/Application\ Support/Playback/data
if [ -d "$DATA_DIR/temp" ] && [ -d "$DATA_DIR/chunks" ] && [ -f "$DATA_DIR/meta.sqlite3" ]; then
    echo "  ✓ All data directories present"
else
    echo "  ⚠ Warning: Some data directories missing"
fi

echo ""
echo "Migration complete!"
echo ""
echo "Next steps:"
echo "1. Launch Playback.app from /Applications/"
echo "2. Verify recording is working in menu bar"
echo "3. If everything works, you can delete the backup: $BACKUP_DIR"
```

**Automatic Migration Detection:**
```swift
// Check for old apps on first launch
func checkForMigrationNeeded() -> Bool {
    let fileManager = FileManager.default
    let oldApps = [
        "/Applications/Playback Menu.app",
        "/Applications/Uninstall Playback.app"
    ]

    return oldApps.contains { fileManager.fileExists(atPath: $0) }
}

// Prompt user to migrate
if checkForMigrationNeeded() {
    let alert = NSAlert()
    alert.messageText = "Migration Required"
    alert.informativeText = "Old Playback apps detected. Would you like to migrate to the new unified app?"
    alert.addButton(withTitle: "Migrate")
    alert.addButton(withTitle: "Cancel")

    if alert.runModal() == .alertFirstButtonReturn {
        runMigrationScript()
    }
}
```

#### Data Directory Migration
**Scenario:** User has data in non-standard location

**Detection:**
```swift
func checkDataLocation() -> Bool {
    let standardLocation = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first!.appendingPathComponent("Playback/data")

    let config = ConfigManager.shared.config
    guard let dataPath = config.dataPath else { return true }

    return URL(fileURLWithPath: dataPath) == standardLocation
}
```

**Migration:**
```swift
func migrateDataDirectory(from oldPath: String, to newPath: URL) throws {
    let fileManager = FileManager.default
    let oldURL = URL(fileURLWithPath: oldPath)

    // Create new directory
    try fileManager.createDirectory(
        at: newPath,
        withIntermediateDirectories: true,
        attributes: nil
    )

    // Copy subdirectories
    let subdirs = ["temp", "chunks"]
    for subdir in subdirs {
        let oldSubdir = oldURL.appendingPathComponent(subdir)
        let newSubdir = newPath.appendingPathComponent(subdir)

        if fileManager.fileExists(atPath: oldSubdir.path) {
            try fileManager.copyItem(at: oldSubdir, to: newSubdir)
        }
    }

    // Copy database
    let oldDB = oldURL.appendingPathComponent("meta.sqlite3")
    let newDB = newPath.appendingPathComponent("meta.sqlite3")
    if fileManager.fileExists(atPath: oldDB.path) {
        try fileManager.copyItem(at: oldDB, to: newDB)
    }

    // Update config
    var config = ConfigManager.shared.config
    config.dataPath = newPath.path
    try ConfigManager.shared.save(config)

    // Verify migration
    let verifyOldSize = try directorySize(at: oldURL)
    let verifyNewSize = try directorySize(at: newPath)

    guard verifyOldSize == verifyNewSize else {
        throw MigrationError.sizesMismatch
    }

    // Ask user if they want to delete old data
    promptForOldDataDeletion(at: oldURL)
}
```

### Gitignore Configuration

**Complete .gitignore:**
```gitignore
# Development data (not committed)
dev_data/
dev_logs/
dev_config.json

# Xcode
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.xcarchive

# Swift Package Manager
.swiftpm/
.build/

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.pytest_cache/
.coverage
htmlcov/

# macOS
.DS_Store
.AppleDouble
.LSOverride
._*
*.swp
*.swo
*~

# Build artifacts
*.pkg
*.dmg
*.ipa
*.dSYM.zip
*.dSYM

# Logs
*.log
*.log.*

# IDE
.vscode/
.idea/
*.sublime-project
*.sublime-workspace

# Temporary files
*.tmp
*.temp
.cache/

# Distribution
dist/
*.zip
```

### Backup Script Details

**Complete Backup Script:** `src/scripts/backup_playback_data.sh`
```bash
#!/bin/bash
# Backup Playback user data to specified location

set -e

# Default backup location
BACKUP_ROOT=~/Backups
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_NAME="Playback-${TIMESTAMP}"
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_NAME}"

# Source directories
SOURCE_BASE=~/Library/Application\ Support/Playback
SOURCE_DATA="${SOURCE_BASE}/data"
SOURCE_CONFIG="${SOURCE_BASE}/config.json"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--destination)
            BACKUP_ROOT="$2"
            BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_NAME}"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [-d|--destination DIR]"
            echo ""
            echo "Options:"
            echo "  -d, --destination DIR   Backup destination (default: ~/Backups)"
            echo "  -h, --help             Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo "Playback Data Backup Tool"
echo "========================="
echo ""
echo "Source: ${SOURCE_BASE}"
echo "Destination: ${BACKUP_DIR}"
echo ""

# Check if source exists
if [ ! -d "$SOURCE_DATA" ]; then
    echo "ERROR: Source data directory not found: $SOURCE_DATA"
    exit 1
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup configuration
echo "Backing up configuration..."
if [ -f "$SOURCE_CONFIG" ]; then
    cp "$SOURCE_CONFIG" "$BACKUP_DIR/config.json"
    echo "  ✓ Config backed up"
else
    echo "  ⚠ Config not found"
fi

# Backup database
echo "Backing up database..."
if [ -f "${SOURCE_DATA}/meta.sqlite3" ]; then
    cp "${SOURCE_DATA}/meta.sqlite3" "$BACKUP_DIR/meta.sqlite3"
    echo "  ✓ Database backed up ($(du -h "${SOURCE_DATA}/meta.sqlite3" | cut -f1))"
else
    echo "  ⚠ Database not found"
fi

# Backup video chunks (using rsync for efficiency)
echo "Backing up video chunks..."
if [ -d "${SOURCE_DATA}/chunks" ]; then
    rsync -ah --info=progress2 "${SOURCE_DATA}/chunks/" "$BACKUP_DIR/chunks/"
    CHUNKS_SIZE=$(du -sh "$BACKUP_DIR/chunks" | cut -f1)
    echo "  ✓ Chunks backed up ($CHUNKS_SIZE)"
else
    echo "  ⚠ Chunks directory not found"
fi

# Optional: Backup screenshots (usually not needed, takes long time)
read -p "Backup screenshots? (not recommended, takes ~20GB/day) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Backing up screenshots..."
    if [ -d "${SOURCE_DATA}/temp" ]; then
        rsync -ah --info=progress2 "${SOURCE_DATA}/temp/" "$BACKUP_DIR/temp/"
        TEMP_SIZE=$(du -sh "$BACKUP_DIR/temp" | cut -f1)
        echo "  ✓ Screenshots backed up ($TEMP_SIZE)"
    fi
fi

# Calculate total size
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

# Create backup info file
cat > "$BACKUP_DIR/backup_info.txt" <<EOF
Playback Backup
===============
Created: $(date)
Source: ${SOURCE_BASE}
Total Size: ${TOTAL_SIZE}

Contents:
- config.json (configuration file)
- meta.sqlite3 (metadata database)
- chunks/ (video segments)
$([ -d "$BACKUP_DIR/temp" ] && echo "- temp/ (screenshots)")

Restore Instructions:
1. Stop Playback services:
   launchctl unload ~/Library/LaunchAgents/com.playback.*.plist
2. Replace data directory:
   rm -rf "${SOURCE_DATA}"
   mkdir -p "${SOURCE_DATA}"
   cp -r chunks/ "${SOURCE_DATA}/chunks/"
   cp meta.sqlite3 "${SOURCE_DATA}/"
   $([ -d "$BACKUP_DIR/temp" ] && echo "cp -r temp/ \"${SOURCE_DATA}/temp/\"")
3. Replace config:
   cp config.json "${SOURCE_CONFIG}"
4. Restart services:
   launchctl load ~/Library/LaunchAgents/com.playback.*.plist
EOF

echo ""
echo "Backup complete!"
echo "Location: $BACKUP_DIR"
echo "Total size: $TOTAL_SIZE"
echo ""
echo "See backup_info.txt for restore instructions"
```

**Swift Integration:**
```swift
// src/Playback/Playback/Settings/BackupView.swift
func performBackup(destination: URL) {
    let scriptPath = Paths.scriptsDirectory()
        .appendingPathComponent("backup_playback_data.sh")

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = [
        scriptPath.path,
        "--destination", destination.path
    ]

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            showNotification(
                title: "Backup Complete",
                message: "Data backed up to \(destination.path)"
            )
        } else {
            showError("Backup failed")
        }
    } catch {
        showError("Failed to run backup: \(error)")
    }
}
```

### Key Differences: Development vs Production

| Aspect | Development | Production |
|--------|------------|------------|
| **App Location** | `src/Playback/` (source) | `/Applications/Playback.app/` |
| **Data Directory** | `dev_data/` | `~/Library/Application Support/Playback/data/` |
| **Config File** | `dev_config.json` | `~/Library/Application Support/Playback/config.json` |
| **Logs Directory** | `dev_logs/` | `~/Library/Logs/Playback/` |
| **Scripts Location** | `src/scripts/` (source, via SRCROOT) | `Playback.app/Contents/Resources/scripts/` |
| **LaunchAgent Labels** | `com.playback.dev.recording` | `com.playback.recording` |
| **Environment Variables** | `PLAYBACK_DEV_MODE=1` (required)<br>`SRCROOT=/path/to/project` (required) | Not set |
| **Build Flag** | `#if DEVELOPMENT` | Not defined |
| **Data Isolation** | Complete (no overlap) | Standard user directories |
| **Hot Reload** | Yes (config changes immediate) | No (restart required) |

**Source Files Created:**
- `src/Playback/Playback/Paths.swift` - Path resolution with SRCROOT requirement (implemented)
- `.gitignore` - Git exclusions for development data (implemented)
- `src/scripts/requirements.txt` - Python dependencies (implemented)
- `scripts/setup_dev_env.sh` - Automated development environment setup (implemented)

**SRCROOT Setup (Required for Development):**
1. Open Xcode project: `src/Playback/Playback.xcodeproj`
2. Click scheme dropdown → "Edit Scheme..."
3. Select "Run" → "Arguments" tab
4. Add TWO environment variables:
   - `PLAYBACK_DEV_MODE` = `1`
   - `SRCROOT` = `/Users/YOUR_USERNAME/Playback` (or `~/Playback`)
5. Both are **mandatory** - app will crash with `fatalError` if SRCROOT is missing
6. Tilde (`~`) expansion is supported

## Testing Checklist

### Unit Tests
- [ ] Test environment detection
  - Dev mode: `PLAYBACK_DEV_MODE=1` detected correctly
  - Prod mode: Default when env var not set
  - Build flag: `#if DEVELOPMENT` compiles correctly

- [ ] Test path resolution
  - Dev paths: Resolve to `dev_data/`, `dev_config.json`, `dev_logs/`
  - Prod paths: Resolve to `~/Library/Application Support/Playback/`
  - Generic paths: No hardcoded usernames in any path
  - Bundle paths: Scripts found in Resources/ in production

- [ ] Test file naming
  - Screenshots: Correct format with timestamp, UUID, app ID
  - Videos: Valid segment IDs (20 hex chars)
  - Logs: Proper rotation with .N suffixes

### Integration Tests
- [ ] Test development isolation
  - Run app in dev mode: Uses dev_data/, doesn't touch production
  - Run app in prod mode: Uses production paths, ignores dev_data/
  - Simultaneous: Both can run without conflict

- [ ] Test directory creation
  - First launch: All directories created with correct permissions
  - Missing directories: Automatically recreated on next launch
  - Permissions: Verified after creation

- [ ] Test script embedding
  - Build: Scripts copied to Resources/scripts/
  - Runtime: Scripts executable and found in bundle
  - Development: Scripts run from source, changes immediate

### Migration Tests
- [ ] Test migration from old structure
  - Old apps removed: Separate apps deleted correctly
  - LaunchAgents updated: Point to unified app
  - Data preserved: No data loss during migration
  - Rollback: Can restore if migration fails

- [ ] Test backup functionality
  - Backup creation: All essential data backed up
  - Restore: Can restore from backup successfully
  - Verification: Backup integrity checked

### Storage Tests
- [ ] Test storage monitoring
  - Disk space: Monitor available space, warn at threshold
  - Growth rate: Track storage growth over time
  - Cleanup: Old data deletion works correctly

- [ ] Test file operations
  - Write: Can write screenshots and videos
  - Read: Can read data back for playback
  - Delete: Cleanup removes files correctly
  - Permissions: All operations respect file permissions

### Performance Tests
- [ ] Test with large datasets
  - 30 days: Verify performance with ~12GB data
  - 90 days: Test with ~37GB data
  - Directory traversal: Fast access to date-based structure
  - Database: Query performance with thousands of segment records
