<!--
 Copyright (c) 2025 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Playback - Implementation Plan

Based on comprehensive technical specifications in `specs/` and verified against actual source code (2026-02-08).

---

## How to Read This Plan

- Items are **sorted by priority** within each section (highest first)
- **Confirmed** = verified by reading the actual source file and line numbers
- Items marked with checkboxes: `[ ]` = TODO, `[x]` = COMPLETE
- Each item references the spec and exact source file + line numbers
- **Ultimate Goals (ALL COMPLETE ✅):**
  1. ✅ Fix SIGABRT crash when `launchctl list` fails (pipe deadlock in LaunchAgentManager.swift:307)
  2. ✅ Fix ConfigWatcher double-close SIGABRT crash
  3. ✅ Ensure no custom storage location picker exists (confirmed: it doesn't)
  4. ✅ Storage paths: `~/Library/Application Support/Playback/` for production, `dev_data/` for development (already correct in code)

---

## Completed Work Summary

### Python Backend -- 100% Complete
- All 280 tests passing, zero bugs, production-ready
- Core libs: paths, timestamps, config, database, video, macos, logging_config, utils
- Services: record_screen, build_chunks_from_temp, cleanup_old_chunks, ocr_processor, export_data
- Security & network tests complete (38 tests)
- All 3 services migrated to structured JSON logging (80 print statements migrated)

### Swift Infrastructure -- Complete
- Config system with hot-reload, validation, backup rotation (`Config/`)
- Paths with dev/prod switching, signal file manager (`Paths.swift`)
- LaunchAgent lifecycle management for 3 agent types (`Services/LaunchAgentManager.swift`)
- Global hotkey via Carbon API with permission handling (`Services/GlobalHotkeyManager.swift`)
- Timeline data model with segment selection and gap handling (`TimelineStore.swift`)
- Diagnostics UI with logs, health, performance tabs (`Diagnostics/`)
- NotificationManager fully implemented (`Services/NotificationManager.swift`)

### Swift Testing -- 95% Complete
- 203 Swift unit tests passing (9 test classes)
- 72 integration tests passing
- 115 UI tests written (build-verified, require GUI)
- 21 performance tests written (build-verified)
- 280 Python tests passing

### Previously Verified Complete Items
- [x] **Error/empty/loading states** -- `EmptyStateView.swift`, `ErrorStateView.swift`, `LoadingStateView.swift` all exist and are integrated into `ContentView.swift`
- [x] **Loading screen during processing** -- `LoadingScreenView.swift` with `ProcessMonitor.swift` polling every 500ms
- [x] **updateProcessingInterval()** -- Fully implemented in `LaunchAgentManager.swift:187-225` (reads/writes plist, validates 1-60 min range, reloads agent)
- [x] **Search text highlighting** -- `SearchResultRow.swift` has `highlightedSnippet()` with yellow background on matched terms
- [x] **NotificationManager** -- Full implementation in `Services/NotificationManager.swift` (231 lines) with UNUserNotificationCenter, categories, permission handling, and convenience methods for recording/processing/disk/cleanup/permission notifications
- [x] **Search result markers on timeline** -- `TimelineView.swift:262-279` renders yellow vertical line markers at search match timestamps within visible window
- [x] **Processing tab features** -- `SettingsView.swift:182-517` has last run timestamp/duration/status display, "Process Now" button, auto-refresh every 10s
- [x] **Processing interval picker** -- `SettingsView.swift:267-277` with 1/5/10/15/30/60 minute options
- [x] **Custom storage location picker** -- Confirmed NOT present, which is correct. StorageSetupView.swift shows only the default path with no picker. NSSavePanel usage is limited to export operations (data export and log export), which is correct behavior.
- [x] **Storage paths correct** -- Production paths use `~/Library/Application Support/Playback/` (Swift Paths.swift, Python paths.py, LaunchAgentManager.swift all consistent). Development uses `dev_data/`. No path changes needed.

---

## Priority 1 -- Critical Bugs (Crashes and Deadlocks) ✅ COMPLETE

**All Priority 1 items fixed (2026-02-08):**
- Fixed pipe deadlock SIGABRT crashes in 8 locations by creating shared `ShellCommand` utility
- Fixed ConfigWatcher double-close file descriptor crash
- Fixed force unwrap crashes in Paths.swift, SettingsView.swift, DateTimePickerView.swift, DependencyCheckView.swift
- Eliminated code duplication across 8 shell command implementations

### 1.1 SIGABRT Crash: Pipe Deadlock in LaunchAgentManager.swift:307 ✅ FIXED

- [x] **Fix pipe deadlock in `runCommand()` that causes SIGABRT**
- **Source:** `src/Playback/Playback/Services/LaunchAgentManager.swift` lines 296-318
- **Root Cause:** `runCommand()` calls `process.waitUntilExit()` on line 307 BEFORE reading pipe data on lines 309-310. When `launchctl list com.playback.recording` returns "Could not find service" on stderr, the process may block if the pipe buffer fills, causing `waitUntilExit()` to deadlock. The system eventually sends SIGABRT.
- **Fix applied:** Migrated to shared `ShellCommand.run()` utility that reads pipe data before waiting. LaunchAgentManager now uses `ShellCommand.run()` for all process execution.

### 1.2 SIGABRT Crash: ConfigWatcher Double-Close File Descriptor ✅ FIXED

- [x] **Fix ConfigWatcher deinit double-close**
- **Source:** `src/Playback/Playback/Config/ConfigManager.swift` lines 163-209
- **Root Cause:** ConfigWatcher closes the file descriptor in TWO places (cancel handler and deinit).
- **Fix applied:** Removed `close(fileDescriptor)` from deinit entirely. Cancel handler is now the sole owner of fd closure, eliminating the double-close race condition.

### 1.3 Pipe Deadlock: 7 Additional Locations with Same Pattern ✅ FIXED

- [x] **Fix pipe deadlock in ProcessMonitor.swift:81**
- [x] **Fix pipe deadlock in DependencyCheckView.swift:174**
- [x] **Fix pipe deadlock in SettingsView.swift (5 instances: lines 506, 846, 1084, 1167, 1514)**
- **Source:** 7 additional locations across 3 files (8 total including 1.1)
- **Root Cause:** All locations call `process.waitUntilExit()` BEFORE `pipe.fileHandleForReading.readDataToEndOfFile()`. Same deadlock pattern as 1.1.
- **Fix applied:** All 7 locations migrated to shared `ShellCommand.run()` utility. Deadlock pattern eliminated across entire codebase.

### 1.4 Force Unwrap Crash: Paths.swift .first! ✅ FIXED

- [x] **Fix force unwrap in Paths.swift:24 and Paths.swift:58**
- **Source:** `src/Playback/Playback/Paths.swift` lines 24 and 58
- **Root Cause:** Both production path branches use `.first!` on `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`.
- **Fix applied:** Replaced `.first!` with `guard let` statements. Also fixed in SettingsView.swift lines 829 and 1150 (findProjectRoot() methods).

### 1.5 Code Quality: 8 Duplicated Shell Command Implementations ✅ FIXED

- [x] **Extract shared ShellCommand utility**
- **Source:** 7 separate `runShellCommand()`/`runCommand()` implementations (8 call sites)
- **Problem:** Every implementation has the same pipe deadlock bug (1.1/1.3).
- **Fix applied:** Created `Utilities/ShellCommand.swift` with comprehensive implementation supporting synchronous, async/await, and completion handler patterns. All 8 call sites migrated successfully.

### 1.6 Force-Unwrapped URLs in SettingsView.swift ✅ FIXED

- [x] **Fix force-unwrapped URL(string:)! calls**
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift` lines 1100 and 1104
- **Root Cause:** `URL(string: "x-apple.systempreferences:...")!` -- if the URL string is somehow invalid, this crashes.
- **Fix applied:** Replaced force unwraps with `guard let` statements. Also fixed DependencyCheckView.swift line 279 `URL(string: "https://brew.sh")!`.

### 1.7 Force Unwrap in DateTimePickerView.swift ✅ FIXED

- [x] **Fix force unwraps in calendar operations**
- **Source:** `src/Playback/Playback/Timeline/DateTimePickerView.swift` lines 191-192
- **Root Cause:** `calendar.range(of: .day, in: .month, for: currentMonth)!` and `calendar.date(from: ...)!` can fail with invalid date/calendar configurations.
- **Fix applied:** Replaced force unwraps with `guard let` statements and safe fallbacks.

---

## Priority 2 -- Important Missing Features

These features are specified but not implemented. They impact UX but are not blocking core functionality.

### 2.1 Settings: General Tab Missing Key Controls

- [ ] **Add Launch at Login toggle**
- [ ] **Add Hotkey Recorder**
- [ ] **Add Permission status section**
- **Spec:** `specs/menu-bar.md` lines 114-152
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:63-106`
- **Missing features:**
  - Launch at Login toggle using `SMAppService` API (macOS 13+)
  - Hotkey Recorder for customizing the timeline shortcut (currently read-only text display at line 85)
  - Permission status section showing Screen Recording and Accessibility status with visual indicators
- **Currently:** Only shows notification toggles and a read-only shortcut display

### 2.2 Search: App Icon in Result Rows

- [ ] **Add app icon and app name to search results**
- **Spec:** `specs/search-ocr.md` lines 101-103 -- "App icon (20x20), app name, timestamp, snippet"
- **Source:** `src/Playback/Playback/Search/SearchResultRow.swift`
- **Missing:** No app icon or app name shown; only timestamp + confidence + snippet displayed

### 2.3 Permission Checking Uses Python Subprocess Instead of Native API

- [ ] **Replace Python subprocess with CGPreflightScreenCaptureAccess()**
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:1065-1092`
- **Current:** The `checkScreenRecordingPermission()` function spawns a Python subprocess that imports `Quartz` and calls `CGWindowListCopyWindowInfo`. This is slow and fragile.
- **Fix:** Replace with Swift's native `CGPreflightScreenCaptureAccess()` -- a single synchronous function call that returns Bool immediately.

### 2.4 App Icon Missing

- [ ] **Create app icon assets** (requires graphic design work)
- **Spec:** `specs/timeline-graphical-interface.md` lines 32-36
- **Source:** `Assets.xcassets/AppIcon.appiconset/Contents.json` -- all 10 size slots defined but zero image files present
- **Blocker:** Cannot be generated programmatically -- requires manual design work

---

## Priority 3 -- UX Polish and Completeness

These items improve the overall experience but are not blocking core functionality.

### 3.1 Timeline: Zoom Anchor Point Missing

- [ ] **Implement cursor-anchored zoom**
- **Spec:** `specs/timeline-graphical-interface.md` lines 179, 388
- **Source:** `ContentView.swift:288-319`
- **Problem:** Pinch zoom changes scale but doesn't maintain the timestamp under the cursor

### 3.2 Timeline: No Segment Preloading

- [ ] **Preload next segment at 80% playback**
- **Spec:** `specs/timeline-graphical-interface.md` lines 329-332
- **Source:** `PlaybackController.swift`
- **Missing:** Segments loaded reactively, causing 100-500ms pause on each segment transition

### 3.3 Timeline: Fullscreen Configuration Incomplete

- [ ] **Add letterboxing, gesture disabling, presentation options**
- **Spec:** `specs/timeline-graphical-interface.md` lines 69-88
- **Source:** `PlaybackApp.swift`

### 3.4 Timeline: No Momentum Scrolling / Deceleration

- [ ] **Add logarithmic decay after scroll gesture ends**
- **Spec:** `specs/timeline-graphical-interface.md` lines 361-364
- **Source:** `ContentView.swift`

### 3.5 Settings: App Exclusion Only Supports Manual Entry

- [ ] **Add drag-drop from /Applications and file picker**
- **Spec:** `specs/menu-bar.md` lines 314-316
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:966-1001`

### 3.6 Settings: Database Rebuild Is a Stub

- [ ] **Implement actual database rebuild logic with progress feedback**
- **Spec:** `specs/menu-bar.md` lines 393-402
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:1450-1452`
- **Currently:** `rebuildDatabase()` just sets `showRebuildProgress = true`, no actual rebuild logic.

### 3.7 Settings: Reset All Doesn't Restart App

- [ ] **Add app restart after reset**
- **Spec:** `specs/menu-bar.md` line 390
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:1446-1448`

### 3.8 Settings: Export Logs Is Minimal

- [ ] **Improve log export with system info and structured archive**
- **Spec:** `specs/menu-bar.md` lines 405-418
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:1454-1474`

### 3.9 Config: Migration Logic Is a Stub

- [ ] **Implement actual config migration between versions**
- **Source:** `src/Playback/Playback/Config/ConfigManager.swift:132-145`
- **Currently:** `migrateConfig()` only matches version "1.0.0" and sets it back to "1.0.0" -- no-op.

### 3.10 Config: Environment Variable Overrides Not Implemented

- [ ] **Support PLAYBACK_CONFIG and PLAYBACK_DATA_DIR env vars**
- **Spec:** `specs/configuration.md` -- PLAYBACK_CONFIG and PLAYBACK_DATA_DIR environment variables
- **Source:** `src/Playback/Playback/Paths.swift` -- only checks `PLAYBACK_DEV_MODE`

### 3.11 FirstRun: No Notification Listener for Permission Re-check

- [ ] **Auto-refresh permission status when app becomes active**
- **Source:** `PermissionsView.swift`

### 3.12 Diagnostics: Tab Organization Differs from Spec

- [ ] **Align diagnostics tabs with spec or document deviation**
- **Spec:** `specs/logging-diagnostics.md` -- Overview, Recording Logs, Processing Logs, Resource Usage
- **Source:** `Diagnostics/DiagnosticsView.swift` -- Logs (generic), Health, Performance, Reports

### 3.13 Portuguese Comments in Source Files

- [ ] **Translate Portuguese comments to English**
- **Source:** 5 files with ~105 Portuguese comments total:
  - `src/Playback/Playback/PlaybackController.swift` -- ~55 Portuguese comments
  - `src/Playback/Playback/TimelineStore.swift` -- ~30 Portuguese comments
  - `src/Playback/Playback/TimelineView.swift` -- ~20 Portuguese comments
  - `src/scripts/build_chunks_from_temp.py` -- ~4 Portuguese comments
  - `src/scripts/stop_record_screen.sh` -- 1 Portuguese comment

### 3.14 Incorrect Bundle ID in MenuBarViewModel.swift

- [ ] **Fix hardcoded bundle ID**
- **Source:** `src/Playback/Playback/MenuBar/MenuBarViewModel.swift` line 130
- **Current:** `"com.playback.timeline"` -- incorrect/stale bundle ID used to find timeline viewer
- **Fix:** Change to `"com.falconer.Playback"` to match the actual bundle identifier
- **Note:** In single-app architecture, this code likely doesn't work anyway since there's no separate timeline app to terminate.

---

## Priority 4 -- Architectural Considerations

These are significant decisions that may or may not be pursued for MVP.

### 4.1 Single-App vs Dual-App Architecture

- **Spec:** `specs/architecture.md`, `specs/README.md` -- describes dual-app
- **Current:** Single `Playback.app` containing all functionality
- **Decision needed:** Refactoring to dual-app requires new Xcode target, splitting code. Single-app works for MVP.

### 4.2 Swift OCRService Wrapper Missing

- **Spec:** `specs/search-ocr.md` -- `OCRService.swift` using Vision framework
- **Current:** Only Python `ocr_processor.py` exists
- **Decision needed:** For MVP, Python OCR is sufficient.

---

## Storage Path Reference (VERIFIED CORRECT)

**Important:** The production storage paths are already correct in the codebase. No path consolidation changes are needed.

| Resource | Production Path | Status |
|----------|----------------|--------|
| Data dir | `~/Library/Application Support/Playback/data/` | Correct (Paths.swift:20-28, paths.py:78) |
| Config | `~/Library/Application Support/Playback/config.json` | Correct (Paths.swift:54-62, paths.py:134) |
| Logs | `~/Library/Logs/Playback/` | Correct (logging_config.py:84, DiagnosticsController.swift:116) |
| LaunchAgents | `~/Library/LaunchAgents/com.playback.*.plist` | Correct (LaunchAgentManager.swift:20) |
| Database | `~/Library/Application Support/Playback/data/meta.sqlite3` | Correct (Paths.swift:32-34) |
| Dev data | `dev_data/` | Correct (Paths.swift:11-18) |
| Dev config | `dev_config.json` | Correct (Paths.swift:48-53) |
| Dev logs | `dev_logs/` | Correct (logging_config.py:82) |

**Custom storage location picker:** Confirmed NOT present in the UI (correct per requirements). StorageSetupView.swift shows only the default path.

---

## Phases 5-6: Remaining (Requires macOS Environment)

### Phase 5.6: Manual Testing -- Requires macOS
- Test on clean macOS Tahoe 26.0 installation
- Test permission prompts (Screen Recording, Accessibility)
- Test display configurations, screen lock, screensaver
- Test app exclusion, low disk space, corrupted database recovery
- Test uninstallation with data preservation/deletion

### Phase 6: Distribution and Deployment -- Requires macOS/Xcode
- 6.1 Build System: build scripts, code signing, CI/CD
- 6.2 Notarization: xcrun notarytool workflow
- 6.3 Arc-Style Distribution: .zip packaging, checksums, release notes
- 6.4 Installation and Updates: first-run wizard improvements, update checker
- 6.5 Documentation: user guide, developer guide, FAQ

---

## Quick Reference: File Locations

| Component | Files |
|-----------|-------|
| Menu Bar | `MenuBar/MenuBarView.swift`, `MenuBar/MenuBarViewModel.swift` |
| Timeline | `ContentView.swift`, `TimelineView.swift`, `TimelineStore.swift`, `PlaybackController.swift` |
| Date Picker | `Timeline/DateTimePickerView.swift` |
| Search | `Search/SearchController.swift`, `Search/SearchBar.swift`, `Search/SearchResultsList.swift`, `Search/SearchResultRow.swift` |
| Settings | `Settings/SettingsView.swift` (single 1537-line file with all 6 tabs) |
| Config | `Config/Config.swift`, `Config/ConfigManager.swift` |
| Services | `Services/LaunchAgentManager.swift`, `Services/GlobalHotkeyManager.swift`, `Services/NotificationManager.swift`, `Services/ProcessMonitor.swift` |
| FirstRun | `FirstRun/WelcomeView.swift`, `FirstRun/PermissionsView.swift`, `FirstRun/StorageSetupView.swift`, `FirstRun/DependencyCheckView.swift`, `FirstRun/InitialConfigView.swift`, `FirstRun/FirstRunCoordinator.swift`, `FirstRun/FirstRunWindowView.swift` |
| Diagnostics | `Diagnostics/DiagnosticsView.swift`, `Diagnostics/DiagnosticsController.swift`, `Diagnostics/LogEntry.swift` |
| Utilities | `Paths.swift`, `VideoBackgroundView.swift` |
| State Views | `Timeline/EmptyStateView.swift`, `Timeline/ErrorStateView.swift`, `Timeline/LoadingStateView.swift`, `Timeline/LoadingScreenView.swift` |
| App Entry | `PlaybackApp.swift` |

All Swift source files are under `src/Playback/Playback/`.
All Python source files are under `src/lib/` (libraries) and `src/scripts/` (services).
All tests are under `src/Playback/PlaybackTests/` (Swift) and `src/lib/test_*.py` (Python).

---

## Test Coverage Summary

| Category | Count | Status |
|----------|-------|--------|
| Python unit tests | 280 | All passing |
| Swift unit tests | 203 | All passing |
| Swift integration tests | 72 | All passing |
| Swift UI tests | 115 | Build-verified (requires GUI) |
| Swift performance tests | 21 | Build-verified |
| **Total** | **691** | **555 running, 136 build-verified** |
