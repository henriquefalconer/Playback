# File Structure Specification

**Component:** Project Layout

## Source Directory

```
src/
└── Playback/
    ├── Playback.xcodeproj
    ├── Playback/
    │   ├── PlaybackApp.swift              # App entry (MenuBarExtra + WindowGroup)
    │   ├── ContentView.swift              # Timeline view with gestures
    │   ├── Paths.swift                    # Environment-aware path resolution
    │   ├── PlaybackController.swift       # AVPlayer, scrubbing, segment preload
    │   ├── TimelineView.swift             # Segment bars, playhead, ticks
    │   ├── TimelineStore.swift            # SQLite queries, segment models
    │   ├── VideoBackgroundView.swift      # AVPlayerLayer rendering
    │   ├── Config/
    │   │   ├── Config.swift               # Config data model
    │   │   └── ConfigManager.swift        # Config persistence
    │   ├── MenuBar/
    │   │   ├── MenuBarView.swift          # Menu bar dropdown UI
    │   │   └── MenuBarViewModel.swift     # Recording state, controls
    │   ├── Settings/
    │   │   ├── SettingsView.swift         # Single-panel settings
    │   │   └── HotkeyRecorderView.swift   # Hotkey recorder
    │   ├── Services/
    │   │   ├── RecordingService.swift      # Screenshot capture (ScreenCaptureKit)
    │   │   ├── GlobalHotkeyManager.swift   # Carbon Events hotkey
    │   │   └── LaunchAtLoginManager.swift  # SMAppService wrapper
    │   ├── Timeline/
    │   │   ├── DateTimePickerView.swift   # Calendar + time list
    │   │   ├── ErrorStateView.swift       # Error display with retry
    │   │   ├── EmptyStateView.swift       # No recordings state
    │   │   ├── LoadingStateView.swift     # Loading indicator
    │   │   └── LoadingScreenView.swift    # Processing overlay
    │   ├── Utilities/
    │   │   └── ShellCommand.swift         # Process execution
    │   ├── Resources/
    │   │   └── Assets.xcassets
    │   └── Playback.entitlements
    ├── PlaybackTests/
    └── PlaybackUITests/
```

## Data Directory

**Production:**
```
~/Library/Application Support/Playback/
├── data/
│   ├── temp/YYYYMM/DD/     # Screenshots (0700)
│   ├── chunks/YYYYMM/DD/   # Videos (0700)
│   ├── meta.sqlite3         # Database (0600)
│   └── .timeline_open       # Signal file
└── config.json              # Configuration (0644)
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

## Path Resolution

`Paths.swift` resolves all paths based on `PLAYBACK_DEV_MODE` environment variable:

| Path | Development | Production |
|---|---|---|
| Base data | `SRCROOT/dev_data` | `~/Library/Application Support/Playback/data` |
| Config | `SRCROOT/dev_config.json` | `~/Library/Application Support/Playback/config.json` |
| Database | `dev_data/meta.sqlite3` | `data/meta.sqlite3` |
| Temp | `dev_data/temp/` | `data/temp/` |
| Chunks | `dev_data/chunks/` | `data/chunks/` |
| Signal file | `dev_data/.timeline_open` | `data/.timeline_open` |

## File Naming

**Screenshots:** `YYYYMMDD-HHMMSS-<8hex-uuid>-<bundle.id>` (no extension)

**Videos:** `<20hex-segment-id>.mp4`

**Date directories:** `YYYYMM/DD/` (e.g., `202603/15/`)
