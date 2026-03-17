# Display Sleep / Screen Saver Auto-Pause — IMPLEMENTED

All items from this plan have been implemented. Summary of changes:

## Changes Made

### `RecordingService.swift`
- Added `isPausedBySystem` published property and `pendingTerminationWork` for delayed termination
- Added `pause()` — stops timer + indicator stream, sets `isPausedBySystem = true`
- Added `resume()` — restarts timer + indicator stream if recording was enabled and permission still granted
- Added `cancelPendingTermination()` — cancels grace period termination when system pause arrives
- Added `setupDisplaySleepObservers()` — listens to `screensDidSleep/Wake` and `screenIsLocked/Unlocked`
- Modified `stop()` to clear `isPausedBySystem`
- Modified `IndicatorStreamDelegate.stream(_:didStopWithError:)` — 2-second grace period before termination to handle race condition where macOS kills SCStream before sleep notification arrives

### `MenuBarViewModel.swift`
- Modified `updateRecordingState()` — when `isPausedBySystem` is true, shows paused state but keeps toggle enabled (so user doesn't see recording as user-disabled)

### Specs Updated
- `specs/recording-service.md` — lifecycle now includes display sleep/wake events, published state includes `isPausedBySystem`
- `specs/architecture.md` — RecordingService description and component communication updated
- `specs/privacy-security.md` — Recording Pause section expanded with display sleep/screen saver mechanism
