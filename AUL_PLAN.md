# AUL Migration Plan — COMPLETED

## Summary

All logging migrated from `#if DEBUG` / `print()` to Apple Unified Logging (AUL) using `os.Logger`.

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

## Streaming Logs

```bash
log stream --predicate 'subsystem == "com.falconer.Playback"'
# Filter by category:
log stream --predicate 'subsystem == "com.falconer.Playback" AND category == "Recording"'
# Show recent logs:
log show --predicate 'subsystem == "com.falconer.Playback"' --last 5m --style compact
```
