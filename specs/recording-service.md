# Recording Service Specification

**Component:** In-Process Screenshot Capture (Swift)

## Overview

The recording service runs inside Playback.app using ScreenCaptureKit. It captures a screenshot every 2 seconds and saves it to the temp directory.

## Implementation

- **Source:** `src/Playback/Playback/Services/RecordingService.swift`
- **Singleton:** `RecordingService.shared`
- **Capture API:** ScreenCaptureKit (`SCScreenshotManager.captureImage`)
- **Interval:** 2 seconds (hardcoded, not configurable)
- **Output:** PNG files in `temp/YYYYMM/DD/`

## Capture Loop

Each timer tick:

1. Check if timeline is open (`.timeline_open` signal file exists) → skip if yes
2. Get frontmost app bundle ID via `NSWorkspace.shared.frontmostApplication`
3. Check if app is in excluded list → skip if yes
4. Capture screenshot via ScreenCaptureKit
5. Generate filename: `YYYYMMDD-HHMMSS-<8char-uuid>-<bundleid>`
6. Create date directory: `temp/YYYYMM/DD/`
7. Write PNG data to file

## Filename Format

```
YYYYMMDD-HHMMSS-<uuid>-<app_id>
```

Example: `20260315-143052-a3f8b29c-com.apple.Safari`

- No file extension (extensionless)
- UUID: first 8 hex chars of UUID4
- App ID: bundle identifier from NSWorkspace

## Lifecycle

1. App launches → `start()` if recording enabled in config
2. Timeline opens → pauses capture (signal file mechanism)
3. Timeline closes → resumes capture
4. Display sleeps / screen saver starts → `pause()` (stops timer + indicator stream)
5. Display wakes / screen saver ends → `resume()` (if recording was enabled)
6. Config changes → `reload()` (re-reads excluded apps)
7. App quits → `stop()`

## Permission

Uses the app's Screen Recording permission (`CGPreflightScreenCaptureAccess`). Will not start without it.

## App Exclusion

- Mode: skip only (no "invisible" mode)
- Check: `excludedApps.contains(frontmostApp)`
- Action: skip capture entirely, no file created

## Published State

```swift
@Published private(set) var isRecording: Bool
@Published private(set) var lastCaptureTime: Date?
@Published private(set) var captureCount: UInt64
@Published private(set) var isPausedBySystem: Bool
```

Consumed by `MenuBarViewModel` for status display.
