# Architecture Specification

**Component:** System Architecture

## Architecture: Single Swift App

Playback is a single unified macOS app (`Playback.app`) with two scenes and two in-process services.

### Scenes

1. **MenuBarExtra** — Always-visible system tray icon
   - Recording toggle
   - Open Timeline button
   - Settings button
   - Quit Playback button

2. **WindowGroup** — Fullscreen timeline viewer window
   - Opened on demand (menu bar, hotkey, app icon)
   - Can be closed without stopping the app
   - Always pauses recording while open

### In-Process Services

1. **RecordingService** — Screenshot capture
   - Uses ScreenCaptureKit (app's Screen Recording permission)
   - Fixed 2-second interval via Timer
   - Pauses when timeline window is open (hardcoded, always on)
   - Respects excluded apps list from config
   - Saves PNGs to `temp/YYYYMM/DD/`

2. **ProcessingService** — Video generation (to be implemented)
   - Converts temp PNGs to MP4 video segments using AVFoundation
   - Fixed 5-minute interval (hardcoded)
   - Writes segments + appsegments to SQLite
   - Deletes processed temp files after successful conversion

### Permission Model

**Single permission grant: Playback.app**

| Permission | Required | Purpose |
|---|---|---|
| Screen Recording | Yes | Screenshot capture via ScreenCaptureKit |
| Accessibility | Optional | Global hotkey (Option+Shift+Space) |

### Component Communication

All communication is in-process (no IPC needed):

- **Config changes** → `ConfigManager` publishes via `@Published` / NotificationCenter
- **Recording state** → `RecordingService.shared.isRecording` observed by MenuBarViewModel
- **Timeline open/close** → `SignalFileManager` creates/removes `.timeline_open` file; RecordingService checks before each capture
- **Segment data** → `TimelineStore` reads SQLite directly; auto-refreshes every 5 seconds

### Data Flow

```
RecordingService (2s timer)
    → temp/YYYYMM/DD/YYYYMMDD-HHMMSS-uuid-appid.png

ProcessingService (5min timer)
    → chunks/YYYYMM/DD/segmentid.mp4
    → meta.sqlite3 (segments + appsegments tables)

TimelineStore (5s refresh)
    → reads meta.sqlite3
    → feeds PlaybackController (AVPlayer)
    → renders in ContentView / TimelineView
```

### File System Layout

**Production:**
```
~/Library/Application Support/Playback/
├── data/
│   ├── temp/YYYYMM/DD/          # Screenshots (deleted after processing)
│   ├── chunks/YYYYMM/DD/        # Video segments
│   ├── meta.sqlite3              # Segment metadata
│   └── .timeline_open            # Signal file
└── config.json                   # User configuration
```

**Development (PLAYBACK_DEV_MODE=1):**
```
<project>/
├── dev_data/
│   ├── temp/
│   ├── chunks/
│   ├── meta.sqlite3
│   └── .timeline_open
└── dev_config.json
```

### Error Handling

- Recording failures: Log, skip frame, continue
- Processing failures: Log, preserve temp files, skip segment
- Database failures: Show error state in timeline UI with retry button
- Permission denied: Inline prompt in settings panel with "Open System Settings" button

### Performance Targets

| Component | CPU | Memory |
|---|---|---|
| Recording (idle) | <5% | <50MB |
| Processing (burst) | <20% | <200MB |
| App (timeline closed) | <1% | <50MB |
| App (timeline open) | 15-30% | <300MB |
