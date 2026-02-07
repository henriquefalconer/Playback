# Installation & Deployment Implementation Plan

**Component:** Installation and Deployment
**Version:** 1.0
**Last Updated:** 2026-02-07

## Implementation Checklist

### .zip Distribution Package (Arc-Style)
- [ ] Create package_release.sh script
  - Location: `scripts/package_release.sh`
  - Inputs: Version number, build directory
  - Outputs: `Playback-{VERSION}.zip`
  - Contents: Playback.app, README.txt
  - Reference: See original spec § "Package Creation (Arc Style)"

- [ ] Configure README.txt template
  - Installation steps (drag to Applications)
  - First-run instructions
  - Permission requirements
  - Support URL

- [ ] Implement zip creation with preservation
  - Use `ditto -c -k --keepParent` for proper attribute preservation
  - Preserve code signatures
  - Include proper file permissions

### First-Run Setup
- [ ] Implement welcome screen
  - Source: `Playback/FirstRun/WelcomeView.swift`
  - Display on first launch only (check UserDefaults)
  - Brief explanation of Playback
  - "Get Started" button
  - Reference: See original spec § "First Run Experience"

- [ ] Implement permissions request flow
  - Source: `Playback/FirstRun/PermissionsView.swift`
  - Screen Recording permission (required)
    - Show explanation with screenshot example
    - "Open System Preferences" button
    - Uses: `CGPreflightScreenCaptureAccess()` and `CGRequestScreenCaptureAccess()`
  - Accessibility permission (optional)
    - Show explanation for app tracking
    - "Open System Preferences" or "Skip" buttons
    - Check status: `AXIsProcessTrusted()`

- [ ] Implement storage location setup
  - Source: `Playback/FirstRun/StorageView.swift`
  - Default: `~/Library/Application Support/Playback/data/`
  - Allow custom location selection (NSOpenPanel)
  - Validate:
    - Check available disk space (100 GB minimum recommended)
    - Check write permissions
    - Create directory structure
  - Store location in config

- [ ] Create data directory structure
  - Source: `Playback/Config/DirectoryManager.swift`
  - Create directories:
    - `data/temp/` - Temporary screenshots
    - `data/chunks/` - Processed video segments
    - `logs/` - Application logs
  - Set proper permissions (user read/write only)
  - Initialize empty database: `data/meta.sqlite3`

- [ ] Generate default configuration
  - Source: `Playback/Config/ConfigManager.swift`
  - File: `~/Library/Application Support/Playback/config.json`
  - Defaults:
    - Recording enabled: false (user must opt-in)
    - Processing interval: 300 seconds
    - Retention: temp=7 days, chunks=never
    - Storage location
  - Validate JSON schema

- [ ] Implement initial configuration screen
  - Source: `Playback/FirstRun/ConfigurationView.swift`
  - Prompts:
    - "Start recording now?" (Yes/No toggle)
    - Processing interval slider (default: 5 minutes)
    - Retention policies (temp: 1 week, recordings: never)
  - Save choices to config file

- [ ] Install LaunchAgents on first run
  - Source: `Playback/Services/LaunchAgentInstaller.swift`
  - Create plist files in `~/Library/LaunchAgents/`:
    - `com.playback.recording.plist`
    - `com.playback.processing.plist`
    - `com.playback.menubar.plist`
  - Load processing and menubar agents immediately
  - Load recording agent only if user enabled
  - Reference: See original spec § "LaunchAgent Installation"

### Dependency Detection & Validation
- [ ] Implement Python version check
  - Source: `Playback/Dependencies/PythonChecker.swift`
  - Run: `python3 --version`
  - Parse output, verify >= 3.12
  - Show error with installation instructions if not found
  - Reference: See original spec § "Dependency Management → Python"

- [ ] Implement FFmpeg detection
  - Source: `Playback/Dependencies/FFmpegChecker.swift`
  - Check locations:
    - `/usr/local/bin/ffmpeg` (Intel Homebrew)
    - `/opt/homebrew/bin/ffmpeg` (Apple Silicon Homebrew)
    - Bundled: `Playback.app/Contents/Resources/ffmpeg`
  - Verify version >= 7.0
  - Verify libx264 support: `ffmpeg -version | grep libx264`
  - Show error with installation instructions if not found
  - Reference: See original spec § "Dependency Management → FFmpeg"

- [ ] Create dependency validation flow
  - Source: `Playback/FirstRun/DependencyView.swift`
  - Run checks on first launch
  - Display status for each dependency (checkmark or error)
  - Block setup if critical dependencies missing
  - Offer "Install via Homebrew" buttons (opens Terminal with commands)

### Code Signing
- [ ] Configure development signing
  - Xcode setting: "Sign to Run Locally"
  - Team: None (ad-hoc signing)
  - Use for development builds only

- [ ] Configure production signing
  - Certificate: "Developer ID Application: Your Name"
  - Enable Hardened Runtime
  - Entitlements: `Playback/Playback.entitlements`
  - Required entitlements:
    - `com.apple.security.device.camera` (for screen recording)
    - `com.apple.security.automation.apple-events` (for system events)
  - Reference: See original spec § "Distribution → Code Signing"

- [ ] Add code signing to build script
  - Location: `scripts/package_release.sh`
  - Sign app bundle: `codesign --sign "Developer ID Application" --deep --force`
  - Sign embedded frameworks
  - Verify: `codesign --verify --verbose Playback.app`
  - Check Gatekeeper: `spctl --assess --verbose Playback.app`

### Notarization
- [ ] Implement notarization workflow
  - Location: `scripts/notarize.sh`
  - Create submission zip: `ditto -c -k --keepParent Playback.app Playback.zip`
  - Submit to Apple: `xcrun notarytool submit`
    - Apple ID from keychain
    - Team ID from developer account
    - Wait for completion (--wait flag)
  - Check status: `xcrun notarytool info`
  - Staple ticket: `xcrun stapler staple Playback.app`
  - Verify staple: `xcrun stapler validate Playback.app`
  - Reference: See original spec § "Distribution → Notarization"

- [ ] Configure notarization credentials
  - Store Apple ID in keychain: `AC_PASSWORD`
  - Store Team ID in environment variable
  - Document setup process in README

- [ ] Add notarization to release script
  - Call notarize.sh from package_release.sh
  - Block release if notarization fails
  - Log notarization audit log for debugging

### Package Creation Script
- [ ] Create comprehensive package_release.sh
  - Location: `scripts/package_release.sh`
  - Parameters:
    - VERSION (required): Version string (e.g., "1.0.0")
    - BUILD_CONFIG (optional): Debug or Release (default: Release)
  - Steps:
    1. Clean build directory
    2. Build app with xcodebuild
    3. Run tests (integration tests)
    4. Validate dependencies bundled
    5. Code sign app bundle
    6. Notarize with Apple
    7. Create README.txt
    8. Create distribution zip
    9. Generate SHA256 checksum
    10. Output: `dist/Playback-{VERSION}.zip`
  - Reference: See original spec § "Package Creation (Arc Style)"

- [ ] Add build validation steps
  - Verify app launches successfully
  - Check entitlements: `codesign -d --entitlements - Playback.app`
  - Verify bundle structure
  - Check Info.plist values
  - Test on clean VM (optional but recommended)

- [ ] Generate release artifacts
  - `Playback-{VERSION}.zip` - Main distribution
  - `Playback-{VERSION}.zip.sha256` - Checksum file
  - `RELEASE_NOTES.md` - Version changelog
  - Upload instructions for GitHub releases

### Uninstaller
- [ ] Create uninstaller app bundle
  - Location: `Uninstaller/` (separate Xcode target)
  - App name: "Uninstall Playback.app"
  - Bundle ID: `com.playback.uninstaller`
  - Simple SwiftUI interface

- [ ] Implement uninstallation logic
  - Source: `Uninstaller/UninstallerApp.swift`
  - Steps:
    1. Show confirmation dialog
    2. Stop all running services:
       - `killall "Playback"`
       - Unload LaunchAgents
    3. Remove LaunchAgent plists
    4. Remove app bundles from /Applications
    5. Ask: "Delete recordings and data?"
       - Yes: Delete `~/Library/Application Support/Playback/`
       - No: Keep recordings for potential reinstall
    6. Remove logs: `~/Library/Logs/Playback/`
    7. Show completion message
  - Reference: See original spec § "Uninstallation"

- [ ] Add uninstaller to distribution
  - Include in Playback.app/Contents/Resources/
  - Add menu item: "Uninstall Playback..."
  - Opens uninstaller app when clicked

- [ ] Create standalone uninstall script
  - Location: `scripts/uninstall.sh`
  - For users who deleted app manually
  - Cleans up LaunchAgents and data
  - Can be run from Terminal

### Update Mechanism
- [ ] Implement update check
  - Source: `Playback/Updates/UpdateChecker.swift`
  - Check on launch (once per day)
  - Fetch latest version from URL: `https://falconer.com/playback/version.json`
  - Compare with current version (CFBundleShortVersionString)
  - Show notification if update available
  - Reference: See original spec § "Update Strategy"

- [ ] Create update installation flow
  - Source: `Playback/Updates/UpdateInstaller.swift`
  - Steps:
    1. Download new version to temp directory
    2. Verify code signature
    3. Verify notarization
    4. Show "Ready to Update" dialog
    5. On confirmation:
       - Quit all Playback components
       - Backup current version
       - Replace app bundle
       - Migrate config (if schema changed)
       - Migrate database (if schema changed)
       - Restart app
    6. On failure: Restore backup
  - Use NSWorkspace for app replacement

- [ ] Implement config migration
  - Source: `Playback/Config/ConfigMigrator.swift`
  - Version schema in config.json
  - Migration functions for each schema version
  - Backup old config before migration
  - Validate after migration

- [ ] Implement database migration
  - Source: `Playback/Database/DatabaseMigrator.swift`
  - Use SQL migrations (numbered files)
  - Track current schema version in database
  - Run migrations sequentially
  - Backup database before migration

- [ ] Add Sparkle framework (future enhancement)
  - Framework: Sparkle 2.x
  - Configure appcast.xml
  - Add to build: embed framework in app bundle
  - Initialize in AppDelegate
  - Enable auto-download and install
  - Reference: https://sparkle-project.org/

### Build Script Integration
- [ ] Create master build script
  - Location: `scripts/build.sh`
  - Modes:
    - `development`: Debug build, no signing, local testing
    - `release`: Release build, full signing, distribution ready
  - Call from: Xcode schemes, CI/CD pipelines
  - Output: Staged builds in `build/` directory

- [ ] Set up CI/CD integration (future)
  - GitHub Actions workflow
  - Automated testing on PR
  - Automated release builds on tag
  - Upload to GitHub Releases
  - Update website download link

### Testing & Validation
- [ ] Create installation test VM
  - Fresh macOS 26.0 (Tahoe) installation
  - No Homebrew or development tools
  - Test complete installation flow
  - Verify all permissions work
  - Validate recording and playback

- [ ] Test upgrade scenarios
  - Install old version
  - Upgrade to new version
  - Verify data preservation
  - Verify config migration
  - Verify LaunchAgents update

- [ ] Test uninstallation
  - Uninstall with data preservation
  - Verify services stopped
  - Verify LaunchAgents removed
  - Reinstall and verify data accessible

- [ ] Test code signing and notarization
  - Download .zip from web server
  - Unzip and verify signature intact
  - Verify Gatekeeper allows launch
  - Verify no security warnings

## Installation & Deployment Details

### System Requirements

**Hardware Requirements:**
- **Processor:** Apple Silicon (M1, M2, M3, M4)
- **Architecture:** ARM64 only (no Intel support)
- **Memory:** Minimum 8 GB RAM, 16 GB recommended
- **Storage:** 100 GB available disk space recommended
  - Base install: ~50 MB (app bundle)
  - With bundled FFmpeg: ~100 MB
  - Recordings: ~1-2 GB per hour at 720p, 1fps
  - Estimate: 10 hours/day × 30 days × 1.5 GB = ~450 GB/month

**Software Requirements:**
- **Operating System:** macOS 26.0 (Tahoe) or later
- **Python:** Version 3.12 or later (system Python acceptable)
- **FFmpeg:** Version 7.0 or later with libx264 support
- **Network:** Internet connection for updates (optional)

**Permissions Required:**
- **Screen Recording:** Required for capturing screen content
- **Accessibility:** Optional, enables app window tracking
- **File System:** Read/write to ~/Library/Application Support/Playback/

### Arc-Style .zip Distribution Process

**Package Creation Command:**

```bash
#!/bin/bash
# scripts/package_release.sh

set -e

VERSION="${1:-1.0.0}"
BUILD_CONFIG="${2:-Release}"
BUILD_DIR="build"
DIST_DIR="dist"
APP_NAME="Playback"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DIST_ZIP="${DIST_DIR}/${APP_NAME}-${VERSION}.zip"

echo "Building Playback v${VERSION} (${BUILD_CONFIG})..."

# Clean previous builds
rm -rf "${BUILD_DIR}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# Build with xcodebuild
xcodebuild clean build \
  -project "${APP_NAME}.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration "${BUILD_CONFIG}" \
  -derivedDataPath "${BUILD_DIR}" \
  -destination "platform=macOS,arch=arm64" \
  CODE_SIGN_IDENTITY="Developer ID Application: Your Name" \
  CODE_SIGN_STYLE="Manual" \
  DEVELOPMENT_TEAM="TEAM_ID_HERE"

# Find the built app
BUILT_APP=$(find "${BUILD_DIR}" -name "${APP_NAME}.app" -type d | head -1)
if [ ! -d "${BUILT_APP}" ]; then
  echo "Error: App bundle not found"
  exit 1
fi

# Copy to build root
cp -R "${BUILT_APP}" "${APP_BUNDLE}"

# Sign the app (deep signing for all components)
echo "Code signing app..."
codesign --sign "Developer ID Application: Your Name" \
  --deep \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "${APP_NAME}/${APP_NAME}.entitlements" \
  "${APP_BUNDLE}"

# Verify signature
codesign --verify --verbose "${APP_BUNDLE}"
spctl --assess --verbose "${APP_BUNDLE}"

# Notarize
echo "Notarizing app..."
./scripts/notarize.sh "${APP_BUNDLE}"

# Create README.txt
cat > "${BUILD_DIR}/README.txt" <<EOF
Playback v${VERSION}
====================

Installation Instructions:
1. Unzip this archive
2. Drag Playback.app to your Applications folder
3. Launch Playback from Applications
4. Follow the first-run setup wizard

Requirements:
- macOS 26.0 (Tahoe) or later
- Apple Silicon Mac (M1/M2/M3/M4)
- Python 3.12+ (install via Homebrew if needed)
- FFmpeg 7.0+ (install via Homebrew if needed)

First Run:
On first launch, Playback will guide you through:
1. Welcome screen
2. System permissions (Screen Recording required)
3. Storage location selection
4. Initial configuration
5. Dependency validation

Support:
Website: https://falconer.com/playback
Issues: https://github.com/yourname/playback/issues
Email: support@falconer.com

Uninstallation:
Open Playback, go to menu > Uninstall Playback...
Or run: ~/Library/Application Support/Playback/uninstall.sh
EOF

# Create distribution zip (Arc-style with proper attribute preservation)
echo "Creating distribution archive..."
cd "${BUILD_DIR}"
ditto -c -k --keepParent "${APP_NAME}.app" "../${DIST_ZIP}"
cd ..

# Add README to zip
zip -u "${DIST_ZIP}" "${BUILD_DIR}/README.txt"

# Generate checksum
shasum -a 256 "${DIST_ZIP}" > "${DIST_ZIP}.sha256"

echo "Package created: ${DIST_ZIP}"
echo "SHA256: $(cat ${DIST_ZIP}.sha256)"
echo "Size: $(du -h ${DIST_ZIP} | cut -f1)"
```

**Notarization Script:**

```bash
#!/bin/bash
# scripts/notarize.sh

set -e

APP_BUNDLE="$1"
APP_NAME=$(basename "${APP_BUNDLE}" .app)
TEMP_ZIP="/tmp/${APP_NAME}-notarize.zip"
APPLE_ID="your@email.com"
TEAM_ID="YOUR_TEAM_ID"
KEYCHAIN_PROFILE="notarytool-password"

if [ ! -d "${APP_BUNDLE}" ]; then
  echo "Error: App bundle not found: ${APP_BUNDLE}"
  exit 1
fi

# Create temporary zip for notarization
echo "Creating archive for notarization..."
ditto -c -k --keepParent "${APP_BUNDLE}" "${TEMP_ZIP}"

# Submit to Apple
echo "Submitting to Apple notary service..."
xcrun notarytool submit "${TEMP_ZIP}" \
  --apple-id "${APPLE_ID}" \
  --team-id "${TEAM_ID}" \
  --password "@keychain:${KEYCHAIN_PROFILE}" \
  --wait \
  --timeout 30m

# Check status
echo "Checking notarization status..."
SUBMISSION_ID=$(xcrun notarytool history \
  --apple-id "${APPLE_ID}" \
  --team-id "${TEAM_ID}" \
  --password "@keychain:${KEYCHAIN_PROFILE}" \
  | grep "Accepted" | head -1 | awk '{print $5}')

if [ -z "${SUBMISSION_ID}" ]; then
  echo "Error: Notarization failed or pending"
  xcrun notarytool log "${SUBMISSION_ID}" \
    --apple-id "${APPLE_ID}" \
    --team-id "${TEAM_ID}" \
    --password "@keychain:${KEYCHAIN_PROFILE}"
  exit 1
fi

# Staple the ticket
echo "Stapling ticket to app bundle..."
xcrun stapler staple "${APP_BUNDLE}"

# Verify staple
echo "Verifying staple..."
xcrun stapler validate "${APP_BUNDLE}"

# Clean up
rm "${TEMP_ZIP}"

echo "Notarization complete!"
```

**Keychain Setup (one-time):**

```bash
# Store notarization password in keychain
xcrun notarytool store-credentials "notarytool-password" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "app-specific-password"
```

### LaunchAgent Plist Examples

**Recording Agent (com.playback.recording.plist):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Agent Identification -->
    <key>Label</key>
    <string>com.playback.recording</string>

    <!-- Program to Run -->
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Applications/Playback.app/Contents/Resources/scripts/record_screen.py</string>
    </array>

    <!-- Working Directory -->
    <key>WorkingDirectory</key>
    <string>/Users/USERNAME/Library/Application Support/Playback</string>

    <!-- Keep Alive (restart if crashes) -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>

    <!-- Logging -->
    <key>StandardOutPath</key>
    <string>/Users/USERNAME/Library/Logs/Playback/recording.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/USERNAME/Library/Logs/Playback/recording-error.log</string>

    <!-- Environment Variables -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PLAYBACK_CONFIG</key>
        <string>/Users/USERNAME/Library/Application Support/Playback/config.json</string>
        <key>PLAYBACK_DATA_DIR</key>
        <string>/Users/USERNAME/Library/Application Support/Playback/data</string>
    </dict>

    <!-- Resource Limits -->
    <key>ProcessType</key>
    <string>Background</string>
    <key>Nice</key>
    <integer>5</integer>

    <!-- Don't start automatically on load -->
    <key>RunAtLoad</key>
    <false/>

    <!-- Only run when user is logged in -->
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
```

**Processing Agent (com.playback.processing.plist):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Agent Identification -->
    <key>Label</key>
    <string>com.playback.processing</string>

    <!-- Program to Run -->
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Applications/Playback.app/Contents/Resources/scripts/build_chunks_from_temp.py</string>
    </array>

    <!-- Working Directory -->
    <key>WorkingDirectory</key>
    <string>/Users/USERNAME/Library/Application Support/Playback</string>

    <!-- Run Every 5 Minutes (300 seconds) -->
    <key>StartInterval</key>
    <integer>300</integer>

    <!-- Run Immediately When Loaded -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Logging -->
    <key>StandardOutPath</key>
    <string>/Users/USERNAME/Library/Logs/Playback/processing.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/USERNAME/Library/Logs/Playback/processing-error.log</string>

    <!-- Environment Variables -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PLAYBACK_CONFIG</key>
        <string>/Users/USERNAME/Library/Application Support/Playback/config.json</string>
        <key>PLAYBACK_DATA_DIR</key>
        <string>/Users/USERNAME/Library/Application Support/Playback/data</string>
        <key>FFMPEG_PATH</key>
        <string>/opt/homebrew/bin/ffmpeg</string>
    </dict>

    <!-- Resource Limits -->
    <key>ProcessType</key>
    <string>Background</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>LowPriorityIO</key>
    <true/>

    <!-- Only run when user is logged in -->
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>

    <!-- Throttle if taking too long -->
    <key>ThrottleInterval</key>
    <integer>60</integer>
</dict>
</plist>
```

**Menu Bar Agent (com.playback.menubar.plist):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Agent Identification -->
    <key>Label</key>
    <string>com.playback.menubar</string>

    <!-- Program to Run -->
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Playback.app/Contents/MacOS/Playback</string>
        <string>--menubar-only</string>
    </array>

    <!-- Keep Alive -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>

    <!-- Run Immediately When Loaded -->
    <key>RunAtLoad</key>
    <true/>

    <!-- Logging -->
    <key>StandardOutPath</key>
    <string>/Users/USERNAME/Library/Logs/Playback/menubar.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/USERNAME/Library/Logs/Playback/menubar-error.log</string>

    <!-- Run in user session (required for menu bar apps) -->
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
```

**LaunchAgent Installation Commands:**

```bash
# Copy plist to LaunchAgents directory
cp com.playback.recording.plist ~/Library/LaunchAgents/
cp com.playback.processing.plist ~/Library/LaunchAgents/
cp com.playback.menubar.plist ~/Library/LaunchAgents/

# Set proper permissions
chmod 644 ~/Library/LaunchAgents/com.playback.*.plist

# Validate plist syntax
plutil -lint ~/Library/LaunchAgents/com.playback.recording.plist
plutil -lint ~/Library/LaunchAgents/com.playback.processing.plist
plutil -lint ~/Library/LaunchAgents/com.playback.menubar.plist

# Load agents
launchctl load ~/Library/LaunchAgents/com.playback.menubar.plist
launchctl load ~/Library/LaunchAgents/com.playback.processing.plist
# Recording agent loaded only if user enables it
# launchctl load ~/Library/LaunchAgents/com.playback.recording.plist

# Check agent status
launchctl list | grep com.playback

# View agent output
tail -f ~/Library/Logs/Playback/processing.log

# Unload agents
launchctl unload ~/Library/LaunchAgents/com.playback.menubar.plist
launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist
launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist
```

### First-Run Wizard Implementation

**WelcomeView.swift:**

```swift
import SwiftUI

struct WelcomeView: View {
    @Binding var currentStep: Int

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // App Icon
            Image("AppIcon")
                .resizable()
                .frame(width: 120, height: 120)
                .cornerRadius(20)

            // Title
            Text("Welcome to Playback")
                .font(.system(size: 36, weight: .bold))

            // Subtitle
            Text("Your personal screen history")
                .font(.system(size: 18))
                .foregroundColor(.secondary)

            // Description
            Text("Playback continuously captures your screen in the background, allowing you to search and replay anything you've seen or done on your Mac.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 50)

            Spacer()

            // Get Started Button
            Button(action: {
                currentStep += 1
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
            }) {
                Text("Get Started")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 200, height: 44)
                    .background(Color.accentColor)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(width: 600, height: 500)
    }
}
```

**PermissionsView.swift:**

```swift
import SwiftUI
import AVFoundation

struct PermissionsView: View {
    @Binding var currentStep: Int
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        VStack(spacing: 30) {
            Text("System Permissions")
                .font(.system(size: 32, weight: .bold))

            Text("Playback needs the following permissions to work correctly:")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            // Screen Recording Permission
            PermissionRow(
                icon: "video.fill",
                title: "Screen Recording",
                description: "Required to capture your screen",
                status: screenRecordingGranted,
                isRequired: true,
                action: {
                    openScreenRecordingPreferences()
                }
            )

            // Accessibility Permission
            PermissionRow(
                icon: "accessibility",
                title: "Accessibility",
                description: "Optional: Track active window names",
                status: accessibilityGranted,
                isRequired: false,
                action: {
                    openAccessibilityPreferences()
                }
            )

            Spacer()

            HStack(spacing: 20) {
                // Back Button
                Button("Back") {
                    currentStep -= 1
                }
                .buttonStyle(.plain)

                // Continue Button
                Button(action: {
                    if screenRecordingGranted {
                        currentStep += 1
                    }
                }) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 150, height: 44)
                        .background(screenRecordingGranted ? Color.accentColor : Color.gray)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!screenRecordingGranted)
            }
        }
        .frame(width: 600, height: 500)
        .onAppear(perform: checkPermissions)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            checkPermissions()
        }
    }

    func checkPermissions() {
        // Check Screen Recording
        screenRecordingGranted = CGPreflightScreenCaptureAccess()

        // Check Accessibility
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    func openScreenRecordingPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)

        // Request permission
        CGRequestScreenCaptureAccess()
    }

    func openAccessibilityPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: Bool
    let isRequired: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 40, height: 40)

            // Text
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    if isRequired {
                        Text("Required")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Status / Button
            if status {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.green)
            } else {
                Button("Open Settings") {
                    action()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .padding(.horizontal, 50)
    }
}
```

**StorageView.swift:**

```swift
import SwiftUI

struct StorageView: View {
    @Binding var currentStep: Int
    @State private var storageLocation: URL
    @State private var availableSpace: String = "Calculating..."
    @State private var showingFilePicker = false

    init(currentStep: Binding<Int>) {
        self._currentStep = currentStep
        let defaultPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Playback/data")
        self._storageLocation = State(initialValue: defaultPath)
    }

    var body: some View {
        VStack(spacing: 30) {
            Text("Storage Location")
                .font(.system(size: 32, weight: .bold))

            Text("Choose where Playback should store your recordings")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            VStack(spacing: 15) {
                // Current Location
                HStack {
                    Text("Location:")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                }

                HStack {
                    Text(storageLocation.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Change...") {
                        showingFilePicker = true
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Available Space
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundColor(.accentColor)
                    Text("Available space: \(availableSpace)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }

                // Space Requirements
                VStack(alignment: .leading, spacing: 10) {
                    Text("Estimated storage requirements:")
                        .font(.system(size: 12, weight: .semibold))

                    StorageEstimateRow(label: "Per hour (720p, 1fps)", value: "~1.5 GB")
                    StorageEstimateRow(label: "Per day (10 hours)", value: "~15 GB")
                    StorageEstimateRow(label: "Per month (30 days)", value: "~450 GB")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
            }
            .padding(.horizontal, 50)

            Spacer()

            HStack(spacing: 20) {
                Button("Back") {
                    currentStep -= 1
                }
                .buttonStyle(.plain)

                Button(action: {
                    if validateStorageLocation() {
                        createDirectoryStructure()
                        saveStorageLocation()
                        currentStep += 1
                    }
                }) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 150, height: 44)
                        .background(Color.accentColor)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 600, height: 500)
        .onAppear(perform: updateAvailableSpace)
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder]
        ) { result in
            if case .success(let url) = result {
                storageLocation = url.appendingPathComponent("Playback/data")
                updateAvailableSpace()
            }
        }
    }

    func updateAvailableSpace() {
        do {
            let values = try storageLocation.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                availableSpace = ByteCountFormatter.string(fromByteCount: capacity, countStyle: .file)
            }
        } catch {
            availableSpace = "Unknown"
        }
    }

    func validateStorageLocation() -> Bool {
        // Check write permissions
        let testFile = storageLocation.appendingPathComponent(".test")
        do {
            try "test".write(to: testFile, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFile)
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = "Invalid Location"
            alert.informativeText = "Cannot write to selected location. Please choose a different folder."
            alert.runModal()
            return false
        }
    }

    func createDirectoryStructure() {
        let dirs = ["temp", "chunks", "logs"]
        for dir in dirs {
            let path = storageLocation.appendingPathComponent(dir)
            try? FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }

        // Set permissions (user read/write only)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: storageLocation.path
        )
    }

    func saveStorageLocation() {
        UserDefaults.standard.set(storageLocation.path, forKey: "storageLocation")
    }
}

struct StorageEstimateRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }
}
```

**DependencyView.swift:**

```swift
import SwiftUI

struct DependencyView: View {
    @Binding var currentStep: Int
    @State private var pythonStatus: DependencyStatus = .checking
    @State private var ffmpegStatus: DependencyStatus = .checking

    enum DependencyStatus {
        case checking
        case found(String)
        case notFound
        case error(String)
    }

    var body: some View {
        VStack(spacing: 30) {
            Text("System Dependencies")
                .font(.system(size: 32, weight: .bold))

            Text("Checking required software...")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            VStack(spacing: 20) {
                // Python Dependency
                DependencyRow(
                    icon: "terminal.fill",
                    title: "Python 3.12+",
                    status: pythonStatus,
                    installCommand: "brew install python@3.12"
                )

                // FFmpeg Dependency
                DependencyRow(
                    icon: "video.fill",
                    title: "FFmpeg 7.0+",
                    status: ffmpegStatus,
                    installCommand: "brew install ffmpeg"
                )
            }
            .padding(.horizontal, 50)

            Spacer()

            HStack(spacing: 20) {
                Button("Back") {
                    currentStep -= 1
                }
                .buttonStyle(.plain)

                Button("Check Again") {
                    checkDependencies()
                }
                .buttonStyle(.bordered)

                Button(action: {
                    if allDependenciesMet {
                        currentStep += 1
                    }
                }) {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 150, height: 44)
                        .background(allDependenciesMet ? Color.accentColor : Color.gray)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
                .disabled(!allDependenciesMet)
            }
        }
        .frame(width: 600, height: 500)
        .onAppear(perform: checkDependencies)
    }

    var allDependenciesMet: Bool {
        if case .found = pythonStatus, case .found = ffmpegStatus {
            return true
        }
        return false
    }

    func checkDependencies() {
        pythonStatus = .checking
        ffmpegStatus = .checking

        DispatchQueue.global(qos: .userInitiated).async {
            checkPython()
            checkFFmpeg()
        }
    }

    func checkPython() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            if let versionMatch = output.range(of: #"Python (\d+\.\d+)"#, options: .regularExpression) {
                let versionStr = String(output[versionMatch])
                let version = versionStr.replacingOccurrences(of: "Python ", with: "")

                if let major = Double(version.split(separator: ".").prefix(2).joined(separator: ".")),
                   major >= 3.12 {
                    DispatchQueue.main.async {
                        pythonStatus = .found(version)
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                pythonStatus = .notFound
            }
        } catch {
            DispatchQueue.main.async {
                pythonStatus = .error(error.localizedDescription)
            }
        }
    }

    func checkFFmpeg() {
        let paths = [
            "/opt/homebrew/bin/ffmpeg",  // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",     // Intel Homebrew
            Bundle.main.resourceURL?.appendingPathComponent("ffmpeg").path ?? ""
        ]

        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["-version"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                if let versionMatch = output.range(of: #"ffmpeg version (\d+\.\d+)"#, options: .regularExpression) {
                    let versionStr = String(output[versionMatch])
                    let version = versionStr.replacingOccurrences(of: "ffmpeg version ", with: "")

                    // Check for libx264
                    if output.contains("--enable-libx264") {
                        DispatchQueue.main.async {
                            ffmpegStatus = .found("\(version) (libx264)")
                        }
                        return
                    }
                }
            } catch {}
        }

        DispatchQueue.main.async {
            ffmpegStatus = .notFound
        }
    }
}

struct DependencyRow: View {
    let icon: String
    let title: String
    let status: DependencyView.DependencyStatus
    let installCommand: String

    var body: some View {
        HStack(spacing: 15) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.accentColor)
                .frame(width: 40, height: 40)

            // Title
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                // Status
                switch status {
                case .checking:
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Checking...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                case .found(let version):
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Found: \(version)")
                            .font(.system(size: 12))
                            .foregroundColor(.green)
                    }

                case .notFound:
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("Not found")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }

                        Text("Install via Homebrew:")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        HStack {
                            Text(installCommand)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(installCommand, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(4)
                    }

                case .error(let message):
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Error: \(message)")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }
}
```

### Code Signing and Notarization

**Entitlements File (Playback.entitlements):**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Screen Recording Permission -->
    <key>com.apple.security.device.camera</key>
    <true/>

    <!-- Automation and Apple Events -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>

    <!-- App Sandbox (disabled for screen recording) -->
    <key>com.apple.security.app-sandbox</key>
    <false/>

    <!-- Hardened Runtime -->
    <key>com.apple.security.cs.allow-jit</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <false/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>

    <!-- File Access -->
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
```

**Code Signing Commands:**

```bash
# Sign app bundle with Developer ID
codesign --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --deep \
  --force \
  --options runtime \
  --timestamp \
  --entitlements Playback/Playback.entitlements \
  build/Playback.app

# Verify signature
codesign --verify --verbose=4 build/Playback.app

# Display signature details
codesign --display --verbose=4 build/Playback.app

# Check entitlements
codesign --display --entitlements - build/Playback.app

# Verify Gatekeeper will allow
spctl --assess --verbose=4 --type execute build/Playback.app
```

### Update Mechanism

**version.json Format:**

```json
{
  "version": "1.2.0",
  "build": 120,
  "releaseDate": "2026-02-07",
  "minimumSystemVersion": "26.0",
  "downloadUrl": "https://falconer.com/playback/downloads/Playback-1.2.0.zip",
  "sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "fileSize": 52428800,
  "releaseNotes": "https://falconer.com/playback/releases/1.2.0.html",
  "changelog": [
    "Added search performance improvements",
    "Fixed memory leak in video processing",
    "Updated FFmpeg to version 7.1"
  ],
  "critical": false,
  "deprecated": []
}
```

**UpdateChecker.swift:**

```swift
import Foundation

class UpdateChecker {
    static let shared = UpdateChecker()
    private let versionURL = URL(string: "https://falconer.com/playback/version.json")!
    private let currentVersion: String
    private let lastCheckKey = "lastUpdateCheck"

    init() {
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    func checkForUpdates(completion: @escaping (UpdateInfo?) -> Void) {
        // Check once per day
        if let lastCheck = UserDefaults.standard.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < 86400 {
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: versionURL) { data, response, error in
            guard let data = data, error == nil else {
                completion(nil)
                return
            }

            do {
                let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
                UserDefaults.standard.set(Date(), forKey: self.lastCheckKey)

                if self.isNewerVersion(info.version) {
                    DispatchQueue.main.async {
                        completion(info)
                    }
                } else {
                    completion(nil)
                }
            } catch {
                print("Failed to decode update info: \(error)")
                completion(nil)
            }
        }.resume()
    }

    private func isNewerVersion(_ remoteVersion: String) -> Bool {
        let current = currentVersion.split(separator: ".").compactMap { Int($0) }
        let remote = remoteVersion.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(current.count, remote.count) {
            let c = i < current.count ? current[i] : 0
            let r = i < remote.count ? remote[i] : 0

            if r > c { return true }
            if r < c { return false }
        }

        return false
    }
}

struct UpdateInfo: Codable {
    let version: String
    let build: Int
    let releaseDate: String
    let minimumSystemVersion: String
    let downloadUrl: String
    let sha256: String
    let fileSize: Int
    let releaseNotes: String
    let changelog: [String]
    let critical: Bool
    let deprecated: [String]
}
```

### Uninstallation Script

**uninstall.sh (Complete Bash Implementation):**

```bash
#!/bin/bash
# Playback Uninstaller Script
# Version: 1.0
# This script removes all Playback components from your system

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

APP_NAME="Playback"
BUNDLE_ID="com.playback"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
APP_SUPPORT_DIR="${HOME}/Library/Application Support/Playback"
LOGS_DIR="${HOME}/Library/Logs/Playback"
APP_DIR="/Applications/Playback.app"

echo -e "${GREEN}Playback Uninstaller${NC}"
echo "======================================"
echo ""

# Function to print status
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Confirm uninstallation
echo "This will remove Playback from your system."
echo ""
read -p "Do you want to continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstallation cancelled."
    exit 0
fi

echo ""
echo "Starting uninstallation..."
echo ""

# Step 1: Stop running processes
echo "Stopping running processes..."
PIDS=$(pgrep -f "Playback" || true)
if [ -n "$PIDS" ]; then
    killall "Playback" 2>/dev/null || true
    sleep 2
    print_status "Stopped Playback processes"
else
    print_warning "No running Playback processes found"
fi

# Step 2: Unload LaunchAgents
echo ""
echo "Unloading LaunchAgents..."

AGENTS=(
    "${BUNDLE_ID}.recording"
    "${BUNDLE_ID}.processing"
    "${BUNDLE_ID}.menubar"
)

for agent in "${AGENTS[@]}"; do
    PLIST="${LAUNCH_AGENTS_DIR}/${agent}.plist"
    if [ -f "${PLIST}" ]; then
        launchctl unload "${PLIST}" 2>/dev/null || true
        print_status "Unloaded ${agent}"
    fi
done

# Step 3: Remove LaunchAgent plists
echo ""
echo "Removing LaunchAgent plists..."

for agent in "${AGENTS[@]}"; do
    PLIST="${LAUNCH_AGENTS_DIR}/${agent}.plist"
    if [ -f "${PLIST}" ]; then
        rm "${PLIST}"
        print_status "Removed ${agent}.plist"
    fi
done

# Step 4: Remove application bundle
echo ""
echo "Removing application bundle..."

if [ -d "${APP_DIR}" ]; then
    rm -rf "${APP_DIR}"
    print_status "Removed ${APP_DIR}"
else
    print_warning "Application bundle not found at ${APP_DIR}"
fi

# Step 5: Ask about data deletion
echo ""
echo "Playback stores recordings and data in:"
echo "  ${APP_SUPPORT_DIR}"
echo ""

# Calculate data size
if [ -d "${APP_SUPPORT_DIR}" ]; then
    DATA_SIZE=$(du -sh "${APP_SUPPORT_DIR}" 2>/dev/null | cut -f1)
    echo "Current data size: ${DATA_SIZE}"
    echo ""
fi

read -p "Do you want to delete all recordings and data? (y/N) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    if [ -d "${APP_SUPPORT_DIR}" ]; then
        rm -rf "${APP_SUPPORT_DIR}"
        print_status "Deleted ${APP_SUPPORT_DIR}"
    fi
else
    print_warning "Keeping data at ${APP_SUPPORT_DIR}"
    echo "         You can manually delete this folder later if needed."
fi

# Step 6: Remove logs
echo ""
echo "Removing logs..."

if [ -d "${LOGS_DIR}" ]; then
    rm -rf "${LOGS_DIR}"
    print_status "Removed ${LOGS_DIR}"
else
    print_warning "Logs directory not found"
fi

# Step 7: Clean up preferences
echo ""
echo "Cleaning up preferences..."

defaults delete com.playback 2>/dev/null || print_warning "No preferences found"
print_status "Cleaned preferences"

# Step 8: Verify uninstallation
echo ""
echo "Verifying uninstallation..."

REMAINING=()

if pgrep -f "Playback" >/dev/null 2>&1; then
    REMAINING+=("Running processes still found")
fi

for agent in "${AGENTS[@]}"; do
    if [ -f "${LAUNCH_AGENTS_DIR}/${agent}.plist" ]; then
        REMAINING+=("LaunchAgent plist still exists: ${agent}.plist")
    fi
done

if [ -d "${APP_DIR}" ]; then
    REMAINING+=("Application bundle still exists")
fi

if [ ${#REMAINING[@]} -eq 0 ]; then
    print_status "Uninstallation complete!"
    echo ""
    echo -e "${GREEN}Playback has been successfully removed from your system.${NC}"

    if [ -d "${APP_SUPPORT_DIR}" ]; then
        echo ""
        echo "Data preserved at: ${APP_SUPPORT_DIR}"
    fi
else
    echo ""
    print_error "Uninstallation incomplete. Remaining items:"
    for item in "${REMAINING[@]}"; do
        echo "  - ${item}"
    done
    echo ""
    echo "Please manually remove these items or run the script again."
    exit 1
fi

echo ""
echo "Thank you for using Playback!"
echo ""
```

**Make script executable:**

```bash
chmod +x uninstall.sh
```

### Dependency Detection Code Examples

**PythonChecker.swift:**

```swift
import Foundation

class PythonChecker {
    static func checkPython() -> (available: Bool, version: String?, path: String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["--version"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse version (e.g., "Python 3.12.1")
            let regex = try NSRegularExpression(pattern: #"Python (\d+\.\d+\.\d+)"#)
            let range = NSRange(output.startIndex..., in: output)

            if let match = regex.firstMatch(in: output, range: range),
               let versionRange = Range(match.range(at: 1), in: output) {
                let version = String(output[versionRange])
                let versionComponents = version.split(separator: ".").compactMap { Int($0) }

                // Check if >= 3.12
                if versionComponents.count >= 2,
                   versionComponents[0] >= 3,
                   versionComponents[1] >= 12 {
                    return (true, version, "/usr/bin/python3")
                }
            }

            return (false, nil, nil)
        } catch {
            return (false, nil, nil)
        }
    }

    static func getInstallInstructions() -> String {
        return """
        Python 3.12 or later is required but not found.

        To install Python via Homebrew:
        1. Open Terminal
        2. Run: brew install python@3.12
        3. Restart Playback

        Alternatively, download from: https://www.python.org/downloads/
        """
    }
}
```

**FFmpegChecker.swift:**

```swift
import Foundation

class FFmpegChecker {
    static func checkFFmpeg() -> (available: Bool, version: String?, path: String?, hasLibx264: Bool) {
        let searchPaths = [
            "/opt/homebrew/bin/ffmpeg",     // Apple Silicon Homebrew
            "/usr/local/bin/ffmpeg",        // Intel Homebrew
            Bundle.main.resourceURL?.appendingPathComponent("ffmpeg").path ?? ""  // Bundled
        ]

        for path in searchPaths {
            guard FileManager.default.fileExists(atPath: path) else { continue }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: path)
            task.arguments = ["-version"]

            let pipe = Pipe()
            task.standardOutput = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                // Parse version (e.g., "ffmpeg version 7.0")
                let regex = try NSRegularExpression(pattern: #"ffmpeg version (\d+\.\d+)"#)
                let range = NSRange(output.startIndex..., in: output)

                if let match = regex.firstMatch(in: output, range: range),
                   let versionRange = Range(match.range(at: 1), in: output) {
                    let version = String(output[versionRange])
                    let hasLibx264 = output.contains("--enable-libx264") || output.contains("libx264")

                    // Check if >= 7.0
                    if let majorVersion = Double(version), majorVersion >= 7.0 {
                        return (true, version, path, hasLibx264)
                    }
                }
            } catch {}
        }

        return (false, nil, nil, false)
    }

    static func getInstallInstructions() -> String {
        return """
        FFmpeg 7.0 or later with libx264 support is required but not found.

        To install FFmpeg via Homebrew:
        1. Open Terminal
        2. Run: brew install ffmpeg
        3. Restart Playback

        Alternatively, download from: https://ffmpeg.org/download.html
        """
    }
}

## Testing Checklist

### Installation Tests
- [ ] Fresh install on clean macOS Tahoe 26.0
  - Verify .zip downloads correctly
  - Verify unzip preserves code signature
  - Verify drag to Applications works
  - Verify first launch triggers setup wizard
  - Verify all 5 setup screens display correctly

- [ ] Install with existing Python 3.12+
  - Verify Python detection succeeds
  - Verify no duplicate Python installation

- [ ] Install without FFmpeg
  - Verify FFmpeg detection fails gracefully
  - Verify error message shows installation instructions
  - Verify Homebrew install command is correct

- [ ] Install on different Apple Silicon Macs
  - [ ] M1 Mac
  - [ ] M2 Mac
  - [ ] M3 Mac
  - [ ] M4 Mac

### Permission Tests
- [ ] Screen Recording permission
  - Verify request appears on first run
  - Verify "Open System Preferences" button works
  - Verify app detects when permission granted
  - Verify recording fails gracefully without permission

- [ ] Accessibility permission (optional)
  - Verify request appears on first run
  - Verify "Skip" option works
  - Verify app functions without it
  - Verify app tracking works with it

- [ ] File system permissions
  - Verify data directory creation succeeds
  - Verify write permissions for recordings
  - Verify custom storage location works

### LaunchAgent Tests
- [ ] Recording LaunchAgent
  - Verify plist file created correctly
  - Verify plutil validation passes
  - Verify launchctl load succeeds
  - Verify process starts when loaded
  - Verify KeepAlive restarts on crash

- [ ] Processing LaunchAgent
  - Verify plist file created correctly
  - Verify StartInterval triggers every 5 minutes
  - Verify process runs successfully
  - Verify RunAtLoad starts immediately

- [ ] Menu bar LaunchAgent
  - Verify plist file created correctly
  - Verify KeepAlive keeps app running
  - Verify app appears in menu bar

### Dependency Tests
- [ ] Python version detection
  - Test with Python 3.12 (pass)
  - Test with Python 3.11 (fail with error)
  - Test with no Python (fail with error)
  - Verify error message includes installation instructions

- [ ] FFmpeg detection
  - Test with Homebrew FFmpeg (pass)
  - Test with bundled FFmpeg (pass)
  - Test with no FFmpeg (fail with error)
  - Test with FFmpeg 6.x (warn but allow)
  - Verify libx264 support detected

### Code Signing Tests
- [ ] Development signing
  - Verify ad-hoc signature applied
  - Verify app runs locally
  - Verify debug builds work

- [ ] Production signing
  - Verify Developer ID certificate used
  - Verify deep signing (all components signed)
  - Verify signature verification passes
  - Verify Hardened Runtime enabled
  - Verify entitlements present

### Notarization Tests
- [ ] Submission
  - Verify zip upload succeeds
  - Verify notarization completes without errors
  - Verify stapling succeeds
  - Verify staple validation passes

- [ ] Gatekeeper
  - Download signed+notarized app
  - Verify first launch shows no warnings
  - Verify "Unidentified Developer" warning absent
  - Verify app opens normally

### Update Tests
- [ ] Version check
  - Verify update check runs once per day
  - Verify network request to version.json
  - Verify version comparison logic
  - Verify notification shows when update available

- [ ] Update installation
  - Install version 1.0
  - Update to version 1.1
  - Verify app replaced successfully
  - Verify config preserved
  - Verify database preserved
  - Verify recordings accessible
  - Verify LaunchAgents updated

- [ ] Config migration
  - Create config with old schema
  - Run migration
  - Verify new schema applied
  - Verify values preserved
  - Verify defaults added for new fields

- [ ] Database migration
  - Create database with old schema
  - Run migration
  - Verify new schema applied
  - Verify data preserved
  - Verify foreign keys intact

### Uninstallation Tests
- [ ] Uninstall with data preservation
  - Run uninstaller
  - Verify services stopped
  - Verify LaunchAgents removed
  - Verify app removed from /Applications
  - Verify data directory preserved
  - Reinstall and verify data accessible

- [ ] Uninstall with data deletion
  - Run uninstaller
  - Choose "Delete all data"
  - Verify data directory deleted
  - Verify logs deleted
  - Verify config deleted
  - Verify no Playback files remain

- [ ] Manual cleanup
  - Delete app bundle manually
  - Run standalone uninstall script
  - Verify LaunchAgents cleaned up
  - Verify orphaned processes killed

### Distribution Tests
- [ ] GitHub Releases
  - Upload .zip file
  - Verify download link works
  - Verify SHA256 checksum matches
  - Verify release notes display

- [ ] Direct download from website
  - Download over HTTPS
  - Verify Safari unzips automatically
  - Verify signature preserved after download
  - Verify first launch works

### Compatibility Tests
- [ ] macOS 26.0 (Tahoe)
  - Verify all features work
  - Verify Screen Recording API works
  - Verify LaunchAgents work
  - Verify permissions UI correct

- [ ] Apple Silicon architectures
  - [ ] M1 (arm64)
  - [ ] M2 (arm64)
  - [ ] M3 (arm64)
  - [ ] M4 (arm64)

### Performance Tests
- [ ] Package size
  - Verify .zip under 100 MB (with bundled FFmpeg)
  - Verify .zip under 20 MB (without bundled FFmpeg)

- [ ] Installation time
  - Verify unzip completes in < 10 seconds
  - Verify first launch setup in < 60 seconds
  - Verify LaunchAgent installation in < 5 seconds

- [ ] Update time
  - Verify update download in < 60 seconds
  - Verify update installation in < 30 seconds
  - Verify app restart in < 10 seconds

### Error Handling Tests
- [ ] Missing dependencies
  - Test without Python installed
  - Test without FFmpeg installed
  - Verify error messages are clear
  - Verify installation instructions correct

- [ ] Permission denied errors
  - Test with read-only /Applications
  - Test with read-only home directory
  - Verify error messages helpful

- [ ] Disk space issues
  - Test with < 100 GB free space
  - Verify warning shown
  - Verify recording disabled if critical

- [ ] Network failures
  - Test update check with no internet
  - Verify graceful fallback
  - Verify no crash or hang

### Security Tests
- [ ] Data protection
  - Verify data directory not world-readable
  - Verify database file permissions correct
  - Verify logs not world-readable

- [ ] Code integrity
  - Verify signature tampering detected
  - Verify modified app won't launch
  - Verify Gatekeeper blocks unsigned updates

- [ ] Privilege escalation
  - Verify no sudo required for installation
  - Verify no admin password prompt
  - Verify runs with user privileges only
