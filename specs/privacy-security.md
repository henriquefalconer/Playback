# Privacy and Security Specification

**Component:** Privacy and Security
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

Playback handles highly sensitive data (screen recordings of user activity). This specification defines privacy features, security measures, and data protection strategies.

## Privacy Features

### App Exclusion

**Purpose:** Prevent recording of sensitive applications (password managers, banking apps, etc.)

**Configuration:** User-configurable list in Settings → Privacy tab

**Exclusion Modes:**

1. **Skip Screenshot (Recommended)**
   - Don't take screenshot at all when excluded app is frontmost
   - Most privacy-preserving option
   - No record of excluded app activity

2. **Make App Invisible**
   - Take screenshot but black out excluded app windows
   - Preserves timeline continuity
   - Requires window bounds detection

### Exclusion Mode Implementation

**Mode 1: Skip Screenshot**
```python
def should_skip_screenshot() -> bool:
    app_id = get_frontmost_app_bundle_id()
    config = load_config()

    if config["exclusion_mode"] == "skip":
        if app_id in config["excluded_apps"]:
            log_info("Screenshot skipped", metadata={"reason": "excluded_app", "app": app_id})
            return True

    return False
```

**Mode 2: Make App Invisible**
```python
def capture_with_exclusion():
    # 1. Take screenshot normally
    temp_path = capture_screen()

    # 2. Get excluded app windows
    excluded_windows = get_window_bounds_for_apps(config["excluded_apps"])

    # 3. Black out excluded regions
    from PIL import Image, ImageDraw

    img = Image.open(temp_path)
    draw = ImageDraw.Draw(img)

    for window in excluded_windows:
        # Draw black rectangle over window
        draw.rectangle(
            [(window.x, window.y), (window.x + window.width, window.y + window.height)],
            fill="black"
        )

    img.save(temp_path)
```

### Default Exclusions

**Recommended Apps to Exclude:**
- `com.apple.Keychain` - Keychain Access
- `com.1password.1password` - 1Password
- `com.lastpass.LastPass` - LastPass
- `com.dashlane.Dashlane` - Dashlane
- Banking apps (user-specific)

**Not Pre-Configured:** User must explicitly add apps to exclusion list

### Screen Unavailability

**Automatic Pauses (Always Active):**

1. **Screensaver Active**
   - Detected via AppleScript
   - No configuration needed
   - Always skips recording

2. **Display Off**
   - Detected via CoreGraphics (CGGetActiveDisplayList returns 0)
   - No configuration needed
   - Always skips recording

3. **Playback App Visible**
   - Detected via process check
   - Configurable via `pause_on_timeline_open` setting
   - Default: ON

**Implementation:** See `is_screen_unavailable()` in Recording Service Specification

## Security Measures

### Data Storage

**Location:** User's home directory
- `~/Library/Application Support/Playback/data/`
- User-owned, user-writable
- Not accessible by other user accounts

**File Permissions:**
- Screenshots: `0600` (user read/write only)
- Videos: `0600` (user read/write only)
- Database: `0600` (user read/write only)
- Config: `0644` (user read/write, others read)
- Logs: `0644` (user read/write, others read)

**No Encryption at Rest:**
- Files stored unencrypted
- Relies on FileVault for disk-level encryption (user's choice)
- Future enhancement: Optional encryption

### Network Security

**No Network Access:**
- No cloud uploads
- No telemetry/analytics
- No external API calls
- All processing local only

**Firewall:**
- No listening ports
- No network services
- Cannot be accessed remotely

### Process Isolation

**LaunchAgents:**
- Run as user (not root)
- No elevated privileges
- Sandboxed to user's home directory

**App Sandbox:**
- Menu bar app: Not sandboxed (needs to control LaunchAgents)
- Playback app: Not sandboxed (needs full file system access)
- Future: Sandboxed versions for App Store distribution

### Code Signing

**Development:**
- Ad-hoc signing (local development only)

**Distribution:**
- Developer ID signed (for distribution outside App Store)
- Notarized by Apple
- Verifiable signature

### macOS Permissions

**Required Permissions:**

1. **Screen Recording** (TCC)
   - Required by: Recording service, Playback app
   - Purpose: Capture screenshots, display recorded videos
   - Prompt: System automatically prompts on first use
   - Location: System Preferences → Privacy & Security → Screen Recording

2. **Accessibility** (TCC)
   - Required by: Recording service (for app detection)
   - Purpose: Identify frontmost application
   - Prompt: System automatically prompts on first use
   - Location: System Preferences → Privacy & Security → Accessibility
   - Degraded Mode: If denied, app tracking unavailable (records as "unknown")

**Optional Permissions:**
- None

**Denied Permissions Handling:**
```python
def check_permissions():
    # Check Screen Recording permission
    if not has_screen_recording_permission():
        log_critical("Screen Recording permission denied")
        show_notification(
            "Playback Needs Permission",
            "Grant Screen Recording permission in System Preferences"
        )
        sys.exit(1)

    # Check Accessibility permission (non-critical)
    if not has_accessibility_permission():
        log_warning("Accessibility permission denied, app tracking unavailable")
        show_notification(
            "Playback: App Tracking Unavailable",
            "Grant Accessibility permission for app-based timeline colors"
        )
        # Continue without app tracking
```

## Data Retention

### User Control

**Configuration:**
- Temp files: Never, 1 day, 1 week, 1 month
- Recordings: Never, 1 day, 1 week, 1 month

**Default:** Temp files deleted after 1 week, recordings kept indefinitely

**Compliance:**
- User has full control over data retention
- Can delete all data at any time
- No external copies exist

### Manual Deletion

**Settings UI:**
- "Clean Up Now" button triggers immediate cleanup
- Preview before deletion (file count, disk space)
- Confirmation dialog required

**Command Line:**
```bash
# Delete all temp files
rm -rf ~/Library/Application\ Support/Playback/data/temp/*

# Delete all recordings
rm -rf ~/Library/Application\ Support/Playback/data/chunks/*
rm ~/Library/Application\ Support/Playback/data/meta.sqlite3
```

### Uninstallation

**User Data Preservation:**
- Uninstaller asks: "Keep recordings or delete?"
- Option 1: Keep data (only remove apps and LaunchAgents)
- Option 2: Delete everything (including recordings)

**Complete Removal Script:**
```bash
#!/bin/bash
# uninstall.sh

# Stop and remove LaunchAgents
launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist
launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist
rm ~/Library/LaunchAgents/com.playback.*.plist

# Remove app
rm -rf /Applications/Playback.app

# Ask about data
read -p "Delete all recordings and data? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf ~/Library/Application\ Support/Playback
    rm -rf ~/Library/Logs/Playback
fi

echo "Playback uninstalled"
```

## Data Access Control

### Who Can Access Recordings?

**User Only:**
- Files owned by user account
- Standard Unix permissions prevent other users from reading

**Admin Users:**
- Can use `sudo` to access files
- Required for system administration

**Other Apps:**
- Can request permission via TCC (Transparency, Consent, and Control)
- User must explicitly grant permission

### Preventing Unauthorized Access

**Recommendations to User:**

1. **Enable FileVault** (full disk encryption)
   - Protects data if Mac is lost/stolen
   - System Preferences → Privacy & Security → FileVault

2. **Screen Lock When Away**
   - Require password after sleep or screensaver
   - System Preferences → Lock Screen

3. **Strong User Password**
   - Protects against unauthorized login
   - System Preferences → Users & Groups

4. **Don't Share Mac**
   - Each user should have own account
   - Recordings visible only to recording user

## Threat Model

### In Scope

**Threats Addressed:**

1. **Accidental Exposure**
   - App exclusion prevents recording of sensitive apps
   - Automatic pause during screensaver/lock

2. **Local User Snooping**
   - File permissions prevent other users from accessing recordings

3. **Data Leakage**
   - No network transmission
   - No cloud uploads
   - No telemetry

### Out of Scope

**Threats NOT Addressed:**

1. **Physical Access**
   - If attacker has physical access and user password, they can access recordings
   - Mitigation: FileVault, strong password

2. **Malware**
   - If user's account is compromised, malware can access recordings
   - Mitigation: Keep macOS updated, use antivirus

3. **Forensics**
   - Deleted files may be recoverable with forensic tools
   - Mitigation: Secure deletion tools (if needed)

4. **Screen Sharing / Remote Access**
   - Recordings may be visible during screen sharing sessions
   - Mitigation: User awareness, disable screen sharing when not needed

## Privacy Best Practices

### Recommendations for Users

**1. Review Exclusion List Regularly**
- Add any new sensitive apps
- Settings → Privacy → Excluded Apps

**2. Set Appropriate Retention Policies**
- Don't keep recordings longer than needed
- Settings → Storage → Cleanup Policies

**3. Be Aware of Visible Content**
- Notifications, background windows, desktop files
- All visible content is recorded

**4. Secure Your Mac**
- Enable FileVault
- Use strong password
- Enable screen lock

**5. Don't Record Sensitive Sessions**
- Temporarily disable recording for sensitive work
- Menu Bar → Record Screen → OFF

### Recommendations for Developers

**1. Minimize Data Retention**
- Default retention policies favor privacy
- Temp files deleted after 1 week (default)

**2. No External Transmission**
- No network code in recording/processing services
- No telemetry, analytics, or crash reporting

**3. Clear User Consent**
- Explain what data is collected (screen content)
- Explain where it's stored (local only)
- Explain how to delete it (settings UI, manual deletion)

**4. Transparent Operation**
- Menu bar icon shows recording status
- Logs document all operations
- Open source (ideally)

## Compliance

### GDPR (if applicable)

**Right to Access:**
- User has full access to all recordings via playback app
- Can export recordings via timeline viewer (future feature)

**Right to Deletion:**
- User can delete all recordings via settings UI
- Can manually delete files from disk
- Uninstaller offers complete removal

**Right to Portability:**
- Recordings stored in standard formats (PNG, MP4, SQLite)
- Can be copied/moved/exported freely

**Data Minimization:**
- Only captures what's necessary (screen content)
- No additional tracking or profiling

### CCPA (if applicable)

**Notice:**
- Installation documentation explains data collection
- Settings window explains data storage location

**Opt-Out:**
- User can disable recording at any time (menu bar toggle)
- User can delete all data at any time

**Transparency:**
- Full access to all collected data
- No hidden data collection

## Security Audit Checklist

- [ ] No network code in recording/processing services
- [ ] File permissions set correctly (0600 for sensitive files)
- [ ] No hardcoded credentials or API keys
- [ ] Input validation on all user inputs (config file, CLI args)
- [ ] Safe file operations (no path traversal vulnerabilities)
- [ ] No use of deprecated/insecure APIs
- [ ] Code signed and notarized (for distribution)
- [ ] Permissions checked before use (Screen Recording, Accessibility)
- [ ] Error messages don't leak sensitive information
- [ ] Logs don't contain user passwords or secrets

## Future Security Enhancements

### Potential Features

1. **Encryption at Rest**
   - Encrypt screenshots and videos with user password
   - Requires password to view recordings

2. **Automatic Locking**
   - Lock playback app with password after N minutes of inactivity

3. **Redaction Tools**
   - Manual redaction of sensitive areas before archiving
   - Automatic PII detection and blurring (OCR + ML)

4. **Secure Deletion**
   - Overwrite deleted files (DOD 5220.22-M standard)
   - Prevent forensic recovery

5. **Multi-Factor Authentication**
   - Require 2FA to access recordings (for shared Macs)

6. **Audit Logging**
   - Log all access to recordings
   - Detect unauthorized viewing attempts

7. **Watermarking**
   - Embed invisible watermark in recordings
   - Track unauthorized copies
