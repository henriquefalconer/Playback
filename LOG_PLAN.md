# Comprehensive Logging Plan

Goal: instrument every result, interaction, shortcut, load-state, and processing stage in Playback so that Claude Code sessions can reconstruct exactly what happened. Each log entry specifies **trigger type**: `EVENT` (fires on action/state change) or `TEMPORAL` (fires on timer/poll interval).

---

## 1. Logging Infrastructure ✅ DONE

**File:** `Logging.swift`

Added `Log.session`, `Log.settings`, `Log.datepicker` categories. All new logs use structured `privacy: .public` interpolation.

---

## 2. App Lifecycle & Window Management ✅ DONE

**Source:** `PlaybackApp.swift`

Implemented:
- App launch config summary (recording_enabled, excluded_apps count, shortcut, version)
- Timeline window opened (with dimensions) / closed (with session duration)
- Settings window opened / closed
- Screen Recording permission check (granted/denied) on launch
- Accessibility permission check (granted/denied) on hotkey registration

Not implemented (low value, signal file already logged in Paths.swift):
- Signal file timing info — existing logs sufficient

---

## 3. Menu Bar Interactions ✅ DONE

**Source:** `MenuBarView.swift`, `MenuBarViewModel.swift`

Implemented:
- Recording toggled ON (with excluded app count) / OFF (with total capture count)
- Open Timeline, Settings, About Playback button clicks
- Quit with uptime and total captures
- Permission denied alert shown (Screen Recording)
- Menu bar icon state change logging (old→new on actual transitions)

---

## 4. Recording Service ✅ DONE

**Source:** `RecordingService.swift`

Implemented:
- Capture cycle summary every 60 captures (total, recent, skipped by exclusion/timeline, avg size, cumulative MB)
- Capture interval changed on reload
- Excluded apps list changed on reload (count diff + app list)
- Config observer fired notification log
- Display enumeration (count + dimensions) on each capture
- Screenshot file size elevated to info with cumulative session bytes
- All logs use `privacy: .public` for diagnostics visibility

---

## 5. Processing Service ✅ DONE

**Source:** `ProcessingService.swift`

Implemented:
- Processing cycle started with trigger source (initial_start vs timer) and cycle number
- Processing cycle completed with segments created, frames processed, total duration
- Day directory scan result with pending day count
- Frame group formed with group count, frames per group, resolution
- Video encoding started with segment ID, frame count, dimensions, bitrate
- Video encoding progress every 100th frame with elapsed time
- Video encoding completed with file size, encoding duration, effective FPS
- Database segment inserted with ID, date, duration, frame count, file size
- Database appsegment inserted with app ID and duration
- Temp file cleanup result with deleted/failed counts
- Processing service heartbeat (5-minute timer) with running state, last processing time, total segments created

---

## 6. Timeline Store & Data Loading

**Spec:** `timeline-graphical-interface.md` lines 181-183 (auto-refresh every 5s), `database-schema.md` lines 90-122 (queries)
**Source:** `TimelineStore.swift`

### Existing coverage
- DB open/close, segment count, table-not-found, segment lookup logic (15 log calls)

### New logs needed

- **`EVENT`** Loading state transition — every time `loadingState` changes (lines 152-154, 270-276), log old state -> new state
- **`EVENT`** Segment load completed — `loadSegments()` (line 278), log total segments, total appsegments, timeline span (earliest to latest), total duration covered, total gap duration
- **`EVENT`** Segment load query timing — wrap SQL execution in `loadSegments()` (lines 174-226) with elapsed time measurement
- **`TEMPORAL`** Auto-refresh tick — `refreshIfNeeded()` (line 139), log even when no change detected (currently only logs on change at line 143), include segment count and whether reload triggered
- **`EVENT`** New segments detected — `refreshIfNeeded()` (line 139), log count delta (old vs new)
- **`EVENT`** Segment lookup result — `segment(for:direction:)` already has debug logs but add structured result: found/gap/boundary, segment ID if found, offset, lookup duration

---

## 7. Playback Controller & AVPlayer

**Spec:** `timeline-graphical-interface.md` lines 20-25 (AVPlayer), lines 27-31 (preloading), lines 33-38 (frozen frame), lines 50-52 (consecutive failures)
**Source:** `PlaybackController.swift`

### Existing coverage
- Frozen frame errors, preload events, scrub details, seek status, consecutive failures (21 log calls)

### New logs needed

- **`EVENT`** Play started — `play()` (line 333), log current segment ID, current time, video offset
- **`EVENT`** Pause triggered — `pause()` (line 344), log current segment ID, current time, reason (user vs scrub vs system)
- **`EVENT`** Play/pause toggled — `togglePlayPause()` (line 328), log resulting state
- **`EVENT`** Segment transition — `seek()` when segment changes (line 357), log old segment ID -> new segment ID, transition type (preloaded vs fresh load), gap crossed
- **`EVENT`** Frozen frame shown — when `showFrozenFrame` set to true (line 250-260 in scrub, line 354 in seek), log reason (scrub gap, segment transition, loading)
- **`EVENT`** Frozen frame hidden — when `showFrozenFrame` set to false (line 386 in seek status observer), log duration shown
- **`EVENT`** Preload triggered — `checkAndPreloadNextSegment()` (line 138), log current progress %, current segment ID, next segment ID
- **`EVENT`** Preload used — `usePreloadedSegmentIfAvailable()` (line 213), log latency saved estimate
- **`EVENT`** Consecutive failure count changed — after increment (line 395-403, 475-484), log count and threshold status
- **`EVENT`** Error state entered — when `playbackError` set (line 399-401, 476-478), log error type and details
- **`EVENT`** Error state cleared — when `playbackError` set to nil (line 384, 469), log recovery
- **`TEMPORAL`** Time observer tick — periodic observer (line 63-87, every 0.2s), log every 5 seconds: current absolute time, video offset, segment ID, buffer state — avoid flooding by sampling

---

## 8. Timeline UI & Gestures

**Spec:** `timeline-graphical-interface.md` lines 94-99 (scrubbing), lines 101-108 (pinch zoom), lines 110-113 (click to seek), lines 115-121 (keyboard shortcuts)
**Source:** `ContentView.swift`, `TimelineView.swift`

### Existing coverage
- Segment count change (ContentView:58), pinch zoom (ContentView:89), scroll event (ContentView:244), click/drag details (TimelineView:275-295)

### New logs needed

- **`EVENT`** Keyboard shortcut: ESC pressed — keyboard monitor (ContentView:204), log "timeline_close_requested"
- **`EVENT`** Keyboard shortcut: Space pressed — keyboard monitor (ContentView:207-210), log play/pause resulting state
- **`EVENT`** Keyboard shortcut: Arrow key pressed — keyboard monitor (ContentView:212-224), log direction and seek delta (5s)
- **`EVENT`** Scroll scrub started — scroll monitor (ContentView:229), log initial phase, delta, and centerTime
- **`EVENT`** Scroll scrub ended — when scroll phase ends (ContentView:252-270), log total scroll distance, time range traversed
- **`EVENT`** Momentum started — `startMomentum()` (ContentView:310), log initial velocity
- **`EVENT`** Momentum ended — `stopMomentum()` (ContentView:333), log final velocity and total distance
- **`EVENT`** Pinch zoom started — MagnificationGesture `.onChanged` first call (ContentView:66), log starting visibleWindowSeconds
- **`EVENT`** Pinch zoom ended — MagnificationGesture `.onEnded` (ContentView:92-95, add if missing), log final visibleWindowSeconds and zoom factor
- **`EVENT`** Click-to-seek on timeline bar — DragGesture `.onEnded` (TimelineView:269), log target timestamp and whether segment exists at that time
- **`EVENT`** Time bubble clicked (date picker opened) — Button action (TimelineView:249-264), log current timestamp
- **`EVENT`** Visible window range — on every centerTime or visibleWindowSeconds change, log visible range [start, end] — use `.onChange` on centerTime (add to ContentView), sampled to max 2/second
- **`EVENT`** Retry notification received — NotificationCenter observer (ContentView:190), log retry attempt number

---

## 9. Date/Time Picker

**Spec:** `timeline-graphical-interface.md` lines 127-161 (DateTimePicker layout, actions, data loading)
**Source:** `DateTimePickerView.swift`

### Existing coverage
- DB open errors and query failures (4 log calls)

### New logs needed

- **`EVENT`** Date picker opened — `.onAppear` (line 45), log current selected date and time
- **`EVENT`** Date picker closed (cancel) — background tap (line 23) or Cancel button (line 169), log "cancelled"
- **`EVENT`** Date picker closed (jump) — Jump button (line 177), log target date and time
- **`EVENT`** Month navigated — Previous/Next buttons (lines 54-68), log old month -> new month
- **`EVENT`** "Today" button pressed — Today button (line 71), log current date
- **`EVENT`** Day selected — Day button action (lines 93-110), log selected date, whether it has recordings
- **`EVENT`** Time slot selected — Time button action (lines 135-160), log selected timestamp
- **`EVENT`** Available dates loaded — `loadAvailableDates()` success path (line 262), log count of dates with recordings, query duration
- **`EVENT`** Available times loaded — `loadAvailableTimesForSelectedDate()` success path (line 314), log count of time slots, selected date, query duration

---

## 10. State Views

**Spec:** `timeline-graphical-interface.md` lines 165-179 (empty, loading, error states)
**Source:** `EmptyStateView.swift`, `LoadingStateView.swift`, `ErrorStateView.swift`

### Currently: zero logging in any state view

### New logs needed

- **`EVENT`** Empty state shown — `EmptyStateView` body rendered, add `.onAppear` log
- **`EVENT`** "Open Menu Bar" button clicked — EmptyStateView button (line 26), log action
- **`EVENT`** Loading state shown — `LoadingStateContentView` body rendered, add `.onAppear` log with timestamp
- **`EVENT`** Loading state dismissed — add `.onDisappear` log with duration shown
- **`EVENT`** Error state shown — `ErrorStateView` body rendered, add `.onAppear` log with error type (line 14)
- **`EVENT`** "Retry" button clicked — `retryLoading()` (ErrorStateView:110-121), log error type being retried
- **`EVENT`** "Open System Settings" clicked — `openSystemSettings()` (ErrorStateView:96-107), log which permission

---

## 11. Settings Panel

**Spec:** `configuration.md` lines 25-51 (settings), `privacy-security.md` lines 32-50 (permissions UI)
**Source:** `SettingsView.swift`, `HotkeyRecorderView.swift`

### Currently: zero logging in settings views

### New logs needed

- **`EVENT`** Settings panel opened — `SettingsPanel` `.onAppear` (SettingsView:214), log current config snapshot
- **`EVENT`** Launch at login toggled — `.onChange(of: launchAtLoginEnabled)` (SettingsView:44), log old -> new, success/failure
- **`EVENT`** Launch at login error — `updateLaunchAtLogin()` (SettingsView:248-259), log error description
- **`EVENT`** Screen Recording permission checked — `checkPermissions()` (SettingsView:231), log granted/denied
- **`EVENT`** Accessibility permission checked — `checkPermissions()` (SettingsView:233), log granted/denied
- **`EVENT`** "Open System Settings" clicked (Screen Recording) — `openScreenRecordingSettings()` (SettingsView:236)
- **`EVENT`** "Open System Settings" clicked (Accessibility) — `openAccessibilitySettings()` (SettingsView:242)
- **`EVENT`** Hotkey recording started — `HotkeyRecorderView` `.onTapGesture` (HotkeyRecorderView:35)
- **`EVENT`** Hotkey recorded — `handleKeyPress()` (HotkeyRecorderView:76), log new shortcut string
- **`EVENT`** Hotkey conflict detected — `checkForConflict()` (HotkeyRecorderView:126), log conflicting shortcut
- **`EVENT`** Hotkey reset to default — `resetToDefault()` (HotkeyRecorderView:145), log old shortcut
- **`EVENT`** Recommended app added to exclusions — `addRecommendedApp()` (SettingsView:261), log bundle ID
- **`EVENT`** App manually added to exclusions — `addApp()` (SettingsView:269), log bundle ID
- **`EVENT`** App removed from exclusions — `deleteApps()` (SettingsView:278), log bundle ID(s)
- **`EVENT`** App dragged onto exclusion list — `handleAppDrop()` (SettingsView:284), log bundle ID extracted

---

## 12. Configuration Changes

**Spec:** `configuration.md` lines 65-71 (config management)
**Source:** `ConfigManager.swift`, `Config.swift`

### Existing coverage
- Load error (ConfigManager:34), save error (ConfigManager:67), sync issue (ConfigManager:63)

### New logs needed

- **`EVENT`** Config loaded from disk — `loadConfiguration()` success path (ConfigManager:28), log config version, excluded app count, recording enabled, shortcut
- **`EVENT`** Config saved to disk — `saveConfiguration()` success path (ConfigManager:42), log file size, what changed (diff from previous)
- **`EVENT`** Config change notification posted — `updateConfig()` (ConfigManager:76), log which fields changed
- **`EVENT`** Config validated — `Config.validated()` (Config:23), log if any fields were sanitized
- **`EVENT`** Default config created — `loadConfiguration()` when file missing (ConfigManager:36-38), log path

---

## 13. Video Background & Rendering

**Spec:** `timeline-graphical-interface.md` lines 56-90 (timeline rendering)
**Source:** `VideoBackgroundView.swift`, `TimelineView.swift`

### Existing coverage
- Scroll debug in unused ScrollCaptureView (VideoBackgroundView:66)

### New logs needed

- **`EVENT`** AVPlayerLayer attached — `makeNSView()` (VideoBackgroundView:48), log player status
- **`EVENT`** AVPlayerLayer updated — `updateNSView()` (VideoBackgroundView:54), log whether player reference changed
- **`EVENT`** Visible app segments computed — `visibleAppSegments` (TimelineView:87), log count visible, total in store — sampled to avoid flooding (log only when count changes)
- **`EVENT`** App color resolved — `appColor(for:)` (TimelineView:149), log bundle ID and resulting color hex — cache-miss only
- **`EVENT`** Tick interval changed — `tickInterval` (TimelineView:309), log old interval -> new interval when zoom changes tick density

---

## 14. Global Hotkey

**Spec:** `privacy-security.md` lines 39-43 (Accessibility permission)
**Source:** `GlobalHotkeyManager.swift`

### Existing coverage
- Registration info (line 93), unregistration info (line 108)

### New logs needed

- **`EVENT`** Hotkey pressed (callback fired) — Carbon event handler callback (GlobalHotkeyManager:35-69), log timestamp and current app state (timeline open/closed)
- **`EVENT`** Accessibility permission check — `checkAccessibilityPermission()` (GlobalHotkeyManager:111), log result
- **`EVENT`** Hotkey unregistered on deinit — deinit (GlobalHotkeyManager:116), log cleanup

---

## 15. Launch at Login

**Source:** `LaunchAtLoginManager.swift`

### Existing coverage
- Enable/disable/skip/error (5 log calls)

### New logs needed

- **`EVENT`** SMAppService status queried — `isEnabled` property (LaunchAtLoginManager:14), log current registration status

---

## 16. Session-Level Temporal Summaries

These are new periodic logs that aggregate state for session diagnostics.

- **`TEMPORAL` (60s)** System health snapshot — new timer in `PlaybackApp`, log: CPU usage estimate (process info), memory footprint, recording active, processing active, segment count, disk usage of data dir
- **`TEMPORAL` (300s)** Recording session summary — in `RecordingService`, log: captures in last 5 min, skips (exclusion + timeline), average capture latency, cumulative file size
- **`TEMPORAL` (300s)** Processing session summary — in `ProcessingService`, log: segments created in last 5 min, frames processed, encoding time total, DB write time total
- **`TEMPORAL` (5s)** Timeline viewer state (only while open) — in `ContentView` or `PlaybackController`, log: current time, visible window, zoom level, playing/paused, current segment ID, frozen frame visible

---

## Summary of Changes by File

| File | Existing Logs | New Logs | Trigger Mix |
|------|--------------|----------|-------------|
| `Logging.swift` | 9 categories | +3 categories (session, settings, datepicker) | — |
| `PlaybackApp.swift` | 8 | +10 | 9 EVENT, 1 TEMPORAL |
| `MenuBarView.swift` | 0 | +4 | 4 EVENT |
| `MenuBarViewModel.swift` | 3 | +5 | 4 EVENT, 1 TEMPORAL |
| `RecordingService.swift` | 24 | +6 | 4 EVENT, 2 TEMPORAL |
| `ProcessingService.swift` | 18 | +11 | 10 EVENT, 1 TEMPORAL |
| `TimelineStore.swift` | 15 | +6 | 5 EVENT, 1 TEMPORAL |
| `PlaybackController.swift` | 21 | +12 | 11 EVENT, 1 TEMPORAL |
| `ContentView.swift` | 3 | +12 | 12 EVENT |
| `TimelineView.swift` | 6 | +4 | 4 EVENT |
| `DateTimePickerView.swift` | 4 | +9 | 9 EVENT |
| `EmptyStateView.swift` | 0 | +2 | 2 EVENT |
| `LoadingStateView.swift` | 0 | +2 | 2 EVENT |
| `ErrorStateView.swift` | 0 | +3 | 3 EVENT |
| `SettingsView.swift` | 0 | +14 | 14 EVENT |
| `HotkeyRecorderView.swift` | 0 | +4 | 4 EVENT |
| `ConfigManager.swift` | 3 | +5 | 5 EVENT |
| `Config.swift` | 0 | +1 | 1 EVENT |
| `VideoBackgroundView.swift` | 1 | +3 | 3 EVENT |
| `GlobalHotkeyManager.swift` | 2 | +3 | 3 EVENT |
| `LaunchAtLoginManager.swift` | 5 | +1 | 1 EVENT |
| **Totals** | **113** | **~117** | ~105 EVENT, ~12 TEMPORAL |
