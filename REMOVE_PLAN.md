# Dev Mode Removal Plan

Remove all dev setup, dev build configuration, dev-specific code paths, and dev instructions. All development will use Release builds with production paths (`~/Library/Application Support/Playback/`).

---

## 1. Swift Source Code

### Paths.swift (`src/Playback/Playback/Paths.swift`)
- **Delete `isDevelopment` property** (lines 5-7) — env var check for `PLAYBACK_DEV_MODE`
- **Delete dev branch in `baseDataDirectory`** (lines 16-23) — `SRCROOT/dev_data` path resolution
- **Delete `SRCROOT` env var lookup and `fatalError`** (lines 18-20) — only used by dev mode
- **Simplify `configPath()`** (lines 59-84) — remove dev branch (lines 65-72) that returns `SRCROOT/dev_config.json`
- **Remove `PLAYBACK_DEV_MODE` env var check** — keep only `PLAYBACK_DATA_DIR` and `PLAYBACK_CONFIG` overrides as escape hatches
- **Remove all `if Paths.isDevelopment { print(...) }` guards** (lines 119, 132, 136) — replace with `#if DEBUG` or remove entirely

### RecordingService.swift (`src/Playback/Playback/Services/RecordingService.swift`)
- **Remove ~17 `if Paths.isDevelopment { print(...) }` blocks** (lines 30, 35, 44, 48, 56, 64, 72, 79, 84, 92, 99, 103, 112, 136, 142, 150, 157, 163, 267, 295, 320)
- Replace with `#if DEBUG` guards or remove entirely

### PlaybackController.swift (`src/Playback/Playback/PlaybackController.swift`)
- **Remove ~18 `if Paths.isDevelopment { print(...) }` blocks** (lines 112, 117, 148, 154, 206, 210, 225, 253, 309, 318, 325, 406, 421, 439, 443, 465, 470, 505, 516, 534, 538)

### TimelineStore.swift (`src/Playback/Playback/TimelineStore.swift`)
- **Remove ~14 `if Paths.isDevelopment { print(...) }` blocks** (lines 115, 144, 169, 187, 260, 275, 310, 317, 327, 345, 352, 364, 389, 394)

### ProcessingService.swift (`src/Playback/Playback/Services/ProcessingService.swift`)
- **Remove ~9 `if Paths.isDevelopment { print(...) }` blocks** (lines 149, 162, 182, 207, 231, 242, 289, 410)

### PlaybackApp.swift (`src/Playback/Playback/PlaybackApp.swift`)
- **Remove ~7 `if Paths.isDevelopment { print(...) }` blocks** (lines 40, 115, 120, 153, 187, 195)

### TimelineView.swift (`src/Playback/Playback/TimelineView.swift`)
- **Remove 6 `if Paths.isDevelopment { print(...) }` blocks** (lines 274, 279, 284, 295, 300, 304)

### MenuBarViewModel.swift (`src/Playback/Playback/MenuBar/MenuBarViewModel.swift`)
- **Remove 3 `if Paths.isDevelopment { print(...) }` blocks** (lines 72, 139, 145)

### ContentView.swift (`src/Playback/Playback/ContentView.swift`)
- **Remove 3 `if Paths.isDevelopment { print(...) }` blocks** (lines 57, 90, 247)

### ConfigManager.swift (`src/Playback/Playback/Config/ConfigManager.swift`)
- **Remove 2 `if Paths.isDevelopment { print(...) }` blocks** (lines 33, 65)

### GlobalHotkeyManager.swift (`src/Playback/Playback/Services/GlobalHotkeyManager.swift`)
- **Remove 2 `if Paths.isDevelopment { print(...) }` blocks** (lines 92, 109)

### VideoBackgroundView.swift (`src/Playback/Playback/VideoBackgroundView.swift`)
- **Remove 1 `if Paths.isDevelopment { print(...) }` block** (line 65)

### Decision: What replaces `if Paths.isDevelopment` for debug prints?
- **Option A (recommended):** Use `#if DEBUG` compiler directive — zero cost in Release, no runtime check needed
- **Option B:** Remove all debug prints entirely — cleanest, but loses diagnostics during Xcode debugging
- Either way, the `isDevelopment` property and `PLAYBACK_DEV_MODE` env var are deleted

---

## 2. Tests

### PathsTests.swift (`src/Playback/PlaybackTests/PathsTests.swift`)
- **Delete `testIsDevelopmentReturnsTrueWhenEnvVarSet()`** (lines 8-19)
- **Delete `testIsDevelopmentReturnsFalseWhenEnvVarNotSet()`** (lines 21-30)
- **Update any path resolution tests** that assert dev-mode paths (`dev_data`, `dev_config.json`)

---

## 3. Xcode Project

### Playback.xcscheme (`src/Playback/Playback.xcodeproj/xcshareddata/xcschemes/Playback.xcscheme`)
- **Remove `PLAYBACK_DEV_MODE` environment variable** (lines 78-82)
- **Remove `SRCROOT` environment variable override** (lines 83-87)
- **Remove entire `<EnvironmentVariables>` block** if empty after above (lines 77-88)

### project.pbxproj (`src/Playback/Playback.xcodeproj/project.pbxproj`)
- No changes needed — Debug/Release Xcode configurations are standard and useful for `#if DEBUG`; they are not "dev mode"

---

## 4. Scripts

### Delete entirely
- `scripts/setup_dev_env.sh` — dev environment setup (creates dev_data, dev_config.json, dev_logs)
- `scripts/stop-dev.sh` — stops dev LaunchAgents (`com.playback.dev.*`)

### Modify
- **`scripts/status.sh`** — remove dev signal file checks (line ~43-46 dev vs prod distinction), remove dev screenshot directory checks, remove `com.playback.dev.*` LaunchAgent status checks
- **`scripts/uninstall.sh`** — remove dev agent labels from `LAUNCH_AGENTS` array (lines 27-30: `com.playback.dev.recording`, `com.playback.dev.processing`, `com.playback.dev.cleanup`), remove dev data directory references (`$HOME/dev_data`, `$HOME/dev_logs`)
- **`scripts/smoke-test.sh`** — currently builds Debug config; consider changing to Release or keep as-is (Debug Xcode config is not the same as "dev mode")
- **`scripts/verify-production-build.sh`** — remove dev agent cleanup references (lines 187-188)

---

## 5. Documentation

### Delete entirely
- `DEVELOPMENT_SETUP.md` — entire file is dev environment setup guide (202 lines)

### CLAUDE.md (project instructions)
- **Line 40:** Remove `Paths.isDevelopment` gating instruction — no longer applicable
- **Line 42:** Remove "development builds" command reference
- **Lines 59-61:** Remove Debug build command and `build/Debug/Playback.app` output reference; keep Release only
- **Lines 68-71:** Change test commands from `-configuration Debug` to `-configuration Release` (or remove `-configuration` flag to use scheme default)
- **Lines 77-83:** Delete "Development Environment Setup" section (setup_dev_env.sh, dev_data, dev_logs, dev_config.json, install_dev_launchagents.sh)
- **Lines 85-91:** Remove dev LaunchAgent labels (`com.playback.dev.*`), dev log paths (`dev_logs/`)
- **Lines 108-120:** Delete "Development Mode Testing" section (PLAYBACK_DEV_MODE, dev_data, dev_config.json references)
- **Line 173:** Remove "Use dev mode: Tests should use development data directories"
- **Line 206:** Update smoke test description if it changes from Debug
- **Line 228:** Remove "Automatically uses dev or prod labels and paths"
- **Line 262:** Remove `{{DEV_MODE}}` variable substitution reference

### README.md
- **Lines 84-100:** Rewrite "Development Build" section — remove `setup_dev_env.sh`, `dev_data/`, `dev_config.json` references
- **Lines 188-204:** Remove "Development" quick start section referencing `PLAYBACK_DEV_MODE` and `SRCROOT` env vars
- Remove link to `DEVELOPMENT_SETUP.md` (line 192)

### AGENTS.md
- Same content as CLAUDE.md — apply identical changes (or deduplicate)

---

## 6. Specifications

### specs/file-structure.md
- **Lines 60-69:** Delete "Development (PLAYBACK_DEV_MODE=1)" file structure diagram
- **Lines 73-82:** Remove dev column from path resolution table (dev_data, dev_config.json rows)

### specs/architecture.md
- **Lines 84-93:** Delete "Development (PLAYBACK_DEV_MODE=1)" file system layout

### specs/configuration.md
- **Line 9:** Remove "Development: `<project>/dev_config.json`"

### specs/database-schema.md
- **Line 12:** Remove "Development: `<project>/dev_data/meta.sqlite3`"

### specs/build-process.md
- **Line 21:** Remove "Signing: ad-hoc (development)"
- **Lines 33-34:** Remove development build command
- **Line 70:** Update smoke test description if changed

### specs/README.md
- **Line 3:** Change "Active Development" status if desired (cosmetic, not blocking)

---

## 7. LaunchAgent Templates

- **Remove `{{DEV_MODE}}` variable** from any plist templates (referenced in CLAUDE.md/AGENTS.md line 262)
- **Remove dev label logic** (`com.playback.dev.*`) from LaunchAgentManager if it gets implemented
- Note: No actual template files were found in the repo; only documented in specs

---

## 8. Gitignore / Generated Files

- **Remove `dev_data/`, `dev_logs/`, `dev_config.json` entries** from `.gitignore` (if present)
- **Delete `dev_data/`, `dev_logs/`, `dev_config.json`** if they exist locally (they're gitignored)

---

## Summary

| Category | Files to delete | Files to modify |
|----------|----------------|-----------------|
| Swift source | 0 | 12 (~90 `isDevelopment` blocks) |
| Tests | 0 | 1 (PathsTests.swift) |
| Xcode config | 0 | 1 (Playback.xcscheme) |
| Scripts | 2 (setup_dev_env.sh, stop-dev.sh) | 3 (status.sh, uninstall.sh, verify-production-build.sh) |
| Docs | 1 (DEVELOPMENT_SETUP.md) | 4 (CLAUDE.md, AGENTS.md, README.md, specs) |
| Specs | 0 | 5 (file-structure, architecture, configuration, database-schema, build-process) |

**Total: ~90 runtime dev-mode checks removed, 3 files deleted, 26 files modified.**
