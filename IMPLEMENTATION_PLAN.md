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
- **Ultimate Goals:** Fix SIGABRT crashes, consolidate storage paths, clean up remaining issues

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

---

## Priority 1 -- Critical Bugs (Crashes and Deadlocks)

These bugs cause SIGABRT crashes and potential deadlocks. They must be fixed first.

### 1.1 SIGABRT Crash: ConfigWatcher Double-Close File Descriptor

- [ ] **Fix ConfigWatcher deinit double-close**
- **Source:** `src/Playback/Playback/Config/ConfigManager.swift` lines 163-209
- **Root Cause:** ConfigWatcher closes the file descriptor in TWO places:
  - Line 193-196: `setCancelHandler` closure calls `close(fd)` when the dispatch source is cancelled
  - Lines 202-207: `deinit` calls `close(fileDescriptor)` on line 204 AND THEN calls `source?.cancel()` on line 207
- **Crash sequence:**
  1. ConfigWatcher is deallocated, `deinit` runs
  2. Line 204: `close(fileDescriptor)` closes the fd, sets `fileDescriptor = -1`
  3. Line 207: `source?.cancel()` fires the cancel handler
  4. Cancel handler (line 194) reads `self?.fileDescriptor` -- but `self` may already be partially torn down, or the fd value was cached before the `-1` assignment
  5. If the cancel handler gets the original fd value (not -1), it calls `close()` on an already-closed fd
  6. Double-close on a file descriptor -> **SIGABRT**
- **Additional risk:** Between step 2 and the cancel handler executing, the OS may have reused the file descriptor number for another resource. Closing a reused fd corrupts unrelated state.
- **Fix approach:** Remove `close(fileDescriptor)` from `deinit` entirely. Let the cancel handler be the sole owner of closing the fd. The `deinit` should only call `source?.cancel()`, which triggers the cancel handler to close the fd safely.
- **Alternative fix:** Set `fileDescriptor = -1` atomically before closing, and check in the cancel handler:
  ```swift
  deinit {
      source?.cancel()
      // cancel handler will close the fd
  }
  ```

### 1.2 Pipe Deadlock: waitUntilExit() Before readDataToEndOfFile()

- [ ] **Fix pipe deadlock in LaunchAgentManager.swift:296-318**
- [ ] **Fix same pattern in ProcessMonitor.swift:70-91**
- [ ] **Fix same pattern in DependencyCheckView.swift:162-188**
- [ ] **Fix same pattern in SettingsView.swift (5 instances: lines 494-517, 834-857, 1065-1092, 1155-1178, 1502-1525)**
- **Source:** 8 locations total across 4 files
- **Root Cause:** All locations call `process.waitUntilExit()` BEFORE `pipe.fileHandleForReading.readDataToEndOfFile()`. If the child process writes more than ~64KB to stdout/stderr, the pipe buffer fills, the process blocks waiting for the reader to consume data, and `waitUntilExit()` blocks waiting for the process to exit. Classic deadlock.
- **Affected files and lines:**
  - `LaunchAgentManager.swift:307` -- `process.waitUntilExit()` then line 309 `readDataToEndOfFile()`
  - `ProcessMonitor.swift:81` -- `process.waitUntilExit()` then line 83 `readDataToEndOfFile()`
  - `DependencyCheckView.swift:173-176` -- `process.run(); process.waitUntilExit(); readDataToEndOfFile()`
  - `SettingsView.swift:505-508` -- ProcessingSettingsTab.runShellCommand()
  - `SettingsView.swift:845-848` -- StorageSettingsTab.runShellCommand()
  - `SettingsView.swift:1083-1086` -- PrivacySettingsTab.checkScreenRecordingPermission() (Python subprocess)
  - `SettingsView.swift:1166-1169` -- PrivacySettingsTab.runShellCommand()
  - `SettingsView.swift:1513-1516` -- AdvancedSettingsTab.runShellCommand()
- **Fix approach:** Read pipe data BEFORE calling `waitUntilExit()`:
  ```swift
  try process.run()
  let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
  let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  ```
- **Better fix:** Extract a shared `ShellCommand` utility to eliminate all 8 duplicated implementations (see item 1.4).

### 1.3 Force Unwrap Crash: Paths.swift .first!

- [ ] **Fix force unwrap in Paths.swift:24 and Paths.swift:58**
- **Source:** `src/Playback/Playback/Paths.swift` lines 24 and 58
- **Root Cause:** Both production path branches use `.first!` on `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`. If this returns an empty array (theoretically possible on sandboxed or restricted environments), the app crashes instantly.
- **Fix approach:** Use `guard let` with a fallback:
  ```swift
  guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
  ).first else {
      fatalError("Application Support directory not available")
      // Or return a fallback path
  }
  ```
- **Also fix in SettingsView.swift:** Lines 829 and 1150 have the same `.first!` pattern in `findProjectRoot()` methods within `StorageSettingsTab` and `PrivacySettingsTab`.

### 1.4 Code Quality: 8 Duplicated Shell Command Implementations

- [ ] **Extract shared ShellCommand utility**
- **Source:** 7 separate `runShellCommand()`/`runCommand()` implementations (8 call sites):
  - `LaunchAgentManager.swift:296-318` -- synchronous, returns (String, Int32)
  - `ProcessMonitor.swift:70-91` -- synchronous nonisolated, returns Bool
  - `DependencyCheckView.swift:162-188` -- async on global queue, completion handler
  - `SettingsView.swift:494-517` -- async/await, ProcessingSettingsTab
  - `SettingsView.swift:834-857` -- async/await, StorageSettingsTab
  - `SettingsView.swift:1065-1092` -- async/await, PrivacySettingsTab.checkScreenRecordingPermission()
  - `SettingsView.swift:1155-1178` -- async/await, PrivacySettingsTab.runShellCommand()
  - `SettingsView.swift:1502-1525` -- async/await, AdvancedSettingsTab
- **Problem:** Every implementation has the same pipe deadlock bug (1.2). Fixing in 8 places is error-prone. A shared utility fixes the bug once and prevents future drift.
- **Fix approach:** Create `Utilities/ShellCommand.swift` with a single async function that reads pipe data before waiting. All 8 call sites should migrate to this shared utility.

### 1.5 Force-Unwrapped URLs in SettingsView.swift

- [ ] **Fix force-unwrapped URL(string:)! calls**
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift` lines 1100 and 1104
- **Root Cause:** `URL(string: "x-apple.systempreferences:...")!` -- if the URL string is somehow invalid, this crashes. While unlikely for hardcoded strings, force unwraps are a code smell.
- **Fix approach:** Use `guard let url = URL(string: ...) else { return }` pattern.
- **Also:** `DependencyCheckView.swift` line 279 has `URL(string: "https://brew.sh")!` -- same issue.

---

## Priority 2 -- Storage Path Consolidation

Consolidate all production paths from `~/Library/Application Support/Playback/` to `~/Library/Application Support/com.falconer.Playback/`. Development paths (`dev_data/`, `dev_config.json`, `dev_logs/`) remain unchanged.

### Target Path Layout

| Resource | Current (WRONG) | Target (CORRECT) |
|----------|-----------------|-------------------|
| Data dir | `~/Library/Application Support/Playback/data/` | `~/Library/Application Support/com.falconer.Playback/data/` |
| Config | `~/Library/Application Support/Playback/config.json` | `~/Library/Application Support/com.falconer.Playback/config.json` |
| Logs | `~/Library/Logs/Playback/` | `~/Library/Logs/com.falconer.Playback/` |
| LaunchAgents | `~/Library/LaunchAgents/com.playback.*.plist` | `~/Library/LaunchAgents/com.falconer.Playback.*.plist` |
| Database | `~/Library/Application Support/Playback/data/meta.sqlite3` | `~/Library/Application Support/com.falconer.Playback/data/meta.sqlite3` |

### 2.1 Update Paths.swift (Primary Swift Path Resolution)

- [ ] **Update production paths in Paths.swift**
- **Source:** `src/Playback/Playback/Paths.swift`
- **Changes needed:**
  - Line 20-28: `baseDataDirectory` -- change from `~/Library/Application Support/Playback/data/` to `~/Library/Application Support/com.falconer.Playback/data/`
  - Line 54-62: `configPath()` -- change from `~/Library/Application Support/Playback/config.json` to `~/Library/Application Support/com.falconer.Playback/config.json`
- **Note:** Development paths (lines 11-18, 48-53) remain unchanged (`dev_data/`, `dev_config.json`)
- **No permissions issue:** `~/Library/Application Support/` is user-writable by default, no admin privileges needed.

### 2.2 Update paths.py (Primary Python Path Resolution)

- [ ] **Update production paths in paths.py**
- **Source:** `src/lib/paths.py`
- **Changes needed:**
  - Line 77-78: `get_base_data_directory()` -- change from `home / "Library" / "Application Support" / "Playback" / "data"` to `home / "Library" / "Application Support" / "com.falconer.Playback" / "data"`
  - Line 133-134: `get_config_path()` -- change from `home / "Library" / "Application Support" / "Playback" / "config.json"` to `home / "Library" / "Application Support" / "com.falconer.Playback" / "config.json"`
  - Line 150-151: `get_logs_directory()` -- change from `home / "Library" / "Logs" / "Playback"` to `home / "Library" / "Logs" / "com.falconer.Playback"`
- **Note:** Development paths remain unchanged. Update all docstrings to reflect new production paths.

### 2.3 Update LaunchAgentManager.swift (Template Variables)

- [ ] **Update buildVariables() production paths**
- **Source:** `src/Playback/Playback/Services/LaunchAgentManager.swift` lines 227-275
- **Changes needed:**
  - Line 249-250: `workingDir` -- change from `~/Library/Application Support/Playback` to `~/Library/Application Support/com.falconer.Playback`
  - Line 251-252: `logPath` -- change from `~/Library/Logs/Playback` to `~/Library/Logs/com.falconer.Playback`
  - Line 253-254: `configPath` -- change from `~/Library/Application Support/Playback/config.json` to `~/Library/Application Support/com.falconer.Playback/config.json`
  - Line 255-256: `dataDir` -- change from `~/Library/Application Support/Playback/data` to `~/Library/Application Support/com.falconer.Playback/data`
- **Also update AgentType.label:** Lines 18-21 -- change from `com.playback` prefix to `com.falconer.Playback` prefix for production labels.

### 2.4 Update DiagnosticsController.swift (Hardcoded Log Path)

- [ ] **Update hardcoded log directory path**
- **Source:** `src/Playback/Playback/Diagnostics/DiagnosticsController.swift`
- **Changes needed:**
  - Line 116: Change `"\(NSHomeDirectory())/Library/Logs/Playback"` to `"\(NSHomeDirectory())/Library/Logs/com.falconer.Playback"` (or better: use a `Paths.logsDirectory` helper)
  - Line 212: Same change in `clearLogs()` method
- **Note:** Both locations duplicate the same hardcoded path. Consider adding a `Paths.logsDirectory` computed property to centralize this.

### 2.5 Update SettingsView.swift (Hardcoded Paths)

- [ ] **Update hardcoded paths in SettingsView.swift**
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift`
- **Changes needed:**
  - Line 327: ProcessingSettingsTab `logPath` -- change from `~/Library/Logs/Playback/processing.log` to `~/Library/Logs/com.falconer.Playback/processing.log`
  - Line 829: StorageSettingsTab `findProjectRoot()` -- uses `.first!` and appends `Playback`, should use Paths helper
  - Line 1150: PrivacySettingsTab `findProjectRoot()` -- same issue
  - Line 1470: AdvancedSettingsTab `exportLogsToFile()` -- change from `~/Library/Logs/Playback` to `~/Library/Logs/com.falconer.Playback`
- **Recommendation:** All these should call `Paths` methods instead of duplicating path logic.

### 2.6 Update logging_config.py (Log Directory Path)

- [ ] **Update production log directory in logging_config.py**
- **Source:** `src/lib/logging_config.py` line 84
- **Change:** `Path.home() / "Library" / "Logs" / "Playback"` to `Path.home() / "Library" / "Logs" / "com.falconer.Playback"`
- **Better approach:** Use `paths.get_logs_directory()` instead of duplicating the logic.

### 2.7 Update StorageSetupView.swift

- [ ] **Verify StorageSetupView uses Paths helper**
- **Source:** `src/Playback/Playback/FirstRun/StorageSetupView.swift` line 12
- **Current:** Uses `Paths.baseDataDirectory` (correct -- will automatically update when Paths.swift is changed)
- **Status:** No direct changes needed if Paths.swift is updated (item 2.1). Just verify it displays correctly.

### 2.8 Add Data Migration for Existing Installations

- [ ] **Create migration logic for existing data**
- **Source:** New logic needed in app startup
- **Problem:** Existing users have data at `~/Library/Application Support/Playback/data/`. After path changes, the app will look at a new location and find no data.
- **Implementation:**
  - On first launch after update, check if old path exists and new path does not
  - If so, move (or copy) data from old location to new location
  - Preserve database, config, chunks, temp files
  - Log the migration for diagnostics
  - Delete old directory after successful migration (or leave a symlink)
- **Critical:** Without migration, users lose all their recording history on update.

### 2.9 Update Python Tests for New Paths

- [ ] **Update test assertions referencing old paths**
- **Source:** `src/lib/test_paths.py` and other test files
- **Changes:** Update all assertions that check for `~/Library/Application Support/Playback/` to reference the new path structure.

### 2.10 Update Spec Files and Documentation

- [ ] **Update all spec files with new paths**
- **Source:** `specs/` directory, `CLAUDE.md`, `README.md` (if exists)
- **Files to update:** Any spec that documents production paths (architecture.md, configuration.md, installation-deployment.md, logging-diagnostics.md, etc.)
- **Note:** Do NOT create new documentation files -- only update existing ones.

### 2.11 Custom Storage Location Picker -- WON'T FIX

- **Spec:** `specs/installation-deployment.md` mentions "Allow custom location selection (NSOpenPanel)"
- **Decision:** Per project requirements, NO custom storage location picker should exist. The current `StorageSetupView.swift` correctly shows only the default path with no picker. This is the intended behavior.
- **Status:** No changes needed. Mark as intentional deviation from spec.

---

## Priority 3 -- Important Missing Features

These features are specified but not implemented. They impact UX but are not blocking core functionality.

### 3.1 Settings: General Tab Missing Key Controls

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
- **Implementation complexity:** SMAppService requires macOS 13+ API knowledge. Hotkey recorder requires Carbon API event monitoring. Permission status is partially addressed in Privacy tab but not in General tab per spec.

### 3.2 Search: App Icon in Result Rows

- [ ] **Add app icon and app name to search results**
- **Spec:** `specs/search-ocr.md` lines 101-103 -- "App icon (20x20), app name, timestamp, snippet"
- **Source:** `src/Playback/Playback/Search/SearchResultRow.swift`
- **Missing:** No app icon or app name shown; only timestamp + confidence + snippet displayed
- **Implementation:** Use `NSWorkspace.shared.icon(forFile:)` to fetch app icons at runtime from bundle IDs stored in OCR metadata. Need image caching and placeholder icon for missing apps.

### 3.3 Permission Checking Uses Python Subprocess Instead of Native API

- [ ] **Replace Python subprocess with CGPreflightScreenCaptureAccess()**
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:1065-1092`
- **Current:** The `checkScreenRecordingPermission()` function spawns a Python subprocess that imports `Quartz` and calls `CGWindowListCopyWindowInfo`. This is slow and fragile.
- **Fix:** Replace with Swift's native `CGPreflightScreenCaptureAccess()` from the ApplicationServices framework -- a single synchronous function call that returns Bool immediately.

### 3.4 App Icon Missing

- [ ] **Create app icon assets** (requires graphic design work)
- **Spec:** `specs/timeline-graphical-interface.md` lines 32-36
- **Source:** `Assets.xcassets/AppIcon.appiconset/Contents.json` -- all 10 size slots defined but zero image files present
- **Impact:** App has no icon in Dock, About panel, Finder, or menu bar
- **Design requirements:**
  - Style: Play button (rounded triangle pointing right) with vibrant blue/purple gradient background
  - Sizes: 10 PNG files (16px, 32px, 64px, 128px, 256px, 512px, 1024px, plus @2x variants)
  - Requires graphic design software (Sketch, Figma, etc.)
- **Blocker:** Cannot be generated programmatically -- requires manual design work

---

## Priority 4 -- UX Polish and Completeness

These items improve the overall experience but are not blocking core functionality.

### 4.1 Timeline: Zoom Anchor Point Missing

- [ ] **Implement cursor-anchored zoom**
- **Spec:** `specs/timeline-graphical-interface.md` lines 179, 388
- **Source:** `ContentView.swift:288-319`
- **Problem:** Pinch zoom changes scale but doesn't maintain the timestamp under the cursor (the timeline drifts during zoom)
- **Fix:** Calculate anchor timestamp at cursor position before zoom, then reposition scroll offset after zoom to keep that timestamp at the same screen position.

### 4.2 Timeline: No Segment Preloading

- [ ] **Preload next segment at 80% playback**
- **Spec:** `specs/timeline-graphical-interface.md` lines 329-332
- **Source:** `PlaybackController.swift`
- **Missing:** When 80% through a segment, the next segment should be preloaded in a background AVPlayer for seamless transition
- **Currently:** Segments loaded reactively, causing 100-500ms pause on each segment transition

### 4.3 Timeline: Fullscreen Configuration Incomplete

- [ ] **Add letterboxing, gesture disabling, presentation options**
- **Spec:** `specs/timeline-graphical-interface.md` lines 69-88
- **Source:** `PlaybackApp.swift`
- **Missing:** Letterboxing for aspect ratio mismatches, three-finger swipe gesture disabling, Mission Control/Dock/Cmd+Tab presentation options

### 4.4 Timeline: No Momentum Scrolling / Deceleration

- [ ] **Add logarithmic decay after scroll gesture ends**
- **Spec:** `specs/timeline-graphical-interface.md` lines 361-364
- **Source:** `ContentView.swift`
- **Missing:** Timeline scrolling stops instantly when finger lifts. Spec calls for logarithmic decay momentum animation using CADisplayLink at 60fps.

### 4.5 Settings: App Exclusion Only Supports Manual Entry

- [ ] **Add drag-drop from /Applications and file picker**
- **Spec:** `specs/menu-bar.md` lines 314-316 -- supports NSOpenPanel, drag-drop, and manual entry
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:966-1001`
- **Currently:** Only manual bundle ID text entry in a TextField. No file picker to browse /Applications or drag-drop support.

### 4.6 Settings: Database Rebuild Is a Stub

- [ ] **Implement actual database rebuild logic with progress feedback**
- **Spec:** `specs/menu-bar.md` lines 393-402
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:1450-1452`
- **Currently:** `rebuildDatabase()` just sets `showRebuildProgress = true`, which shows an alert saying "Database rebuild initiated" with no actual rebuild logic.
- **Implementation:** Scan chunks directory, rebuild segments table from video file metadata, show progress bar during operation.

### 4.7 Settings: Reset All Doesn't Restart App

- [ ] **Add app restart after reset**
- **Spec:** `specs/menu-bar.md` line 390
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:1446-1448`
- **Currently:** `resetAllSettings()` calls `configManager.updateConfig(Config.defaultConfig)` but doesn't restart the app as spec requires.

### 4.8 Settings: Export Logs Is Minimal

- [ ] **Improve log export with system info and structured archive**
- **Spec:** `specs/menu-bar.md` lines 405-418
- **Source:** `src/Playback/Playback/Settings/SettingsView.swift:1454-1474`
- **Currently:** Simple `cd <logdir> && zip -r <dest> .` -- no system info, no specific file selection, no format structure.

### 4.9 Config: Migration Logic Is a Stub

- [ ] **Implement actual config migration between versions**
- **Source:** `src/Playback/Playback/Config/ConfigManager.swift:132-145`
- **Currently:** `migrateConfig()` only matches version "1.0.0" and sets it back to "1.0.0" -- no actual field migration, no version bumping, no handling of added/removed/renamed fields.
- **Impact:** Future config schema changes will silently lose data or fail to load.

### 4.10 Config: Environment Variable Overrides Not Implemented

- [ ] **Support PLAYBACK_CONFIG and PLAYBACK_DATA_DIR env vars**
- **Spec:** `specs/configuration.md` -- PLAYBACK_CONFIG and PLAYBACK_DATA_DIR environment variables
- **Source:** `src/Playback/Playback/Paths.swift` -- only checks `PLAYBACK_DEV_MODE`
- **Missing:** No support for overriding config path or data directory via environment variables.

### 4.11 FirstRun: No Notification Listener for Permission Re-check

- [ ] **Auto-refresh permission status when app becomes active**
- **Source:** `PermissionsView.swift`
- **Problem:** When user returns from System Preferences after granting a permission, the UI doesn't auto-refresh. User must click "Check Status" manually.
- **Fix:** Listen for `NSApplication.didBecomeActiveNotification` and re-check permissions automatically.

### 4.12 Diagnostics: Tab Organization Differs from Spec

- [ ] **Align diagnostics tabs with spec or document deviation**
- **Spec:** `specs/logging-diagnostics.md` -- Overview, Recording Logs, Processing Logs, Resource Usage
- **Source:** `Diagnostics/DiagnosticsView.swift` -- Logs (generic), Health, Performance, Reports
- **Status:** Functionally similar but different organization. Consider aligning with spec or documenting as an intentional improvement.

### 4.13 Portuguese Comments in Timeline Files

- [ ] **Translate Portuguese comments to English**
- **Source:** 3 files with ~70+ Portuguese comments total:
  - `src/Playback/Playback/TimelineView.swift` -- ~30 Portuguese comments
  - `src/Playback/Playback/TimelineStore.swift` -- ~15 Portuguese comments
  - `src/Playback/Playback/PlaybackController.swift` -- ~25 Portuguese comments
- **Impact:** Code readability for English-speaking contributors

### 4.14 Incorrect Bundle ID in MenuBarViewModel.swift

- [ ] **Fix hardcoded bundle ID**
- **Source:** `src/Playback/Playback/MenuBar/MenuBarViewModel.swift` line 130
- **Current:** `"com.playback.timeline"` -- incorrect/stale bundle ID
- **Fix:** Change to `"com.falconer.Playback"` to match the actual bundle identifier

---

## Priority 5 -- Architectural Considerations

These are significant decisions that may or may not be pursued for MVP.

### 5.1 Single-App vs Dual-App Architecture

- **Spec:** `specs/architecture.md`, `specs/README.md` -- describes dual-app: PlaybackMenuBar.app (LaunchAgent) + Playback.app (Timeline Viewer)
- **Current:** Single `Playback.app` containing all functionality (menu bar, timeline, settings, diagnostics)
- **Implications:**
  - Quitting the app stops everything (menu bar disappears, recording loses control interface)
  - Spec says: menu bar agent should survive timeline viewer quit
  - Spec says: timeline viewer can be closed independently
- **Decision needed:** Refactoring to dual-app requires new Xcode target, splitting code into a shared framework, and reworking app lifecycle. Single-app works for MVP but doesn't match the spec's UX model.

### 5.2 Swift OCRService Wrapper Missing

- **Spec:** `specs/search-ocr.md` lines 10-20 -- `OCRService.swift` using Vision framework in Swift
- **Source:** Only Python `ocr_processor.py` exists
- **Impact:** OCR only works during Python processing; no real-time OCR capability from Swift
- **Decision needed:** For MVP, Python OCR is sufficient. Swift OCR would enable future features (live search, real-time indexing).

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
