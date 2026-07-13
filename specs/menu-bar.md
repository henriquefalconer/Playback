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

## App Lifecycle

Recording belongs to the menu bar item, not the Dock icon. The app is a menu-bar
accessory app (`LSUIElement`): the Dock icon exists only while a timeline or
settings window is visible, and disappears when the last one closes.

- **Manual launch (Finder/Dock) or Option+Shift+Space:** Opens the rewind view
  (showing the Dock icon while it is open).
- **Login-item launch:** Stays in the background — menu bar item only, no windows.
- **ESC, Cmd+Q, or quitting from the Dock icon:** Closes windows only. The app
  drops back to menu-bar-only mode and recording continues.
- **"Quit Playback" from menu bar:** Stops everything and quits the app. This is
  the only user action that terminates the process.
- **Logout / restart / shutdown:** Always allowed to terminate the app.
- **"Stop Presenting" on the macOS recording indicator:** Turns recording off
  (persisted to config) but keeps the menu bar app running.

## Source Files

- `src/Playback/Playback/PlaybackApp.swift` — Status item, menu, quit interception, activation policy
- `src/Playback/Playback/MenuBar/MenuBarViewModel.swift` — State management
