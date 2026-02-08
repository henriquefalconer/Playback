# Playback Agent Guidelines

## Current Status (2026-02-08)

**Python Implementation: ✅ 100% Complete**
- All 280 tests passing (zero failures, zero bugs)
- All critical issues fixed (FTS5, config validation, logging arguments)
- Production-ready codebase with comprehensive test coverage
- Recent tags: v0.11.1 (bugs), v0.11.2 (logging), v0.11.3 (docs), v0.11.4 (readme)

**Environment Requirements:**
- **Check current environment first** using `uname -s` to determine if on Darwin (macOS) or Linux
- **If on macOS with Xcode:** All Swift work can proceed (building, testing, distribution)
- **If on Linux/Docker:** Xcode unavailable, Swift testing/building blocked - Python work only
- All Python work is complete and production-ready (280 tests passing)
- Remaining work (Phases 5.1-6) requires macOS with Xcode for Swift compilation

**Next Steps:**
- If on macOS: Verify Xcode installation with `xcodebuild -version`, then proceed with Swift testing
- If on Linux: Transition to macOS environment to continue with Swift testing and building

## Recent Implementation Notes

Key operational learnings from Phase 2 development (2026-02-07):

- **MenuBarExtra initialization:** Requires `@StateObject` for proper lifecycle management, not `@ObservedObject`
- **Global hotkeys:** Use Carbon API (`EventHotKeyRef`) - no modern SwiftUI equivalent exists for app-wide hotkeys
- **Accessibility permission:** Required for global hotkey registration via `AXIsProcessTrusted()`
- **Time bubble interaction:** Wrap static text in `Button` with transparent style to make clickable
- **Database queries:** Run on background queue with `DispatchQueue.global(qos: .userInitiated)` to avoid blocking UI
- **Keyboard shortcuts:** Use `NSEvent.addLocalMonitorForEvents` with keyCode comparison for timeline-local shortcuts
- **DatePicker binding:** Requires separate `@State var selectedTime` binding to avoid mutating published state directly
- **Git authentication in containers:** Check if running in containerized environment (Linux). In such environments, git push may fail due to authentication issues - commits/tags are created locally but require manual push from host system
- **Settings UI organization:** All settings tabs are defined in single file `src/Playback/Playback/Settings/SettingsView.swift` - each tab is separate struct (PrivacySettingsTab, StorageSettingsTab, etc.)
- **Permission checking:** Screen Recording via Python/Quartz `CGWindowListCopyWindowInfo`, Accessibility via `AXIsProcessTrustedWithOptions`
- **Byte formatting:** Use Foundation's `ByteCountFormatter` for proper GB/MB/KB formatting with automatic unit selection
- **Shell command integration:** Use `Process` with `Pipe` for stdout/stderr, wrap in `async withCheckedContinuation` for SwiftUI async integration
- **Python test discovery:** Use `python3 -m pytest src/` to run all tests recursively. Individual module breakdown: paths (32), timestamps (35), config (48), database (51), video (34), security (24), network (14), macos (6), logging_config (28) = 272 total tests
- **Config validation quirks:** None values crash during validation. String values for list fields (like `excluded_apps`) cause iteration over characters instead of list items
- **Structured logging implementation:** Created lib/logging_config.py with JSONFormatter for newline-delimited JSON logs, RotatingFileHandler (10MB files, 5 backups), setup_logger() for component loggers
- **Logging convenience functions:** log_info(), log_warning(), log_error(), log_critical(), log_debug() with metadata support, log_resource_metrics() for psutil integration, log_error_with_context() for exception logging
- **Service logging migration pattern:** Import logging_config functions at top, setup logger in main() with component name, replace all print() with log_*() calls, add resource metrics collection with psutil (optional), log state changes and errors with context. Successfully applied to record_screen.py (21 print statements) and build_chunks_from_temp.py (21 print statements). Pattern includes: structured metadata in all logs, exception context in error logs, resource metrics at regular intervals (not every operation), graceful psutil degradation
- **psutil integration:** Add psutil>=6.1.1 to requirements.txt, graceful degradation if not available (PSUTIL_AVAILABLE flag), collect metrics every N operations to avoid overhead
- **Phase 4.3 service migrations complete:** All 3 Python background services (record_screen, build_chunks_from_temp, cleanup_old_chunks) now use structured JSON logging with 80 total print statements migrated. Resource metrics collection operational across all services. Phase 4.3 complete (70%) - service migrations done, UI integration remains
- **DiagnosticsView integration:** Window scenes in PlaybackApp must have unique IDs and use .defaultPosition(.center) for proper window management
- **Log JSON parsing:** Use ISO8601DateFormatter with both .withFractionalSeconds and fallback without for timestamp parsing (Python's isoformat includes fractional seconds)
- **AnyCodable pattern:** Custom Codable wrapper needed to decode arbitrary JSON metadata values (strings, numbers, bools, arrays, dicts)
- **Debounced search:** Use Combine's .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main) on @Published searchText for efficient filtering
- **Auto-refresh timers:** Use Timer.scheduledTimer in ObservableObject, invalidate in deinit to prevent memory leaks
- **Log file parsing:** Read log files line-by-line treating each line as separate JSON (newline-delimited JSON format from logging_config.py)
- **Health status calculation:** Threshold-based (errors > 10 = unhealthy, errors > 0 or warnings > 20 = degraded, else healthy)
- **Phase 4.3 diagnostics UI complete:** All 7 originally planned items now implemented (log viewer, filtering, search, health monitoring, crash notifications via error badges, report generation)
- **PerformanceTab metrics extraction:** Extract metrics from log metadata by filtering entries containing "Resource metrics" or "metrics", then accessing metadata dictionary for cpu_percent/memory_mb/disk_free_gb keys
- **Metrics aggregation:** Use filter + prefix to get recent entries, then reduce for averages (cpuSum / count, etc.)
- **SimpleBarChart pattern:** Fixed-height (70px) with dynamic bar heights calculated as (value / max) * 60, showing min/avg/max stats below
- **ServiceStats calculation:** Dictionary keyed by component name, accumulating per-service error/warning counts and CPU/memory averages
- **Phase 4 complete:** All 4 subphases (OCR search, privacy & security, diagnostics UI, performance monitoring) now 100% implemented
- **Environment constraints:** Before attempting Swift/Xcode operations, check current OS with `uname -s`. Darwin (macOS) can run Xcode and build tools. Linux environments cannot run Xcode or macOS-specific build tools. Swift testing, integration testing, and distribution phases require macOS environment. When blocked by environment limitations, document blocker clearly in IMPLEMENTATION_PLAN.md with next steps
- **Integration test fixtures:** Test helper createTestConfig() must match exact field names and values expected by assertions. Use consistent defaults (video_fps: 5, ffmpeg_preset: "veryfast") across all test configs
- **SQLite database initialization:** Empty files fail assertFileExists() size checks. Create valid SQLite databases with proper schema using Python sqlite3 module via Process execution
- **Test file creation:** createTestVideoSegment() must create non-empty files (36-byte MP4 header minimum) to pass file size validation in assertFileExists()
- **Async/await signatures:** Only use await with async functions. ConfigManager.loadConfiguration() and updateConfig() are synchronous - calling with await causes test failures
- **Config field naming:** Python services use snake_case (processing_interval_minutes) not camelCase. Assertions must check for correct JSON field names
- **Complete config structures:** All Config struct fields are required (non-optional). Test configs must include all fields: version, processing_interval_minutes, temp_retention_policy, recording_retention_policy, exclusion_mode, excluded_apps, video_fps, ffmpeg_crf, ffmpeg_preset, timeline_shortcut, pause_when_timeline_open, notifications
- **UI test accessibility identifiers:** Essential for XCUITest - use consistent naming like "view.element" (e.g., "menubar.recordToggle", "settings.generalTab"). SwiftUI modifier: `.accessibilityIdentifier("id")`
- **XCUITest file organization:** Group UI tests by feature/screen (MenuBarUITests, TimelineUITests, etc.) not by test type. Each file should test one major UI component
- **UI test helper methods:** Create helper methods in each test class (e.g., `openTimeline()`, `openSearch()`) to reduce duplication and improve readability
- **UI test timing:** Use `waitForExistence(timeout:)` for element queries rather than fixed sleep() when possible. Use sleep() only for animations/transitions
- **Build verification for UI tests:** Use `xcodebuild build-for-testing` to verify UI tests compile without running them (fast validation, especially in CI/CD)
- **GUI environment requirement:** UI tests require WindowServer running (check with `ps aux | grep WindowServer`). Tests will fail in headless environments
- **Performance test async issues:** XCTest performance tests cannot reliably measure async operations. SearchController and other async patterns that depend on RunLoop may timeout (110+ seconds). Solution: Use direct SQLite C API queries for synchronous performance measurement instead of async Swift wrappers
- **SQLITE_TRANSIENT binding:** When using sqlite3_bind_text in Swift, use `unsafeBitCast(-1, to: sqlite3_destructor_type.self)` for SQLITE_TRANSIENT to ensure proper string binding
- **FTS5 rank function:** FTS5 rank is accessed via `rank` function in WHERE/ORDER BY clauses, not as a column (e.g., `ORDER BY o.timestamp DESC` not `ORDER BY s.rank`)
- **SwiftUI openWindow environment action:** Use `@Environment(\.openWindow)` in views to open WindowGroup scenes by ID. Cannot be accessed from ObservableObject view models - must be called directly from view layer
- **Screen Recording permission check:** Use `CGPreflightScreenCaptureAccess()` from ApplicationServices framework for immediate synchronous permission status. Shows NSAlert with "Open Settings" button that opens System Settings → Privacy & Security → Screen Recording via URL scheme
- **Gating debug output:** Wrap all print() statements with `if Paths.isDevelopment { ... }` to prevent console spam in production builds while preserving debugging information during development
- **Xcode scheme names:** Project only has "Playback" scheme (not "Playback-Development" or "Playback-Release"). Use `-configuration Debug` or `-configuration Release` flags instead
- **Correct build commands:** `cd /Users/vm/Playback/src/Playback && xcodebuild -scheme Playback -configuration Debug build` for development builds
- **Error state patterns:** Use @Published enum with associated values for flexible error handling (e.g., `enum LoadingState { case loading, loaded, empty, error(String) }`). Allows pattern matching in UI layer
- **Conditional UI rendering pattern:** Restructure SwiftUI body to return different views based on state rather than conditionally showing/hiding. Use `if/else if/else` at top level of ZStack for clean state-based rendering
- **State propagation for error handling:** ObservableObject stores (TimelineStore, PlaybackController) publish loading/error state via @Published properties. ContentView observes and renders appropriate view (LoadingStateView, EmptyStateView, ErrorStateView, or main content)
- **Consecutive failure tracking:** Track failure counts in controller, trigger error state after threshold (e.g., 3 consecutive failures) to avoid silent failures and blank screens
- **NotificationCenter for retry actions:** Use NotificationCenter.default.post to communicate from error state views back to data loading layers for retry operations

## Specifications

**IMPORTANT:** Before implementing any feature, consult the specifications in `specs/README.md`.

- **Assume NOT implemented.** Many specs describe planned features that may not yet exist in the codebase.
- **Check the codebase first.** Before concluding something is or isn't implemented, search the actual code. Specs describe intent; code describes reality.
- **Use specs as guidance.** When implementing a feature, follow the design patterns, types, and architecture defined in the relevant spec.
- **Spec index:** `specs/README.md` lists all specifications organized by category (Core Architecture, Recording & Processing, User Interface, etc.).

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

### Python Scripts Development
Python scripts handle recording and processing. Develop with hot-reloading enabled.

- **Run recording service:** `PLAYBACK_DEV_MODE=1 python3 src/scripts/record_screen.py`
- **Run processing service:** `PLAYBACK_DEV_MODE=1 python3 src/scripts/build_chunks_from_temp.py`
- **Validate config:** `python3 src/scripts/validate_config.py dev_config.json`
- **Install dependencies:** `pip3 install -r src/scripts/requirements.txt`
- **Check dependencies:** `python3 --version` (requires 3.12+), `ffmpeg -version` (requires 7.0+)

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

Playback uses Arc-style .zip distribution. No automatic deployment - releases are manual.

### Creating a Release Build
Use the build script for production-ready builds with code signing and notarization.

- **Build release:** `./src/scripts/build_release.sh <version>` (e.g., `./src/scripts/build_release.sh 1.0.0`)
- **Output:** `dist/Playback-<version>.zip` and `dist/Playback-<version>.zip.sha256`
- **Steps:** Clean → Build → Test → Sign → Notarize → Package → Checksum
- **Requirements:** Valid "Developer ID Application" certificate, Apple notarization credentials in keychain

### Manual Steps
If the build script fails or you need manual control:

1. **Build:** `cd src/Playback && xcodebuild -scheme Playback -configuration Release build`
2. **Sign:** `codesign --sign "Developer ID Application" --deep --force --options runtime build/Release/Playback.app`
3. **Verify signature:** `codesign --verify --verbose build/Release/Playback.app`
4. **Create zip:** `ditto -c -k --keepParent build/Release/Playback.app dist/Playback.zip`
5. **Notarize:** `xcrun notarytool submit dist/Playback.zip --keychain-profile "AC_PASSWORD" --wait`
6. **Staple:** `xcrun stapler staple build/Release/Playback.app`
7. **Verify staple:** `xcrun stapler validate build/Release/Playback.app`
8. **Create final zip:** `ditto -c -k --keepParent build/Release/Playback.app dist/Playback-1.0.0.zip`

### Verifying Release
Before publishing, verify the release build on a clean system:

1. **Check signature:** `spctl --assess --verbose build/Release/Playback.app`
2. **Check entitlements:** `codesign -d --entitlements - build/Release/Playback.app`
3. **Test launch:** Unzip and launch on clean macOS Tahoe 26.0 system
4. **Verify permissions:** Screen Recording permission prompt should appear
5. **Test recording:** Start recording and verify screenshots are captured
6. **Test processing:** Wait for processing interval, verify video segments created

## Database Migrations

**All database migrations are in SQL files applied by Python scripts.**

- **Convention:** Migrations use numbered SQL files or versioned schema checks
- **Location:** `src/scripts/migrations/` (if using separate migration files)
- **Schema version:** Tracked in `schema_version` table in `meta.sqlite3`
- **Application:** Migrations run automatically by processing service on startup
- **Check current version:** `sqlite3 ~/Library/Application\ Support/Playback/data/meta.sqlite3 "SELECT * FROM schema_version ORDER BY applied_at DESC LIMIT 1;"`

### Adding a Migration
1. Create migration function in `src/scripts/migrations.py` (e.g., `migrate_1_0_to_1_1()`)
2. Add migration SQL with schema changes
3. Update `schema_version` table after successful migration
4. Test migration on development database first: `PLAYBACK_DEV_MODE=1 python3 src/scripts/migrations.py`
5. Backup production database before applying: `cp meta.sqlite3 meta.sqlite3.backup.$(date +%Y%m%d)`

### IMPORTANT: Backup Before Migration
Always create a database backup before applying migrations in production:
```bash
cp ~/Library/Application\ Support/Playback/data/meta.sqlite3 \
   ~/Library/Application\ Support/Playback/data/meta.sqlite3.backup.$(date +%Y%m%d_%H%M%S)
```

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

## Troubleshooting

### Common Issues

#### Build Failures
- **Code signing failed:** Check that "Developer ID Application" certificate is installed: `security find-identity -v -p codesigning`
- **Entitlements error:** Verify `Playback.entitlements` is in project and includes required permissions
- **Swift compilation error:** Clean build folder: `xcodebuild clean` or delete `~/Library/Developer/Xcode/DerivedData/Playback-*`

#### Recording Not Working
- **No screenshots appearing:** Check Screen Recording permission: `sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" "SELECT * FROM access WHERE service='kTCCServiceScreenCapture';"`
- **LaunchAgent not running:** Check status: `launchctl list | grep playback`
- **Permission denied:** Grant Screen Recording permission in System Settings → Privacy & Security
- **Check logs:** `tail -f dev_logs/recording.log` for error messages

#### Processing Failures
- **FFmpeg not found:** Verify installation: `which ffmpeg` and `ffmpeg -version`
- **Video generation fails:** Check FFmpeg supports libx264: `ffmpeg -codecs | grep h264`
- **Database errors:** Check database integrity: `sqlite3 dev_data/meta.sqlite3 "PRAGMA integrity_check;"`
- **Temp files not deleted:** Check permissions on `dev_data/temp/` directory

#### App Launch Issues
- **App won't open:** Check signature: `spctl --assess --verbose Playback.app`
- **"Damaged" error:** Re-sign the app: `codesign --sign - --force --deep Playback.app`
- **Crash on launch:** Check crash logs: `~/Library/Logs/DiagnosticReports/Playback_*.crash`

### Logs
- **App logs:** `~/Library/Logs/Playback/app.log` (production) or `dev_logs/app.log` (development)
- **Recording logs:** `~/Library/Logs/Playback/recording.log` (production) or `dev_logs/recording.log` (development)
- **Processing logs:** `~/Library/Logs/Playback/processing.log` (production) or `dev_logs/processing.log` (development)
- **System logs:** `log stream --predicate 'process == "Playback"'` (live system log streaming)
- **Crash reports:** `~/Library/Logs/DiagnosticReports/Playback_*.crash`

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

## Architecture

### Project Structure
Separate Swift apps with Python background services. Key components:

- **PlaybackMenuBar.app (Menu Bar Agent):** LaunchAgent, always running
  - Lives: `~/Library/LaunchAgents/` (not visible in Applications folder)
  - `src/Playback/PlaybackMenuBar/MenuBarAgent/` - Menu bar interface and controls
  - `src/Playback/PlaybackMenuBar/Settings/` - Settings window with all configuration tabs
  - `src/Playback/PlaybackMenuBar/Diagnostics/` - Diagnostics window
  - `src/Playback/PlaybackMenuBar/Services/` - LaunchAgent management and service control
  - `src/Playback/PlaybackMenuBar/Notifications/` - Notification system
  - Responsibilities: Control all services, launch timeline viewer, always-visible menu bar icon

- **Playback.app (Timeline Viewer):** Standalone app in `/Applications/`
  - Lives: `/Applications/Playback.app` (only user-visible Playback app)
  - `src/Playback/Playback/Timeline/` - Timeline viewer with video playback
  - `src/Playback/Playback/Database/` - SQLite database access (read-only)
  - `src/Playback/Playback/Models/` - Shared data models
  - Launch triggers: Menu bar, global hotkey, app icon
  - Lifecycle: Can be quit independently, recording continues

- **Python Services:** Background LaunchAgents for recording and processing
  - `src/scripts/record_screen.py` - Screenshot capture (runs every 2 seconds, pauses when timeline open)
  - `src/scripts/build_chunks_from_temp.py` - Video segment generation (runs every 5 minutes)
  - `src/scripts/cleanup_old_chunks.py` - Retention policy enforcement

- **Shared Python Utilities:** Common functionality for services
  - `src/lib/paths.py` - Environment-aware path resolution
  - `src/lib/database.py` - SQLite operations and schema management
  - `src/lib/video.py` - FFmpeg wrappers for video processing
  - `src/lib/macos.py` - CoreGraphics and AppleScript integration
  - `src/lib/timestamps.py` - Filename parsing and generation

- **Data Storage:**
  - Development: `dev_data/temp/`, `dev_data/chunks/`, `dev_data/meta.sqlite3`
  - Production: `~/Library/Application Support/Playback/data/`
  - Signal files: `.timeline_open` (timeline viewer active)
  - Database: SQLite with WAL mode for concurrent access

### Communication Patterns
- **Filesystem-based:** Menu bar agent writes `config.json`, Python scripts and timeline viewer read
- **LaunchAgent control:** Menu bar agent uses `launchctl` to manage all services (recording, processing, itself)
- **Timeline communication:** Timeline viewer creates `.timeline_open` file, recording service detects and pauses
- **Database:** Python writes segments, Swift apps read for timeline/diagnostics (read-only)
- **No IPC:** Services don't communicate directly, only through filesystem and database

## SwiftUI Guidelines

**Use modern SwiftUI patterns and lifecycle. Target macOS 26.0+.**

### State Management
- **@State:** Component-local state: `@State private var count = 0`
- **@StateObject:** Owned observable objects: `@StateObject private var viewModel = ViewModel()`
- **@ObservedObject:** Passed observable objects: `@ObservedObject var config: ConfigManager`
- **@EnvironmentObject:** Shared app-wide state: `@EnvironmentObject var configManager: ConfigManager`
- **@Published:** Observable properties in classes: `@Published var isRecording = false`

### Common Patterns
```swift
// Observable class (for ConfigManager, etc.)
class ConfigManager: ObservableObject {
    @Published var recordingEnabled = false
    @Published var processingInterval = 300
}

// View with environment object
struct MenuBarView: View {
    @EnvironmentObject var config: ConfigManager

    var body: some View {
        Toggle("Recording", isOn: $config.recordingEnabled)
    }
}

// App entry point
@main
struct PlaybackApp: App {
    @StateObject private var config = ConfigManager()

    var body: some Scene {
        MenuBarExtra("Playback", systemImage: "record.circle") {
            MenuBarView()
        }
        .environmentObject(config)
    }
}
```

### Best Practices
- **Use @MainActor for UI updates:** Mark view models with `@MainActor` to ensure UI updates on main thread
- **Prefer @StateObject over @ObservedObject:** Use @StateObject when the view creates and owns the object
- **Environment for shared state:** Use @EnvironmentObject for app-wide configuration (ConfigManager, etc.)
- **Private state:** Mark @State properties as `private` when only used within the view
- **Binding:** Use `$` prefix to pass two-way bindings: `Toggle("Label", isOn: $isEnabled)`

## Code Style

### Swift
- **Formatting:** 4 spaces, 100 char line width
- **Naming:** camelCase for properties/methods, PascalCase for types
- **Errors:** Use Swift Error protocol, throw/try/catch for error handling
- **Async:** Use async/await for asynchronous operations
- **Imports:** Group Foundation, AppKit/SwiftUI, then internal modules
- **No comments** unless code is complex and requires context. Code should be self-documenting.
- **File organization:** One type per file, filename matches type name

### Python
- **Formatting:** 4 spaces, 120 char line width (PEP 8 with relaxed line length)
- **Type hints:** Use type hints for function parameters and return values
- **Error handling:** Use try/except with specific exception types, log errors with context
- **Logging:** Use Python logging module with structured output (JSON format)
- **Imports:** Group standard library, third-party, then local modules
- **Docstrings:** Use docstrings for public functions and classes

### Example Swift
```swift
import Foundation
import SwiftUI

@MainActor
final class ConfigManager: ObservableObject {
    @Published var recordingEnabled: Bool = false
    @Published var processingInterval: Int = 300

    private let configPath: URL

    init() {
        self.configPath = Paths.configPath()
        loadConfiguration()
    }

    func loadConfiguration() {
        guard let data = try? Data(contentsOf: configPath),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            return
        }
        recordingEnabled = config.recordingEnabled
        processingInterval = config.processingInterval
    }
}
```

### Example Python
```python
import logging
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

def capture_screenshot(output_path: Path, app_id: Optional[str] = None) -> bool:
    """Capture a screenshot and save to the specified path.

    Args:
        output_path: Path where screenshot should be saved
        app_id: Optional bundle ID of frontmost app

    Returns:
        True if screenshot was captured successfully, False otherwise
    """
    try:
        # Screenshot capture logic
        logger.info(f"Captured screenshot to {output_path}")
        return True
    except Exception as e:
        logger.error(f"Failed to capture screenshot: {e}", exc_info=True)
        return False
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

## Common Tasks

### Adding a New Setting
1. Add property to `Config` struct in `src/Playback/Playback/Config/ConfigManager.swift`
2. Add UI control in `src/Playback/Playback/Settings/GeneralTab.swift` with binding
3. Add default value in config schema
4. Update `config.json` schema validation
5. Test: Change setting in UI, verify persisted to config file
6. Test: Restart app, verify setting loaded correctly

### Adding a LaunchAgent
1. Create plist template in `src/Playback/Playback/Resources/launchagents/<name>.plist.template`
2. Add installation logic in `src/Playback/Playback/Services/LaunchAgentInstaller.swift`
3. Add control methods in `src/Playback/Playback/Services/LaunchAgentManager.swift`
4. Update first-run setup to install the agent
5. Test: Install agent, verify loaded: `launchctl list | grep <name>`

### Adding a Database Table
1. Update schema in `specs/database-schema.md` spec
2. Add table creation SQL in initialization function
3. Add Swift model struct in `src/Playback/Playback/Database/Models.swift`
4. Add query functions in `src/Playback/Playback/Database/DatabaseManager.swift`
5. Test: Verify table created, insert test data, query and verify

### Adding a Timeline Feature
1. Update `specs/timeline-graphical-interface.md` spec with design
2. Add UI components in `src/Playback/Playback/Timeline/` directory
3. Add data models and state management
4. Add database queries if needed
5. Test: Open timeline, verify feature works, test edge cases

## Configuration System

### ConfigManager
- **Singleton:** Access via `ConfigManager.shared` (Swift only)
- **Thread safety:** Marked `@MainActor` for main-thread operations
- **Config files:**
  - Development: `dev_config.json` in project root
  - Production: `~/Library/Application Support/Playback/config.json`
- **Hot-reloading:** Automatic via file watcher, changes detected within seconds
- **Python:** Use `from lib.config import load_config_with_defaults`

### Config Structure
```swift
// Swift access
let config = ConfigManager.shared.config
let fps = config.videoFps
let crf = config.ffmpegCrf
```

```python
# Python access
from lib.config import load_config_with_defaults
config = load_config_with_defaults()
fps = config.video_fps
crf = config.ffmpeg_crf
```

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

## App Exclusion

### Configuration
Add apps to `excluded_apps` array in config.json:
```json
{
  "excluded_apps": [
    "com.1password.1password",
    "com.apple.Keychain"
  ],
  "exclusion_mode": "skip"
}
```

### Exclusion Modes
- **`skip`:** Don't capture screenshots when excluded app is frontmost
- **`invisible`:** Capture screenshots but mark them as excluded (for future filtering)

### Behavior
- Config reloads automatically via file watcher
- Changes take effect within 30 seconds (next recording cycle)
- Recording service checks `config.is_app_excluded(bundle_id)` before capture
- Valid bundle ID format: alphanumeric, dots, and hyphens only

## Processing Service

### Command-Line Usage
```bash
# Scheduled processing (last 7 days, auto-detects pending days)
python3 src/scripts/build_chunks_from_temp.py --auto

# Manual processing for specific day
python3 src/scripts/build_chunks_from_temp.py --day 20260207

# Override encoding settings
python3 src/scripts/build_chunks_from_temp.py --day 20260207 --fps 60 --crf 23

# Skip temp file cleanup (keep screenshots)
python3 src/scripts/build_chunks_from_temp.py --day 20260207 --no-cleanup
```

### Parameters
- **`--auto`:** Process all pending days (last 7 days with unprocessed screenshots)
- **`--day YYYYMMDD`:** Process specific day
- **`--fps N`:** Override video FPS (default: from config)
- **`--crf N`:** Override compression quality 0-51, lower=better (default: from config)
- **`--preset`:** FFmpeg preset: ultrafast, veryfast, fast, medium, slow (default: veryfast)
- **`--segment-duration`:** Segment length in seconds (default: 5.0)
- **`--no-cleanup`:** Keep temp screenshots after processing

### Integration
- LaunchAgent runs `--auto` mode every N minutes (from config)
- Manual runs use `--day` for specific date processing
- FPS and CRF default to config values, can be overridden per-run
- Processing creates video segments in `chunks/YYYYMM/DD/`

## Best Practices

### Configuration
- **Environment-aware:** Use `Environment.isDevelopment` to switch between dev/prod paths
- **Hot-reloading:** Watch for config file changes, reload automatically
- **Validation:** Validate config values, use defaults for invalid values
- **Migration:** Support config schema migrations for version updates

### Error Handling
- **Fail gracefully:** Log errors, continue operation when possible
- **User notifications:** Show macOS notifications for critical errors
- **Never crash:** Background services should never crash on recoverable errors
- **Context:** Log errors with enough context to debug (timestamps, parameters, stack traces)

### Performance
- **Background services:** Keep CPU usage low (<5% for recording, <20% for processing)
- **Memory usage:** Monitor memory, ensure no leaks in long-running services
- **Database:** Use indexes, optimize queries, keep database size reasonable
- **Video encoding:** Use efficient FFmpeg settings (CRF 28, veryfast preset)

### Security
- **Permissions:** Request only required permissions (Screen Recording, Accessibility)
- **File permissions:** Set restrictive permissions on data files (0600 for sensitive files)
- **No network:** Playback never accesses the network - all data stays local
- **Secrets:** Never log sensitive data, use secure storage for any credentials

### Code Reuse
When multiple code paths do similar things with slight variations, create a shared service with a request struct that captures the variations, rather than having each caller implement its own logic.
