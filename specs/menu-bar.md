# Menu Bar Specification

**Component:** Menu Bar UI

## Overview

The menu bar provides an always-visible system tray icon for controlling Playback. It is implemented as a `MenuBarExtra` scene in `PlaybackApp.swift`.

## Menu Bar Icon

**States:**
- Recording active: red filled circle (`record.circle.fill`)
- Recording paused: gray outlined circle (`record.circle`)
- Error: exclamation mark (`exclamationmark.circle.fill`)

**Size:** 16x16 points (standard menu bar icon)

**Status polling:** Every 5 seconds, syncs icon with `RecordingService.shared.isRecording`

## Menu Items

```
┌─────────────────────────┐
│ Record Screen    [toggle]│
│─────────────────────────│
│ Open Timeline           │
│ Settings...             │
│─────────────────────────│
│ About Playback          │
│ Quit Playback           │
└─────────────────────────┘
```

### Record Screen

- Toggle switch
- Checks `CGPreflightScreenCaptureAccess()` before enabling
- Updates `config.recordingEnabled` and calls `RecordingService.start()` / `.stop()`

### Open Timeline

- Opens the timeline viewer window
- If already open, brings to front

### Settings

- Opens the settings panel (single panel, not tabbed)
- Contains: Launch at login, permissions, hotkey, excluded apps

### Quit Playback

- Stops recording service
- Closes all windows
- Terminates the app

## Quit Behavior

- **ESC or Cmd+Q:** Closes timeline window only. App continues running, recording continues.
- **"Quit Playback" from menu bar:** Stops everything and quits the app.

## Source Files

- `src/Playback/Playback/MenuBar/MenuBarView.swift` — UI layout
- `src/Playback/Playback/MenuBar/MenuBarViewModel.swift` — State management
