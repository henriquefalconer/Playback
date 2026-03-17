# "Delete All Recordings" Button — Implementation Plan

## Status: COMPLETE

All steps implemented, builds and smoke tests pass.

## What Was Done

1. **Created `Services/DataManager.swift`** — Singleton with `deleteAllRecordings()` that stops services, deletes all data files (temp, chunks, database + WAL/SHM, timeline signal), recreates directories, restarts services, and posts a notification.

2. **Added TimelineStore reset observer** — Listens for `RecordingsDidReset` notification in `init()` and reloads segments to clear the UI.

3. **Added button to SettingsView Storage section** — Destructive "Delete All Recordings" button with confirmation dialog, progress spinner, and error display. Recalculates storage info after deletion.

4. **Logging throughout** — Uses `Log.system` for file operations in DataManager and `Log.settings` for UI actions in SettingsView. Every deletion, service transition, and user action is logged.

## Files Changed

| File | Change |
|------|--------|
| `Services/DataManager.swift` | New — singleton with `deleteAllRecordings()` |
| `Settings/SettingsView.swift` | Added `import os`, state vars, button, confirmation dialog, error display |
| `TimelineStore.swift` | Added `RecordingsDidReset` notification observer in `init()` |
