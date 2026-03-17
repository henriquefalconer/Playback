# Unpause Plan: Resume Recording on User Login (Not Display Wake)

## Status: COMPLETED

All changes implemented. Recording now only auto-resumes on `com.apple.screenIsUnlocked` (after user authentication), not on `screensDidWakeNotification` (display wake before login).

## What Changed

- **Removed** `screensDidWakeNotification` → `resume()` observer from `RecordingService.swift`
- **Renamed** `setupDisplaySleepObservers()` → `setupSystemPauseObservers()`
- **Updated** docstrings and log messages to reflect new behavior
- **Updated** specs: `recording-service.md`, `architecture.md`, `privacy-security.md`

## Edge Cases

- **Screen saver with password** — `com.apple.screenIsUnlocked` fires on dismissal, resume works
- **Screen saver without password** — Recording won't auto-resume (acceptable, rare case)
- **Lid open without login** — Recording stays paused until user authenticates (desired)
- **Fast User Switching** — `com.apple.screenIsUnlocked` fires for incoming session, works correctly
