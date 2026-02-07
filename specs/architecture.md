# Architecture Implementation Plan

**Component:** System Architecture
**Version:** 1.0
**Last Updated:** 2026-02-07

## Implementation Checklist

### Project Structure Setup
- [ ] Create Xcode project structure
  - Location: `src/Playback/Playback.xcodeproj`
  - Target: Playback (unified app with menu bar + timeline)
  - Minimum deployment: macOS 26.0 (Tahoe)
  - Architecture: Apple Silicon only (arm64)
  - Bundle ID: `com.playback.Playback`
  - SwiftUI lifecycle with App protocol

- [ ] Set up Swift source directory structure
  - `src/Playback/Playback/MenuBar/` - Menu bar component
  - `src/Playback/Playback/Timeline/` - Timeline viewer component
  - `src/Playback/Playback/Settings/` - Settings window component
  - `src/Playback/Playback/Services/` - LaunchAgent management
  - `src/Playback/Playback/Config/` - Configuration management
  - `src/Playback/Playback/Database/` - SQLite database access

- [ ] Set up Python scripts directory
  - `src/scripts/record_screen.py` - Recording service (captures screenshots)
  - `src/scripts/build_chunks_from_temp.py` - Processing service (creates videos)
  - `src/scripts/cleanup_old_chunks.py` - Retention cleanup service
  - `src/scripts/requirements.txt` - Python dependencies (Pillow, ffmpeg-python)
  - `src/scripts/tests/` - Python test files

- [ ] Create shared Python library directory (planned)
  - `src/lib/` - Shared utilities (paths, database, video, macos, timestamps)

- [ ] Create development data directory (gitignored)
  - `dev_data/temp/` - Development screenshots
  - `dev_data/chunks/` - Development videos
  - `dev_data/meta.sqlite3` - Development database

### Application Entry Point
- [ ] Implement main app structure
  - Source: `src/Playback/Playback/PlaybackApp.swift`
  - Components: MenuBarExtra, Window (Timeline), Settings
  - MenuBarExtra: Always visible system tray icon
  - Timeline Window: On-demand viewer for recorded content
  - Settings Window: Configuration panel for recording preferences

### Component Communication
- [ ] Implement shared state management
  - Source: `src/Playback/Playback/Config/ConfigManager.swift`
  - Uses: SwiftUI @EnvironmentObject for state sharing
  - Config persists to: `~/Library/Application Support/Playback/config.json`
  - Shared state includes: recording enabled, interval, retention days
  - Updates propagate to all UI components automatically

- [ ] Set up LaunchAgent control
  - Source: `src/Playback/Playback/Services/LaunchAgentManager.swift`
  - Methods: load/unload recording and processing agents
  - Controls: `com.playback.record` and `com.playback.process` LaunchAgents
  - Uses `launchctl` commands: load, unload, start, stop
  - Verifies agent status before state changes

### File System Organization
- [ ] Configure production paths
  - Data: `~/Library/Application Support/Playback/data/`
    - Subdirectories: `temp/`, `chunks/`
    - Database: `meta.sqlite3`
  - Config: `~/Library/Application Support/Playback/config.json`
  - Logs: `~/Library/Logs/Playback/`
    - Separate logs: `recording.log`, `processing.log`, `cleanup.log`
  - LaunchAgents: `~/Library/LaunchAgents/com.playback.*.plist`
    - Three agents: record, process, cleanup

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
- Swift app writes configuration to `config.json`
- Python services read configuration on startup
- No direct IPC between processes (simpler, more reliable)
- Configuration changes require service restart via LaunchAgent control

**LaunchAgent Control:**
- Swift app uses `launchctl` to manage Python services
- Commands: `load`, `unload`, `start`, `stop`
- Plist files define service behavior (intervals, restart policies)
- Status verification before state changes (check if loaded before unloading)

**SQLite Database Access:**
- Python scripts write recording metadata to `meta.sqlite3`
- Swift app reads metadata for timeline display
- Read-only access from Swift (Python owns writes)
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
│   └── meta.sqlite3       # Metadata database
├── config.json            # User configuration (intervals, retention, etc.)
└── logs/                  # Service logs (recording.log, processing.log)

~/Library/LaunchAgents/
├── com.playback.record.plist    # Recording service definition
└── com.playback.process.plist   # Processing service definition
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
