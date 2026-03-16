<!--
 Copyright (c) 2026 Henrique Falconer. All rights reserved.
 SPDX-License-Identifier: Proprietary
-->

# Playback - Implementation Plan

Canonical specs live in `specs/`. This plan tracks only actionable work going forward.

---

## Phase 5: Polish

- [x] App icon assets (generated from playback.svg)

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
| Services | `Services/RecordingService.swift`, `Services/ProcessingService.swift`, `Services/GlobalHotkeyManager.swift`, `Services/LaunchAtLoginManager.swift` |
| State Views | `Timeline/EmptyStateView.swift`, `Timeline/ErrorStateView.swift`, `Timeline/LoadingStateView.swift` |
| Paths | `Paths.swift` |

All Swift source under `src/Playback/Playback/`. Tests under `src/Playback/PlaybackTests/` and `src/Playback/PlaybackUITests/`.
