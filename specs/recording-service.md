# Recording Service Specification

**Component:** Recording Service (Python)
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

The Recording Service is a Python script that runs as a macOS LaunchAgent, continuously capturing screenshots of the active display at a fixed 2-second interval. It monitors display state, tracks the frontmost application, and intelligently skips captures when the screen is unavailable.

## Responsibilities

1. Capture screenshots of the active display every 2 seconds
2. Detect which display is currently in use (based on mouse position)
3. Identify the frontmost application (via Accessibility API)
4. Skip captures when screen is unavailable (screensaver, display off, locked)
5. Write screenshots to temp directory with structured naming
6. Log all operations with timestamps and resource usage
7. Handle errors gracefully and notify user of critical issues

## LaunchAgent Configuration

### Plist File

**Location:** `~/Library/LaunchAgents/com.playback.recording.plist`

```xml
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
        <string>/Applications/Playback.app/Contents/Resources/scripts/record_screen.py</string>
    </array>

    <key>RunAtLoad</key>
    <false/>  <!-- Only start when explicitly loaded -->

    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>  <!-- Don't restart on clean exit -->
        <key>Crashed</key>
        <true/>   <!-- Restart on crash -->
    </dict>

    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/Playback/recording.stdout.log</string>

    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/Playback/recording.stderr.log</string>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PLAYBACK_CONFIG</key>
        <string>$HOME/Library/Application Support/Playback/config.json</string>
    </dict>

    <key>ProcessType</key>
    <string>Interactive</string>

    <key>Nice</key>
    <integer>0</integer>  <!-- Normal priority -->
</dict>
</plist>
```

### Loading/Unloading

**Enable Recording:**
```bash
launchctl load ~/Library/LaunchAgents/com.playback.recording.plist
launchctl start com.playback.recording
```

**Disable Recording:**
```bash
launchctl stop com.playback.recording
launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist
```

## Script Behavior

### Main Loop

```python
while True:
    now = datetime.now()

    # Check if recording is enabled in config
    if not is_recording_enabled():
        log("Recording disabled in config, sleeping")
        time.sleep(interval_seconds)
        continue

    # Check screen availability
    if is_screen_unavailable():
        log("Screen unavailable, skipping capture")
        time.sleep(interval_seconds)
        continue

    # Capture screenshot
    try:
        capture_screen(...)
        log("Screenshot captured", metadata={...})
    except Exception as e:
        log_error("Screenshot failed", error=e)

    time.sleep(interval_seconds)
```

### Interval

- **Fixed:** 2 seconds (not configurable)
- **Rationale:** Balance between granularity and performance/storage

### Screen Availability Detection

**The script skips captures when:**

1. **Screensaver is active** - Detected via AppleScript:
   ```applescript
   tell application "System Events" to tell screen saver preferences to get running
   ```

2. **Display is off** - Detected via CoreGraphics:
   ```python
   CGGetActiveDisplayList(...)
   # If count == 0, display is off
   ```

3. **Playback app is visible** - Detected by checking for running playback app process AND checking if it's frontmost

**Implementation:** `is_screen_unavailable() -> bool`

### Active Display Detection

**Strategy:** Use mouse cursor position to determine which display is "active"

```python
def _get_active_display_index() -> Optional[int]:
    # 1. Get list of active displays via CGGetActiveDisplayList
    # 2. Get mouse cursor position via CGEventGetLocation
    # 3. Find which display bounds contains the cursor
    # 4. Return 1-based index for screencapture -D flag
```

**Fallback:** If detection fails, use display 1 (primary)

### Frontmost App Detection

**Strategy:** Use Accessibility API via AppleScript

```applescript
tell application "System Events" to get bundle identifier of (first process whose frontmost is true)
```

**Fallback:** If detection fails, use "unknown" as app ID

**Sanitization:** Bundle IDs are sanitized for filename safety:
- Keep: letters, digits, dots
- Replace others with underscore

### Screenshot Capture

**Command:**
```bash
screencapture -x -t png -D <display_index> <temp_path>
```

**Flags:**
- `-x`: No camera sound, no UI
- `-t png`: PNG format
- `-D <N>`: Capture specific display (1-based index)

**Process:**
1. Create temp file with `.png` extension
2. Run `screencapture` command
3. Remove `.png` extension to match expected format
4. Set file creation time to current time

### Filename Format

**Pattern:** `YYYYMMDD-HHMMSS-<uuid>-<app_id>`

**Example:** `20251222-143052-a3f8b29c-com.apple.Safari`

**Components:**
- `YYYYMMDD`: Date (for sorting and directory organization)
- `HHMMSS`: Time (for sorting and timeline reconstruction)
- `<uuid>`: Short UUID (8 chars, for uniqueness)
- `<app_id>`: Sanitized bundle identifier (for app tracking)

**No extension:** Files are written as raw PNG data without `.png` extension

### Directory Structure

**Target Directory:** `com.playback.Playback/temp/`

**Hierarchy:**
```
temp/
└── YYYYMM/         # Year-month (e.g., 202512)
    └── DD/          # Day (e.g., 22)
        ├── 20251222-143050-a1b2c3d4-com.apple.Safari
        ├── 20251222-143052-e5f6g7h8-com.apple.Safari
        └── 20251222-143054-i9j0k1l2-com.apple.Xcode
```

**Directory Creation:** Automatically created via `ensure_chunk_dir(now)`

## Configuration

### Config File

**Location:** `~/Library/Application Support/Playback/config.json`

**Relevant Fields:**
```json
{
  "recording_enabled": true,
  "excluded_apps": [
    "com.apple.Keychain",
    "com.1password.1password"
  ],
  "exclusion_mode": "invisible"  // or "skip"
}
```

### Reading Configuration

**Frequency:** Every loop iteration (2 seconds)

**Behavior:**
- If file doesn't exist: Use defaults (recording enabled, no exclusions)
- If file is malformed: Log error, use defaults
- If file is valid: Apply settings

### App Exclusion Modes

**Mode 1: "invisible" (default)**
- Take screenshot as normal
- Post-process image to black out excluded app windows
- Requires window bounds detection

**Mode 2: "skip"**
- Don't take screenshot at all if excluded app is frontmost
- Simpler implementation, more privacy-preserving

**Implementation:** Check `exclusion_mode` and `excluded_apps` before capture

## Logging

### Log File

**Location:** `~/Library/Logs/Playback/recording.log`

**Format:** Structured JSON lines (one per line)

```json
{"timestamp": "2025-12-22T14:30:52Z", "level": "INFO", "component": "recording", "message": "Screenshot captured", "metadata": {"display": 1, "app": "com.apple.Safari", "path": "temp/202512/22/20251222-143052-a3f8b29c-com.apple.Safari", "duration_ms": 234}}
{"timestamp": "2025-12-22T14:30:54Z", "level": "INFO", "component": "recording", "message": "Screen unavailable, skipping capture", "metadata": {"reason": "screensaver_active"}}
{"timestamp": "2025-12-22T14:30:56Z", "level": "ERROR", "component": "recording", "message": "Screenshot failed", "metadata": {"error": "CalledProcessError", "details": "screencapture returned 1"}}
```

### Log Levels

- **INFO:** Normal operations (screenshot captured, screen unavailable)
- **WARNING:** Recoverable errors (app detection failed, fallback used)
- **ERROR:** Non-critical failures (single screenshot failed)
- **CRITICAL:** Service-stopping errors (permissions denied, disk full)

### Logged Events

1. **Service started**
   - Timestamp, Python version, macOS version

2. **Screenshot captured**
   - Timestamp, display index, app ID, file path, capture duration (ms)

3. **Screenshot skipped**
   - Timestamp, reason (screensaver, display off, playback visible, excluded app)

4. **Screenshot failed**
   - Timestamp, error type, error details, stack trace

5. **Configuration reloaded**
   - Timestamp, new config values

6. **Service stopped**
   - Timestamp, reason (user request, crash, disk full)

### Resource Metrics

**Logged every 100 captures (~200 seconds):**

```json
{
  "timestamp": "2025-12-22T14:35:00Z",
  "level": "INFO",
  "component": "recording",
  "message": "Resource metrics",
  "metadata": {
    "captures_last_interval": 100,
    "cpu_percent": 2.3,
    "memory_mb": 45.2,
    "disk_space_gb": 123.4,
    "uptime_hours": 2.5
  }
}
```

## Error Handling

### Permission Denied

**Scenario:** Screen Recording permission not granted

**Behavior:**
1. Log critical error
2. Show macOS notification: "Playback needs Screen Recording permission"
3. Exit cleanly (exit code 1)
4. LaunchAgent will NOT restart (KeepAlive Crashed=true, but this is clean exit)

**User Action Required:** Grant permission in System Preferences, then toggle recording ON again

### Disk Full

**Scenario:** Screenshot write fails due to no disk space

**Behavior:**
1. Log critical error with disk space info
2. Show macOS notification: "Playback stopped: Disk full"
3. Write `recording_enabled: false` to config
4. Exit cleanly (exit code 2)

**User Action Required:** Free up disk space, then toggle recording ON again

### Accessibility Permission Denied

**Scenario:** Cannot detect frontmost app due to missing permission

**Behavior:**
1. Log warning
2. Use "unknown" as app ID
3. Continue capturing screenshots
4. Show macOS notification: "Playback needs Accessibility permission for app tracking"

**Degraded Mode:** Screenshots captured, but app tracking unavailable

### screencapture Command Failed

**Scenario:** `screencapture` returns non-zero exit code

**Behavior:**
1. Log error with stderr output
2. Skip this capture
3. Continue with next iteration
4. If 10 consecutive failures: Log critical error and exit

**Possible Causes:** Display disconnected, system under heavy load, TCC database corruption

### Process Crash

**Scenario:** Unhandled exception crashes Python script

**Behavior:**
1. LaunchAgent automatically restarts service (KeepAlive Crashed=true)
2. Stack trace logged to stderr
3. Continue from clean state

**Monitoring:** Check for crash-restart cycles (multiple restarts in short time)

## Performance Characteristics

### CPU Usage

- **Idle:** < 1% (sleeping between captures)
- **Active:** 3-5% during screenshot capture
- **Peak:** 8-10% during display detection + app detection

### Memory Usage

- **Baseline:** ~30MB (Python interpreter + libraries)
- **Peak:** ~50MB (during CoreGraphics operations)
- **Growth:** Minimal (no leaks expected)

### Disk I/O

- **Write Rate:** 1 file every 2 seconds
- **File Size:** 200KB - 2MB per screenshot (depends on display resolution and content)
- **Daily Storage:** ~20GB - 50GB per day (24-hour recording)

### Network Usage

- **None:** No network access required

## Testing

### Unit Tests

- `test_screen_availability_detection()`
- `test_active_display_detection()`
- `test_frontmost_app_detection()`
- `test_filename_generation()`
- `test_config_loading()`
- `test_app_exclusion_invisible()`
- `test_app_exclusion_skip()`

### Integration Tests

- `test_full_capture_cycle()` - Mock screencapture, verify file written
- `test_screensaver_detection()` - Mock AppleScript, verify skip
- `test_permission_denied()` - Mock screencapture failure, verify notification
- `test_disk_full()` - Mock filesystem full, verify graceful shutdown

### Manual Testing

- Run for 24 hours, check for memory leaks
- Disconnect/reconnect external display
- Enable screensaver, verify skipping
- Launch playback app, verify recording pauses
- Revoke permissions, verify error handling

## Dependencies

### System

- macOS 12.0+ (Monterey or later)
- Python 3.8+
- `screencapture` (built-in macOS command)

### Python Packages

- **Standard Library Only:**
  - `subprocess` - Run screencapture command
  - `time` - Sleep between captures
  - `datetime` - Timestamp generation
  - `pathlib` - File path handling
  - `uuid` - Unique ID generation
  - `re` - Filename sanitization
  - `ctypes` - CoreGraphics access
  - `json` - Config file parsing

### System Frameworks (via ctypes)

- `CoreGraphics.framework` - Display detection, mouse position

## Security Considerations

### Permissions Required

1. **Screen Recording** - TCC permission, required
2. **Accessibility** - TCC permission, optional (for app tracking)

### Data Sensitivity

- Screenshots contain **ALL visible content** on screen
- May include passwords, personal data, confidential information
- Files stored **unencrypted** in user directory
- No network transmission

### Privacy Features

- App exclusion (user-configurable)
- No telemetry or analytics
- No cloud uploads
- Local-only storage

### Attack Surface

- No network exposure
- No IPC endpoints
- Limited to user account permissions
- Follows macOS sandbox guidelines

## Future Enhancements

### Potential Features

1. **Adaptive Interval** - Reduce interval when no activity detected
2. **Content-Aware Capture** - Skip duplicate frames (no changes)
3. **OCR Integration** - Extract text from screenshots for search
4. **Window-Level Capture** - Capture individual windows instead of full screen
5. **Multi-Display Recording** - Capture all displays simultaneously
6. **Audio Recording** - Capture system audio alongside screenshots

### Performance Optimizations

1. **Delta Encoding** - Only store changed regions
2. **Async I/O** - Non-blocking file writes
3. **Batch Processing** - Group multiple screenshots before disk write

### Privacy Enhancements

1. **Encrypted Storage** - Encrypt screenshots at rest
2. **Secure Deletion** - Overwrite deleted files
3. **Time-Based Exclusion** - Don't record during specific hours
4. **App-Based Triggers** - Pause recording when sensitive apps launch
