# WINSER_PLAN: Display Reconfiguration Pause/Resume

## Status: IMPLEMENTED

All steps completed. Rebuild and test on macOS to verify.

## Problem

When a monitor is disconnected, connected, or resolution changes, macOS WindowServer tears down and recreates display surfaces. ScreenCaptureKit's `SCStream` gets killed (the indicator stream), triggering the 2-second grace period in `IndicatorStreamDelegate.stream(_:didStopWithError:)`. Since no system-pause notification (sleep/lock) arrives, the grace period expires and the app **quits**. The fix: **pause instead of quit**, then **auto-resume** once WindowServer finishes redrawing.

## What Was Done

1. Added `isPausedByDisplayChange` property and `displayStabilizationWork` debounce timer
2. Added `NSApplication.didChangeScreenParametersNotification` observer in `setupSystemPauseObservers()`
3. Implemented `handleDisplayReconfiguration()` — cancels pending termination, pauses recording, schedules 3s stabilization delay
4. Implemented `resumeAfterDisplayChange()` — resumes after stabilization
5. Updated `IndicatorStreamDelegate.stream(_:didStopWithError:)` grace period to check `isPausedByDisplayChange`
6. Added cleanup of `displayStabilizationWork` in `stop()` and `deinit`
7. Updated `specs/recording-service.md` lifecycle section
8. Updated `specs/architecture.md` component communication section

## Key Design Decisions

- **Why `NSApplication.didChangeScreenParametersNotification`:** Fires on monitor connect, disconnect, resolution change, and arrangement change. Standard high-level AppKit API
- **Why 3-second stabilization delay:** WindowServer takes 1-2s to finish redrawing. 3s provides margin. Debounce ensures rapid successive notifications only trigger one resume
- **Why `pause()` + `resume()` reuse:** Existing methods already handle indicator stream teardown, timer invalidation, permission re-checking, and state management
- **Why private `isPausedByDisplayChange`:** The pause is transient (~3s). `isPausedBySystem` (set by `pause()`) already updates the menu bar icon
- **Why cancel `pendingTerminationWork` in handler:** Display change notification may arrive after stream stops but before 2s grace period expires
