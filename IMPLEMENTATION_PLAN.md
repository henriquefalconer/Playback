<!--
 Copyright (c) 2026 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Playback - Implementation Plan

Canonical specs live in `specs/`. This plan tracks only actionable work going forward.

---

## Architecture Simplification (Major Refactor)

**Goal:** Remove bloat, consolidate to all-Swift, polish core features.

See `specs/` for the target architecture. The current codebase has significant code to remove and rewrite.

### Phase 1: Remove Bloat (Delete Code)

Remove all non-key features and their associated code, tests, and UI.

#### Remove Python Layer
- [ ] Delete `src/lib/` (9 modules + 8 test files)
- [ ] Delete `src/scripts/` (5 scripts + 2 test files)
- [ ] Remove Python references from build process and pre-commit hooks

#### Remove OCR & Search
- [ ] Delete `Search/` directory (SearchController, SearchBar, SearchResultsList, SearchResultRow)
- [ ] Remove Command+F handler and search state from `ContentView.swift`
- [ ] Remove search result markers from `TimelineView.swift`
- [ ] Remove `ocr_text` and `ocr_search` tables from database initialization
- [ ] Delete search-related tests (SearchControllerTests, SearchIntegrationTests, SearchUITests)

#### Remove Diagnostics
- [ ] Delete `Diagnostics/` directory (DiagnosticsController, DiagnosticsView, LogEntry)
- [ ] Remove diagnostics window from `PlaybackApp.swift`
- [ ] Remove diagnostics button from `MenuBarView.swift`

#### Remove FirstRun Wizard
- [ ] Delete `FirstRun/` directory (6 files: Coordinator, WelcomeView, StorageSetupView, DependencyCheckView, InitialConfigView, PermissionsView, FirstRunWindowView)
- [ ] Replace with inline permission request on first launch (check `CGPreflightScreenCaptureAccess`, request if needed)
- [ ] Keep `Paths.ensureDirectoriesExist()` call and default config creation on first launch

#### Remove Notifications
- [ ] Delete `Services/NotificationManager.swift`
- [ ] Remove notification references from other files

#### Remove LaunchAgent Infrastructure
- [ ] Delete `Services/LaunchAgentManager.swift`
- [ ] Delete `Services/ProcessMonitor.swift`
- [ ] Delete `Resources/launchagents/` (3 plist templates)
- [ ] Delete LaunchAgent-related tests

#### Remove Non-Key Settings
- [ ] Remove tab structure from `SettingsView.swift` — flatten to single panel
- [ ] Keep only: Launch at login, permissions status, hotkey config, excluded apps list
- [ ] Remove: notification toggles, recording info display, processing interval picker, "Process Now" button, retention policies, manual cleanup, exclusion mode picker, data export, video encoding display, system info, service status, maintenance options (reset, rebuild, export logs, run diagnostics)
- [ ] Remove `pauseWhenTimelineOpen` from Config (hardcode always-on behavior)
- [ ] Remove `processingIntervalMinutes` from Config (hardcode 5 minutes)
- [ ] Remove `exclusionMode` from Config (hardcode "skip")
- [ ] Remove notification-related fields from Config
- [ ] Remove `tempRetentionPolicy`, `recordingRetentionPolicy`, `ffmpegCrf`, `videoFps` from Config
- [ ] Delete `HotkeyRecorderView.swift` only if hotkey config is simplified to non-recordable

#### Clean Up Config
- [ ] Strip `Config.swift` to: `excludedApps`, `timelineShortcut`, `recordingEnabled`, `launchAtLogin`
- [ ] Strip `ConfigManager.swift` — remove ConfigWatcher (hot-reload unnecessary for 4 settings), remove backup rotation, simplify

### Phase 2: Implement Swift Processing Service

Replace `build_chunks_from_temp.py` with in-process Swift service.

- [ ] Create `Services/ProcessingService.swift`
- [ ] Implement frame loading from `temp/YYYYMM/DD/` directory
- [ ] Implement frame grouping (by resolution, max count)
- [ ] Implement video creation using AVAssetWriter (H.264, hardware-accelerated)
- [ ] Implement app segment aggregation (group consecutive frames by bundle ID)
- [ ] Implement SQLite writes (segments + appsegments tables)
- [ ] Implement temp file cleanup after successful processing
- [ ] Set up 5-minute Timer (hardcoded interval)
- [ ] Integrate into `PlaybackApp.swift` lifecycle

### Phase 3: Clean Up Tests

- [ ] Delete all Python tests
- [ ] Delete tests for removed features (LaunchAgent, ProcessMonitor, Diagnostics, Search, Notification, FirstRun)
- [ ] Update remaining tests to reflect simplified architecture
- [ ] Ensure smoke test passes after all changes

---

## Remaining Polish Items

### Still TODO
- [ ] App icon assets (requires graphic design)
- [ ] Momentum scrolling with logarithmic deceleration
- [ ] Drag-drop app exclusion from /Applications
- [ ] Remove quit confirmation dialog (quit immediately)

### Already Working
- Recording service (ScreenCaptureKit, 2s interval)
- Timeline viewer (AVPlayer, scrubbing, pinch zoom, frozen frames, segment preload)
- Date/time picker (calendar + time list)
- Menu bar (recording toggle, open timeline, settings, quit)
- Global hotkey (Option+Shift+Space via Carbon Events)
- Config persistence
- Database (SQLite with WAL, segments + appsegments)
- Error/empty/loading states
- Fullscreen presentation options
- Cursor-anchored zoom

---

## Pre-Commit Validation

```bash
./smoke-test.sh
```

- **Exit 0** — safe to commit
- **Exit 1** — fix before committing (or document in Active Runtime Issues below)
- **Exit 2** — skipped (not on macOS)

### Active Runtime Issues Log

(Document any crashes discovered during validation that can't be immediately fixed)

---

## File Reference

| Component | Files |
|-----------|-------|
| App Entry | `PlaybackApp.swift` |
| Menu Bar | `MenuBar/MenuBarView.swift`, `MenuBar/MenuBarViewModel.swift` |
| Timeline | `ContentView.swift`, `TimelineView.swift`, `TimelineStore.swift`, `PlaybackController.swift` |
| Video | `VideoBackgroundView.swift` |
| Date Picker | `Timeline/DateTimePickerView.swift` |
| Settings | `Settings/SettingsView.swift`, `Settings/HotkeyRecorderView.swift` |
| Config | `Config/Config.swift`, `Config/ConfigManager.swift` |
| Services | `Services/RecordingService.swift`, `Services/GlobalHotkeyManager.swift`, `Services/LaunchAtLoginManager.swift` |
| State Views | `Timeline/EmptyStateView.swift`, `Timeline/ErrorStateView.swift`, `Timeline/LoadingStateView.swift`, `Timeline/LoadingScreenView.swift` |
| Utilities | `Paths.swift`, `Utilities/ShellCommand.swift` |

All Swift source under `src/Playback/Playback/`. Tests under `src/Playback/PlaybackTests/` and `src/Playback/PlaybackUITests/`.
