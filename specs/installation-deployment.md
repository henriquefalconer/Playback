# Installation and Deployment Specification

**Component:** Installation and Deployment
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

Playback is distributed as a macOS application bundle with automated installation of dependencies and LaunchAgents. This specification defines the installation process, dependency management, and deployment strategy.

## System Requirements

### Hardware

- **Mac:** Apple Silicon only (M1, M2, M3, M4, or later)
- **RAM:** 8 GB minimum, 16 GB recommended
- **Disk Space:** 100 GB minimum free space (for recordings)
- **Display:** Any resolution (optimized for Retina displays)

### Software

- **macOS:** 26.0 (Tahoe)
- **Python:** 3.12+ (system Python)
- **FFmpeg:** 7.0+ (installed via Homebrew or bundled)

## Installation Methods

### Method 1: Direct Download (.zip) - Arc Style

**Recommended for end users** - Simple, no installer required

**Package Contents:**
- `Playback-1.0.zip` containing:
  - Playback.app (single unified app)
  - README.txt (quick start guide)

**Installation Steps:**
1. User downloads `Playback-1.0.zip` from website
2. Unzip (Safari does this automatically)
3. Drag Playback.app to /Applications
4. Launch Playback.app
5. App handles setup automatically:
   - Creates data directory
   - Installs LaunchAgents (with user permission)
   - Generates default config
   - Requests permissions (Screen Recording, Accessibility)
6. Menu bar icon appears
7. User can enable recording via menu bar toggle

**No installer wizard, no admin password required** - Just like Arc!

### Method 2: Development Build

**For developers**

**Steps:**
1. Clone repository:
   ```bash
   git clone https://github.com/henriquefalconer/playback.git
   cd playback
   ```

2. Install dependencies:
   ```bash
   brew install ffmpeg python@3.10
   ```

3. Build in Xcode:
   ```bash
   xcodebuild -project Playback/Playback.xcodeproj \
     -scheme Playback-Development \
     -configuration Debug \
     build
   ```

4. Run development build:
   ```bash
   open build/Debug/Playback.app
   # Uses isolated dev_data/, doesn't affect production
   ```

## LaunchAgent Installation

### Plist Files

**Location:** `~/Library/LaunchAgents/`

**Files:**
- `com.playback.recording.plist`
- `com.playback.processing.plist`
- `com.playback.menubar.plist`

### Installation Script

```bash
#!/bin/bash
# install_launchagents.sh

LAUNCHAGENT_DIR="$HOME/Library/LaunchAgents"
INSTALL_DIR="/Applications/Playback"

mkdir -p "$LAUNCHAGENT_DIR"

# Recording service
cat > "$LAUNCHAGENT_DIR/com.playback.recording.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.playback.recording</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$HOME/Library/Application Support/Playback/scripts/record_screen.py</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/Playback/recording.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Playback/recording.stderr.log</string>
</dict>
</plist>
EOF

# Processing service
cat > "$LAUNCHAGENT_DIR/com.playback.processing.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.playback.processing</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$HOME/Library/Application Support/Playback/scripts/build_chunks_from_temp.py</string>
        <string>--auto</string>
    </array>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/Playback/processing.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Playback/processing.stderr.log</string>
</dict>
</plist>
EOF

# Menu bar app
cat > "$LAUNCHAGENT_DIR/com.playback.menubar.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.playback.menubar</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Playback Menu.app/Contents/MacOS/Playback Menu</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOF

# Load LaunchAgents
launchctl load "$LAUNCHAGENT_DIR/com.playback.processing.plist"
launchctl load "$LAUNCHAGENT_DIR/com.playback.menubar.plist"

echo "LaunchAgents installed successfully"
```

## Dependency Management

### Python

**Detection:**
```bash
python3 --version
# Python 3.12+ required
```

**Installation:**
```bash
# Option 1: System Python (macOS Tahoe includes Python 3.12+)
# No action needed

# Option 2: Homebrew (for specific version)
brew install python@3.12

# Option 3: python.org installer
# Download from https://www.python.org/downloads/
```

**Verification:**
```python
import sys
assert sys.version_info >= (3, 12), "Python 3.12+ required"
```

### FFmpeg

**Detection:**
```bash
which ffmpeg
# /usr/local/bin/ffmpeg or /opt/homebrew/bin/ffmpeg
```

**Installation:**
```bash
# Homebrew (recommended)
brew install ffmpeg

# MacPorts
sudo port install ffmpeg

# Download binary
# https://evermeet.cx/ffmpeg/
```

**Verification:**
```bash
ffmpeg -version
# ffmpeg version 7.0 or later
# Configuration includes libx264
```

**Bundling (optional):**
- Include FFmpeg binary in app bundle
- Size: ~70 MB (static build)
- Simplifies installation (no Homebrew required)

### Python Packages

**Standard Library Only:**
- No external pip packages required
- All dependencies included in Python standard library

**Optional Enhancement:**
- `psutil` for resource monitoring (can be installed via pip if available)
- Gracefully degrades if not available

## First Run Experience

### 1. Welcome Screen

**Displayed on:** First launch of menu bar app

**Content:**
- Welcome message
- Brief explanation of Playback
- Next button

### 2. Permissions Request

**Screen Recording:**
- Explanation: "Playback needs Screen Recording permission to capture screenshots"
- Button: "Open System Preferences"
- Opens: System Preferences → Privacy & Security → Screen Recording

**Accessibility:**
- Explanation: "Playback needs Accessibility permission to track which app you're using"
- Button: "Open System Preferences" (optional)
- Opens: System Preferences → Privacy & Security → Accessibility
- Note: Optional (can proceed without)

### 3. Storage Location

**Default:** `~/Library/Application Support/Playback/data/`

**Customization (optional):**
- Allow user to choose different location
- Useful for external drives (more space)

**Validation:**
- Check disk space (100 GB minimum recommended)
- Check write permissions

### 4. Initial Configuration

**Prompt for:**
- Start recording now? (Yes/No)
- Processing interval (default: 5 minutes)
- Retention policies (defaults: 1 week temp, never recordings)

**Generate:**
- Default config file
- Data directory structure
- Initial database

### 5. Start Recording

**If user enabled recording:**
- Load recording LaunchAgent
- Show menu bar icon (recording active)
- Show notification: "Playback is now recording"

**If user deferred:**
- Menu bar icon (recording paused)
- User can enable later via toggle

## Update Strategy

### In-Place Updates

**Process:**
1. Download new version
2. Quit all Playback components
3. Replace app bundles in /Applications
4. Replace scripts in ~/Library/Application Support/Playback/
5. Migrate configuration (if schema changed)
6. Migrate database (if schema changed)
7. Reload LaunchAgents
8. Restart menu bar app

**Update Script:**
```bash
#!/bin/bash
# update.sh

NEW_VERSION="$1"

# Stop all services
launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist
launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist
killall "Playback Menu"

# Backup current version
mv /Applications/Playback.app /Applications/Playback.app.backup
mv "/Applications/Playback Menu.app" "/Applications/Playback Menu.app.backup"

# Install new version
cp -R "Playback-$NEW_VERSION/Playback.app" /Applications/
cp -R "Playback-$NEW_VERSION/Playback Menu.app" /Applications/

# Migrate config (if needed)
python3 migrate_config.py

# Restart services
launchctl load ~/Library/LaunchAgents/com.playback.processing.plist
open "/Applications/Playback Menu.app"

echo "Updated to version $NEW_VERSION"
```

### Auto-Update (Future)

**Mechanism:**
- Check for updates on launch (once per day)
- Use Sparkle framework (standard macOS auto-update)
- Notify user when update available
- Download and install in background

## Uninstallation

### Uninstaller Script

**Location:** `/Applications/Uninstall Playback.app`

**Process:**
1. Stop all running services
2. Unload LaunchAgents
3. Remove LaunchAgent plists
4. Remove app bundles
5. Ask: "Delete recordings and data?"
   - Yes: Delete data directory, config, logs
   - No: Keep recordings for future use

**Script:**
```bash
#!/bin/bash
# uninstall.sh

echo "Uninstalling Playback..."

# Stop services
echo "Stopping services..."
launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist 2>/dev/null
launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist 2>/dev/null
launchctl unload ~/Library/LaunchAgents/com.playback.menubar.plist 2>/dev/null

killall "Playback Menu" 2>/dev/null
killall "Playback" 2>/dev/null

# Remove LaunchAgents
echo "Removing LaunchAgents..."
rm ~/Library/LaunchAgents/com.playback.*.plist

# Remove apps
echo "Removing applications..."
rm -rf /Applications/Playback.app
rm -rf "/Applications/Playback Menu.app"
rm -rf "/Applications/Uninstall Playback.app"

# Ask about data
echo ""
read -p "Delete all recordings and data? This cannot be undone. (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Deleting data..."
    rm -rf ~/Library/Application\ Support/Playback
    rm -rf ~/Library/Logs/Playback
    echo "All data deleted"
else
    echo "Recordings preserved at:"
    echo "  ~/Library/Application Support/Playback/data/"
fi

echo ""
echo "Playback uninstalled successfully"
```

## Distribution

### Code Signing

**Development:**
```bash
codesign --sign "Developer ID Application: Your Name" --deep --force Playback.app
```

**Verification:**
```bash
codesign --verify --verbose Playback.app
spctl --assess --verbose Playback.app
```

### Notarization

**Submit for notarization:**
```bash
# Create zip
ditto -c -k --keepParent Playback.app Playback.zip

# Submit to Apple
xcrun notarytool submit Playback.zip \
  --apple-id "your@email.com" \
  --team-id "TEAMID" \
  --password "@keychain:AC_PASSWORD" \
  --wait

# Staple notarization ticket
xcrun stapler staple Playback.app
```

### Package Creation (Arc Style)

**Create .zip with signed app:**
```bash
#!/bin/bash
# scripts/package_release.sh

VERSION="1.0.0"
BUILD_DIR="build/Release"
DIST_DIR="dist"

# Create distribution directory
mkdir -p "$DIST_DIR"

# Copy app
cp -R "$BUILD_DIR/Playback.app" "$DIST_DIR/"

# Create README
cat > "$DIST_DIR/README.txt" <<EOF
Playback v${VERSION}

Installation:
1. Drag Playback.app to your Applications folder
2. Launch Playback.app
3. Grant Screen Recording permission when prompted
4. Enable recording from the menu bar icon

For help: https://falconer.com/playback/help
EOF

# Create zip
cd "$DIST_DIR"
ditto -c -k --keepParent Playback.app ../Playback-${VERSION}.zip
cd ..

echo "✓ Created: Playback-${VERSION}.zip"
```

**No installer scripts needed** - App handles setup on first launch
**Just like Arc Browser** - Simple download, unzip, drag to Applications

### Distribution Channels

**1. GitHub Releases**
- Upload .zip file
- Include checksums (SHA256)
- Release notes

**2. Direct Download**
- Host on website
- HTTPS only
- Verified signatures

**3. Mac App Store (Future)**
- Requires sandboxing
- Requires additional entitlements
- Simplified distribution

## Troubleshooting

### Common Installation Issues

**1. Permission Denied**
```
Error: Permission denied copying to /Applications
```
**Solution:** Run installer with admin privileges

**2. FFmpeg Not Found**
```
Error: ffmpeg command not found
```
**Solution:** Install FFmpeg via Homebrew: `brew install ffmpeg`

**3. Python Version Too Old**
```
Error: Python 3.12+ required, found 3.10
```
**Solution:** Install Python 3.12+: `brew install python@3.12`

**4. LaunchAgent Not Loading**
```
Error: launchctl load failed
```
**Solution:** Check plist syntax: `plutil -lint ~/Library/LaunchAgents/com.playback.recording.plist`

## Testing

### Installation Testing

- [ ] Clean macOS Tahoe 26 installation
- [ ] Installation with existing Python
- [ ] Installation without FFmpeg
- [ ] Installation on M1/M2/M3/M4 Mac
- [ ] Update from previous version
- [ ] Uninstallation (keep data)
- [ ] Uninstallation (delete data)

### Compatibility Testing

- [ ] macOS 26.0 (Tahoe)
- [ ] Apple Silicon M1
- [ ] Apple Silicon M2
- [ ] Apple Silicon M3
- [ ] Apple Silicon M4

## Future Enhancements

1. **App Store Distribution** - Sandbox and submit to Mac App Store
2. **Homebrew Formula** - `brew install playback`
3. **Auto-Update** - Sparkle framework for automatic updates
4. **Multi-Language Support** - Localized installers
5. **Enterprise Deployment** - MDM integration for IT admins
