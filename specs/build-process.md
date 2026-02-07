# Build Process Implementation Plan

**Component:** Build System & Testing Pipeline
**Version:** 1.0
**Last Updated:** 2026-02-07

## Implementation Checklist

### Xcode Project Configuration
- [ ] Create Xcode project with unified app target
  - Location: `src/Playback/Playback.xcodeproj`
  - Target: Playback (single app bundle)
  - Minimum deployment: macOS 26.0 (Tahoe)
  - Architecture: Apple Silicon only

- [ ] Configure Debug scheme (Development)
  - Build configuration: Debug
  - Code signing: Development (ad-hoc)
  - Compilation conditions: `DEBUG`, `DEVELOPMENT`
  - Optimization level: `-Onone`
  - Enable testability: true

- [ ] Configure Release scheme (Production)
  - Build configuration: Release
  - Code signing: Developer ID Application
  - Optimization level: `-O`
  - Enable testability: false
  - Hardened runtime: enabled

### Build Settings Configuration
- [ ] Set development build settings
  - `SWIFT_ACTIVE_COMPILATION_CONDITIONS` = "DEBUG DEVELOPMENT"
  - `SWIFT_OPTIMIZATION_LEVEL` = "-Onone"
  - `GCC_PREPROCESSOR_DEFINITIONS` = "DEBUG=1 DEVELOPMENT=1"
  - `ENABLE_TESTABILITY` = true

- [ ] Set production build settings
  - `SWIFT_ACTIVE_COMPILATION_CONDITIONS` = "RELEASE"
  - `SWIFT_OPTIMIZATION_LEVEL` = "-O"
  - `CODE_SIGN_IDENTITY` = "Developer ID Application"
  - `CODE_SIGN_STYLE` = "Manual"
  - `ENABLE_HARDENED_RUNTIME` = true

- [ ] Configure copy resources build phase
  - Copy Python scripts from `src/scripts/` to `Contents/Resources/scripts/`
  - Include: record_screen.py, build_chunks_from_temp.py
  - Preserve directory structure

### Development Build Setup
- [ ] Create development build script
  - Location: `src/scripts/build_dev.sh`
  - Command: `xcodebuild -scheme Playback-Development -project src/Playback/Playback.xcodeproj`
  - Output: `build/Debug/Playback.app`

- [ ] Implement development data directory creation
  - Auto-create `dev_data/temp/` directory
  - Auto-create `dev_data/chunks/` directory
  - Generate `dev_config.json` with development settings

- [ ] Configure development environment variables
  - Set `PLAYBACK_DEV_MODE=1` in LaunchAgents
  - Set `PLAYBACK_DATA_DIR` to project dev_data path

### Production Build Setup
- [ ] Create production build script
  - Location: `src/scripts/build_release.sh`
  - Commands: archive, export, sign, package, notarize
  - Output: `build/Playback-{VERSION}.pkg`

- [ ] Configure archive settings
  - Archive path: `build/Playback.xcarchive`
  - Export options: `exportOptions.plist`
  - Export method: Developer ID

- [ ] Implement code signing
  - Sign with: "Developer ID Application"
  - Options: `--deep --force --options runtime`
  - Target: `build/Release/Playback.app`

- [ ] Configure package creation
  - Tool: `pkgbuild`
  - Bundle ID: `com.playback.Playback`
  - Install location: `/Applications`
  - Post-install scripts: `src/scripts/pkg/`

- [ ] Implement notarization workflow
  - Tool: `xcrun notarytool`
  - Credentials: Keychain (AC_PASSWORD)
  - Wait for completion
  - Staple ticket to package

### Hot-Reloading Configuration
- [ ] Set up Swift hot-reloading (optional)
  - Method: InjectionIII or Xcode built-in
  - Enabled only in DEVELOPMENT builds
  - SwiftUI: `.enableInjection()` modifier

- [ ] Configure Python script hot-reloading
  - Run scripts directly from source directory
  - Detect `PLAYBACK_DEV_MODE` environment variable
  - Use dev_data/ path in development

### Unit Test Setup
- [ ] Create unit test target
  - Location: `src/Playback/PlaybackTests/`
  - Host application: Playback
  - Test configuration coverage and database logic

- [ ] Implement TimelineStore tests
  - Test: Segment selection logic
  - Test: Time mapping (absolute ↔ video offset)
  - Test: Gap handling
  - Source: `src/Playback/PlaybackTests/TimelineStoreTests.swift`

- [ ] Implement ConfigManager tests
  - Test: Configuration loading/saving
  - Test: Environment detection (dev vs production)
  - Test: Path resolution

- [ ] Implement Database tests
  - Test: Segment queries
  - Test: AppSegment queries
  - Test: OCR text search
  - Test: Search query parsing

- [ ] Configure unit test execution
  - Command: `xcodebuild test -scheme Playback-Development`
  - Destination: `platform=macOS`
  - Expected time: ~5 seconds

### Integration Test Setup
- [ ] Create integration test suite
  - Location: `src/Playback/PlaybackTests/IntegrationTests.swift`
  - Test end-to-end workflows

- [ ] Implement recording-to-processing flow test
  - Start RecordingService
  - Wait for screenshots
  - Run ProcessingService
  - Verify database has segments

- [ ] Implement settings-to-service test
  - Change settings
  - Verify LaunchAgent reloads
  - Verify new settings propagate

- [ ] Implement manual processing trigger test
  - Trigger processing from menu bar
  - Wait for completion
  - Verify segments created

- [ ] Configure integration test execution
  - Use dev mode: `devMode: true`
  - Expected time: ~30 seconds

### UI Test Setup
- [ ] Create UI test target
  - Location: `src/Playback/PlaybackUITests/`
  - Test application: Playback

- [ ] Implement menu bar UI tests
  - Test: App launch → menu bar appears
  - Test: Toggle recording → status icon changes
  - Test: Open settings → all tabs accessible

- [ ] Implement timeline UI tests
  - Test: Open timeline (Option+Shift+Space)
  - Test: Video playback starts
  - Test: Date/time picker navigation
  - Test: Search (Command+F) → results appear
  - Source: `src/Playback/PlaybackUITests/TimelineUITests.swift`

- [ ] Implement settings UI tests
  - Test: Open settings from menu bar
  - Test: Navigate between tabs
  - Test: Toggle preferences
  - Test: Uninstall confirmation dialog

- [ ] Configure UI test execution
  - Use XCUIApplication
  - Expected time: ~2 minutes

### Pre-Commit Hook Setup
- [ ] Create pre-commit hook script
  - Location: `.git/hooks/pre-commit`
  - Run: SwiftLint, flake8, fast tests
  - Expected time: ~15 seconds

- [ ] Implement Swift linting
  - Tool: SwiftLint
  - Config: `--strict --quiet`
  - Install: `brew install swiftlint`

- [ ] Implement Python linting
  - Tool: flake8
  - Config: `--max-line-length=120`
  - Target: `src/scripts/`
  - Install: `pip install flake8`

- [ ] Implement fast unit test subset
  - Only run tests tagged with @fast
  - Command: `-only-testing:PlaybackTests/FastTests`
  - Expected time: ~5 seconds

- [ ] Implement Python test execution
  - Tool: pytest
  - Target: `src/scripts/tests/`
  - Command: `python3 -m pytest src/scripts/tests/ -v --tb=short`

- [ ] Implement configuration validation
  - Script: `src/scripts/validate_config.py`
  - Validate: config.json schema

- [ ] Make pre-commit hook executable
  - Command: `chmod +x .git/hooks/pre-commit`
  - Alternative: Use pre-commit framework

### CI/CD Pipeline Setup
- [ ] Create GitHub Actions workflow
  - Location: `.github/workflows/test.yml`
  - Trigger: push, pull_request
  - Runner: macos-latest

- [ ] Configure Xcode setup step
  - Action: maxim-lobanov/setup-xcode@v1
  - Version: latest

- [ ] Configure dependency installation
  - Install: ffmpeg, python@3.10
  - Install: flake8, pytest
  - Command: `brew install`, `pip3 install`

- [ ] Configure Swift linting step
  - Command: `swiftlint --strict`

- [ ] Configure Python linting step
  - Command: `flake8 scripts/ --max-line-length=120`

- [ ] Configure unit test execution step
  - Command: `xcodebuild test -scheme Playback-Development`
  - Destination: `platform=macOS`

- [ ] Configure Python test execution step
  - Command: `python3 -m pytest scripts/tests/ -v`

- [ ] Configure production build step
  - Command: `./scripts/build_release.sh`
  - Only on: main branch

### Dependencies Management
- [ ] Document build dependencies
  - Xcode 15.0+
  - Swift 5.9+
  - Python 3.8+
  - FFmpeg 4.0+

- [ ] Create dependency installation script
  - Location: `src/scripts/install_deps.sh`
  - Commands: `brew install ffmpeg python@3.10`
  - Python packages: pyobjc-framework-Vision, pyobjc-framework-Quartz

- [ ] Document optional development dependencies
  - SwiftLint (linting)
  - InjectionIII (hot-reloading)
  - pre-commit (git hooks)
  - Install: `brew install swiftlint`, etc.

- [ ] Create development environment setup script
  - Location: `src/scripts/setup_dev_env.sh`
  - Install: Optional dependencies
  - Create: dev_data/ directories
  - Generate: dev_config.json

### Environment Configuration
- [ ] Create development config template
  - Location: `dev_config.json` (gitignored)
  - Settings: recording_enabled, processing_interval, data_directory
  - Log level: DEBUG

- [ ] Create production config template
  - Location: `~/Library/Application Support/Playback/config.json`
  - Settings: recording_enabled, processing_interval, data_directory
  - Log level: INFO

- [ ] Implement environment detection
  - Source: `src/Playback/Playback/Config/Environment.swift`
  - Enum: development, production
  - Preprocessor: `#if DEVELOPMENT`

- [ ] Configure data directory resolution
  - Development: `<project>/dev_data`
  - Production: `~/Library/Application Support/Playback/data`

## Build System Details

This section contains complete build commands, configuration examples, CI/CD workflows, pre-commit hook scripts, and hot-reloading setup. All information needed to set up and maintain the build system is self-contained in this document.

### Development Build Script

**File:** `src/scripts/build_dev.sh`

```bash
#!/bin/bash
set -e

echo "Building Playback (Development)..."

# Build for development
xcodebuild \
  -project src/Playback/Playback.xcodeproj \
  -scheme Playback-Development \
  -configuration Debug \
  -derivedDataPath build \
  -destination 'platform=macOS,arch=arm64' \
  build

echo "Development build complete: build/Debug/Playback.app"

# Create dev data directories
mkdir -p dev_data/temp
mkdir -p dev_data/chunks
mkdir -p dev_data/segments

# Generate dev config if not exists
if [ ! -f dev_config.json ]; then
  echo "Creating dev_config.json..."
  cat > dev_config.json << 'EOF'
{
  "recording_enabled": true,
  "recording_interval": 5,
  "processing_interval": 300,
  "data_directory": "./dev_data",
  "log_level": "DEBUG",
  "excluded_apps": [
    "1Password",
    "Keychain Access"
  ],
  "video_quality": "medium",
  "max_storage_gb": 50
}
EOF
fi

echo "Development environment ready!"
```

### Production Build Script

**File:** `src/scripts/build_release.sh`

```bash
#!/bin/bash
set -e

VERSION="1.0.0"
APP_NAME="Playback"
BUNDLE_ID="com.playback.Playback"
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"

echo "Building ${APP_NAME} v${VERSION} (Production)..."

# Clean previous builds
rm -rf build/Release
rm -rf build/${APP_NAME}.xcarchive

# Archive the app
echo "Archiving..."
xcodebuild \
  -project src/Playback/Playback.xcodeproj \
  -scheme Playback-Production \
  -configuration Release \
  -archivePath build/${APP_NAME}.xcarchive \
  -destination 'platform=macOS,arch=arm64' \
  archive

# Export the archive
echo "Exporting archive..."
xcodebuild \
  -exportArchive \
  -archivePath build/${APP_NAME}.xcarchive \
  -exportPath build/Release \
  -exportOptionsPlist exportOptions.plist

# Sign the app
echo "Signing app..."
codesign \
  --sign "${DEVELOPER_ID}" \
  --deep \
  --force \
  --options runtime \
  --timestamp \
  build/Release/${APP_NAME}.app

# Verify signature
echo "Verifying signature..."
codesign --verify --verbose build/Release/${APP_NAME}.app

# Create installer package
echo "Creating installer package..."
pkgbuild \
  --component build/Release/${APP_NAME}.app \
  --install-location /Applications \
  --identifier ${BUNDLE_ID} \
  --version ${VERSION} \
  --scripts src/scripts/pkg \
  build/${APP_NAME}-${VERSION}.pkg

# Sign the package
echo "Signing package..."
productsign \
  --sign "Developer ID Installer: Your Name (TEAMID)" \
  build/${APP_NAME}-${VERSION}.pkg \
  build/${APP_NAME}-${VERSION}-signed.pkg

mv build/${APP_NAME}-${VERSION}-signed.pkg build/${APP_NAME}-${VERSION}.pkg

# Notarize the package
echo "Submitting for notarization..."
xcrun notarytool submit \
  build/${APP_NAME}-${VERSION}.pkg \
  --keychain-profile "AC_PASSWORD" \
  --wait

# Staple the notarization ticket
echo "Stapling notarization ticket..."
xcrun stapler staple build/${APP_NAME}-${VERSION}.pkg

echo "Production build complete: build/${APP_NAME}-${VERSION}.pkg"
```

### Export Options Plist

**File:** `exportOptions.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>TEAMID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
    <key>destination</key>
    <string>export</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
```

### Pre-Commit Hook Script

**File:** `.git/hooks/pre-commit`

```bash
#!/bin/bash
set -e

echo "Running pre-commit checks..."

# Check if SwiftLint is installed
if ! command -v swiftlint &> /dev/null; then
    echo "Warning: SwiftLint not installed. Install with: brew install swiftlint"
    exit 1
fi

# Check if flake8 is installed
if ! command -v flake8 &> /dev/null; then
    echo "Warning: flake8 not installed. Install with: pip3 install flake8"
    exit 1
fi

# Run SwiftLint
echo "Running SwiftLint..."
swiftlint --strict --quiet
if [ $? -ne 0 ]; then
    echo "SwiftLint failed. Fix the issues before committing."
    exit 1
fi

# Run flake8 on Python scripts
echo "Running flake8..."
flake8 src/scripts/ --max-line-length=120 --exclude=src/scripts/venv
if [ $? -ne 0 ]; then
    echo "flake8 failed. Fix the issues before committing."
    exit 1
fi

# Run fast unit tests
echo "Running fast unit tests..."
xcodebuild test \
  -scheme Playback-Development \
  -destination 'platform=macOS' \
  -only-testing:PlaybackTests/FastTests \
  -quiet
if [ $? -ne 0 ]; then
    echo "Fast unit tests failed. Fix the issues before committing."
    exit 1
fi

# Run Python tests
echo "Running Python tests..."
python3 -m pytest src/scripts/tests/ -v --tb=short
if [ $? -ne 0 ]; then
    echo "Python tests failed. Fix the issues before committing."
    exit 1
fi

# Validate configuration schema
echo "Validating configuration..."
python3 src/scripts/validate_config.py
if [ $? -ne 0 ]; then
    echo "Configuration validation failed. Fix the schema before committing."
    exit 1
fi

echo "All pre-commit checks passed!"
```

Make the script executable:
```bash
chmod +x .git/hooks/pre-commit
```

### CI/CD Workflow (GitHub Actions)

**File:** `.github/workflows/test.yml`

```yaml
name: Test and Build

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-14

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '15.2'

    - name: Install dependencies
      run: |
        brew install ffmpeg python@3.10 swiftlint
        pip3 install flake8 pytest pyobjc-framework-Vision pyobjc-framework-Quartz

    - name: Run SwiftLint
      run: swiftlint --strict

    - name: Run flake8
      run: flake8 src/scripts/ --max-line-length=120 --exclude=src/scripts/venv

    - name: Run unit tests
      run: |
        xcodebuild test \
          -project src/Playback/Playback.xcodeproj \
          -scheme Playback-Development \
          -destination 'platform=macOS' \
          -enableCodeCoverage YES

    - name: Run Python tests
      run: python3 -m pytest src/scripts/tests/ -v

    - name: Build development
      run: ./src/scripts/build_dev.sh

    - name: Upload test results
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: test-results
        path: build/Logs/Test/*.xcresult

  build-release:
    runs-on: macos-14
    needs: test
    if: github.ref == 'refs/heads/main'

    steps:
    - name: Checkout code
      uses: actions/checkout@v4

    - name: Set up Xcode
      uses: maxim-lobanov/setup-xcode@v1
      with:
        xcode-version: '15.2'

    - name: Install dependencies
      run: brew install ffmpeg python@3.10

    - name: Import certificates
      env:
        CERTIFICATE_P12: ${{ secrets.CERTIFICATE_P12 }}
        CERTIFICATE_PASSWORD: ${{ secrets.CERTIFICATE_PASSWORD }}
      run: |
        echo $CERTIFICATE_P12 | base64 --decode > certificate.p12
        security create-keychain -p actions temp.keychain
        security default-keychain -s temp.keychain
        security unlock-keychain -p actions temp.keychain
        security import certificate.p12 -k temp.keychain -P $CERTIFICATE_PASSWORD -T /usr/bin/codesign
        security set-key-partition-list -S apple-tool:,apple: -s -k actions temp.keychain

    - name: Build release
      env:
        NOTARIZATION_USERNAME: ${{ secrets.NOTARIZATION_USERNAME }}
        NOTARIZATION_PASSWORD: ${{ secrets.NOTARIZATION_PASSWORD }}
      run: ./src/scripts/build_release.sh

    - name: Upload build artifact
      uses: actions/upload-artifact@v4
      with:
        name: playback-installer
        path: build/Playback-*.pkg
```

### Hot-Reloading Setup

#### Swift Hot-Reloading with InjectionIII

**Installation:**
```bash
brew install injectioniii
```

**Code Setup (SwiftUI Views):**

Add to your SwiftUI views in development:

```swift
import SwiftUI
#if DEBUG
import Inject
#endif

struct TimelineView: View {
    #if DEBUG
    @ObserveInjection var inject
    #endif

    var body: some View {
        VStack {
            // Your view code
        }
        #if DEBUG
        .enableInjection()
        #endif
    }
}
```

**AppDelegate Setup:**

```swift
#if DEBUG
import Inject

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Enable InjectionIII
        Bundle(path: "/Applications/InjectionIII.app/Contents/Resources/iOSInjection.bundle")?.load()
    }
}
#endif
```

#### Python Script Hot-Reloading

**Implementation in Swift:**

```swift
class PythonScriptRunner {
    static func runScript(name: String, args: [String]) throws {
        let scriptPath: String

        #if DEVELOPMENT
        // In development, run from source directory for hot-reloading
        let projectRoot = FileManager.default.currentDirectoryPath
        scriptPath = "\(projectRoot)/src/scripts/\(name).py"
        #else
        // In production, run from app bundle
        guard let bundlePath = Bundle.main.resourcePath else {
            throw ScriptError.bundleNotFound
        }
        scriptPath = "\(bundlePath)/scripts/\(name).py"
        #endif

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [scriptPath] + args

        // Set environment variables
        var environment = ProcessInfo.processInfo.environment
        if Environment.current == .development {
            environment["PLAYBACK_DEV_MODE"] = "1"
            environment["PLAYBACK_DATA_DIR"] = ConfigManager.shared.dataDirectory.path
        }
        process.environment = environment

        try process.run()
        process.waitUntilExit()
    }
}
```

**Python Script Detection:**

```python
import os
import sys

def get_data_dir():
    """Get data directory based on environment"""
    if os.getenv('PLAYBACK_DEV_MODE') == '1':
        # Development mode - use project dev_data
        data_dir = os.getenv('PLAYBACK_DATA_DIR', './dev_data')
    else:
        # Production mode - use Application Support
        home = os.path.expanduser('~')
        data_dir = os.path.join(home, 'Library/Application Support/Playback/data')

    return data_dir

def main():
    data_dir = get_data_dir()
    print(f"Using data directory: {data_dir}")

    # Script logic here...
```

### Xcode Build Scheme Configuration

#### Debug Scheme (Development)

**Build Settings:**
- Configuration: Debug
- Build Active Architecture Only: Yes
- Defines Module: Yes
- Enable Testability: Yes

**Swift Compiler - Code Generation:**
- Optimization Level: No Optimization [-Onone]
- Compilation Mode: Incremental
- Active Compilation Conditions: DEBUG DEVELOPMENT

**Swift Compiler - Custom Flags:**
- Other Swift Flags: -D DEBUG -D DEVELOPMENT

**Signing & Capabilities:**
- Signing Certificate: Sign to Run Locally (ad-hoc)
- Automatic Signing: Yes (Development)

**Environment Variables (Scheme Settings):**
```
PLAYBACK_DEV_MODE=1
PLAYBACK_DATA_DIR=$(SOURCE_ROOT)/dev_data
```

#### Release Scheme (Production)

**Build Settings:**
- Configuration: Release
- Build Active Architecture Only: No
- Defines Module: Yes
- Enable Testability: No

**Swift Compiler - Code Generation:**
- Optimization Level: Optimize for Speed [-O]
- Compilation Mode: Whole Module
- Active Compilation Conditions: RELEASE

**Signing & Capabilities:**
- Signing Certificate: Developer ID Application
- Automatic Signing: No (Manual)
- Hardened Runtime: Enabled
- Entitlements: Playback.entitlements

**Code Signing Entitlements:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.device.camera</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
</dict>
</plist>
```

### Development Environment Setup Script

**File:** `src/scripts/setup_dev_env.sh`

```bash
#!/bin/bash
set -e

echo "Setting up Playback development environment..."

# Install Homebrew dependencies
echo "Installing Homebrew dependencies..."
brew install ffmpeg python@3.10 swiftlint

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install flake8 pytest pyobjc-framework-Vision pyobjc-framework-Quartz

# Install optional development tools
read -p "Install InjectionIII for hot-reloading? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    brew install injectioniii
fi

# Create dev data directories
echo "Creating dev data directories..."
mkdir -p dev_data/temp
mkdir -p dev_data/chunks
mkdir -p dev_data/segments

# Create dev config
echo "Creating dev_config.json..."
cat > dev_config.json << 'EOF'
{
  "recording_enabled": true,
  "recording_interval": 5,
  "processing_interval": 300,
  "data_directory": "./dev_data",
  "log_level": "DEBUG",
  "excluded_apps": [
    "1Password",
    "Keychain Access"
  ],
  "video_quality": "medium",
  "max_storage_gb": 50
}
EOF

# Add dev_config.json to .gitignore if not already present
if ! grep -q "dev_config.json" .gitignore 2>/dev/null; then
    echo "dev_config.json" >> .gitignore
fi

# Install pre-commit hook
echo "Installing pre-commit hook..."
cp src/scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

echo ""
echo "Development environment setup complete!"
echo ""
echo "Next steps:"
echo "1. Open src/Playback/Playback.xcodeproj in Xcode"
echo "2. Select 'Playback-Development' scheme"
echo "3. Build and run (Cmd+R)"
echo ""
echo "For hot-reloading:"
echo "- Swift: Open InjectionIII.app and inject"
echo "- Python: Scripts run from source directory automatically"
```

### Dependency Installation Script

**File:** `src/scripts/install_deps.sh`

```bash
#!/bin/bash
set -e

echo "Installing Playback dependencies..."

# Check for Homebrew
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install system dependencies
echo "Installing system dependencies..."
brew install ffmpeg python@3.10

# Install Python packages
echo "Installing Python packages..."
pip3 install pyobjc-framework-Vision pyobjc-framework-Quartz

echo "Dependencies installed successfully!"
```

### Configuration Validation Script

**File:** `src/scripts/validate_config.py`

```python
#!/usr/bin/env python3
"""Validate config.json against schema"""

import json
import sys
from pathlib import Path

SCHEMA = {
    "recording_enabled": bool,
    "recording_interval": int,
    "processing_interval": int,
    "data_directory": str,
    "log_level": str,
    "excluded_apps": list,
    "video_quality": str,
    "max_storage_gb": int
}

VALID_LOG_LEVELS = ["DEBUG", "INFO", "WARNING", "ERROR"]
VALID_VIDEO_QUALITIES = ["low", "medium", "high"]

def validate_config(config_path):
    """Validate configuration file"""
    if not Path(config_path).exists():
        print(f"Error: Config file not found: {config_path}")
        return False

    try:
        with open(config_path) as f:
            config = json.load(f)
    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in {config_path}: {e}")
        return False

    # Check required fields
    for key, expected_type in SCHEMA.items():
        if key not in config:
            print(f"Error: Missing required field: {key}")
            return False

        if not isinstance(config[key], expected_type):
            print(f"Error: Field '{key}' should be {expected_type.__name__}, got {type(config[key]).__name__}")
            return False

    # Validate log level
    if config["log_level"] not in VALID_LOG_LEVELS:
        print(f"Error: Invalid log_level '{config['log_level']}'. Must be one of: {VALID_LOG_LEVELS}")
        return False

    # Validate video quality
    if config["video_quality"] not in VALID_VIDEO_QUALITIES:
        print(f"Error: Invalid video_quality '{config['video_quality']}'. Must be one of: {VALID_VIDEO_QUALITIES}")
        return False

    # Validate positive integers
    if config["recording_interval"] <= 0:
        print("Error: recording_interval must be positive")
        return False

    if config["processing_interval"] <= 0:
        print("Error: processing_interval must be positive")
        return False

    if config["max_storage_gb"] <= 0:
        print("Error: max_storage_gb must be positive")
        return False

    print(f"Configuration valid: {config_path}")
    return True

if __name__ == "__main__":
    config_file = "dev_config.json" if Path("dev_config.json").exists() else "config.json"
    success = validate_config(config_file)
    sys.exit(0 if success else 1)
```

### Build Commands Reference

**Quick Reference:**

```bash
# Development build
xcodebuild -project src/Playback/Playback.xcodeproj -scheme Playback-Development -configuration Debug build

# Run development build
open build/Debug/Playback.app

# Run unit tests
xcodebuild test -project src/Playback/Playback.xcodeproj -scheme Playback-Development -destination 'platform=macOS'

# Run only fast tests
xcodebuild test -project src/Playback/Playback.xcodeproj -scheme Playback-Development -only-testing:PlaybackTests/FastTests

# Production build
./src/scripts/build_release.sh

# Clean build
xcodebuild clean -project src/Playback/Playback.xcodeproj -scheme Playback-Development
rm -rf build/

# Lint code
swiftlint --strict
flake8 src/scripts/ --max-line-length=120

# Run Python tests
python3 -m pytest src/scripts/tests/ -v

# Validate configuration
python3 src/scripts/validate_config.py
```

### Troubleshooting Common Build Issues

**Issue: Code signing failed**
```bash
# List available signing identities
security find-identity -v -p codesigning

# Unlock keychain
security unlock-keychain ~/Library/Keychains/login.keychain
```

**Issue: Python scripts not found in development**
```bash
# Verify PLAYBACK_DEV_MODE is set
echo $PLAYBACK_DEV_MODE

# Check script paths
ls -la src/scripts/
```

**Issue: FFmpeg not found**
```bash
# Install FFmpeg
brew install ffmpeg

# Verify installation
ffmpeg -version
```

**Issue: Tests failing in CI/CD**
```bash
# Run tests locally with same configuration
xcodebuild test \
  -project src/Playback/Playback.xcodeproj \
  -scheme Playback-Development \
  -destination 'platform=macOS' \
  -enableCodeCoverage YES
```

**Issue: Notarization failed**
```bash
# Check notarization status
xcrun notarytool log <submission-id> --keychain-profile "AC_PASSWORD"

# Verify entitlements
codesign -d --entitlements :- build/Release/Playback.app
```

## Testing Checklist

### Unit Tests (Fast - ~5 seconds)
- [ ] Test segment selection logic
  - Given: Multiple segments in database
  - When: Query for timestamp
  - Then: Return correct segment with offset

- [ ] Test time mapping calculations
  - Given: Segment with known duration and frame count
  - When: Convert absolute time to video offset
  - Then: Return correct video position

- [ ] Test gap handling
  - Given: Timestamp between segments
  - When: Query for segment
  - Then: Return closest segment

- [ ] Test configuration loading
  - Given: Valid config.json file
  - When: Load configuration
  - Then: Parse all settings correctly

- [ ] Test environment detection
  - Given: DEVELOPMENT build flag
  - When: Check Environment.current
  - Then: Return .development

- [ ] Test path resolution
  - Given: Development environment
  - When: Resolve data directory
  - Then: Return dev_data/ path

### Integration Tests (~30 seconds)
- [ ] Test recording to processing flow
  - Start RecordingService in dev mode
  - Wait for screenshots (5 seconds)
  - Stop recording
  - Run ProcessingService
  - Verify: Database has segments

- [ ] Test settings to service propagation
  - Change recording interval in settings
  - Reload LaunchAgent
  - Verify: Agent uses new interval

- [ ] Test manual processing trigger
  - Trigger processing from menu bar
  - Wait for completion
  - Verify: Segments created and database updated

- [ ] Test app exclusion configuration
  - Add app to exclusion list
  - Trigger recording
  - Verify: Screenshots skipped when app is active

### UI Tests (~2 minutes)
- [ ] Test app launch and menu bar
  - Launch app
  - Verify: Menu bar icon appears
  - Verify: Menu items accessible

- [ ] Test recording toggle
  - Click "Start Recording" in menu bar
  - Verify: Status icon changes
  - Verify: RecordingService starts

- [ ] Test settings window
  - Open settings from menu bar
  - Verify: All tabs accessible
  - Verify: Preferences can be toggled

- [ ] Test timeline viewer
  - Open timeline (Option+Shift+Space)
  - Verify: Timeline window appears
  - Verify: Video plays

- [ ] Test date/time picker
  - Click time bubble in timeline
  - Verify: Date picker appears
  - Select date
  - Verify: Video jumps to selected time

- [ ] Test search functionality
  - Open timeline
  - Press Command+F
  - Enter search query
  - Verify: Results appear

- [ ] Test uninstall dialog
  - Open settings
  - Click "Uninstall" tab
  - Click "Uninstall Playback"
  - Verify: Confirmation dialog appears

### Pre-Commit Tests (~15 seconds)
- [ ] Verify SwiftLint passes
  - Run: `swiftlint --strict --quiet`
  - Expected: No violations

- [ ] Verify flake8 passes
  - Run: `flake8 scripts/ --max-line-length=120`
  - Expected: No violations

- [ ] Verify fast unit tests pass
  - Run: Unit tests tagged with @fast
  - Expected: All pass

- [ ] Verify Python tests pass
  - Run: `python3 -m pytest scripts/tests/ -v`
  - Expected: All pass

- [ ] Verify configuration validation passes
  - Run: `python3 scripts/validate_config.py`
  - Expected: Config schema valid

### Build Tests
- [ ] Test development build
  - Run: `xcodebuild -scheme Playback-Development`
  - Expected: Build succeeds in ~30 seconds
  - Verify: Playback.app in build/Debug/

- [ ] Test production build
  - Run: `./scripts/build_release.sh`
  - Expected: Build succeeds in ~2 minutes
  - Verify: Playback-{VERSION}.pkg created
  - Verify: Package is signed and notarized

- [ ] Test incremental build
  - Make small code change
  - Run: `xcodebuild -scheme Playback-Development`
  - Expected: Build succeeds in ~5 seconds

### Performance Tests
- [ ] Verify build time benchmarks
  - Development build: ~30 seconds (full)
  - Development build: ~5 seconds (incremental)
  - Production build: ~2 minutes (full)
  - Unit tests: ~5 seconds
  - Integration tests: ~30 seconds
  - UI tests: ~2 minutes
  - Pre-commit tests: ~15 seconds

- [ ] Test under continuous development
  - Make 10 sequential code changes
  - Run development build each time
  - Verify: Incremental builds remain fast

### CI/CD Tests
- [ ] Verify GitHub Actions workflow
  - Push to branch
  - Verify: Workflow triggers
  - Verify: All steps pass
  - Expected time: ~10 minutes

- [ ] Test on clean environment
  - Use fresh macOS installation
  - Run: `scripts/install_deps.sh`
  - Run: GitHub Actions workflow steps manually
  - Verify: All steps succeed
