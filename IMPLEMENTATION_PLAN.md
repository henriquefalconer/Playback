<!--
 Copyright (c) 2026 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Playback - Implementation Plan

Canonical specs live in `specs/`. This plan tracks only actionable work going forward.

---

## Phase 1: Remove Bloat (Delete Code)

Remove all non-key features. This is the highest priority — it unblocks everything else.

### 1.1 Delete Entire Directories and Files

These files/directories are deleted wholesale. No code is salvaged.

- [ ] Delete `src/lib/` (Python shared library — 9 modules + 8 test files)
- [ ] Delete `src/scripts/` (Python pipeline scripts — 5 scripts + 2 test files)
- [ ] Delete `Search/` directory (SearchController, SearchBar, SearchResultsList, SearchResultRow)
- [ ] Delete `Diagnostics/` directory (DiagnosticsController, DiagnosticsView, LogEntry)
- [ ] Delete `FirstRun/` directory (FirstRunCoordinator, WelcomeView, StorageSetupView, DependencyCheckView, InitialConfigView, PermissionsView, FirstRunWindowView)
- [ ] Delete `Services/NotificationManager.swift`
- [ ] Delete `Services/LaunchAgentManager.swift`
- [ ] Delete `Services/ProcessMonitor.swift`
- [ ] Delete `Resources/launchagents/` (recording.plist.template, processing.plist.template, cleanup.plist.template)
- [ ] Delete `Timeline/LoadingScreenView.swift` (dead code — never instantiated anywhere)
- [ ] Delete `Utilities/ShellCommand.swift` (all callers are in removed files after this phase)

### 1.2 Clean Up PlaybackApp.swift

Remove references to deleted components:

- [ ] Remove `Window("Welcome to Playback", id: "firstrun")` scene (line 79-84)
- [ ] Remove `Window("Diagnostics", id: "diagnostics")` scene (line 86-90)
- [ ] Remove `@StateObject processMonitor = ProcessMonitor.shared` (line 14) and its `.environmentObject(processMonitor)` (line 30)
- [ ] Remove `processMonitor.startMonitoring()` / `.stopMonitoring()` from onAppear/onDisappear (lines 53, 65)
- [ ] Remove `firstRunWindow` property, `"FirstRunComplete"` observer, `handleFirstRunComplete()`, `showFirstRunWindow()` from AppDelegate (lines 95-194)
- [ ] Remove `FirstRunCoordinator.hasCompletedFirstRun` check from `applicationDidFinishLaunching` — make it unconditional
- [ ] Simplify `ensureServicesRunning()`: remove all LaunchAgentManager calls (lines 142-156), keep only RecordingService start/stop based on config
- [ ] Replace first-run gate with inline: `Paths.ensureDirectoriesExist()` + request Screen Recording permission if not granted

### 1.3 Clean Up ContentView.swift

- [ ] Remove `@State private var showSearch` and `@StateObject private var searchController` (lines 12-13)
- [ ] Remove SearchController instantiation from init (lines 30-33)
- [ ] Remove `searchResults:` parameter passed to TimelineView (line 163)
- [ ] Remove search overlay UI block (lines 194-209)
- [ ] Remove Command+F keyboard handler (lines 251-257)
- [ ] Remove `showSearch` branch from ESC handler (lines 260-263)
- [ ] Remove `"JumpToTimestamp"` notification observer (lines 228-238)
- [ ] Remove `@EnvironmentObject var processMonitor: ProcessMonitor` (line 8)

### 1.4 Clean Up TimelineView.swift

- [ ] Remove `searchResults` parameter (line 76)
- [ ] Remove search marker rendering block (lines 262-279)

### 1.5 Clean Up MenuBarView.swift

- [ ] Remove `DEBUG: Toggle Recording` button (lines 24-31)
- [ ] Remove diagnostics button with error badge (lines 73-98)
- [ ] Remove debug print statement (line 11)

### 1.6 Clean Up MenuBarViewModel.swift

- [ ] Remove `launchAgentManager` property, init parameter, and assignment (lines 53, 60, 64)
- [ ] Remove `launchAgentManager.stopAgent(.processing)` from `performQuit()` (line 154)
- [ ] Remove `showDiagnostics` and `errorCount` published properties (lines 49-50) — dead state after diagnostics removal

### 1.7 Rewrite SettingsView.swift (~85% deletion)

Current file: 2409 lines, 6 tabs. Target: single panel, ~250 lines.

**Delete entirely:**
- [ ] RecordingSettingsTab (lines 289-361)
- [ ] ProcessingSettingsTab (lines 363-687)
- [ ] StorageSettingsTab (lines 689-1022)
- [ ] AdvancedSettingsTab (lines 1336-2403)

**Delete from GeneralSettingsTab:**
- [ ] Notifications section — 4 toggles (lines 159-170)
- [ ] Dead `parseShortcut()` function (lines 223-258)

**Delete from PrivacySettingsTab:**
- [ ] `exclusionMode` Picker (lines 1123-1128)
- [ ] Data Management section + Export All Data (lines 1161-1187)
- [ ] `exportAllData()`, `performExport()`, `findProjectRoot()`, `runShellCommand()`, `formatExportDate()` (lines 1249-1310)
- [ ] Export alert modifier (lines 1199-1203)

**Keep and merge into single panel:**
- [ ] Launch at login toggle + error display (from GeneralSettingsTab lines 73-91)
- [ ] Permissions status section (from GeneralSettingsTab lines 93-143)
- [ ] HotkeyRecorderView section (from GeneralSettingsTab lines 145-157)
- [ ] Excluded apps list with recommended exclusions (from PrivacySettingsTab lines 1033-1042, 1094-1158, 1312-1333)
- [ ] `binding<T>()` helper, permission check functions, openSettings functions

**Also remove imports:** `Combine` and `UniformTypeIdentifiers` (only used by deleted tabs)

### 1.8 Strip Config.swift

Remove bloat fields, keep only 5:

- [ ] Remove: `processingIntervalMinutes`, `tempRetentionPolicy`, `recordingRetentionPolicy`, `exclusionMode`, `ffmpegCrf`, `videoFps`, `pauseWhenTimelineOpen` (lines 8-16)
- [ ] Remove: `Notifications` nested struct entirely (lines 19-33)
- [ ] Remove corresponding entries from `defaultConfig` (lines 38-54)
- [ ] Remove validation logic for removed fields in `validated()` (lines 61-88)
- [ ] Remove CodingKeys for removed fields (lines 99-110)

### 1.9 Strip ConfigManager.swift

- [ ] Remove `ConfigWatcher` class entirely (lines 205-247)
- [ ] Remove `watcher` property, `lastModificationDate`, `startWatching()`, `deinit` (lines 12-13, 21, 28-35, 189-202)
- [ ] Remove backup methods: `createBackup()`, `cleanupOldBackups()` (lines 64, 101-133)
- [ ] Remove migration logic: `migrateConfig()` and template (lines 44-46, 135-187)

### 1.10 Remove Python References from Build/CI

- [ ] Remove Python linting (`flake8`) from pre-commit hooks
- [ ] Remove Python test execution (`pytest`) from pre-commit hooks
- [ ] Remove Python dependency installation from setup scripts
- [ ] Remove `src/scripts/` copy phase from Xcode build if present

---

## Phase 2: Build Swift ProcessingService

**This service does not exist in any form.** No `ProcessingService.swift`, no `AVAssetWriter` usage, no Swift-side video creation anywhere in the codebase. Must be built from scratch.

- [ ] Create `Services/ProcessingService.swift` as `@MainActor final class` singleton
- [ ] Implement frame loading: scan `temp/YYYYMM/DD/` directories, sort PNGs by filename timestamp
- [ ] Implement filename parsing: extract timestamp and app bundle ID from `YYYYMMDD-HHMMSS-<uuid>-<appid>` format
- [ ] Implement frame grouping: split on resolution changes, enforce max frames per segment
- [ ] Implement video creation using `AVAssetWriter` + `AVAssetWriterInput` (H.264, hardware-accelerated via VideoToolbox)
- [ ] Implement app segment aggregation: group consecutive frames by bundle ID into appsegment records
- [ ] Implement SQLite writes: INSERT segments and appsegments using sqlite3 C API (same pattern as TimelineStore reads)
- [ ] Implement database initialization: CREATE TABLE IF NOT EXISTS for segments, appsegments, schema_version + PRAGMA journal_mode=WAL + PRAGMA secure_delete=ON
- [ ] Implement temp file cleanup: delete processed PNGs after successful video creation
- [ ] Implement segment ID generation: 20 hex chars from random bytes
- [ ] Set up 5-minute Timer (hardcoded, not configurable)
- [ ] Integrate into PlaybackApp lifecycle: start in `ensureServicesRunning()`, stop on quit
- [ ] Handle errors gracefully: log, skip frame/segment, continue (never crash)

---

## Phase 3: Fix Bugs Found During Audit

Bugs discovered in code that is being kept (not removed).

### High Priority

- [ ] **PlaybackController: frozen frame hidden on failure** — `showFrozenFrame = false` in `.failed` branches (lines 420-421 and 516) should remain `true` to keep the fallback visible. Currently shows blank/black screen on segment load failure.

### Medium Priority

- [ ] **RecordingService: ungated print() statements** — Lines 40-74 and 79-88 have print() calls not wrapped in `if Paths.isDevelopment { }`, violating CLAUDE.md guidelines. Gate all with isDevelopment check.
- [ ] **ErrorStateView: no retry button for consecutive failures** — `.multipleConsecutiveFailures` case renders `EmptyView()` (no action button). Spec expects a retry button.
- [ ] **DateTimePickerView: time list empty on first open** — `loadAvailableTimesForSelectedDate()` is not called on `.onAppear`, so if today has recordings, the time list shows "No recordings" until user explicitly taps today's date cell.

### Low Priority

- [ ] **RecordingService: captureCount resets on every start()** — `captureCount = 0` in `start()` resets the counter on service restart. Minor, but `UInt64` type suggests lifetime intent.
- [ ] **RecordingService: lastLoggedError never cleared** — `lastLoggedError` is never reset in `stop()` or `reload()`, causing duplicate suppression to persist across restarts.
- [ ] **PlaybackController: duplicate code in seek() and update()** — Status observer and failure tracking logic is copy-pasted between the two methods. Maintainability concern.

---

## Phase 4: Clean Up Tests

### Delete Test Files (10 files)

- [ ] `PlaybackTests/ConfigurationIntegrationTests.swift` — tests Config watcher, cleanup, notifications, OCR schema
- [ ] `PlaybackTests/FullPipelineIntegrationTests.swift` — tests processing pipeline, cleanup/retention
- [ ] `PlaybackTests/IntegrationTestBase.swift` — support class for removed integration tests
- [ ] `PlaybackTests/LaunchAgentIntegrationTests.swift` — tests LaunchAgent + FirstRun
- [ ] `PlaybackTests/LaunchAgentManagerTests.swift` — tests LaunchAgent management
- [ ] `PlaybackTests/NotificationManagerTests.swift` — tests Notification feature
- [ ] `PlaybackTests/PerformanceTests.swift` — primarily tests Search/OCR performance
- [ ] `PlaybackTests/SearchControllerTests.swift` — tests Search
- [ ] `PlaybackTests/SearchIntegrationTests.swift` — tests Search/OCR
- [ ] `PlaybackUITests/FirstRunUITests.swift` — tests FirstRun wizard
- [ ] `PlaybackUITests/SearchUITests.swift` — tests Search UI
- [ ] `PlaybackUITests/SettingsUITests.swift` — tests removed settings tabs

### Edit Test Files (3 files)

- [ ] `PlaybackTests/MenuBarViewModelTests.swift` — remove `testShowDiagnosticsPublishedProperty` and `testOpenDiagnosticsMethodExists` stubs
- [ ] `PlaybackUITests/MenuBarUITests.swift` — remove `testDiagnosticsButtonExists`, `testDiagnosticsButtonClick`, diagnostics references in `testMenuBarNavigationFlow`
- [ ] `PlaybackUITests/TimelineUITests.swift` — remove `testCommandFOpensSearch` method

### Keep Test Files (10 files — no changes needed)

- `ConfigManagerTests.swift`, `GlobalHotkeyManagerTests.swift`, `PathsTests.swift`, `PlaybackControllerTests.swift`, `PlaybackTests.swift`, `TimelineStoreTests.swift`, `DateTimePickerUITests.swift`, `MenuBarUITests.swift` (after edit), `PlaybackUITests.swift`, `TimelineUITests.swift` (after edit)

---

## Phase 5: Polish

- [ ] App icon assets (requires graphic design)
- [ ] Momentum scrolling with logarithmic deceleration
- [ ] Drag-drop app exclusion from /Applications
- [ ] Remove quit confirmation dialog (quit immediately)

---

## Already Working (Verified by Audit)

These components match their specs and need no changes beyond Phase 1 cleanup:

- **RecordingService** — ScreenCaptureKit, 2s timer, signal file pause (already hardcoded), excluded apps. Clean.
- **PlaybackController** — AVPlayer, preloading at 80%, frozen frames, scrubbing with sticky edges, consecutive failure tracking. Clean.
- **TimelineStore** — SQLite reads for segments + appsegments, gap handling, 5s auto-refresh. No OCR references. Clean.
- **TimelineView** — segment bars, playhead, ticks, app colors. Clean after search marker removal.
- **Paths.swift** — dev/prod switching, env var overrides, signal file manager. Clean.
- **GlobalHotkeyManager** — Carbon Events, Option+Shift+Space. Clean.
- **LaunchAtLoginManager** — SMAppService wrapper. Clean.
- **DateTimePickerView** — calendar + time list, correct DB queries. Clean (minor bug in Phase 3).
- **ErrorStateView / EmptyStateView / LoadingStateView** — UI states. Clean (minor bug in Phase 3).
- **VideoBackgroundView** — AVPlayerLayer rendering. Clean.
- **HotkeyRecorderView** — keyboard shortcut recorder. Clean.

---

## Pre-Commit Validation

```bash
./smoke-test.sh
```

- **Exit 0** — safe to commit
- **Exit 1** — fix before committing (or document in Active Runtime Issues below)
- **Exit 2** — skipped (not on macOS)

### Active Runtime Issues Log

(none)

---

## File Reference (Post-Refactor Target)

| Component | Files |
|-----------|-------|
| App Entry | `PlaybackApp.swift` |
| Menu Bar | `MenuBar/MenuBarView.swift`, `MenuBar/MenuBarViewModel.swift` |
| Timeline | `ContentView.swift`, `TimelineView.swift`, `TimelineStore.swift`, `PlaybackController.swift` |
| Video | `VideoBackgroundView.swift` |
| Date Picker | `Timeline/DateTimePickerView.swift` |
| Settings | `Settings/SettingsView.swift`, `Settings/HotkeyRecorderView.swift` |
| Config | `Config/Config.swift`, `Config/ConfigManager.swift` |
| Services | `Services/RecordingService.swift`, `Services/ProcessingService.swift` (new), `Services/GlobalHotkeyManager.swift`, `Services/LaunchAtLoginManager.swift` |
| State Views | `Timeline/EmptyStateView.swift`, `Timeline/ErrorStateView.swift`, `Timeline/LoadingStateView.swift` |
| Paths | `Paths.swift` |

All Swift source under `src/Playback/Playback/`. Tests under `src/Playback/PlaybackTests/` and `src/Playback/PlaybackUITests/`.
