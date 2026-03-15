# AUL Migration Plan — COMPLETED

## Summary

All logging migrated from `#if DEBUG` / `print()` to Apple Unified Logging (AUL) using `os.Logger`. All silent error paths now have appropriate logging.

## What Was Done

1. **Created `Logging.swift`** with `Log` enum providing category loggers:
   - `Log.recording`, `Log.processing`, `Log.playback`, `Log.timeline`, `Log.ui`, `Log.menuBar`, `Log.hotkey`, `Log.config`
   - Subsystem: `"com.falconer.Playback"` (matches bundle ID)

2. **Migrated 13 files**, replacing ~90 `#if DEBUG`/`print()`/`#endif` blocks with single `Log.<category>.<level>(...)` calls:
   - RecordingService.swift (21 blocks + deleted custom `log()`/`logError()` functions and `lastLoggedError` property)
   - ProcessingService.swift (8 blocks)
   - PlaybackController.swift (21 blocks)
   - PlaybackApp.swift (6 blocks)
   - TimelineStore.swift (14 blocks)
   - TimelineView.swift (6 blocks)
   - ContentView.swift (3 blocks)
   - VideoBackgroundView.swift (1 block)
   - MenuBarViewModel.swift (3 blocks)
   - ConfigManager.swift (2 blocks)
   - GlobalHotkeyManager.swift (2 blocks)
   - Paths.swift (3 blocks)

3. **Updated docs**: CLAUDE.md, specs/architecture.md, specs/processing-service.md

4. **Verified**: Build succeeds, smoke test passes, AUL logs visible via `log show --predicate 'subsystem == "com.falconer.Playback"'`

5. **Fixed log quality issue**: TimelineStore was spamming "Error preparing segments query" every 5 seconds when the database had no `segments` table (processing service hasn't run). Fixed to:
   - Detect "no such table" case and log at `debug` level instead of `error`
   - Include actual SQLite error message in non-trivial error cases
   - Set loading state to `.empty` when table doesn't exist

6. **Filled logging coverage gaps** in files that had silent failures:
   - **DateTimePickerView.swift**: Added logging for database open failures and query preparation failures in both `loadAvailableDates()` and `loadAvailableTimesForSelectedDate()`
   - **LaunchAtLoginManager.swift**: Added logging for SMAppService register/unregister operations (info level) and unsupported OS errors
   - **Logging.swift**: Added `Log.system` category for system-level operations (launch-at-login, etc.)

7. **Eliminated all silent error paths** (18 instances across 7 files):
   - **ProcessingService.swift**: Directory listing failures now log at error level (3 critical paths that silently stopped the pipeline); file permission, cleanup, and schema init failures now logged at debug/error/fault levels as appropriate
   - **PlaybackApp.swift**: Stale signal file removal and directory initialization failures now logged
   - **RecordingService.swift**: File permission-setting failures now logged at debug level
   - **Paths.swift**: Directory permission-setting failures now logged at debug level
   - **ConfigManager.swift**: File sync/close failures now logged at debug level

## Streaming Logs

```bash
log stream --predicate 'subsystem == "com.falconer.Playback"'
# Filter by category:
log stream --predicate 'subsystem == "com.falconer.Playback" AND category == "Recording"'
# Show recent logs:
log show --predicate 'subsystem == "com.falconer.Playback"' --last 5m --style compact
```
