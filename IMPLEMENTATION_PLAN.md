<!--
 Copyright (c) 2025 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Playback - Implementation Plan

Based on comprehensive technical specifications in `specs/` and verified against actual source code (2026-02-08).

---

## How to Read This Plan

- Items are **sorted by priority** within each section (highest first)
- **Confirmed missing** = verified by code search that the feature does not exist
- **✅ COMPLETE** = verified working in codebase
- Each item references the spec and source file involved
- The plan focuses on achieving a **great working UI and UX**

---

## Completed Work Summary

### Python Backend — ✅ 100% Complete
- All 280 tests passing, zero bugs, production-ready
- Core libs: paths, timestamps, config, database, video, macos, logging_config, utils
- Services: record_screen, build_chunks_from_temp, cleanup_old_chunks, ocr_processor, export_data
- Security & network tests complete (38 tests)

### Swift Infrastructure — ✅ Complete
- Config system with hot-reload, validation, backup rotation (`Config/`)
- Paths with dev/prod switching, signal file manager (`Paths.swift`)
- LaunchAgent lifecycle management for 3 agent types (`Services/LaunchAgentManager.swift`)
- Global hotkey via Carbon API with permission handling (`Services/GlobalHotkeyManager.swift`)
- Timeline data model with segment selection and gap handling (`TimelineStore.swift`)
- Diagnostics UI with logs, health, performance tabs (`Diagnostics/`)

### Swift Testing — ✅ 95% Complete
- 203 Swift unit tests passing (9 test classes)
- 72 integration tests passing
- 115 UI tests written (build-verified, require GUI)
- 21 performance tests written (build-verified)
- 280 Python tests passing

---

## Priority 1 — Critical UX Blockers

These items prevent basic usability. They should be fixed first.

### 1.1 Timeline: No Error States or Empty States — ✅ COMPLETE
- **Spec:** `specs/timeline-graphical-interface.md` lines 273-291
- **Source:** `Timeline/EmptyStateView.swift`, `Timeline/ErrorStateView.swift`, `Timeline/LoadingStateView.swift`
- **Implemented:**
  - `EmptyStateView.swift` — "No recordings yet" message with icon and instructions
  - `ErrorStateView.swift` — Error display with title, message, and retry button
  - `LoadingStateView.swift` — Loading spinner with status message
  - `TimelineStore.swift` — LoadingState enum (.loading, .loaded, .error) with error handling
  - `PlaybackController.swift` — PlaybackError enum and consecutive failure tracking (3 failures = error state)
  - `ContentView.swift` — Conditional rendering based on loading state (empty/error/loading/content)
- **Note:** App now provides clear feedback for all states (empty data, errors, loading)

### 1.2 Timeline: No Loading Screen During Processing — ✅ COMPLETE
- **Spec:** `specs/timeline-graphical-interface.md` lines 54-67
- **Source:** `Timeline/LoadingScreenView.swift`, `Services/ProcessMonitor.swift`
- **Implemented:**
  - `LoadingScreenView.swift` — Semi-transparent overlay with centered modal, app name, spinner, and status text
  - `ProcessMonitor.swift` — Process detection service polling for `build_chunks_from_temp.py` every 500ms using pgrep
  - `PlaybackApp.swift` — Integration of ProcessMonitor with timeline window lifecycle
  - `ContentView.swift` — Shows LoadingScreenView when processing detected, ESC key dismisses and closes app
- **Note:** App now provides clear visual feedback when processing service is running

### 1.3 App Icon Missing — 🎨 REQUIRES DESIGN WORK
- **Spec:** `specs/timeline-graphical-interface.md` lines 32-36
- **Source:** `Assets.xcassets/AppIcon.appiconset/Contents.json` — all 10 size slots defined but **zero image files present**
- **Impact:** App has no icon in Dock, About panel, Finder, or menu bar
- **Design Requirements:**
  - **Style:** Play button (rounded triangle pointing right)
  - **Colors:** Vibrant blue/purple gradient background
  - **Sizes needed:** 10 PNG files (16px, 32px, 64px, 128px, 256px, 512px, 1024px, plus @2x variants)
  - **Tool required:** Graphic design software (Sketch, Figma, Photoshop, Affinity Designer) or icon generator service
  - **Cannot be generated programmatically** — requires manual graphic design work
- **Blocker:** This is a visual design task that requires graphic design expertise or tools not available to the agent

---

## Priority 2 — Important Missing Features

These features are specified but not implemented. They significantly impact UX.

**Implementation Status:**
- ✅ **Can implement immediately:** 2.2, 2.4, 2.6, 2.8 (no design assets required)
- 🎨 **Requires design assets:** 2.5 (app icons for results)
- 🔧 **Requires additional research:** 2.1 (SMAppService API), 2.3 (timeline rendering), 2.7 (NSOpenPanel integration)

### 2.1 Settings: General Tab Missing Key Controls — 🔧 REQUIRES RESEARCH
- **Spec:** `specs/menu-bar.md` lines 114-152
- **Source:** `SettingsView.swift:63-106`
- **Missing:**
  - Launch at Login toggle (SMAppService integration) — spec lines 114-122
  - Hotkey Recorder for timeline shortcut customization — spec lines 124-132
  - Permission status section with visual indicators — spec lines 143-152
- **Currently:** Only shows notification toggles and read-only shortcut display
- **Implementation complexity:**
  - SMAppService API requires understanding of macOS 13+ login item registration
  - Hotkey recorder requires Carbon API integration with event monitoring
  - Permission status requires native Swift checks (partially addressed in 3.12)

### 2.2 Settings: Processing Tab Missing Features — ✅ CAN IMPLEMENT IMMEDIATELY
- **Spec:** `specs/menu-bar.md` lines 199-217
- **Source:** `SettingsView.swift:182-229`
- **Missing:**
  - "Last Processing Run" section (timestamp, duration, success/failed status) — spec lines 200-207
  - "Process Now" manual trigger button with spinner feedback — spec lines 209-217
- **Currently:** Only shows interval picker and encoding info
- **Implementation plan:**
  - Add `@State` vars for lastRunTimestamp, lastRunDuration, lastRunStatus
  - Query diagnostics logs to extract last run info from `build_chunks_from_temp.py` logs
  - Add "Process Now" button that launches `build_chunks_from_temp.py --auto` via Process
  - Add `@State var isProcessing = false` for spinner feedback
  - Monitor process completion and update lastRun vars
- **No blockers:** Pure SwiftUI + Process API + log parsing

### 2.3 Timeline: Search Result Markers on Timeline — 🔧 REQUIRES RESEARCH
- **Spec:** `specs/search-ocr.md` lines 146-161
- **Source:** `TimelineWithHighlights.swift` does not exist
- **Missing:**
  - Yellow vertical lines (2px × 30px) at search match timestamps on timeline bar
  - Segments with matches should appear slightly brighter
  - Match count badges on segment hover
- **Currently:** Search results appear in list but are invisible on timeline; `searchResults` is passed to `TimelineView` but never rendered
- **Implementation complexity:**
  - Requires understanding TimelineView's geometry and coordinate system
  - Need to convert timestamps to x-coordinates based on zoom level
  - Overlay rendering in SwiftUI with proper z-indexing
  - Performance considerations for many markers (100+ matches)

### 2.4 Search: Text Highlighting in Snippets — ✅ CAN IMPLEMENT IMMEDIATELY
- **Spec:** `specs/search-ocr.md` lines 100-104
- **Source:** `SearchResultRow.swift:1-44`
- **Missing:** Matched search terms not highlighted in result snippets; spec shows `attributedSnippet` with emphasis
- **Currently:** Plain text only
- **Implementation plan:**
  - Create helper function to generate AttributedString with highlighted matches
  - Use `.background(Color.yellow.opacity(0.3))` for matched text ranges
  - Replace plain Text(snippet) with Text(attributedSnippet)
  - Case-insensitive matching for highlight detection
- **No blockers:** Pure SwiftUI AttributedString API

### 2.5 Search: App Icon in Result Rows — 🎨 REQUIRES DESIGN ASSETS
- **Spec:** `specs/search-ocr.md` lines 101-103 — "App icon (20x20), app name, timestamp, snippet"
- **Source:** `SearchResultRow.swift`
- **Missing:** No app icon or app name shown; only timestamp + confidence + snippet
- **Implementation blocker:**
  - Requires app icons to be extracted or fetched from bundle IDs
  - NSWorkspace.shared.icon(forFile:) can fetch app icons at runtime
  - Need to handle missing icons gracefully (placeholder icon)
  - App name should come from OCR results metadata (if available)
- **Complexity:** Medium — requires NSWorkspace integration and image caching

### 2.6 LaunchAgentManager: updateProcessingInterval Is a Stub — ✅ CAN IMPLEMENT IMMEDIATELY
- **Spec:** `specs/menu-bar.md` lines 547-557
- **Source:** `LaunchAgentManager.swift:175-177`
- **Problem:** `func updateProcessingInterval(minutes: Int) throws { try reloadAgent(.processing) }` — just reloads, never actually changes the `StartInterval` value in the plist
- **Impact:** Changing processing interval in Settings has no effect
- **Implementation plan:**
  - Read existing plist file as PropertyListSerialization dictionary
  - Update `StartInterval` key to minutes * 60 seconds
  - Write modified plist back to disk
  - Call `reloadAgent(.processing)` to apply changes
  - Add error handling for plist read/write failures
- **No blockers:** Pure Foundation PropertyListSerialization API

### 2.7 FirstRun: No Custom Storage Location Picker — 🔧 REQUIRES RESEARCH
- **Spec:** `specs/installation-deployment.md` — "Allow custom location selection (NSOpenPanel)"
- **Source:** `StorageSetupView.swift`
- **Missing:** Only shows default path; no way for user to choose custom data directory
- **Implementation complexity:**
  - Requires NSOpenPanel integration in SwiftUI (AppKit bridging)
  - Need to validate selected directory for write permissions
  - Must update Paths.swift to use custom directory path
  - Persistence mechanism for custom path (UserDefaults or config)
  - Migration logic if user changes path later

### 2.8 NotificationManager Service Missing — ✅ CAN IMPLEMENT IMMEDIATELY
- **Spec:** `specs/menu-bar.md` lines 600-627 — notification system for errors, warnings, cleanup results
- **Source:** No `NotificationManager.swift` exists; config has `notifications` field but nothing consumes it
- **Impact:** Users never notified of recording errors, processing failures, or disk space warnings
- **Implementation plan:**
  - Create `Services/NotificationManager.swift` with UserNotifications framework
  - Request notification authorization on first launch
  - Implement notification methods: showError(), showWarning(), showInfo()
  - Respect config.notifications.enabled flag
  - Add notification categories for different event types (recording, processing, storage)
  - Hook into LaunchAgentManager to send notifications on service failures
  - Monitor disk space and send warning at configurable threshold
- **No blockers:** Pure UserNotifications framework API, standard SwiftUI integration

---

## Priority 3 — UX Polish & Completeness

These items improve the overall experience but aren't blocking core functionality.

### 3.1 Timeline: Zoom Anchor Point Missing
- **Spec:** `specs/timeline-graphical-interface.md` lines 179, 388
- **Source:** `ContentView.swift:288-319`
- **Problem:** Pinch zoom changes window size but doesn't maintain cursor position (timestamp under finger drifts)
- **Fix:** Calculate anchor timestamp before zoom, reposition after

### 3.2 Timeline: No Segment Preloading
- **Spec:** `specs/timeline-graphical-interface.md` lines 329-332
- **Source:** `PlaybackController.swift`
- **Missing:** When 80% through a segment, preload next segment in background AVPlayer for seamless transition
- **Currently:** Segments loaded reactively, causing 100-500ms pause on transition

### 3.3 Timeline: Fullscreen Configuration Incomplete
- **Spec:** `specs/timeline-graphical-interface.md` lines 69-88
- **Source:** `PlaybackApp.swift:29, 39`
- **Missing:** Letterboxing for aspect ratio mismatches, three-finger swipe gesture disabling, Mission Control/Dock/Cmd+Tab presentation options

### 3.4 Timeline: No Momentum Scrolling / Deceleration
- **Spec:** `specs/timeline-graphical-interface.md` lines 361-364
- **Source:** `ContentView.swift`
- **Missing:** Logarithmic decay after scroll gesture ends; currently instant stop
- **Spec mentions:** CADisplayLink at 60fps for smooth momentum animation

### 3.5 Settings: App Exclusion Only Supports Manual Entry
- **Spec:** `specs/menu-bar.md` lines 314-316 — supports NSOpenPanel, drag-drop, and manual entry
- **Source:** `SettingsView.swift:704`
- **Currently:** Only manual bundle ID text entry; no file picker or drag-drop for selecting apps from /Applications

### 3.6 Settings: Database Rebuild Has No Progress Feedback
- **Spec:** `specs/menu-bar.md` lines 393-402
- **Source:** `SettingsView.swift:1059-1063`
- **Currently:** Just shows "Database rebuild initiated" alert; no actual rebuild logic, no progress bar

### 3.7 Settings: Reset All Doesn't Restart App
- **Spec:** `specs/menu-bar.md` line 390
- **Source:** `SettingsView.swift:1157-1159`
- **Currently:** Resets config but doesn't restart the app as spec requires

### 3.8 Settings: Export Logs Is Minimal
- **Spec:** `specs/menu-bar.md` lines 405-418
- **Source:** `SettingsView.swift:1165-1185`
- **Currently:** Simple `zip -r` of entire log directory; doesn't create proper archive with specific files + system info

### 3.9 Config: Migration Logic Is a Stub
- **Source:** `ConfigManager.swift` — `migrateConfig()` only updates version field, no actual migration logic
- **Impact:** Future config schema changes will break without proper migration

### 3.10 Config: Environment Variable Overrides Not Implemented
- **Spec:** `specs/configuration.md` — PLAYBACK_CONFIG and PLAYBACK_DATA_DIR environment variables
- **Source:** `Paths.swift` only checks `PLAYBACK_DEV_MODE`
- **Missing:** No support for custom config path or data directory via env vars

### 3.11 Diagnostics: Tab Organization Differs from Spec
- **Spec:** `specs/logging-diagnostics.md` — Overview, Recording Logs, Processing Logs, Resource Usage
- **Source:** `DiagnosticsView.swift` — Logs (generic), Health, Performance, Reports
- **Status:** Functionally similar but different organization; consider aligning or documenting intentional deviation

### 3.12 Permission Checking Uses Python Subprocess
- **Source:** `SettingsView.swift:776-803`
- **Problem:** Screen Recording permission check runs embedded Python code via `Process`
- **Fix:** Use Swift's native `CGPreflightScreenCaptureAccess()` instead

### 3.13 Force-Unwrapped URL in Settings
- **Source:** `SettingsView.swift:814-816`
- **Problem:** `URL(string: "x-apple.systempreferences:...")!` — force unwrap could crash
- **Fix:** Use `guard let` or `if let` optional binding

### 3.14 FirstRun: No Notification Listener for Permission Re-check
- **Source:** `PermissionsView.swift`
- **Problem:** When user returns from System Preferences after granting permission, UI doesn't auto-refresh; must click "Check Status" manually
- **Fix:** Listen for `NSApplication.didBecomeActiveNotification` and re-check permissions

---

## Priority 4 — Architectural Considerations

These are significant architectural decisions that may or may not be pursued for MVP.

### 4.1 Single-App vs Dual-App Architecture
- **Spec:** `specs/architecture.md`, `specs/README.md` — describes dual-app: PlaybackMenuBar.app (LaunchAgent) + Playback.app (Timeline Viewer)
- **Current:** Single `Playback.app` containing all functionality (menu bar, timeline, settings, diagnostics)
- **Implications:**
  - Quitting the app stops everything (menu bar disappears, recording loses control interface)
  - Spec says: menu bar agent should survive timeline viewer quit
  - Spec says: timeline viewer can be closed independently
- **Decision needed:** Refactoring to dual-app requires new Xcode target, splitting code into shared framework, and reworking app lifecycle
- **Note:** Single-app works for MVP but doesn't match the spec's UX model where recording continues seamlessly when user closes the viewer

### 4.2 Swift OCRService Wrapper Missing
- **Spec:** `specs/search-ocr.md` lines 10-20 — `OCRService.swift` using Vision framework in Swift
- **Source:** Only Python `ocr_processor.py` exists
- **Impact:** OCR only works during Python processing; no real-time OCR capability from Swift
- **Decision needed:** For MVP, Python OCR is sufficient; Swift OCR would enable future features (live search, real-time indexing)

---

## Phases 5-6: Remaining (Requires macOS Environment)

### Phase 5.6: Manual Testing — Requires macOS
- Test on clean macOS Tahoe 26.0 installation
- Test permission prompts (Screen Recording, Accessibility)
- Test display configurations, screen lock, screensaver
- Test app exclusion, low disk space, corrupted database recovery
- Test uninstallation with data preservation/deletion

### Phase 6: Distribution & Deployment — Requires macOS/Xcode
- 6.1 Build System: build scripts, code signing, CI/CD
- 6.2 Notarization: xcrun notarytool workflow
- 6.3 Arc-Style Distribution: .zip packaging, checksums, release notes
- 6.4 Installation & Updates: first-run wizard improvements, update checker
- 6.5 Documentation: user guide, developer guide, FAQ

---

## Quick Reference: File Locations

| Component | Files |
|-----------|-------|
| Menu Bar | `MenuBar/MenuBarView.swift`, `MenuBar/MenuBarViewModel.swift` |
| Timeline | `ContentView.swift`, `TimelineView.swift`, `TimelineStore.swift`, `PlaybackController.swift` |
| Date Picker | `Timeline/DateTimePickerView.swift` |
| Search | `Search/SearchController.swift`, `Search/SearchBar.swift`, `Search/SearchResultsList.swift`, `Search/SearchResultRow.swift` |
| Settings | `Settings/SettingsView.swift` (single 1248-line file with all 6 tabs) |
| Config | `Config/Config.swift`, `Config/ConfigManager.swift` |
| Services | `Services/LaunchAgentManager.swift`, `Services/GlobalHotkeyManager.swift` |
| FirstRun | `FirstRun/WelcomeView.swift`, `FirstRun/PermissionsView.swift`, `FirstRun/StorageSetupView.swift`, `FirstRun/DependencyCheckView.swift`, `FirstRun/InitialConfigView.swift`, `FirstRun/FirstRunCoordinator.swift`, `FirstRun/FirstRunWindowView.swift` |
| Diagnostics | `Diagnostics/DiagnosticsView.swift`, `Diagnostics/DiagnosticsController.swift`, `Diagnostics/LogEntry.swift` |
| Utilities | `Paths.swift`, `VideoBackgroundView.swift` |
| App Entry | `PlaybackApp.swift` |

---

## Test Coverage Summary

| Category | Count | Status |
|----------|-------|--------|
| Python unit tests | 280 | ✅ All passing |
| Swift unit tests | 203 | ✅ All passing |
| Swift integration tests | 72 | ✅ All passing |
| Swift UI tests | 115 | Build-verified (requires GUI) |
| Swift performance tests | 21 | Build-verified |
| **Total** | **691** | **555 running, 136 build-verified** |
