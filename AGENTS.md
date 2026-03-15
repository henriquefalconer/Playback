# Playback Agent Guidelines

**Environment Check:**
- **Check current environment first** using `uname -s` to determine if on Darwin (macOS) or Linux
- **If on macOS with Xcode:** All Swift work can proceed (building, development, distribution)
- **If on Linux/Docker:** Xcode unavailable, Swift development/building blocked - Notify user and proceed with non-blocked tasks

**Next Steps:**
- If on macOS: Verify Xcode installation with `xcodebuild -version`, then proceed with Swift development
- If on Linux: Proceed with non-blocked tasks

## Project Nature

- **This is a totally experimental project with no users and no past-state concerns**
- No backwards-compatibility patterns or mentions of how previous versions worked should exist anywhere in the project
- No migration paths, deprecation notices, or "old vs new" comparisons
- When refactoring, delete the old approach entirely — do not preserve it alongside the new one

## Storage Estimates

- **Typical usage produces 10–14 GB/month** of retained video chunks (after processing and compression)
- Cleanup/retention of old chunks is a user preference, NOT a critical system requirement
- Do NOT treat disk storage as an urgent concern or blocker when making architectural decisions

## Development

- **Git authentication in containers:** Check if running in containerized environment (Linux). In such environments, git push may fail due to authentication issues - commits/tags are created locally but require manual push from host system
- **UI test timing:** Use `waitForExistence(timeout:)` for element queries rather than fixed sleep() when possible. Use sleep() only for animations/transitions
- **Build verification for UI tests:** Use `xcodebuild build-for-testing` to verify UI tests compile without running them (fast validation, especially in CI/CD)
- **GUI environment requirement:** UI tests require WindowServer running (check with `ps aux | grep WindowServer`). Tests will fail in headless environments
- **Performance test async issues:** XCTest performance tests cannot reliably measure async operations. SearchController and other async patterns that depend on RunLoop may timeout (110+ seconds). Solution: Use direct SQLite C API queries for synchronous performance measurement instead of async Swift wrappers
- **FTS5 rank function:** FTS5 rank is accessed via `rank` function in WHERE/ORDER BY clauses, not as a column (e.g., `ORDER BY o.timestamp DESC` not `ORDER BY s.rank`)
- **Gating debug output:** Wrap all print() statements with `if Paths.isDevelopment { ... }` to prevent console spam in production builds while preserving debugging information during development
- **Xcode scheme names:** Project only has "Playback" scheme (not "Playback-Development" or "Playback-Release"). Use `-configuration Debug` or `-configuration Release` flags instead
- **Correct build commands:** `cd /Users/vm/Playback/src/Playback && xcodebuild -scheme Playback -configuration Debug build` for development builds
- **Consecutive failure tracking:** Track failure counts in controller, trigger error state after threshold (e.g., 3 consecutive failures) to avoid silent failures and blank screens
- **NotificationCenter for retry actions:** Use NotificationCenter.default.post to communicate from error state views back to data loading layers for retry operations
- **ShellCommand utility pattern:** Created centralized Utilities/ShellCommand.swift to eliminate pipe deadlock pattern. Uses readabilityHandler to drain pipes before waitUntilExit(). All shell command executions should use this utility instead of raw Process() calls
- **Pipe deadlock fix:** NEVER call process.waitUntilExit() before reading pipe data. Always read pipes asynchronously via readabilityHandler or read data before waiting. Classic deadlock: waitUntilExit blocks → pipe fills → process blocks waiting for pipe drain → circular dependency → SIGABRT
- **ConfigWatcher file descriptor management:** Only close file descriptors in ONE location. Use dispatch source cancel handler as the sole owner of fd cleanup. Duplicate close() calls cause SIGABRT on reused file descriptors
- **Bundle identifier consistency:** Actual bundle ID is "com.falconer.Playback", not "com.playback.timeline". Check project.pbxproj PRODUCT_BUNDLE_IDENTIFIER for authoritative value

## Commands

### Building with Xcode (Primary)
Use Xcode for development and production builds. All builds require macOS 26.0+ and Apple Silicon.

- **Development build:** `cd src/Playback && xcodebuild -scheme Playback -configuration Debug build`
- **Release build:** `cd src/Playback && xcodebuild -scheme Playback -configuration Release build`
- **Build output:** `build/Debug/Playback.app` or `build/Release/Playback.app`
- **Clean build:** `cd src/Playback && xcodebuild -scheme Playback clean`
- **Archive:** `cd src/Playback && xcodebuild -scheme Playback -configuration Release archive -archivePath build/Playback.xcarchive`

### Testing
Run tests early and often to catch regressions.

- **All tests:** `cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -destination 'platform=macOS'`
- **Fast tests only:** `cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -only-testing:PlaybackTests/FastTests`
- **Single test:** `cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -only-testing:PlaybackTests/<TestName>`
- **UI tests:** `cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -only-testing:PlaybackUITests`
- **Python tests (all):** `python3 -m pytest src/ -v`
- **Python tests (specific):** `python3 -m pytest src/lib/test_<module>.py -v`
- **Python linting:** `flake8 src/scripts/ --max-line-length=120`
- **Swift linting:** `swiftlint --strict`

### Development Environment Setup
Set up the development environment for first-time setup or after clean checkout.

- **Setup script:** `./src/scripts/setup_dev_env.sh`
- **Install dependencies:** `./src/scripts/install_deps.sh` (installs FFmpeg, Python packages via Homebrew)
- **Create dev directories:** Creates `dev_data/`, `dev_logs/`, generates `dev_config.json`
- **Install dev LaunchAgents:** `./src/scripts/install_dev_launchagents.sh`

### LaunchAgents Management
LaunchAgents run background services. Development agents use separate labels from production.

- **Load recording agent:** `launchctl load ~/Library/LaunchAgents/com.playback.dev.recording.plist`
- **Unload recording agent:** `launchctl unload ~/Library/LaunchAgents/com.playback.dev.recording.plist`
- **Check status:** `launchctl list | grep playback`
- **View logs:** `tail -f dev_logs/recording.log` (development) or `tail -f ~/Library/Logs/Playback/recording.log` (production)
- **Restart agent:** `launchctl unload <plist> && launchctl load <plist>`
- **Validate plist:** `plutil -lint <plist-file>`

## Distribution

Playback uses .zip distribution. No automatic deployment - releases are manual.

### Creating a Release Build
Use the build script for production-ready builds with code signing and notarization.

- **Build release:** `./src/scripts/build_release.sh <version>` (e.g., `./src/scripts/build_release.sh 1.0.0`)
- **Output:** `dist/Playback-<version>.zip` and `dist/Playback-<version>.zip.sha256`

## Local Testing
Before releasing or deploying changes, test locally to verify behavior:

### Development Mode Testing
- **Run app in dev mode:** Launch from Xcode with Debug scheme, automatically uses `dev_data/` and `dev_config.json`
- **Environment variable:** `PLAYBACK_DEV_MODE=1` is set automatically in Debug builds
- **Data isolation:** Development data is completely separate from production (`~/Library/Application Support/Playback/`)
- **Test config changes:** Edit `dev_config.json`, app should hot-reload changes (if implemented)

### Testing Recording Pipeline
1. **Start recording:** Launch app, enable recording from menu bar
2. **Verify screenshots:** Check `dev_data/temp/YYYYMM/DD/` for new screenshot files
3. **Trigger processing:** Run `PLAYBACK_DEV_MODE=1 python3 src/scripts/build_chunks_from_temp.py`
4. **Verify segments:** Check `dev_data/chunks/YYYYMM/DD/` for new video files
5. **Check database:** `sqlite3 dev_data/meta.sqlite3 "SELECT * FROM segments ORDER BY start_ts DESC LIMIT 5;"`
6. **Test playback:** Open timeline viewer, verify video segments play correctly

### Testing UI
- **Menu bar:** Click menu bar icon, verify all menu items appear and function
- **Timeline viewer:** Press Option+Shift+Space, verify timeline appears and video plays
- **Settings:** Open settings, verify all tabs accessible and settings persist
- **Search:** Press Command+F in timeline, enter query, verify results appear
- **Date picker:** Click time bubble, verify date picker appears and jumps work

### Integration Tests
Run the full integration test suite before major releases:
```bash
# Run all integration tests
cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -only-testing:PlaybackTests/IntegrationTests

# Test recording → processing → playback pipeline
cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -only-testing:PlaybackTests/IntegrationTests/testFullPipeline
```

### Database Inspection
Useful SQLite queries for debugging:

```bash
# Open database
sqlite3 ~/Library/Application\ Support/Playback/data/meta.sqlite3

# Check schema version
SELECT * FROM schema_version ORDER BY applied_at DESC LIMIT 1;

# List recent segments
SELECT id, date, start_ts, end_ts, frame_count, file_size_bytes FROM segments ORDER BY start_ts DESC LIMIT 10;

# Check database size
SELECT page_count * page_size / 1024.0 / 1024.0 AS size_mb FROM pragma_page_count(), pragma_page_size();

# Verify WAL mode
PRAGMA journal_mode;

# Check integrity
PRAGMA integrity_check;
```

## Testing Guidelines

### Unit Tests
- **Location:** `src/Playback/PlaybackTests/`
- **Naming:** `test<FeatureName>` (e.g., `testSegmentSelection`)
- **Fast tests:** Tag with `@fast` for pre-commit hook
- **Coverage:** Test configuration loading, path resolution, database queries, state management

### Integration Tests
- **Location:** `src/Playback/PlaybackTests/IntegrationTests.swift`
- **Purpose:** Test end-to-end workflows (recording → processing → playback)
- **Use dev mode:** Tests should use development data directories
- **Cleanup:** Clean up test data after each test

### UI Tests
- **Location:** `src/Playback/PlaybackUITests/`
- **Purpose:** Test user interactions (menu bar clicks, timeline navigation, settings)
- **XCUITest:** Use XCUIApplication for UI automation
- **Accessibility:** Use accessibility identifiers for finding UI elements

### Pre-Commit Tests
Fast tests that run before each commit:
- Swift linting (swiftlint)
- Python linting (flake8)
- Fast unit tests only (<5 seconds)
- Python unit tests

### Pre-Commit Xcode Build Validation (MANDATORY)

**CRITICAL:** Before committing ANY changes involving the Xcode project (Swift source files, project.pbxproj, entitlements, Info.plist, etc.), you MUST perform the following validation:

#### Requirements
- Only required on macOS with Xcode installed
- Skip this check if running on Linux or if `xcodebuild` is not available
- Check environment: `uname -s` (Darwin = macOS, Linux = skip validation)

#### Run the Smoke Test

```bash
./smoke-test.sh
```

This script:
- Checks if running on macOS with Xcode
- Builds the Debug configuration
- Runs the app for 5 seconds to detect initialization crashes
- Reports PASS (exit 0) or FAIL (exit 1)

#### Evaluation
- **Exit 0 + "SMOKE TEST PASSED"** ✅ Validation PASSED - safe to commit
- **Exit 1 + "SMOKE TEST FAILED"** ❌ Validation FAILED - take action:
  - **Option A (Preferred):** Fix the bug before committing
  - **Option B (If fix not immediately possible):** Document the issue in `IMPLEMENTATION_PLAN.md` → "Active Runtime Issues Log" section with:
    - Clear description of the crash/error
    - Stack trace or relevant error output
    - Root cause analysis (if known)
    - Steps to reproduce
    - Proposed fix or workaround
- **Exit 2** ⏭️ Skipped (not on macOS or xcodebuild not available)

## LaunchAgent Management

### LaunchAgentManager
- **Singleton:** Access via `LaunchAgentManager.shared`
- **Agent types:** `.recording` and `.processing` (enum `AgentType`)
- **Plist templates:** Located in `Resources/launchagents/` with `{{VARIABLE}}` substitution
- **Environment-aware:** Automatically uses dev or prod labels and paths

### Commands
```swift
let manager = LaunchAgentManager.shared

// Install agent (creates plist from template)
try manager.installAgent(.recording)

// Load agent (makes launchd aware of it)
try manager.loadAgent(.recording)

// Start agent (begins execution)
try manager.startAgent(.recording)

// Stop agent (halts execution)
try manager.stopAgent(.recording)

// Reload agent (reinstall + reload)
try manager.reloadAgent(.processing)

// Get status
let status = manager.getAgentStatus(.recording)
print("Running: \(status.isRunning), PID: \(status.pid ?? -1)")
```

### Variable Substitution
Templates support these variables:
- `{{LABEL}}` - Agent label (e.g., com.playback.recording)
- `{{SCRIPT_PATH}}` - Path to Python scripts directory
- `{{WORKING_DIR}}` - Working directory for agent
- `{{LOG_PATH}}` - Log file directory
- `{{CONFIG_PATH}}` - Path to config.json
- `{{DATA_DIR}}` - Data directory path
- `{{DEV_MODE}}` - "1" for development, "0" for production
- `{{INTERVAL_SECONDS}}` - Processing interval (processing agent only)
