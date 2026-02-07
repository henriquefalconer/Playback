# Playback Agent Guidelines

## Specifications

**IMPORTANT:** Before implementing any feature, consult the specifications in `specs/README.md`.

- **Assume NOT implemented.** Many specs describe planned features that may not yet exist in the codebase.
- **Check the codebase first.** Before concluding something is or isn't implemented, search the actual code. Specs describe intent; code describes reality.
- **Use specs as guidance.** When implementing a feature, follow the design patterns, types, and architecture defined in the relevant spec.
- **Spec index:** `specs/README.md` lists all specifications organized by category (Core Architecture, Recording & Processing, User Interface, etc.).

## Commands

### Building with Xcode (Primary)
Use Xcode for development and production builds. All builds require macOS 26.0+ and Apple Silicon.

- **Development build:** `xcodebuild -scheme Playback-Development -configuration Debug`
- **Release build:** `xcodebuild -scheme Playback-Release -configuration Release`
- **Build output:** `build/Debug/Playback.app` or `build/Release/Playback.app`
- **Clean build:** `xcodebuild clean -scheme Playback-Development`
- **Archive:** `xcodebuild archive -scheme Playback-Release -archivePath build/Playback.xcarchive`

### Testing
Run tests early and often to catch regressions.

- **All tests:** `xcodebuild test -scheme Playback-Development -destination 'platform=macOS'`
- **Fast tests only:** `xcodebuild test -scheme Playback-Development -only-testing:PlaybackTests/FastTests`
- **Single test:** `xcodebuild test -scheme Playback-Development -only-testing:PlaybackTests/<TestName>`
- **UI tests:** `xcodebuild test -scheme Playback-Development -only-testing:PlaybackUITests`
- **Python tests:** `python3 -m pytest src/scripts/tests/ -v`
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

1. **Build:** `xcodebuild -scheme Playback-Release -configuration Release`
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
xcodebuild test -scheme Playback-Development -only-testing:PlaybackTests/IntegrationTests

# Test recording → processing → playback pipeline
xcodebuild test -scheme Playback-Development -only-testing:PlaybackTests/IntegrationTests/testFullPipeline
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
Swift app with Python background services. Key components:

- **Playback.app:** Single unified SwiftUI app with menu bar + timeline viewer
  - `src/Playback/Playback/MenuBar/` - Menu bar interface and controls
  - `src/Playback/Playback/Timeline/` - Timeline viewer with video playback
  - `src/Playback/Playback/Settings/` - Settings window with all configuration tabs
  - `src/Playback/Playback/Config/` - Configuration management (ConfigManager, Environment, Paths)
  - `src/Playback/Playback/Database/` - SQLite database access layer
  - `src/Playback/Playback/Services/` - LaunchAgent management and service control
  - `src/Playback/Playback/Search/` - OCR and text search functionality

- **Python Scripts:** Background services for recording and processing
  - `src/scripts/record_screen.py` - Screenshot capture (runs every 2 seconds)
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
  - Database: SQLite with WAL mode for concurrent access

### Communication Patterns
- **Filesystem-based:** App writes `config.json`, Python scripts read on startup
- **LaunchAgent control:** App uses `launchctl` to manage Python services
- **Database:** Python writes segments, Swift reads for timeline display (read-only)
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
