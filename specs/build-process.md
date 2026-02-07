# Build Process Specification

**Component:** Build System
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

Playback uses a unified build system that supports both development (hot-reloading, isolated data) and production (optimized, user-installed) environments. This specification defines the build process, testing pipeline, and deployment workflow.

## Architecture

### Single Unified App

**Playback.app** contains:
- Timeline viewer (fullscreen video playback)
- Menu bar interface (always running)
- Settings window
- Diagnostics viewer
- Uninstall functionality

**No separate apps** - everything in one bundle for simplicity.

## Development vs Production

### Development Environment

**Purpose:** Fast iteration with hot-reloading, isolated from production data

**Characteristics:**
- Separate data directory (dev_data/)
- Hot-reloading for Swift code changes
- Debug symbols enabled
- Verbose logging
- Mock data generation
- No code signing required

**Data Isolation:**
```
project/
├── dev_data/               # Development data (gitignored)
│   ├── temp/
│   ├── chunks/
│   └── meta.sqlite3
└── scripts/
    └── dev_config.json     # Development configuration
```

### Production Environment

**Purpose:** Optimized, signed, notarized app for end users

**Characteristics:**
- User data in standard locations
- Optimized build (Release configuration)
- Code signed and notarized
- Production logging levels
- LaunchAgents for background services

**Data Locations:**
```
~/Library/Application Support/Playback/
├── config.json
└── data/
    ├── temp/
    ├── chunks/
    └── meta.sqlite3
```

## Build Configuration

### Xcode Project Structure

```
Playback/
├── Playback.xcodeproj
├── Playback/                    # Main app target
│   ├── PlaybackApp.swift        # Main app entry point
│   ├── MenuBar/                 # Menu bar UI
│   │   ├── MenuBarView.swift
│   │   └── StatusBarController.swift
│   ├── Timeline/                # Timeline viewer
│   │   ├── TimelineView.swift
│   │   ├── VideoPlayer.swift
│   │   └── DateTimePicker.swift
│   ├── Settings/                # Settings window
│   │   ├── SettingsWindow.swift
│   │   └── UninstallView.swift
│   ├── Diagnostics/             # Diagnostics viewer
│   │   └── DiagnosticsWindow.swift
│   ├── Services/                # LaunchAgent management
│   │   ├── RecordingService.swift
│   │   └── ProcessingService.swift
│   ├── Search/                  # OCR search
│   │   └── SearchController.swift
│   ├── Config/                  # Configuration management
│   │   └── ConfigManager.swift
│   └── Resources/
│       ├── Assets.xcassets
│       └── Info.plist
├── PlaybackTests/               # Unit tests
└── PlaybackUITests/             # UI tests
```

### Build Schemes

**1. Development Scheme**
- Configuration: Debug
- Code signing: Development
- Defines: `DEBUG`, `DEVELOPMENT`
- Data directory: `dev_data/`
- Hot-reloading: Enabled

**2. Production Scheme**
- Configuration: Release
- Code signing: Developer ID
- Optimization: -O (full optimization)
- Data directory: `~/Library/Application Support/Playback/data/`
- Notarization: Required

### Build Settings

**Development (Debug):**
```xml
<key>SWIFT_ACTIVE_COMPILATION_CONDITIONS</key>
<string>DEBUG DEVELOPMENT</string>

<key>SWIFT_OPTIMIZATION_LEVEL</key>
<string>-Onone</string>

<key>GCC_PREPROCESSOR_DEFINITIONS</key>
<array>
    <string>DEBUG=1</string>
    <string>DEVELOPMENT=1</string>
</array>

<key>ENABLE_TESTABILITY</key>
<true/>
```

**Production (Release):**
```xml
<key>SWIFT_ACTIVE_COMPILATION_CONDITIONS</key>
<string>RELEASE</string>

<key>SWIFT_OPTIMIZATION_LEVEL</key>
<string>-O</string>

<key>ENABLE_TESTABILITY</key>
<false/>

<key>CODE_SIGN_IDENTITY</key>
<string>Developer ID Application</string>

<key>CODE_SIGN_STYLE</key>
<string>Manual</string>
```

## Hot-Reloading

### Swift Hot-Reloading

**Using:** Swift Package Manager + InjectionIII (development only)

**Setup:**
```swift
#if DEVELOPMENT
import InjectionIII

@main
struct PlaybackApp: App {
    init() {
        // Enable hot-reloading in development
        Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle")?.load()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .enableInjection() // SwiftUI hot-reloading
        }
    }
}
#endif
```

**Alternative:** Use Xcode's built-in "Debug" → "Inject Swift Source" (Shift+Cmd+M)

### Python Script Hot-Reloading

**Development Mode:**
- Scripts run directly from source directory
- Changes take effect on next execution
- No need to rebuild/reinstall

**Implementation:**
```python
# scripts/record_screen.py

import os

# Use dev_data/ in development
if os.getenv('PLAYBACK_DEV_MODE'):
    DATA_DIR = Path(__file__).parent.parent / "dev_data"
else:
    DATA_DIR = Path.home() / "Library/Application Support/Playback/data"
```

## Build Process

### Development Build

**Command:**
```bash
# Build development version
xcodebuild \
  -project Playback.xcodeproj \
  -scheme Playback-Development \
  -configuration Debug \
  -derivedDataPath build/ \
  build

# Run development version
open build/Debug/Playback.app

# Or use Xcode: Cmd+R
```

**Automatic Steps:**
1. Compile Swift sources
2. Copy Python scripts to Resources/
3. Generate dev_data/ directory structure
4. Create dev_config.json with development settings
5. Install development LaunchAgents (pointing to dev environment)

**Development LaunchAgent Example:**
```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PLAYBACK_DEV_MODE</key>
    <string>1</string>
    <key>PLAYBACK_DATA_DIR</key>
    <string>/path/to/project/dev_data</string>
</dict>
```

### Production Build

**Command:**
```bash
# Build production version
xcodebuild \
  -project Playback.xcodeproj \
  -scheme Playback-Production \
  -configuration Release \
  -derivedDataPath build/ \
  archive \
  -archivePath build/Playback.xcarchive

# Export app
xcodebuild \
  -exportArchive \
  -archivePath build/Playback.xcarchive \
  -exportPath build/Release \
  -exportOptionsPlist exportOptions.plist
```

**Automatic Steps:**
1. Compile Swift sources (optimized)
2. Embed Python scripts in Resources/
3. Code sign with Developer ID
4. Create installer package (.pkg)
5. Submit for notarization
6. Staple notarization ticket

**Build Script:**
```bash
#!/bin/bash
# scripts/build_release.sh

set -e

VERSION="1.0.0"
BUNDLE_ID="com.playback.Playback"

echo "Building Playback v${VERSION}..."

# Clean
rm -rf build/

# Build archive
xcodebuild \
  -project Playback.xcodeproj \
  -scheme Playback-Production \
  -configuration Release \
  -archivePath build/Playback.xcarchive \
  archive

# Export app
xcodebuild \
  -exportArchive \
  -archivePath build/Playback.xcarchive \
  -exportPath build/Release \
  -exportOptionsPlist exportOptions.plist

# Sign
codesign --sign "Developer ID Application" \
  --deep --force \
  --options runtime \
  build/Release/Playback.app

# Create package
pkgbuild \
  --root build/Release \
  --identifier ${BUNDLE_ID} \
  --version ${VERSION} \
  --install-location /Applications \
  --scripts scripts/pkg/ \
  build/Playback-${VERSION}.pkg

# Notarize
xcrun notarytool submit build/Playback-${VERSION}.pkg \
  --apple-id "developer@example.com" \
  --team-id "TEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple
xcrun stapler staple build/Playback-${VERSION}.pkg

echo "✓ Build complete: build/Playback-${VERSION}.pkg"
```

## Testing

### Test Levels

**1. Unit Tests** - Fast, isolated
**2. Integration Tests** - Component interactions
**3. UI Tests** - End-to-end user flows
**4. Pre-commit Tests** - Subset run before each commit

### Unit Tests

**Location:** `PlaybackTests/`

**Coverage:**
- Configuration loading/saving
- Database queries (segments, appsegments, OCR)
- Video segment selection logic
- Time mapping (absolute ↔ video offset)
- OCR text extraction
- Search query parsing

**Example:**
```swift
// PlaybackTests/TimelineStoreTests.swift

import XCTest
@testable import Playback

class TimelineStoreTests: XCTestCase {
    func testSegmentSelection() {
        let store = TimelineStore(dbPath: ":memory:")

        // Add test segments
        store.addSegment(id: "seg1", startTS: 100, endTS: 200)
        store.addSegment(id: "seg2", startTS: 300, endTS: 400)

        // Test: timestamp inside segment
        let (segment, offset) = store.segment(for: 150)!
        XCTAssertEqual(segment.id, "seg1")

        // Test: timestamp in gap (should return closest)
        let (segment2, offset2) = store.segment(for: 250)!
        XCTAssertEqual(segment2.id, "seg2")
    }

    func testTimeMapping() {
        let segment = Segment(
            id: "test",
            startTS: 1000,
            endTS: 1150,  // 150s real time
            frameCount: 150,
            fps: 30,
            videoURL: URL(fileURLWithPath: "test.mp4")
        )

        // 30fps * 150 frames = 5s video
        XCTAssertEqual(segment.videoDuration, 5.0, accuracy: 0.01)

        // Midpoint of timeline (1075) should map to midpoint of video (2.5s)
        let offset = segment.videoOffset(forAbsoluteTime: 1075)
        XCTAssertEqual(offset, 2.5, accuracy: 0.01)
    }
}
```

**Run:**
```bash
xcodebuild test \
  -project Playback.xcodeproj \
  -scheme Playback-Development \
  -destination 'platform=macOS'
```

### Integration Tests

**Tests:**
- Recording service → Processing service → Database
- Settings change → LaunchAgent reload
- Manual processing trigger → Process completion
- App exclusion configuration → Screenshot skipping

**Example:**
```swift
// PlaybackTests/IntegrationTests.swift

func testRecordingToProcessingFlow() async throws {
    // 1. Start recording service
    let recording = RecordingService(devMode: true)
    try recording.start()

    // 2. Wait for screenshots
    try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

    // 3. Stop recording
    recording.stop()

    // 4. Run processing
    let processing = ProcessingService(devMode: true)
    try await processing.processAll()

    // 5. Verify database has segments
    let db = Database(path: "dev_data/meta.sqlite3")
    let segments = try db.querySegments()
    XCTAssertGreaterThan(segments.count, 0)
}
```

### UI Tests

**Location:** `PlaybackUITests/`

**Tests:**
- Launch app → Menu bar appears
- Toggle recording → Status icon changes
- Open settings → All tabs accessible
- Open timeline → Video plays
- Date/time picker → Navigation works
- Search (Command+F) → Results appear

**Example:**
```swift
// PlaybackUITests/TimelineUITests.swift

func testDateTimePicker() {
    let app = XCUIApplication()
    app.launch()

    // Open timeline (Option+Shift+Space)
    app.typeKey(" ", modifierFlags: [.option, .shift])

    // Wait for timeline to appear
    XCTAssertTrue(app.windows["Timeline"].waitForExistence(timeout: 5))

    // Click time bubble
    app.staticTexts.matching(NSPredicate(format: "label CONTAINS '2:30'")).firstMatch.click()

    // Date picker should appear
    XCTAssertTrue(app.windows["Date Picker"].waitForExistence(timeout: 2))

    // Select a date
    app.datePickers.firstMatch.click()

    // Verify video jumped
    // ...
}
```

### Pre-Commit Tests

**Purpose:** Fast subset of tests run before every commit

**Configuration:** `.git/hooks/pre-commit`

```bash
#!/bin/bash
# .git/hooks/pre-commit

set -e

echo "Running pre-commit tests..."

# 1. Swift lint
echo "→ Running SwiftLint..."
if which swiftlint >/dev/null; then
  swiftlint --strict --quiet
else
  echo "⚠️  SwiftLint not installed. Run: brew install swiftlint"
fi

# 2. Python lint
echo "→ Running flake8..."
if which flake8 >/dev/null; then
  flake8 scripts/ --max-line-length=120
else
  echo "⚠️  flake8 not installed. Run: pip install flake8"
fi

# 3. Unit tests (fast only, tagged with @fast)
echo "→ Running fast unit tests..."
xcodebuild test \
  -project Playback.xcodeproj \
  -scheme Playback-Development \
  -destination 'platform=macOS' \
  -only-testing:PlaybackTests/FastTests \
  -quiet

# 4. Python tests
echo "→ Running Python tests..."
python3 -m pytest scripts/tests/ -v --tb=short

# 5. Configuration validation
echo "→ Validating config schema..."
python3 scripts/validate_config.py

echo "✓ All pre-commit tests passed"
```

**Installation:**
```bash
# Make pre-commit hook executable
chmod +x .git/hooks/pre-commit

# Or use pre-commit framework
pip install pre-commit
pre-commit install
```

### Continuous Integration

**GitHub Actions:** `.github/workflows/test.yml`

```yaml
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest

    steps:
      - uses: actions/checkout@v3

      - name: Setup Xcode
        uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: latest

      - name: Install dependencies
        run: |
          brew install ffmpeg python@3.10
          pip3 install flake8 pytest

      - name: Lint Swift
        run: swiftlint --strict

      - name: Lint Python
        run: flake8 scripts/ --max-line-length=120

      - name: Run unit tests
        run: |
          xcodebuild test \
            -project Playback.xcodeproj \
            -scheme Playback-Development \
            -destination 'platform=macOS'

      - name: Run Python tests
        run: python3 -m pytest scripts/tests/ -v

      - name: Build production
        run: ./scripts/build_release.sh
```

## Environment Configuration

### Development Config

**File:** `dev_config.json` (gitignored)

```json
{
  "version": "1.0",
  "environment": "development",
  "recording_enabled": true,
  "processing_interval_minutes": 1,
  "data_directory": "dev_data/",
  "log_directory": "dev_logs/",
  "log_level": "DEBUG",
  "mock_screenshots": false,
  "hot_reload": true
}
```

### Production Config

**File:** `~/Library/Application Support/Playback/config.json`

```json
{
  "version": "1.0",
  "environment": "production",
  "recording_enabled": false,
  "processing_interval_minutes": 5,
  "data_directory": "~/Library/Application Support/Playback/data/",
  "log_directory": "~/Library/Logs/Playback/",
  "log_level": "INFO"
}
```

### Environment Detection

```swift
// Config/Environment.swift

enum Environment {
    case development
    case production

    static var current: Environment {
        #if DEVELOPMENT
        return .development
        #else
        return .production
        #endif
    }

    var dataDirectory: URL {
        switch self {
        case .development:
            return Bundle.main.resourceURL!
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("dev_data")
        case .production:
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Playback/data")
        }
    }
}
```

## Dependencies

### Build Dependencies

- Xcode 15.0+
- Swift 5.9+
- Python 3.8+
- FFmpeg 4.0+

**Install:**
```bash
brew install ffmpeg python@3.10
pip3 install pyobjc-framework-Vision pyobjc-framework-Quartz
```

### Optional (Development)

- SwiftLint (linting)
- InjectionIII (hot-reloading)
- pre-commit (git hooks)

**Install:**
```bash
brew install swiftlint
brew install --cask injectioniii
pip3 install pre-commit flake8 pytest
```

## Troubleshooting

### Build Failures

**Issue:** "Code signing failed"
**Solution:** Check Developer ID certificate in Keychain

**Issue:** "Python scripts not found"
**Solution:** Ensure scripts/ copied to Resources in Build Phases

**Issue:** "Database not found"
**Solution:** Create dev_data/ directory: `mkdir -p dev_data/{temp,chunks}`

### Test Failures

**Issue:** UI tests timeout
**Solution:** Increase timeout or run on faster machine

**Issue:** Integration tests fail (LaunchAgent not found)
**Solution:** Install development LaunchAgents: `./scripts/install_dev_launchagents.sh`

## Performance Benchmarks

### Build Times

- **Development build:** ~30 seconds (incremental: ~5 seconds)
- **Production build:** ~2 minutes (full rebuild + notarization: ~10 minutes)

### Test Times

- **Unit tests:** ~5 seconds
- **Integration tests:** ~30 seconds
- **UI tests:** ~2 minutes
- **Pre-commit tests:** ~15 seconds

## Future Enhancements

1. **Incremental Builds** - Cache unchanged modules
2. **Parallel Testing** - Run tests concurrently
3. **Test Coverage Reports** - Track code coverage over time
4. **Performance Testing** - Automated performance regression detection
5. **Docker Builds** - Reproducible builds in containers
