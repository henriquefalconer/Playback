# "Delete All Recordings" Button — Implementation Plan

## Goal

Add a "Delete All Recordings" button to the Settings Storage section that resets all **data** to a clean slate while preserving configuration (`config.json`).

---

## What Gets Deleted

Per `specs/file-structure.md:52-56` and `specs/database-schema.md:10-11`:

- `data/temp/` — raw screenshots
- `data/chunks/` — processed video segments (.mp4)
- `data/meta.sqlite3` — segment/appsegment metadata database
- `data/meta.sqlite3-wal` — WAL journal
- `data/meta.sqlite3-shm` — shared memory file
- `data/.timeline_open` — timeline signal file

## What Gets Preserved

Per `specs/configuration.md:7`:

- `config.json` — lives outside `data/`, not affected

---

## Implementation Steps

### 1. Add `deleteAllRecordings()` method to a new `DataManager` class

- **New file:** `src/Playback/Playback/Services/DataManager.swift`
- Singleton `@MainActor final class DataManager`
- Method: `func deleteAllRecordings() throws`
- Steps inside the method:
  - Log start: `Log.settings.info("Delete all recordings requested")`
  - Stop `RecordingService.shared` (call `stop()` — see `RecordingService.swift:98-113`)
  - Stop `ProcessingService.shared` (call `stop()` — see `ProcessingService.swift:42-47`)
  - Log services stopped
  - Remove `Paths.tempDirectory` recursively (`rm -rf` equivalent)
  - Remove `Paths.chunksDirectory` recursively
  - Remove `Paths.databasePath` (`.sqlite3`, `-wal`, `-shm` files)
  - Remove `Paths.timelineOpenSignalPath`
  - Log each deletion with success/failure
  - Re-create directories via `Paths.ensureDirectoriesExist()` (see `Paths.swift:62-83`)
  - Log directories recreated
  - Restart `ProcessingService.shared.start()` (see `ProcessingService.swift:30-40`)
  - Conditionally restart `RecordingService.shared.start()` if `ConfigManager.shared.config.recordingEnabled` (mirrors `PlaybackApp.swift:304-309`)
  - Log services restarted
  - Post `NotificationCenter` notification `"RecordingsDidReset"` so TimelineStore can reload
  - Log completion with total elapsed time

### 2. Add TimelineStore reload on reset notification

- **File:** `src/Playback/Playback/TimelineStore.swift`
- **Where:** In `init()` (line ~120), add observer for `"RecordingsDidReset"` notification
- **Action:** Call `loadSegments()` (line 151) which will find an empty database and set `loadingState = .empty`
- **Log:** `Log.timeline.info("Reloading segments after data reset")`

### 3. Add the button to SettingsView

- **File:** `src/Playback/Playback/Settings/SettingsView.swift`
- **Where:** Inside the `Section("Storage")` block (lines 50-74), after the info text HStack (line 73)
- **New state variables** (add near line 26):
  - `@State private var showDeleteConfirmation = false`
  - `@State private var isDeleting = false`
  - `@State private var deleteError: String?`
- **UI elements to add:**
  - A destructive `Button("Delete All Recordings")` styled red
  - Disabled while `isDeleting` is true
  - Shows `ProgressView` spinner while deleting
  - On tap: sets `showDeleteConfirmation = true`
  - `.confirmationDialog` or `.alert` confirmation:
    - Title: "Delete All Recordings?"
    - Message: "This will permanently delete all screenshots, video segments, and metadata. Your settings will be preserved. This cannot be undone."
    - Destructive action: "Delete All"
    - Cancel action: "Cancel"
  - On confirm:
    - Set `isDeleting = true`
    - Call `DataManager.shared.deleteAllRecordings()` in a `Task`
    - On success: recalculate storage via `calculateStorage()` (line 254)
    - On failure: set `deleteError` to error message
    - Set `isDeleting = false`
  - Error display: red HStack with exclamation icon (same pattern as `launchAtLoginError`, lines 37-47)
  - Log button tap: `Log.settings.info("Delete All Recordings button tapped")`
  - Log confirmation: `Log.settings.info("Delete All Recordings confirmed by user")`
  - Log cancel: `Log.settings.info("Delete All Recordings cancelled by user")`

### 4. Add logging for every step

- **File:** `src/Playback/Playback/Logging.swift`
- Use existing `Log.settings` category (line 14) for button/UI actions
- Use `Log.system` (line 12) for file deletion operations inside `DataManager`
- Every file/directory deletion logs success or failure with path
- Service stop/start transitions logged
- Total time for the operation logged at completion

---

## Source Files Affected

| File | Lines | Change |
|------|-------|--------|
| `Settings/SettingsView.swift` | 26, 50-74 | Add state vars, button, confirmation dialog, error display |
| `Services/DataManager.swift` | (new) | New singleton with `deleteAllRecordings()` method |
| `TimelineStore.swift` | ~120 | Add observer for `"RecordingsDidReset"` notification |
| `Paths.swift` | 62-83 | Already has `ensureDirectoriesExist()` — no change needed |
| `Logging.swift` | 14 | Already has `Log.settings` — no change needed |

## Spec Files Referenced

| Spec | Lines | What |
|------|-------|------|
| `specs/file-structure.md` | 47-57 | Data directory structure (what to delete vs preserve) |
| `specs/file-structure.md` | 60-71 | Path resolution table |
| `specs/configuration.md` | 7 | Config file location (outside data dir — preserved) |
| `specs/configuration.md` | 21-51 | User-facing settings (adding to this surface) |
| `specs/database-schema.md` | 10-12 | Database path and permissions |
| `specs/database-schema.md` | 16-77 | Tables that get wiped (schema_version, segments, appsegments) |
| `specs/database-schema.md` | 81-86 | Database initialization PRAGMAs (re-created on next use) |

## Key Source Code References

| File | Lines | Relevance |
|------|-------|-----------|
| `RecordingService.swift` | 98-113 | `stop()` — must call before deleting temp files |
| `RecordingService.swift` | 44-57 | `start()` — restart after cleanup |
| `ProcessingService.swift` | 42-47 | `stop()` — must call before deleting database |
| `ProcessingService.swift` | 30-40 | `start()` — restart after cleanup |
| `ProcessingService.swift` | 449-506 | `openDatabase()` — schema auto-creates on next use |
| `PlaybackApp.swift` | 299-315 | `ensureServicesRunning()` — pattern to mirror for restart |
| `Paths.swift` | 23-41 | `databasePath`, `chunksDirectory`, `tempDirectory` — what to delete |
| `Paths.swift` | 62-83 | `ensureDirectoriesExist()` — recreate dirs after deletion |
| `TimelineStore.swift` | 107-121 | `init()` — where to add reset observer |
| `TimelineStore.swift` | 151-280 | `loadSegments()` — called after reset to clear UI state |
| `SettingsView.swift` | 18-26 | State variables section |
| `SettingsView.swift` | 50-74 | Storage section where button goes |
| `SettingsView.swift` | 37-47 | Error display pattern to reuse |
| `SettingsView.swift` | 254-263 | `calculateStorage()` — recalculate after deletion |
| `SettingsView.swift` | 266-294 | `StorageInfo` — will show reduced size after cleanup |
| `MenuBarViewModel.swift` | 121-131 | `performQuit()` — reference for service stop pattern |
| `Logging.swift` | 12, 14 | `Log.system` and `Log.settings` categories to use |
