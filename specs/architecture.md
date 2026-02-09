# Architecture Implementation Plan

**Component:** System Architecture
**Version:** 2.0
**Last Updated:** 2026-02-09

## Architecture Decision: Single Permission Model

**Problem:** Original architecture required two Screen Recording permission grants:
1. Playback.app (Swift) - for UI and controls
2. /usr/bin/python3 (Python scripts via LaunchAgent) - for screenshot capture

**Solution:** Move screenshot capture to Swift to consolidate under single permission grant.

**New Architecture:**
- **Swift (Playback.app)**: Screenshot capture using app's Screen Recording permission
- **Python (LaunchAgent)**: Video processing only (no Screen Recording permission needed)
- **Python (LaunchAgent)**: Cleanup service

## Implementation Checklist

### Project Structure Setup
- [x] Create Xcode project structure
  - Location: `src/Playback/Playback.xcodeproj`
  - Single unified app: **Playback.app**
  - Minimum deployment: macOS 26.0 (Tahoe)
  - Architecture: Apple Silicon only (arm64)
  - Bundle ID: `com.falconer.Playback`
  - SwiftUI lifecycle with App protocol
  - Scenes: MenuBarExtra + WindowGroup for timeline

- [x] Set up Swift source directory structure
  - `src/Playback/Playback/` - Single unified app
    - `PlaybackApp.swift` - App entry with MenuBarExtra + WindowGroup
    - `MenuBar/` - Menu bar UI and controls
    - `Timeline/` - Timeline viewer component
    - `Settings/` - Settings window (all 6 tabs in SettingsView.swift)
    - `Diagnostics/` - Diagnostics window component
    - `Services/` - LaunchAgent management, recording service
    - `Config/` - Configuration management (ConfigManager.swift)
    - `Database/` - SQLite database access (TimelineStore.swift)
    - `Search/` - Search controller and OCR
    - `Models/` - Data models
    - `Utilities/` - Shared utilities (ShellCommand.swift)
    - `Resources/` - Assets, LaunchAgent templates

- [x] Set up Python scripts directory
  - **DEPRECATED:** `src/scripts/record_screen.py` - **Being replaced by Swift RecordingService**
  - `src/scripts/build_chunks_from_temp.py` - Processing service (creates videos from screenshots)
  - `src/scripts/cleanup_old_chunks.py` - Retention cleanup service
  - `src/scripts/requirements.txt` - Python dependencies (Pillow, psutil, PyObjC for FFmpeg)
  - Migration: Recording logic moving to Swift to use app's Screen Recording permission

- [x] Create shared Python library directory (IMPLEMENTED)
  - `src/lib/` - 9 modules, 280 passing tests
  - Modules: paths.py, database.py, video.py, macos.py, timestamps.py, config.py, logging_config.py, security.py, network.py

- [ ] Create development data directory (gitignored)
  - `dev_data/temp/` - Development screenshots
  - `dev_data/chunks/` - Development videos
  - `dev_data/meta.sqlite3` - Development database

### Application Entry Points
- [x] Implement unified Playback.app
  - Source: `src/Playback/Playback/PlaybackApp.swift`
  - Single app with two scenes:
    1. **MenuBarExtra** - Always visible system tray icon
    2. **WindowGroup** - Timeline viewer window (opened on demand)
  - Lives in: `/Applications/Playback.app`
  - Runs as: LaunchAgent (login item) OR manually launched
  - Bundle ID: `com.falconer.Playback`

- [x] MenuBarExtra Scene
  - Always visible system tray icon
  - MenuBarView.swift: Recording toggle, timeline shortcut, settings
  - Responsibilities:
    - Display menu bar icon with recording status
    - Control recording service (Swift-based)
    - Control processing service (Python LaunchAgent)
    - Launch timeline viewer window
    - Provide settings and diagnostics UI
    - Handle "Quit Playback" (stops recording, keeps processing for cleanup)

- [x] Timeline Viewer Window (WindowGroup)
  - Fullscreen timeline with video playback
  - Launch triggers: Menu bar "Open Timeline", Option+Shift+Space, app icon click
  - Lifecycle: Window can be closed without stopping app
  - On open: Creates .timeline_open signal file → pauses recording
  - On close: Removes signal file → resumes recording

### Recording Service Architecture (Swift-Based)

**NEW: Swift Recording Service** (replaces Python record_screen.py)

**Why Swift?**
- Uses Playback.app's Screen Recording permission (single permission grant)
- No separate permission needed for Python/LaunchAgent
- Better integration with app lifecycle
- Simpler permission story for users

**Implementation:**
- Source: `src/Playback/Playback/Services/RecordingService.swift`
- Runs as: Part of Playback.app process (not separate LaunchAgent)
- Uses: Timer or DispatchSourceTimer for 2-second interval
- Captures screenshots using: CGDisplayCreateImage() or similar
- Saves to: `dev_data/temp/YYYYMM/DD/` (same format as Python version)
- Filename format: `YYYYMMDD-HHMMSS-uuid-app_id.png`

**Lifecycle:**
1. App launches → RecordingService starts if recording_enabled
2. Timeline opens → RecordingService pauses (detects .timeline_open)
3. Timeline closes → RecordingService resumes
4. App quits → RecordingService stops

**Integration Points:**
- MenuBarView toggle → RecordingService.start() / .stop()
- Config changes → RecordingService reloads settings
- Permission check → Uses app's existing Screen Recording permission

**Migration Plan:**
- Phase 1: Implement Swift RecordingService alongside Python version
- Phase 2: Test Swift version in development
- Phase 3: Switch to Swift version by default
- Phase 4: Deprecate Python record_screen.py

### Service Comparison: Old vs New Architecture

| Service | Old Architecture | New Architecture | Permission Needed |
|---------|------------------|------------------|-------------------|
| **Recording** | Python LaunchAgent<br>`record_screen.py`<br>Runs as `/usr/bin/python3` | Swift Service<br>`RecordingService.swift`<br>Runs in Playback.app | OLD: python3 ❌<br>NEW: Playback.app ✅ |
| **Processing** | Python LaunchAgent<br>`build_chunks_from_temp.py` | Python LaunchAgent<br>`build_chunks_from_temp.py`<br>(unchanged) | None (just FFmpeg) |
| **Cleanup** | Python LaunchAgent<br>`cleanup_old_chunks.py` | Python LaunchAgent<br>`cleanup_old_chunks.py`<br>(unchanged) | None |

**Key Improvement:**
- Old: User must grant Screen Recording to **TWO** executables (Playback.app + python3)
- New: User grants Screen Recording to **ONE** executable (Playback.app only)

### Permission Model

**Single Permission Grant: Playback.app**

macOS grants Screen Recording permission per executable. By moving screenshot capture to Swift, we consolidate all permissions under Playback.app.

**Required Permissions:**
1. **Screen Recording** (Playback.app)
   - Granted once during first launch
   - Used for: Screenshot capture (Swift RecordingService)
   - Shows in: System Settings → Privacy & Security → Screen Recording

2. **Accessibility** (Playback.app)
   - Granted once during first launch
   - Used for: Frontmost app detection, global hotkeys
   - Shows in: System Settings → Privacy & Security → Accessibility

**No Longer Required:**
- ❌ Screen Recording permission for /usr/bin/python3 (old architecture)
- ❌ Separate LaunchAgent for recording (now in-app)

**Permission Flow:**
1. User launches Playback.app
2. App requests Screen Recording permission (standard macOS dialog)
3. User grants permission → Recording immediately available
4. Processing service starts (no permission needed - just FFmpeg)

### Component Communication
- [x] Implement shared state management
  - Source: `src/Playback/Playback/Config/ConfigManager.swift`
  - Uses: File-based configuration (no IPC between processes)
  - Config persists to: `~/Library/Application Support/Playback/config.json`
  - Shared state includes: recording enabled, interval, retention days
  - Menu bar agent writes, timeline viewer reads

- [x] Set up LaunchAgent control
  - Source: `src/Playback/Playback/Services/LaunchAgentManager.swift`
  - Methods: load/unload processing and cleanup agents
  - Controls:
    - **REMOVED:** `com.playback.recording` (now Swift-based, in-app)
    - `com.playback.processing` (Python processing service)
    - `com.playback.cleanup` (Python cleanup service)
  - Uses `launchctl` commands: load, unload, start, stop
  - Verifies agent status before state changes
  - Templates in: `Resources/` (recording.plist.template, processing.plist.template, cleanup.plist.template)

- [ ] Implement timeline viewer launcher (Menu Bar Agent)
  - Source: `src/Playback/PlaybackMenuBar/Services/TimelineLauncher.swift`
  - Method: `launchTimelineViewer()`
  - Uses: `NSWorkspace.shared.open()` to launch Playback.app
  - Brings window to front if already running
  - Triggered by: Menu item, global hotkey (Option+Shift+Space)

- [ ] Implement process communication (file-based signals)
  - No direct IPC between processes
  - Timeline viewer signals recording service via filesystem:
    - Create: `~/Library/Application Support/Playback/.timeline_open` (pause recording)
    - Delete: Remove file (resume recording)
  - Recording service polls for file existence every iteration

### File System Organization
- [ ] Configure production paths
  - Data: `~/Library/Application Support/Playback/data/`
    - Subdirectories: `temp/`, `chunks/`
    - Database: `meta.sqlite3`
    - Signal files: `.timeline_open` (timeline viewer active)
  - Config: `~/Library/Application Support/Playback/config.json`
  - Logs: `~/Library/Logs/Playback/`
    - Separate logs: `recording.log`, `processing.log`, `menubar.log`
  - LaunchAgents: `~/Library/LaunchAgents/com.playback.*.plist`
    - `com.playback.menubar.plist` - Menu bar agent (always running)
    - `com.playback.recording.plist` - Recording service
    - `com.playback.processing.plist` - Processing service
  - Applications: `/Applications/Playback.app` - Timeline viewer (only visible app)

- [ ] Configure development paths
  - Data: `<project>/dev_data/`
    - Same subdirectory structure as production
  - Config: `<project>/dev_config.json`
  - Logs: `<project>/dev_logs/`
  - Environment variable: `PLAYBACK_DEV_MODE=1`
  - LaunchAgents: Use development paths in plist files

### Error Handling Strategy
- [ ] Implement fail-gracefully pattern
  - Recording failures: Log error with context, skip frame, continue
  - Processing failures: Log error, preserve temp files, skip segment
  - Database failures: Retry once with 1-second delay, then skip
  - Never crash services on recoverable errors

- [ ] Implement notification system
  - Critical errors: macOS notification with "Open Settings" action button
  - Permission denied: Notification with deep link to System Settings → Privacy
  - Disk full: Disable recording, notify with "Free Space" action (opens Finder)
  - Processing errors: Silent logging (no notification unless repeated failures)

### Dependencies & Build Configuration
- [ ] Set up build configurations
  - Debug: Development scheme with DEVELOPMENT flag
  - Release: Production scheme with optimization
  - Swift compiler flags: `-DDEVELOPMENT` for debug builds
  - Optimization level: `-O` for release builds

- [ ] Configure code signing
  - Development: Ad-hoc signing with local certificate
  - Production: Developer ID Application certificate
  - Entitlements: Screen Recording, File System access
  - Hardened Runtime enabled for production builds

## Key Architecture Details

### Component Communication Patterns

**Filesystem-based Communication:**
- Menu bar agent writes configuration to `config.json`
- Python services read configuration on startup
- Timeline viewer reads configuration (read-only)
- No direct IPC between processes (simpler, more reliable)
- Configuration changes require service restart via LaunchAgent control

**LaunchAgent Control (Menu Bar Agent):**
- Menu bar agent uses `launchctl` to manage all services
- Commands: `load`, `unload`, `start`, `stop`
- Plist files define service behavior (intervals, restart policies)
- Status verification before state changes (check if loaded before unloading)
- "Quit Playback" stops all services including menu bar agent itself

**Timeline Viewer Communication:**
- Menu bar agent launches timeline viewer via `NSWorkspace.open()`
- Timeline viewer signals recording pause via `.timeline_open` file
- Recording service detects file presence and pauses
- Timeline viewer removes file on quit, recording resumes
- No direct process communication needed

**SQLite Database Access:**
- Python scripts write recording metadata to `meta.sqlite3`
- Timeline viewer reads metadata for timeline display (read-only)
- Menu bar agent reads for diagnostics display (read-only)
- WAL mode for concurrent read access during writes

### Data Flow Overview

**Recording Phase:**
1. `record_screen.py` runs every N seconds (configurable, default 2s)
2. Captures screenshot using macOS ScreenCaptureKit API
3. Saves to `temp/` directory with timestamp filename
4. Continues indefinitely until disabled or system shutdown

**Processing Phase:**
1. `build_chunks_from_temp.py` runs every 10 minutes
2. Scans `temp/` for screenshots older than 5 minutes
3. Groups screenshots into 10-minute segments
4. Generates H.264 video using ffmpeg (30 fps, low CPU preset)
5. Writes metadata to SQLite database (chunk_id, start/end times, path)
6. Deletes processed temp files to free disk space

**Playback Phase:**
1. Swift timeline UI queries SQLite for chunks in time range
2. Loads video files from `chunks/` directory
3. Displays using AVFoundation video player
4. Scrubbing loads adjacent chunks on-demand

### Critical File Paths and Purposes

**Production Environment:**
```
~/Library/Application Support/Playback/
├── data/
│   ├── temp/              # Temporary screenshots (deleted after processing)
│   ├── chunks/            # Processed video files (retained per retention policy)
│   ├── meta.sqlite3       # Metadata database
│   └── .timeline_open     # Signal file (exists when timeline viewer open)
├── config.json            # User configuration (intervals, retention, etc.)
└── logs/                  # Service logs (recording.log, processing.log, menubar.log)

~/Library/LaunchAgents/
├── com.playback.menubar.plist     # Menu bar agent (always running)
├── com.playback.recording.plist   # Recording service definition
└── com.playback.processing.plist  # Processing service definition

/Applications/
└── Playback.app                   # Timeline viewer (only user-visible app)
```

**Development Environment (when PLAYBACK_DEV_MODE=1):**
```
<project>/dev_data/
├── temp/                  # Development screenshots
├── chunks/                # Development videos
└── meta.sqlite3           # Development database

<project>/dev_config.json  # Development configuration
<project>/dev_logs/        # Development logs
```

**File Naming Conventions:**
- Screenshots: `YYYY-MM-DD_HH-MM-SS.png`
- Video chunks: `YYYY-MM-DD_HH-MM-SS_to_HH-MM-SS.mp4`
- Log files: `recording_YYYY-MM-DD.log`, `processing_YYYY-MM-DD.log`

### Error Handling Principles

**Fail Gracefully:**
- Recording failures: Log error and skip frame (continue recording)
- Processing failures: Log error and skip segment (preserve temp files for retry)
- Database failures: Retry once with exponential backoff, then skip

**Never Exit on Recoverable Errors:**
- Disk space low: Disable recording, notify user, keep app running
- Permission denied: Show notification with "Open System Settings" action
- Network unavailable: Skip any cloud operations, continue local operations

**Log Everything:**
- All errors logged with timestamp, context, stack trace
- Successful operations logged at INFO level for debugging
- Log rotation: Keep 7 days of logs, max 100MB per log file

**User Notifications:**
- Critical errors: macOS notification with actionable message
- Permission issues: Notification with deep link to System Settings
- Disk full: Notification with option to open Settings or Finder

### Performance Targets

**CPU Usage:**
- Recording service: <5% CPU average (single core)
- Processing service: <20% CPU during encoding (burst activity)
- Main app (idle): <1% CPU when timeline not visible

**Memory Usage:**
- Recording service: <50MB resident memory
- Processing service: <200MB during encoding
- Main app: <100MB base, +50MB per hour of timeline loaded

**Disk I/O:**
- Screenshot capture: *Storage TBD after 1 month of usage data* (PNG compression, temporary only)
- Video encoding: ~7.5MB per segment (5s video, represents 5min real-time, H.264)
- Chunk storage: ~7.5MB per 5-minute segment (after processing)
- Daily accumulation: ~360-450 MB/day (typical 4-5 hours active recording)
- Monthly accumulation: ~10-14 GB/month (typical usage)

**Retention and Cleanup:**
- Default retention: 30 days
- Daily cleanup job: Runs at 2 AM, deletes chunks older than retention period
- Temp cleanup: Immediate after processing (no retention)
- Database vacuum: Weekly during cleanup job

## Testing Checklist

### Unit Tests
- [ ] Test environment detection (dev vs production)
  - Verify `PLAYBACK_DEV_MODE` detection
  - Verify correct path resolution per environment
  - Test path creation if directories don't exist

- [ ] Test path resolution for each environment
  - Production: `~/Library/Application Support/Playback/`
  - Development: `<project>/dev_data/`
  - Verify all subdirectories created correctly

- [ ] Test state management (config save/load)
  - Test config serialization/deserialization
  - Test default values when config missing
  - Test config migration when format changes
  - Test concurrent access (read while writing)

- [ ] Test LaunchAgent manager
  - Mock `launchctl` commands
  - Test load/unload/start/stop operations
  - Test status verification before operations
  - Test error handling for failed commands

### Integration Tests
- [ ] Test component communication (menu bar ↔ timeline)
  - Menu bar state updates reflect in timeline
  - Timeline queries trigger correct data loads
  - Settings changes propagate to all components

- [ ] Test LaunchAgent control (load/unload)
  - Start recording from disabled state
  - Stop recording from enabled state
  - Verify Python processes actually start/stop
  - Test service restart after configuration change

- [ ] Test configuration propagation to services
  - Change recording interval, verify applied
  - Change retention days, verify cleanup adjusted
  - Test invalid configuration rejection

- [ ] Test recording → processing → playback pipeline
  - Capture screenshots to temp directory
  - Process temp files into video chunks
  - Load chunks in timeline viewer
  - Verify metadata in database matches files

### Performance Tests
- [ ] Verify resource usage within limits
  - CPU: Recording <5%, Processing <20%, App <1%
  - Memory: Recording <50MB, Processing <200MB, App <100MB
  - Disk I/O: Monitor write rates during recording/processing

- [ ] Test under 24+ hour recording sessions
  - Verify no memory leaks in Python services
  - Check log file rotation works correctly
  - Confirm temp directory doesn't grow unbounded

- [ ] Test with 30+ days of data
  - Verify timeline loads efficiently with large dataset
  - Test cleanup job removes old chunks correctly
  - Check database performance with 100K+ rows
  - Verify database vacuum runs without blocking

### Error Recovery Tests
- [ ] Test disk full scenario
  - Verify recording stops gracefully
  - Confirm user notification appears
  - Test recovery when space freed

- [ ] Test permission revocation
  - Remove Screen Recording permission mid-session
  - Verify appropriate error handling
  - Confirm user notified with actionable message

- [ ] Test service crash recovery
  - Kill recording service, verify LaunchAgent restarts it
  - Kill processing service, verify restart and resume
  - Test handling of corrupted temp files

- [ ] Test database corruption recovery
  - Simulate corrupted SQLite file
  - Verify fallback behavior (rebuild or alert)
  - Test backup/restore mechanism if implemented
