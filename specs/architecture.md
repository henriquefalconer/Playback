# Architecture Specification

**Component:** System Architecture
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

Playback is designed as a multi-process system where independent components communicate through the filesystem and a shared SQLite database. This architecture ensures resilience, allowing each component to fail and restart independently without affecting the entire system.

## System Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                        macOS System                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────┐           │
│  │         Playback.app (Swift)                 │           │
│  │  ┌────────────────────────────────────────┐  │           │
│  │  │ Menu Bar Interface                     │  │           │
│  │  │ - Recording toggle                     │  │           │
│  │  │ - Settings window                      │  │           │
│  │  │ - Diagnostics viewer                   │  │           │
│  │  └────────────────────────────────────────┘  │           │
│  │  ┌────────────────────────────────────────┐  │           │
│  │  │ Timeline Viewer (fullscreen)           │  │           │
│  │  │ - Video playback                       │  │           │
│  │  │ - Date/time picker                     │  │           │
│  │  │ - Text search (OCR)                    │  │           │
│  │  └────────────────────────────────────────┘  │           │
│  │                                              │           │
│  │  Controls LaunchAgents ↓                     │           │
│  └──────────────────────────────────────────────┘           │
│           │                                                   │
│           ├─────────────────┬─────────────────┐              │
│           ▼                 ▼                 ▼              │
│  ┌─────────────────┐  ┌─────────────────┐  ┌──────────┐    │
│  │  Configuration  │  │ Recording Svc   │  │Processing│    │
│  │   (JSON file)   │  │  (LaunchAgent)  │  │   Svc    │    │
│  └─────────────────┘  │  - Python       │  │(LaunchAgt│    │
│                        │  - 2s interval  │  │- Python  │    │
│                        │  - Screenshots  │  │- FFmpeg  │    │
│                        └────────┬────────┘  │- OCR     │    │
│                                 │           │- 5min    │    │
│                                 ▼           └────┬─────┘    │
│                        ┌─────────────────┐      │           │
│                        │   temp/ dir     │──────┘           │
│                        │  (screenshots)  │                  │
│                        └─────────────────┘                  │
│                                 │                            │
│                                 ▼                            │
│                        ┌─────────────────┐                  │
│                        │   chunks/ dir   │                  │
│                        │   (videos)      │                  │
│                        └─────────────────┘                  │
│                                 │                            │
│                                 ▼                            │
│                        ┌─────────────────┐                  │
│                        │  meta.sqlite3   │                  │
│                        │   (metadata)    │                  │
│                        └─────────────────┘                  │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## Component Interactions

### 1. Playback.app ↔ Recording Service

**Communication Method:** LaunchAgent control via `launchctl`

- Playback.app (menu bar component) enables/disables recording by loading/unloading the recording LaunchAgent
- State persisted in configuration file
- No direct IPC needed

### 2. Recording Service → Filesystem

**Communication Method:** File writes

- Recording service writes PNG screenshots to `temp/YYYYMM/DD/`
- Filename format: `YYYYMMDD-HHMMSS-<uuid>-<app_id>`
- No extension (raw PNG data)
- File metadata (creation time) used for timeline reconstruction

### 3. Processing Service → Filesystem + Database

**Communication Method:** File operations + SQLite writes

- Reads from `temp/YYYYMM/DD/`
- Generates videos in `chunks/YYYYMM/DD/<id>.mp4`
- Updates `meta.sqlite3` with segment and app segment metadata
- Optionally deletes processed temp files

### 4. Playback.app (Timeline) → Database + Filesystem

**Communication Method:** SQLite reads + video file access

- Queries `meta.sqlite3` for segment metadata
- Loads videos from `chunks/YYYYMM/DD/<id>.mp4`
- Read-only access (no writes to database or files)

### 5. Playback.app ↔ Configuration

**Communication Method:** JSON file read/write

- Configuration file: `~/Library/Application Support/Playback/config.json`
- Playback.app reads on launch, writes on settings change
- Services read configuration on each execution cycle

### 6. All Components → Logs

**Communication Method:** File appends

- Unified logging directory: `~/Library/Logs/Playback/`
- Each service writes to separate log file
- Playback.app writes to app.log
- Structured logging format (timestamp, level, component, message, metadata)

## Data Flow

### Recording Flow

```
User Activity
    ↓
[Active Display Detection]
    ↓
[Frontmost App Detection]
    ↓
[Screen Availability Check]
    ↓ (if available)
[screencapture -D <display>]
    ↓
temp/YYYYMM/DD/<filename>
    ↓
[Log: Screenshot captured]
```

### Processing Flow

```
Timer Trigger (every 5min)
    ↓
[Scan temp/ for unprocessed files]
    ↓
[Group by day]
    ↓
[Load frames, sort by timestamp]
    ↓
[Group into 5s segments]
    ↓
[FFmpeg: frames → MP4]
    ↓
chunks/YYYYMM/DD/<id>.mp4
    ↓
[SQLite: INSERT segment metadata]
    ↓
[SQLite: INSERT appsegment metadata]
    ↓
[Optional: Delete temp files]
    ↓
[Log: Processing completed with metrics]
```

### Playback Flow

```
User: Option+Shift+Space
    ↓
[Check if processing is running]
    ↓ (if running)
[Show loading screen]
    ↓ (wait for completion)
[Load meta.sqlite3]
    ↓
[Load all segments into timeline]
    ↓
[Seek to latest timestamp]
    ↓
[Display timeline + video]
    ↓
[User scrubs/zooms]
    ↓
[Update video playback position]
```

## Process Lifecycle

### Recording Service (LaunchAgent)

- **Start Condition:** System boot (if enabled) OR user toggles "Record Screen" ON
- **Stop Condition:** User toggles "Record Screen" OFF OR system shutdown
- **Restart Policy:** Always restart on crash (KeepAlive=true in plist)
- **Resource Limits:** None (relies on system throttling)

### Processing Service (LaunchAgent)

- **Start Condition:** Timer interval (default: 5 minutes)
- **Stop Condition:** Task completion (run-once per trigger)
- **Restart Policy:** Next scheduled interval
- **Resource Limits:** None (short-lived process)

### Playback.app (Unified)

- **Start Condition:** User login (LaunchAgent with RunAtLoad)
- **Stop Condition:** Never (runs continuously in menu bar)
- **Restart Policy:** On next login
- **Resource Limits:**
  - Menu bar: Minimal (idle most of the time)
  - Timeline viewer: High (video playback, fullscreen) - only when open
  - Settings window: Minimal - only when open

**Timeline Viewer Window:**
- **Open:** Global hotkey (Option+Shift+Space) OR click menu bar icon
- **Close:** ESC key OR window close
- **State:** Transient (window can close, app keeps running)

**Settings Window:**
- **Open:** Menu bar → Preferences (Cmd+,)
- **Close:** Window close
- **State:** Transient

**Unified App Features:**
- Menu bar interface (always visible)
- Timeline viewer (fullscreen, on-demand)
- Settings window (tabbed interface)
- Diagnostics viewer
- Uninstall functionality (button in settings)
- LaunchAgent management

## File System Organization

**Development:**
```
<project-root>/
├── Playback/                      # Xcode project
│   └── Playback/                  # Single unified app
│       ├── PlaybackApp.swift      # Entry point (menu bar + timeline)
│       ├── MenuBar/
│       ├── Timeline/
│       ├── Settings/
│       └── ...
├── scripts/                       # Python scripts (source)
│   ├── record_screen.py
│   └── build_chunks_from_temp.py
└── dev_data/                      # Development data (gitignored)
    ├── temp/
    ├── chunks/
    └── meta.sqlite3
```

**Production:**
```
/Applications/
└── Playback.app                   # Single unified app
    └── Contents/
        ├── MacOS/Playback         # Single executable
        └── Resources/
            └── scripts/           # Embedded Python scripts

~/Library/Application Support/Playback/
├── config.json                    # User configuration
└── data/                          # User recordings
    ├── temp/                      # Raw screenshots
    │   └── YYYYMM/DD/
    ├── chunks/                    # Video segments
    │   └── YYYYMM/DD/
    └── meta.sqlite3               # Metadata database

~/Library/LaunchAgents/
├── com.playback.recording.plist
└── com.playback.processing.plist

~/Library/Logs/Playback/
├── recording.log                  # Recording service logs
├── processing.log                 # Processing service logs
└── app.log                        # Playback.app logs
```

## State Management

### Recording State

- **Stored in:** `config.json` (`recording_enabled: bool`)
- **Modified by:** Menu bar app
- **Read by:** Menu bar app (for UI state), Recording service (for early exit)

### Processing State

- **Stored in:** Process execution status (no persistent state)
- **Detected by:** Playback app checks for running `build_chunks_from_temp.py` process

### Playback State

- **Stored in:** In-memory only (current timeline position, zoom level)
- **Not persisted:** User starts at latest timestamp on each launch

### Configuration State

- **Stored in:** `config.json`
- **Modified by:** Menu bar app settings window
- **Read by:** All components on startup/reload

## Error Handling Strategy

### Principle: Fail Gracefully, Log Everything

1. **Recording Service Errors:**
   - Screenshot failure → Log error, continue (skip frame)
   - Permission denied → Log critical error, notify user via macOS notification, exit
   - Disk full → Log critical error, notify user, disable recording

2. **Processing Service Errors:**
   - FFmpeg failure → Log error, skip segment, continue with remaining
   - Database write failure → Log error, retry once, then skip
   - Disk full → Log critical error, notify user, exit

3. **Menu Bar App Errors:**
   - Configuration load failure → Use defaults, log warning
   - LaunchAgent control failure → Show error dialog to user

4. **Playback App Errors:**
   - Database read failure → Show error message, graceful exit
   - Video file missing → Show placeholder, log warning, continue
   - Segment loading failure → Show frozen frame, log error

## Performance Considerations

### Recording Service

- **CPU Usage:** Minimal (< 5% avg)
- **Memory:** < 100MB
- **Disk I/O:** 1 write every 2s (~500KB/write)
- **Optimization:** Screenshot only when display is active

### Processing Service

- **CPU Usage:** High during execution (50-80%), but short-lived
- **Memory:** Variable (depends on segment size, typically < 500MB)
- **Disk I/O:** Batch reads from temp/, batch writes to chunks/
- **Optimization:** Run at low priority (nice value)

### Playback App

- **CPU Usage:** Moderate during video playback (20-40%)
- **Memory:** Variable (video buffers, typically < 300MB)
- **GPU:** Used for video decode and rendering
- **Optimization:** Hardware-accelerated video decode via AVPlayer

## Security & Permissions

### Required Permissions

1. **Screen Recording** - Required by recording service and playback app
2. **Accessibility** - Required for frontmost app detection
3. **Full Disk Access** - Not required (files stored in user-writable locations)

### Permission Checks

- Recording service checks permissions on startup
- If missing, logs critical error and shows macOS system prompt
- User must grant permissions in System Preferences

### Data Protection

- All data stored locally
- No network access required
- No telemetry or analytics
- Follows macOS sandbox guidelines (for future App Store distribution)

## Extensibility Points

### Future Enhancements

1. **Plugin System:** Allow custom processing pipelines
2. **Export API:** Programmatic export of time ranges
3. **Search Integration:** Spotlight integration for timeline search
4. **Cloud Sync:** Optional iCloud sync for multi-device access
5. **ML Features:** Activity recognition, smart segmentation
6. **Collaboration:** Shared timelines with annotations

### API Boundaries

- **Configuration:** JSON schema allows extension keys
- **Database:** Schema supports additional tables without migration
- **Logging:** Structured format allows external parsing
- **File System:** Hierarchical structure supports new file types

## Testing Strategy

### Unit Testing

- Recording service: Mock `screencapture`, test screenshot logic
- Processing service: Mock FFmpeg, test segmentation logic
- Database: Test schema, queries, migrations

### Integration Testing

- End-to-end: Record → Process → Playback
- Configuration: Settings changes propagate correctly
- Error scenarios: Disk full, permission denied, process crashes

### Performance Testing

- Long-running recording (24+ hours)
- Large datasets (30+ days of recordings)
- Memory leak detection (instruments)

## Deployment Considerations

### Installation

- Simple .zip download (Arc-style) that:
  1. User downloads and unzips Playback.app
  2. User drags Playback.app to /Applications
  3. App handles first-run setup automatically:
     - Installs LaunchAgents (with user permission)
     - Creates directories with correct permissions
     - Checks for dependencies (Python, FFmpeg)
     - Requests necessary permissions

### Updates

- In-place updates (replace binaries)
- Configuration file migration (backward compatible)
- Database schema migrations (if needed)

### Uninstallation

- Uninstaller script that:
  1. Stops and removes LaunchAgents
  2. Removes app bundles
  3. Optionally removes user data (with confirmation)

## Version Compatibility

- **macOS:** 12.0+ (Monterey or later)
- **Python:** 3.8+
- **FFmpeg:** 4.0+
- **Swift:** 5.5+
- **SQLite:** 3.35+ (system version)

## Monitoring & Observability

### Health Checks

- Recording service: Last screenshot timestamp
- Processing service: Last successful run timestamp
- Database: Row count, last insert timestamp
- Disk space: Available space in data directory

### Metrics (Logged)

- Screenshots captured per hour
- Processing duration per run
- Video segments generated per day
- Disk space used
- CPU/Memory usage peaks

### Alerts

- Permission denied (critical)
- Disk full (critical)
- Service crashed (warning)
- Processing taking > 5 minutes (warning)
