# Dev Mode Removal Plan

Remove all dev setup, dev build configuration, dev-specific code paths, and dev instructions. All development will use Release builds with production paths (`~/Library/Application Support/Playback/`).

---

## ~~1. Swift Source Code~~ DONE

All ~90 `if Paths.isDevelopment { print(...) }` blocks replaced with `#if DEBUG` across 12 files. `isDevelopment` property deleted from Paths.swift. Dev branches in `baseDataDirectory` and `configPath()` removed. Only `PLAYBACK_DATA_DIR` and `PLAYBACK_CONFIG` env var overrides remain as escape hatches.

---

## ~~2. Tests~~ DONE

Deleted `testIsDevelopmentReturnsTrueWhenEnvVarSet()` and `testIsDevelopmentReturnsFalseWhenEnvVarNotSet()` from PathsTests.swift.

---

## ~~3. Xcode Project~~ DONE

Removed `PLAYBACK_DEV_MODE` and `SRCROOT` environment variables and entire `<EnvironmentVariables>` block from Playback.xcscheme.

---

## ~~4. Scripts~~ DONE

Deleted `setup_dev_env.sh` and `stop-dev.sh`. Removed all dev signal file checks, dev screenshot checks, dev LaunchAgent labels (`com.playback.dev.*`), and dev data directory references from `status.sh`, `uninstall.sh`, and `verify-production-build.sh`.

---

## ~~5. Documentation~~ DONE

Deleted `DEVELOPMENT_SETUP.md`. Cleaned CLAUDE.md: removed `Paths.isDevelopment` gating instruction (replaced with `#if DEBUG`), removed "Development Environment Setup" section, removed dev LaunchAgent labels and dev log paths, deleted "Development Mode Testing" section, removed "Use dev mode" from integration tests, removed "Automatically uses dev or prod labels and paths", removed `{{DEV_MODE}}` variable reference. Updated README.md: rewrote "Development Build" section with correct scheme/commands, removed dev quick start section and link to DEVELOPMENT_SETUP.md. AGENTS.md mirrors CLAUDE.md (auto-synced).

---

## ~~6. Specifications~~ DONE

Cleaned all spec files: deleted dev file structure diagram and dev column from path resolution table in `specs/file-structure.md`. Deleted dev file system layout from `specs/architecture.md`. Removed dev config path from `specs/configuration.md`. Removed dev database path from `specs/database-schema.md`. Removed "(development)" qualifier from signing in `specs/build-process.md`.

---

## ~~7. LaunchAgent Templates~~ DONE

Removed `{{DEV_MODE}}` variable from CLAUDE.md/AGENTS.md template docs. No dev label logic existed in LaunchAgentManager (already clean). No actual plist template files exist in the repo.

---

## ~~8. Gitignore / Generated Files~~ DONE

Removed `dev_data/`, `dev_logs/`, `dev_config.json` entries from `.gitignore`.

---

**All sections complete. Dev mode removal is finished.**
