# Privacy & Security Implementation Plan

**Component:** Privacy and Security
**Version:** 1.0
**Last Updated:** 2026-02-07

## Implementation Checklist

### App Exclusion System

#### Skip Screenshot Mode
- [ ] Implement frontmost app detection
  - Source: `scripts/record_screen.py` (extend `_get_frontmost_app_bundle_id()`)
  - Method: AppleScript via System Events (requires Accessibility permission)
  - Return: Bundle identifier string (e.g., "com.apple.Safari")

- [ ] Implement skip logic in recording service
  - Source: `scripts/record_screen.py` (add `should_skip_screenshot()` function)
  - Check: Compare frontmost app against exclusion list from config
  - Action: Skip screenshot capture entirely, log the skip event
  - See: "Privacy & Security Details" section below for Mode 1 implementation details

- [ ] Add exclusion logging
  - Source: `scripts/record_screen.py` (in recording loop)
  - Log: `{"timestamp": "...", "event": "screenshot_skipped", "reason": "excluded_app", "app": "com.1password.1password"}`
  - Level: INFO (not WARNING, since this is expected behavior)

#### Make App Invisible Mode (Future Enhancement)
- [ ] Implement window bounds detection
  - Method: CoreGraphics window list API via ctypes
  - Function: `_get_window_bounds_for_apps(bundle_ids: list[str]) -> list[WindowBounds]`
  - Return: List of rectangles (x, y, width, height) for each window

- [ ] Implement screenshot redaction
  - Source: `scripts/record_screen.py` (new function `_redact_excluded_windows()`)
  - Method: Use PIL/Pillow to draw black rectangles over excluded window areas
  - See: "Privacy & Security Details" section below for Mode 2 implementation details

- [ ] Add mode selection to config
  - Config key: `exclusion_mode` (values: "skip" | "invisible")
  - Default: "skip" (most privacy-preserving)

### Default Exclusions Configuration

- [ ] Define recommended exclusion list
  - Location: `scripts/config.py` (constant `RECOMMENDED_EXCLUSIONS`)
  - Apps:
    - `com.apple.keychainaccess` - Keychain Access
    - `com.1password.1password` - 1Password
    - `com.lastpass.LastPass` - LastPass
    - `com.dashlane.Dashlane` - Dashlane
    - `com.agilebits.onepassword7` - 1Password 7
    - `com.keepassxc.keepassxc` - KeePassXC

- [ ] Do NOT auto-enable exclusions
  - Implementation: Recommended list is documentation only
  - User action required: User must manually add apps to exclusion list
  - Rationale: Explicit user consent, avoid surprise behavior

- [ ] Add UI for recommended apps
  - Source: `Playback/Settings/PrivacyTab.swift`
  - UI: List of recommended apps with "Add" buttons
  - Display: App name, bundle ID, reason (e.g., "Password Manager")

### Permission Checking

#### Screen Recording Permission
- [ ] Implement permission check function
  - Source: `scripts/record_screen.py` (add `_has_screen_recording_permission()`)
  - Method: Attempt `screencapture` to temp location, check if it succeeds
  - Alternative: Check CGWindowListCreateImage capability

- [ ] Enforce permission on startup
  - Location: `scripts/record_screen.py` main()
  - Behavior: Exit with error code 1 if permission denied
  - Notification: Show macOS notification with instructions to grant permission
  - See: "macOS Permissions" section below for permission handling details

- [ ] Add permission status UI
  - Source: `Playback/Settings/PrivacyTab.swift`
  - Display: Permission status (granted/denied) with visual indicator
  - Action: "Open System Settings" button to jump to Screen Recording settings

#### Accessibility Permission
- [ ] Implement permission check function
  - Source: `scripts/record_screen.py` (add `_has_accessibility_permission()`)
  - Method: Try to call AppleScript System Events, check for errors
  - Fallback: Continue without app tracking if denied

- [ ] Handle graceful degradation
  - Behavior: If denied, set frontmost app to "unknown" in all screenshots
  - Notification: Show once per session explaining reduced functionality
  - See: "macOS Permissions" section below for graceful degradation details

- [ ] Add permission status UI
  - Source: `Playback/Settings/PrivacyTab.swift`
  - Display: Permission status with explanation of impact if denied
  - Note: "App tracking unavailable - timeline colors will be generic"

### File Permissions Security

- [ ] Set correct permissions on file creation
  - Source: `scripts/record_screen.py`, `scripts/build_chunks_from_temp.py`
  - Method: `os.chmod(path, 0o600)` immediately after creating file
  - Apply to:
    - Screenshots (temp files): 0600
    - Videos (chunks): 0600
    - Database (meta.sqlite3): 0600
    - Config files: 0644
    - Log files: 0644

- [ ] Implement secure file creation helper
  - Source: `scripts/utils.py` (new function `create_secure_file()`)
  - Method: Create file with umask 0077, then explicitly chmod
  - Usage: Wrapper for all sensitive file creation

- [ ] Verify permissions on startup
  - Source: `scripts/record_screen.py` (add `_verify_data_permissions()`)
  - Check: Scan existing data directory, warn about incorrect permissions
  - Action: Optionally auto-fix permissions with user consent

### Network Access Verification

- [ ] Audit all Python scripts for network calls
  - Check: No `import requests`, `urllib`, `http`, `socket`
  - Check: No subprocess calls to `curl`, `wget`, network tools
  - Exception: Only local subprocess calls (screencapture, osascript)

- [ ] Add network access test
  - Source: `scripts/tests/test_network.py`
  - Test: Static analysis of imports
  - Test: Runtime check for network sockets (none should exist)
  - CI: Fail build if network code detected

- [ ] Document network policy
  - Location: README.md § "Privacy Guarantees"
  - Statement: "Playback never accesses the network. All data stays local."
  - Verification: Link to test results, invite code review

### Data Storage Security

#### Directory Structure
- [ ] Create secure data directory
  - Path: `~/Library/Application Support/Playback/data/`
  - Permissions: 0700 (user only, no group/other access)
  - Subdirectories: temp/ (0700), chunks/ (0700)

- [ ] Isolate database file
  - Path: `~/Library/Application Support/Playback/data/meta.sqlite3`
  - Permissions: 0600 (user read/write only)
  - SQLite: Set PRAGMA secure_delete=ON (overwrite deleted data)

#### Encryption at Rest (Future Enhancement)
- [ ] Document encryption roadmap
  - Location: See "Encryption Roadmap" and "Future Security Enhancements" sections in this document
  - Plan: Optional AES-256 encryption with user-provided password
  - Scope: Encrypt screenshots and videos, keep database unencrypted for indexing

### Uninstallation with Data Preservation

- [ ] Create uninstall script
  - Location: `scripts/uninstall.sh`
  - Actions:
    1. Stop all LaunchAgents (launchctl unload)
    2. Remove LaunchAgent plists from ~/Library/LaunchAgents/
    3. Remove applications from /Applications/
    4. Prompt user about data retention

- [ ] Implement data preservation prompt
  - Script: `scripts/uninstall.sh`
  - Prompt: "Delete all recordings and data? (y/N)"
  - Default: N (preserve data)
  - If Y: Remove ~/Library/Application Support/Playback/
  - If N: Keep data, show path for manual deletion later

- [ ] Add uninstall instructions
  - Location: README.md § "Uninstallation"
  - Steps:
    1. Run uninstall script: `bash scripts/uninstall.sh`
    2. Follow prompts for data retention
    3. Manual cleanup (if needed): Paths to logs and cached data

- [ ] Create data export function (before uninstall)
  - Source: `scripts/export_data.py`
  - Export: Copy all chunks and database to user-specified location
  - Format: ZIP archive with manifest file
  - UI: Settings → Privacy → "Export All Data"

### Privacy Settings UI

- [ ] Create PrivacyTab component
  - Source: `Playback/Settings/PrivacyTab.swift`
  - Sections:
    - Permission Status (Screen Recording, Accessibility)
    - App Exclusion (list of excluded apps, add/remove)
    - Recommended Exclusions (quick-add buttons)
    - Data Location (show path, "Reveal in Finder" button)
    - Data Export ("Export All Data" button)

- [ ] Implement excluded apps list view
  - UI: Table with columns: App Name, Bundle ID, Remove button
  - Add: Button to open app picker dialog
  - Picker: Show all running apps, allow manual bundle ID entry

- [ ] Add exclusion mode selector
  - UI: Radio buttons or segmented control
  - Options: "Skip Screenshot" (recommended), "Make App Invisible" (future)
  - Help text: Explain trade-offs of each mode

### Screen Unavailability Detection

- [ ] Verify screensaver detection
  - Source: `scripts/record_screen.py` (already implemented `_check_screensaver_via_applescript()`)
  - Test: Trigger screensaver manually, verify recording stops
  - Implementation: Uses AppleScript to check ScreenSaverEngine process status

- [ ] Verify display off detection
  - Source: `scripts/record_screen.py` (already implemented `_check_display_active()`)
  - Test: Put display to sleep, verify recording stops
  - Implementation: Uses CoreGraphics CGGetActiveDisplayList() API

- [ ] Add Playback app visibility detection
  - Source: `scripts/record_screen.py` (add to `is_screen_unavailable()`)
  - Method: Check if frontmost app is Playback itself
  - Config: `pause_on_timeline_open` (default: true)
  - See: "Screen Unavailability Detection" section below for complete detection logic

### Data Retention and Cleanup

- [ ] Implement automatic cleanup policy
  - Source: `scripts/cleanup.py` (new script)
  - Config keys:
    - `cleanup_temp_after_days` (default: 7)
    - `cleanup_chunks_after_days` (default: never/0)
  - Schedule: Run daily via dedicated cleanup LaunchAgent

- [ ] Create cleanup LaunchAgent
  - Location: `~/Library/LaunchAgents/com.playback.cleanup.plist`
  - Schedule: Daily at 3 AM
  - Script: `scripts/cleanup.py`

- [ ] Add manual cleanup UI
  - Source: `Playback/Settings/StorageTab.swift`
  - Preview: Show file counts and disk space before deletion
  - Buttons: "Clean Temp Files Now", "Delete All Recordings"
  - Confirmation: Require user confirmation with file count display

### Threat Model Documentation

- [ ] Document security boundaries
  - Location: See "Threat Model" section in this document
  - Verify: In-scope threats are mitigated
  - Verify: Out-of-scope threats are clearly documented

- [ ] Create security best practices guide
  - Location: README.md § "Security Best Practices"
  - Recommendations:
    - Enable FileVault
    - Use strong user password
    - Enable screen lock on sleep
    - Don't share Mac user account
    - Review exclusion list regularly

### Security Audit

- [ ] Audit for network access
  - Tool: Static code analysis (grep for network imports)
  - Check: No HTTP clients, no socket code
  - CI: Add automated check in build pipeline

- [ ] Audit file permissions
  - Tool: `scripts/tests/test_security.py`
  - Check: All sensitive files have 0600 permissions
  - Test: Create files and verify permissions

- [ ] Audit for hardcoded secrets
  - Tool: git-secrets or similar
  - Check: No API keys, passwords, tokens in code
  - Exception: Test fixtures clearly marked as non-secret

- [ ] Audit input validation
  - Check: Config file parsing validates types and ranges
  - Check: CLI arguments validated before use
  - Check: File paths sanitized (no path traversal)

- [ ] Audit error messages
  - Check: Errors don't leak sensitive data (paths OK, content NOT OK)
  - Check: Logs don't contain screenshots or video data
  - Check: Logs sanitize bundle IDs and app names

## Privacy & Security Details

### App Exclusion Modes

**Mode 1: Skip Screenshot (Default & Recommended)**
- Implementation: Detect frontmost app bundle ID before each screenshot
- Action: If app is in exclusion list, skip screenshot entirely
- Privacy: Most protective - no data captured at all
- Performance: Minimal overhead (app detection ~50ms)
- Limitations: Timeline shows gap during excluded app usage

**Mode 2: Make App Invisible (Future Enhancement)**
- Implementation: Detect window bounds of excluded apps
- Action: Take screenshot, then redact excluded app windows (black rectangles)
- Privacy: Screenshot captured but sensitive windows removed
- Performance: Higher overhead (window detection + image processing)
- Benefit: Maintains timeline continuity, shows context around excluded app
- Risk: Potential for information leakage through reflections, shadows, or timing

**Technical Implementation:**
```python
def should_skip_screenshot(frontmost_app: str, exclusion_list: list[str]) -> bool:
    """Returns True if screenshot should be skipped entirely."""
    return frontmost_app in exclusion_list

def _get_frontmost_app_bundle_id() -> str:
    """Uses AppleScript via System Events to get active app bundle ID."""
    script = 'tell application "System Events" to get bundle identifier of first application process whose frontmost is true'
    result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else "unknown"
```

### Default Exclusion Recommendations

**Recommended Apps to Exclude:**
- `com.apple.keychainaccess` - Keychain Access (system password manager)
- `com.1password.1password` - 1Password 8
- `com.agilebits.onepassword7` - 1Password 7
- `com.lastpass.LastPass` - LastPass
- `com.dashlane.Dashlane` - Dashlane
- `com.keepassxc.keepassxc` - KeePassXC
- `com.bitwarden.desktop` - Bitwarden
- `org.keepassx.keepassxc` - KeePassX

**Important Policy:**
- These apps are NOT auto-excluded
- User must explicitly add them to exclusion list
- Rationale: Explicit user consent, no surprise behavior
- UI: Settings provides quick-add buttons for recommended apps

### Screen Unavailability Detection

The recording service automatically pauses in these scenarios:

**1. Screensaver Active**
- Detection: AppleScript query to ScreenSaverEngine process
- Method: Check if screensaver process is running
- Implementation: `_check_screensaver_via_applescript()`
- Frequency: Checked before each screenshot

**2. Display Off**
- Detection: CoreGraphics `CGGetActiveDisplayList()` API
- Method: Check if any displays are active
- Implementation: `_check_display_active()`
- Frequency: Checked before each screenshot

**3. Playback App Visible (Optional)**
- Detection: Check if frontmost app is Playback itself
- Config: `pause_on_timeline_open` (default: true)
- Rationale: Prevent recording timeline viewer (privacy while reviewing)
- Implementation: Compare frontmost app to Playback's bundle ID

**4. Screen Locked**
- Detection: Automatic - screencapture fails when screen locked
- Fallback: Recording continues attempting, resumes when unlocked

### Data Storage Security

**Directory Structure:**
```
~/Library/Application Support/Playback/
├── data/                    # 0700 (user only)
│   ├── temp/               # 0700 (temporary screenshots)
│   ├── chunks/             # 0700 (processed videos)
│   └── meta.sqlite3        # 0600 (database)
├── config.json             # 0644 (user config)
└── logs/                   # 0755 (logs)
    └── recording.log       # 0644
```

**File Permissions:**
- Screenshots (temp): `0600` (rw-------)
- Videos (chunks): `0600` (rw-------)
- Database: `0600` (rw-------)
- Config: `0644` (rw-r--r--)
- Logs: `0644` (rw-r--r--)
- Directories: `0700` (rwx------)

**Permission Enforcement:**
```python
def create_secure_file(path: str, content: bytes) -> None:
    """Create file with secure permissions (0600)."""
    # Set restrictive umask
    old_umask = os.umask(0o077)
    try:
        with open(path, 'wb') as f:
            f.write(content)
        # Explicitly set permissions
        os.chmod(path, 0o600)
    finally:
        os.umask(old_umask)
```

**SQLite Security:**
```sql
-- Enable secure delete (overwrite deleted data)
PRAGMA secure_delete = ON;

-- Enable write-ahead logging for better concurrency
PRAGMA journal_mode = WAL;

-- Set restrictive file permissions
-- (handled at OS level, not SQLite PRAGMA)
```

### Encryption Roadmap (Future Enhancement)

**Phase 1: Optional AES-256 Encryption**
- Scope: Encrypt screenshots and video chunks
- Key derivation: PBKDF2-HMAC-SHA256 from user password
- Algorithm: AES-256-GCM (authenticated encryption)
- Database: Remains unencrypted for indexing (only metadata)
- Performance: Encrypt during chunk processing, decrypt on-demand

**Phase 2: Key Management**
- Option A: Password-based (user provides password on app start)
- Option B: Keychain integration (store encryption key in macOS Keychain)
- Option C: Hardware security (T2/Apple Silicon Secure Enclave)

**Considerations:**
- Encryption impacts search performance (must decrypt to search)
- Key loss = permanent data loss (no recovery mechanism)
- Must work with video codec (encrypt container, not re-encode)

### Network Security

**Zero Network Access Policy:**
- No HTTP/HTTPS clients in code
- No socket operations
- No external API calls
- No telemetry or analytics
- No update checks

**Verification:**
```bash
# Static analysis - should find ZERO matches
grep -r "import requests" scripts/
grep -r "import urllib" scripts/
grep -r "import http" scripts/
grep -r "import socket" scripts/
grep -r "urllib.request" scripts/
grep -r "http.client" scripts/

# Runtime verification - no network connections
lsof -p <recording_pid> | grep -i tcp
# Expected: empty result
```

**Allowed Subprocess Calls:**
- `screencapture` - local screenshot capture
- `osascript` - local AppleScript execution
- `ffmpeg` - local video encoding
- `sqlite3` - local database access

### macOS Permissions

**Screen Recording Permission (Required)**
- Purpose: Capture screenshots of all screens
- Location: System Settings → Privacy & Security → Screen Recording
- Check: Attempt screencapture, verify success
- Failure behavior: Exit with error, show notification with instructions
- Permission persistence: Grant once, remains until revoked

**Accessibility Permission (Optional)**
- Purpose: Detect frontmost app for exclusion
- Location: System Settings → Privacy & Security → Accessibility
- Check: Attempt System Events AppleScript, check for errors
- Failure behavior: Continue with graceful degradation (app = "unknown")
- Impact: Without this, app exclusion and timeline colors unavailable

**Permission Check Implementation:**
```python
def _has_screen_recording_permission() -> bool:
    """Check if Screen Recording permission is granted."""
    try:
        # Attempt screenshot to temp location
        temp_file = tempfile.mktemp(suffix='.png')
        result = subprocess.run(
            ['screencapture', '-x', temp_file],
            capture_output=True,
            timeout=5
        )
        if os.path.exists(temp_file):
            os.remove(temp_file)
            return True
        return False
    except Exception:
        return False

def _has_accessibility_permission() -> bool:
    """Check if Accessibility permission is granted."""
    try:
        # Attempt to get frontmost app
        script = 'tell application "System Events" to get name of first application process whose frontmost is true'
        result = subprocess.run(
            ['osascript', '-e', script],
            capture_output=True,
            timeout=5
        )
        return result.returncode == 0
    except Exception:
        return False
```

### Data Retention and Cleanup

**Automatic Cleanup Policies:**
- Temp files: Delete after 7 days (configurable: `cleanup_temp_after_days`)
- Video chunks: Retain indefinitely (configurable: `cleanup_chunks_after_days`)
- Database: Never auto-delete (metadata is small)
- Logs: Rotate after 30 days, keep 10 most recent

**Cleanup Implementation:**
```python
# scripts/cleanup.py
def cleanup_old_files(directory: str, days: int) -> int:
    """Delete files older than specified days. Returns count deleted."""
    now = time.time()
    cutoff = now - (days * 86400)
    deleted = 0

    for root, dirs, files in os.walk(directory):
        for filename in files:
            path = os.path.join(root, filename)
            if os.path.getmtime(path) < cutoff:
                os.remove(path)
                deleted += 1

    return deleted
```

**LaunchAgent for Scheduled Cleanup:**
```xml
<!-- ~/Library/LaunchAgents/com.playback.cleanup.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.playback.cleanup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/python3</string>
        <string>/path/to/scripts/cleanup.py</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
</dict>
</plist>
```

### Uninstallation Procedures

**Uninstall Script (`scripts/uninstall.sh`):**
```bash
#!/bin/bash
set -e

echo "Uninstalling Playback..."

# Stop LaunchAgents
launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.playback.processing.plist 2>/dev/null || true
launchctl unload ~/Library/LaunchAgents/com.playback.cleanup.plist 2>/dev/null || true

# Remove LaunchAgent plists
rm -f ~/Library/LaunchAgents/com.playback.*.plist

# Remove applications
rm -rf /Applications/Playback.app

echo "Playback uninstalled."
echo ""
read -p "Delete all recordings and data? (y/N): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf ~/Library/Application\ Support/Playback/
    echo "All data deleted."
else
    echo "Data preserved at: ~/Library/Application Support/Playback/"
    echo "To delete manually later, run: rm -rf ~/Library/Application\ Support/Playback/"
fi
```

**Data Export (Before Uninstall):**
```python
# scripts/export_data.py
def export_all_data(output_path: str) -> None:
    """Export all recordings and database to ZIP archive."""
    data_dir = os.path.expanduser('~/Library/Application Support/Playback/data')

    with zipfile.ZipFile(output_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
        # Add all chunks
        for root, dirs, files in os.walk(os.path.join(data_dir, 'chunks')):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, data_dir)
                zipf.write(file_path, arcname)

        # Add database
        zipf.write(
            os.path.join(data_dir, 'meta.sqlite3'),
            'meta.sqlite3'
        )

        # Add manifest
        manifest = {
            'export_date': datetime.now().isoformat(),
            'version': '1.0',
            'file_count': len(zipf.namelist())
        }
        zipf.writestr('manifest.json', json.dumps(manifest, indent=2))
```

### Threat Model

**In-Scope Threats (Mitigated):**

1. **Local Privilege Escalation**
   - Threat: Other users on same Mac access recordings
   - Mitigation: File permissions (0600/0700), ~/Library location
   - Residual risk: Root users can still access (expected behavior)

2. **Application-Level Information Disclosure**
   - Threat: Other apps read recording data
   - Mitigation: File permissions prevent access, no IPC/network
   - Residual risk: Apps running as same user can access (OS limitation)

3. **Accidental Data Exposure**
   - Threat: User shares screen/files with recordings visible
   - Mitigation: Non-obvious directory name, file permissions
   - User responsibility: Don't share ~/Library directory

4. **Sensitive Application Recording**
   - Threat: Password managers, banking apps recorded
   - Mitigation: App exclusion system (user must enable)
   - User responsibility: Configure exclusions appropriately

5. **Recording During Private Moments**
   - Threat: Screen recorded during sensitive activities
   - Mitigation: Screensaver detection, display off detection, manual pause
   - User responsibility: Lock screen or pause recording

**Out-of-Scope Threats (Explicitly Not Mitigated):**

1. **Physical Access Attacks**
   - Scenario: Attacker with physical access to unlocked Mac
   - Reason: Can't protect against user with physical access
   - Recommendation: Enable FileVault, strong password, screen lock

2. **Root/Admin Privilege Escalation**
   - Scenario: Attacker gains root access on Mac
   - Reason: Root can access any user data (OS design)
   - Recommendation: Keep macOS updated, avoid untrusted software

3. **Forensic Recovery**
   - Scenario: Deleted recordings recovered from disk
   - Reason: macOS doesn't overwrite deleted data by default
   - Mitigation: SQLite secure_delete helps but not foolproof
   - Recommendation: FileVault encryption

4. **Screen Content Inference Attacks**
   - Scenario: Timing analysis reveals patterns (e.g., password length)
   - Reason: Screenshots don't capture keystrokes directly
   - Note: File modification times could leak timing info

5. **Malware Running as User**
   - Scenario: Malware in user context reads recording data
   - Reason: Same user = same permissions (OS limitation)
   - Recommendation: Antivirus, careful software installation

6. **Network Eavesdropping**
   - Scenario: Network sniffer captures recording data
   - Reason: No network access = nothing to capture
   - Note: Not applicable (Playback has zero network access)

### Compliance Considerations

**GDPR (General Data Protection Regulation):**

1. **Right to Access (Art. 15)**
   - Implementation: Timeline viewer provides full access to all recordings
   - Export: Future feature to export all data in portable format (ZIP)

2. **Right to Erasure (Art. 17)**
   - Implementation: Cleanup UI allows deletion of all recordings
   - Uninstall: Option to delete all data during uninstallation
   - Selective: Can delete individual chunks via UI

3. **Data Minimization (Art. 5.1.c)**
   - Implementation: Only screen content captured, no additional tracking
   - Metadata: Minimal (timestamp, app bundle ID, file path)
   - No PII: No names, emails, or user identifiers collected

4. **Purpose Limitation (Art. 5.1.b)**
   - Purpose: Personal productivity and screen history recall
   - Storage: Local only, never transmitted
   - Access: User only (via file permissions)

5. **Storage Limitation (Art. 5.1.e)**
   - Implementation: Automatic cleanup policies (configurable)
   - Default: 7-day temp file retention
   - User control: Can set custom retention periods

**CCPA (California Consumer Privacy Act):**

1. **Right to Know**
   - Data collected: Screen recordings (images/video)
   - Purpose: Personal productivity tool
   - Disclosure: No data shared (local-only)

2. **Right to Delete**
   - Implementation: Cleanup UI, uninstall option
   - Verification: User confirms deletion

3. **Right to Opt-Out of Sale**
   - Not applicable: No data sale (local-only app)

4. **Notice at Collection**
   - Implementation: First-run notice explaining data collection
   - Consent: User must grant Screen Recording permission

### Privacy Best Practices for Users

**Essential Recommendations:**

1. **Enable Full Disk Encryption**
   - macOS Feature: FileVault
   - Benefit: Protects recordings if Mac is stolen
   - Setup: System Settings → Privacy & Security → FileVault

2. **Use Strong User Password**
   - Requirement: File permissions only protect against other users
   - Benefit: Prevents unauthorized login
   - Recommendation: 12+ character passphrase

3. **Enable Screen Lock on Sleep**
   - Setup: System Settings → Lock Screen → Require password immediately
   - Benefit: Prevents access when stepping away
   - Automation: Hot corners, timer

4. **Don't Share User Account**
   - Reason: Other users logged in as you can access recordings
   - Solution: Create separate macOS user accounts
   - Setup: System Settings → Users & Groups

5. **Configure App Exclusions**
   - Review: Settings → Privacy → Excluded Apps
   - Add: Password managers, banking apps, sensitive applications
   - Test: Verify exclusions work (check logs)

6. **Review Recordings Periodically**
   - Action: Watch recent timeline, check for sensitive content
   - Delete: Remove recordings containing sensitive data
   - Schedule: Weekly or monthly review

7. **Secure Backups**
   - Warning: Time Machine and cloud backups include recordings
   - Recommendation: Exclude Playback data from backups, OR
   - Alternative: Ensure backups are encrypted

**Optional Recommendations:**

1. **Use Separate Admin Account**
   - Setup: Use standard account daily, admin only for installs
   - Benefit: Limits impact of malware/exploits

2. **Enable Firewall**
   - Note: Playback doesn't use network, but good practice
   - Setup: System Settings → Network → Firewall

3. **Review Screen Recording Permissions**
   - Check: System Settings → Privacy & Security → Screen Recording
   - Verify: Only trusted apps have permission

### Future Security Enhancements

**Roadmap Items:**

1. **Encryption at Rest (v2.0)**
   - Feature: Optional AES-256 encryption of recordings
   - Key management: Keychain integration or password-based
   - Performance: Encrypt during processing, decrypt on-demand

2. **Secure Export (v2.1)**
   - Feature: Export with password protection
   - Format: Encrypted ZIP with AES-256
   - Use case: Sharing selected recordings securely

3. **Screenshot Hashing (v2.2)**
   - Feature: Store SHA-256 hash of each screenshot
   - Purpose: Detect tampering or corruption
   - Benefit: Integrity verification

4. **Audit Logging (v2.3)**
   - Feature: Log all access to recordings
   - Content: Timestamp, action (view/delete/export), user
   - Purpose: Detect unauthorized access attempts

5. **Smart Redaction (v3.0)**
   - Feature: AI-based sensitive content detection
   - Targets: Credit card numbers, SSNs, passwords
   - Action: Auto-blur or redact detected sensitive data

6. **Hardware Security Module (v3.1)**
   - Feature: Store encryption keys in Secure Enclave
   - Platform: T2 chip or Apple Silicon
   - Benefit: Keys never accessible to software

7. **Multi-User Support (v3.2)**
   - Feature: Multiple recording profiles per Mac
   - Isolation: Separate data directories, permissions
   - Use case: Shared Mac with privacy boundaries

## Testing Checklist

### Unit Tests

- [ ] Test app exclusion logic
  - Test: `should_skip_screenshot()` returns True when frontmost app is in exclusion list
  - Test: Returns False when app is not in list
  - Test: Handles "unknown" app gracefully

- [ ] Test permission checking
  - Test: `_has_screen_recording_permission()` detects granted state
  - Test: `_has_accessibility_permission()` detects denied state
  - Test: Recording service exits with error when Screen Recording denied

- [ ] Test file permissions
  - Test: New screenshot files created with 0600 permissions
  - Test: New video files created with 0600 permissions
  - Test: Database file created with 0600 permissions
  - Test: Config files created with 0644 permissions

- [ ] Test screen unavailability detection
  - Test: `is_screen_unavailable()` returns True when screensaver active
  - Test: Returns True when display is off (mock CGGetActiveDisplayList)
  - Test: Returns False during normal operation

- [ ] Test exclusion logging
  - Test: Skipped screenshots generate log entry with app bundle ID
  - Test: Log entries have correct format and metadata
  - Test: Logs don't contain screenshot content

### Integration Tests

- [ ] Test end-to-end exclusion flow
  - Setup: Add 1Password to exclusion list
  - Action: Bring 1Password to foreground
  - Verify: No screenshots taken during 1Password usage
  - Verify: Screenshots resume when switching to non-excluded app

- [ ] Test permission failure handling
  - Setup: Revoke Screen Recording permission
  - Action: Start recording service
  - Verify: Service exits with error
  - Verify: Notification shown to user

- [ ] Test data directory security
  - Setup: Create fresh data directory
  - Verify: Directory has 0700 permissions
  - Verify: All created files have correct permissions (0600 or 0644)

- [ ] Test uninstall with data preservation
  - Setup: Record some data
  - Action: Run uninstall script, choose "preserve data"
  - Verify: LaunchAgents removed
  - Verify: Apps removed
  - Verify: Data directory still exists with recordings intact

- [ ] Test uninstall with data deletion
  - Setup: Record some data
  - Action: Run uninstall script, choose "delete data"
  - Verify: LaunchAgents removed
  - Verify: Apps removed
  - Verify: Data directory completely removed

### Security Tests

- [ ] Test for network access
  - Method: Static analysis of all Python files
  - Verify: No network-related imports
  - Verify: No subprocess calls to network tools

- [ ] Test file permission enforcement
  - Action: Manually change permissions on sensitive file to 0644
  - Verify: Application detects incorrect permissions on startup
  - Verify: Warning logged or shown to user

- [ ] Test input validation
  - Test: Config file with invalid JSON is rejected
  - Test: Config file with invalid values (negative numbers) is rejected
  - Test: File paths with "../" are sanitized or rejected
  - Test: Bundle IDs with special characters are handled safely

- [ ] Test error message sanitization
  - Action: Trigger various error conditions
  - Verify: Error messages don't contain screenshot content
  - Verify: Logs don't contain sensitive data (besides bundle IDs)

### Manual Testing

- [ ] Test app exclusion with real apps
  - Setup: Install 1Password or similar
  - Add to exclusion list
  - Verify: Screenshots not taken when app is frontmost
  - Verify: Timeline shows gap during excluded app usage

- [ ] Test permission prompts
  - Setup: Fresh macOS installation or reset TCC database
  - Action: Launch recording service
  - Verify: System prompts for Screen Recording permission
  - Verify: System prompts for Accessibility permission

- [ ] Test screensaver pause
  - Action: Activate screensaver
  - Verify: Recording stops (check logs)
  - Verify: Recording resumes after screensaver dismissed

- [ ] Test display sleep pause
  - Action: Put display to sleep (close laptop lid)
  - Verify: Recording stops (check logs after wake)
  - Verify: Recording resumes after wake

- [ ] Test cleanup functionality
  - Setup: Create old temp files (> 7 days)
  - Action: Run cleanup script or trigger from UI
  - Verify: Old files deleted
  - Verify: Recent files preserved
  - Verify: Confirmation shown before deletion

### Performance Tests

- [ ] Test permission check overhead
  - Measure: Time to check Screen Recording permission
  - Target: < 10ms (non-blocking)

- [ ] Test app detection overhead
  - Measure: Time to get frontmost app bundle ID
  - Target: < 50ms (called once per screenshot)

- [ ] Test file permission setting overhead
  - Measure: Time to chmod after file creation
  - Target: < 1ms (negligible)

### Compliance Tests

- [ ] Verify GDPR compliance
  - Test: User can access all their data (timeline viewer)
  - Test: User can delete all their data (cleanup UI)
  - Test: User can export all their data (future feature)

- [ ] Verify data minimization
  - Verify: Only screen content is recorded (no additional tracking)
  - Verify: No metadata beyond what's necessary (timestamp, app)
