# Build Process Specification

**Component:** Build System & Testing

## Xcode Project

- **Location:** `src/Playback/Playback.xcodeproj`
- **Target:** Playback (single app bundle)
- **Scheme:** "Playback" (use `-configuration Debug` or `-configuration Release`)
- **Minimum deployment:** macOS 26.0 (Tahoe)
- **Architecture:** Apple Silicon only (arm64)
- **Bundle ID:** `com.falconer.Playback`

## Build Configurations

### Debug

- Compilation conditions: `DEBUG`
- Optimization: `-Onone`
- Testability: enabled
- Signing: macos-codesigning (self-signed)

### Release

- Optimization: `-O`
- Testability: disabled
- Signing: macos-codesigning (self-signed)

## Build Commands

```bash
# Development build
cd src/Playback && xcodebuild -scheme Playback -configuration Debug build

# Release build
cd src/Playback && xcodebuild -scheme Playback -configuration Release build

# Clean
cd src/Playback && xcodebuild -scheme Playback clean

# Archive
cd src/Playback && xcodebuild -scheme Playback -configuration Release archive -archivePath build/Playback.xcarchive
```

## Testing

```bash
# All tests
cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -destination 'platform=macOS'

# Fast tests only
cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -only-testing:PlaybackTests/FastTests

# UI tests
cd src/Playback && xcodebuild test -scheme Playback -configuration Debug -only-testing:PlaybackUITests
```

### Test Targets

- **PlaybackTests/** — Unit tests for models, controllers, services
- **PlaybackUITests/** — UI tests for menu bar, timeline, settings

### Pre-Commit Validation

```bash
./smoke-test.sh
```

Builds Debug configuration and runs the app for 5 seconds to detect initialization crashes.

### Entitlements

```xml
<key>com.apple.security.app-sandbox</key><false/>
<key>com.apple.security.device.camera</key><true/>
<key>com.apple.security.personal-information.screen-capture</key><true/>
```

## Dependencies

- Xcode (latest)
- Swift 6.0+
- No external dependencies (no Python, no FFmpeg)
- All frameworks are Apple system frameworks:
  - SwiftUI, AppKit
  - AVFoundation, ScreenCaptureKit
  - Carbon (for global hotkey)
  - ServiceManagement (for launch at login)
  - SQLite3 (C API)
