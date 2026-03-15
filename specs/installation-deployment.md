# Installation & Deployment Specification

**Component:** Installation and First Launch

## Distribution

Playback uses .zip distribution (Arc-style). No installer, no DMG.

### Package Contents

```
Playback-<version>.zip
└── Playback.app
```

### Installation

1. Download `Playback-<version>.zip`
2. Unzip (double-click or `ditto -x -k`)
3. Drag `Playback.app` to `/Applications/`
4. Launch from Applications, Dock, or Spotlight

## First Launch

On first launch, the app:

1. Checks Screen Recording permission via `CGPreflightScreenCaptureAccess()`
2. If not granted, requests via `CGRequestScreenCaptureAccess()` (standard macOS dialog)
3. Creates data directories (`Paths.ensureDirectoriesExist()`)
4. Creates default `config.json` if missing
5. Starts recording if permission was granted

There is no multi-step wizard. Permissions are requested inline, and defaults are used for everything else. The user can adjust the 4 available settings from the Settings panel at any time.

## Permissions

### Screen Recording (Required)

- Requested on first launch
- Without it, recording cannot start
- Settings panel shows permission status with "Open System Settings" button

### Accessibility (Optional)

- Needed for global hotkey (Option+Shift+Space)
- Not requested automatically — user can enable from Settings panel
- Without it, timeline is accessible via menu bar "Open Timeline" or app icon

## App Lifecycle

- **Launch at login:** Optional, controlled via Settings (`SMAppService`)
- **Menu bar:** Always visible while app is running
- **Timeline:** Opens/closes independently of app lifecycle
- **Quit:** "Quit Playback" from menu bar stops everything

## Uninstallation

1. Quit Playback from menu bar
2. Delete `Playback.app` from `/Applications/`
3. Optionally delete data: `rm -rf ~/Library/Application\ Support/Playback/`
