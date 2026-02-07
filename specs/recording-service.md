# Recording Service Implementation Plan

**Component:** Recording Service (Python LaunchAgent)
**Version:** 1.0
**Last Updated:** 2026-02-07

**Architecture Note:** The recording service is an independent Python script managed by a LaunchAgent:
- Runs independently of timeline viewer (Playback.app)
- Continues running even if timeline viewer crashes or is quit
- Pauses automatically when timeline viewer is open (detects `.timeline_open` file)
- Controlled by menu bar agent via launchctl
- Only stopped when user clicks "Quit Playback" in menu bar

## Implementation Checklist

### Core Recording Loop
- [ ] Implement main recording loop with 2-second interval
  - Source: `src/scripts/record_screen.py`
  - Fixed interval: 2 seconds (not configurable)
  - Check recording enabled status each iteration
  - Check timeline viewer status: Pause if `.timeline_open` file exists
  - Loop structure: `while True: check_config() → check_timeline_open() → check_screen_availability() → capture() → sleep(2)`
  - Timeline detection: Check for `~/Library/Application Support/Playback/data/.timeline_open`
  - Pause behavior: Skip screenshot capture but continue polling
  - Exit on clean shutdown signal or critical errors only

- [ ] Implement configuration reading
  - Location: `~/Library/Application Support/Playback/config.json`
  - Read every loop iteration using `json.load()`
  - Handle missing/malformed files with defaults: `{"recording_enabled": false, "excluded_apps": [], "exclusion_mode": "skip"}`
  - Fields: `recording_enabled` (bool), `excluded_apps` (list of bundle IDs), `exclusion_mode` ("skip" or "invisible")
  - Use `try/except json.JSONDecodeError` to catch malformed JSON

### Screen Availability Detection
- [ ] Implement screensaver detection
  - Use AppleScript: `osascript -e 'tell application "System Events" to get running of screen saver preferences'`
  - Returns "true" or "false" as string
  - Skip capture when result is "true"
  - Log INFO with message "Screen unavailable: screensaver active"

- [ ] Implement display state detection
  - Use CoreGraphics via ctypes: `CG.CGGetActiveDisplayList(max_displays, display_list, count_ptr)`
  - Skip capture when display count == 0 (all displays off)
  - Access via: `ctypes.cdll.LoadLibrary('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')`
  - Log INFO with message "Screen unavailable: display off"

- [ ] Implement Playback app visibility detection
  - Check if Playback app (bundle ID: `com.playback.Playback`) is frontmost
  - Use frontmost app detection (see below) to get current app
  - Skip capture when current app matches Playback bundle ID
  - Log INFO with message "Screen unavailable: Playback app visible"

- [ ] Implement combined screen availability check
  - Function: `is_screen_unavailable() -> bool`
  - Returns `True` if screensaver active OR display off OR Playback frontmost
  - Call all three detection methods and combine with logical OR
  - Return early on first unavailability condition met

### Display and App Detection
- [ ] Implement active display detection
  - Function: `_get_active_display_index() -> Optional[int]`
  - Step 1: Get mouse cursor position using `CG.CGEventGetLocation(None)` (returns CGPoint with x, y)
  - Step 2: Get all active displays using `CG.CGGetActiveDisplayList(max_displays, display_list, count_ptr)`
  - Step 3: For each display, get bounds using `CG.CGDisplayBounds(display_id)` (returns CGRect)
  - Step 4: Check if cursor point is within display bounds using point-in-rect test
  - Step 5: Return 1-based index (first display is 1, second is 2, etc.) for `screencapture -D` flag
  - Fallback to `1` if detection fails or cursor not in any display bounds
  - Log WARNING on fallback with message "Active display detection failed, using display 1"

- [ ] Implement frontmost app detection
  - Use AppleScript: `osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'`
  - Returns bundle ID string like "com.apple.Safari"
  - Fallback to "unknown" if AppleScript fails or returns empty
  - Sanitize bundle IDs using regex: `re.sub(r'[^a-zA-Z0-9.]', '', bundle_id)`
  - Keep only letters, digits, and dots (remove hyphens, underscores, special chars)
  - Log WARNING on fallback with message "Frontmost app detection failed, using 'unknown'"

### Screenshot Capture
- [ ] Implement screenshot capture function
  - Command: `screencapture -x -t png -D <display_index> <temp_path>`
  - Flags breakdown:
    - `-x` = No sound effects, no UI feedback
    - `-t png` = Force PNG format
    - `-D <N>` = Capture display N (1-based index)
  - Execution: `subprocess.run(['screencapture', '-x', '-t', 'png', '-D', str(display_index), temp_path], capture_output=True)`
  - Step 1: Generate temp path with `.png` extension (required by screencapture)
  - Step 2: Run command and check return code
  - Step 3: Remove `.png` extension after successful capture: `os.rename(temp_path, final_path)`
  - Step 4: Set file creation time using `os.utime(final_path, (now, now))`
  - Handle non-zero exit codes (see error handling section)

- [ ] Implement filename generation
  - Pattern: `YYYYMMDD-HHMMSS-<uuid>-<app_id>` (no file extension)
  - Example: `20251222-143052-a3f8b29c-com.apple.Safari`
  - Components:
    - Date: `now.strftime('%Y%m%d')` (e.g., "20251222")
    - Time: `now.strftime('%H%M%S')` (e.g., "143052")
    - UUID: `uuid.uuid4().hex[:8]` (first 8 chars, e.g., "a3f8b29c")
    - App ID: sanitized bundle identifier (e.g., "com.apple.Safari")
  - Separator: hyphen between all components
  - Full generation: `f"{now.strftime('%Y%m%d')}-{now.strftime('%H%M%S')}-{uuid.uuid4().hex[:8]}-{sanitized_app_id}"`

- [ ] Implement directory structure creation
  - Base path: `~/Library/Application Support/com.playback.Playback/temp/`
  - Hierarchy: `temp/YYYYMM/DD/` (e.g., `temp/202512/22/`)
  - Month folder: `now.strftime('%Y%m')` (e.g., "202512")
  - Day folder: `now.strftime('%d')` (e.g., "22")
  - Function: `ensure_chunk_dir(now: datetime) -> Path`
  - Implementation: `chunk_dir.mkdir(parents=True, exist_ok=True)`
  - Create all parent directories automatically if missing

### App Exclusion
- [ ] Implement "skip" exclusion mode
  - Check: `if frontmost_app in config['excluded_apps'] and config['exclusion_mode'] == 'skip':`
  - Action: Skip screenshot capture entirely (don't call screencapture)
  - Log INFO with message: `"Screenshot skipped: excluded app frontmost (skip mode)", app=frontmost_app`
  - Behavior: No file created, no processing done
  - Privacy: Simpler, more privacy-preserving (excluded apps never recorded)

- [ ] Implement "invisible" exclusion mode
  - Check: `if frontmost_app in config['excluded_apps'] and config['exclusion_mode'] == 'invisible':`
  - Action: Capture screenshot normally, then post-process
  - Post-processing steps:
    1. Get window bounds for excluded app using Accessibility API
    2. Load PNG image using PIL/Pillow: `Image.open(screenshot_path)`
    3. Draw black rectangles over excluded app windows: `ImageDraw.Draw(image).rectangle(bounds, fill='black')`
    4. Save modified image: `image.save(screenshot_path)`
  - Log INFO with message: `"Screenshot captured with app windows blacked out (invisible mode)", app=frontmost_app`
  - Complexity: Requires window bounds detection via `CGWindowListCopyWindowInfo`

### LaunchAgent Setup
- [ ] Create LaunchAgent plist file
  - Location: `~/Library/LaunchAgents/com.playback.recording.plist`
  - Label: `com.playback.recording`
  - ProgramArguments: `['/usr/bin/python3', '/path/to/src/scripts/record_screen.py']`
  - RunAtLoad: `false` (do NOT start automatically on login, only via explicit `launchctl start`)
  - KeepAlive: `{'SuccessfulExit': false}` (restart on crash/non-zero exit, NOT on clean exit 0)
  - Full plist structure:
    ```xml
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>Label</key><string>com.playback.recording</string>
        <key>ProgramArguments</key>
        <array>
            <string>/usr/bin/python3</string>
            <string>/path/to/src/scripts/record_screen.py</string>
        </array>
        <key>RunAtLoad</key><false/>
        <key>KeepAlive</key>
        <dict>
            <key>SuccessfulExit</key><false/>
        </dict>
        <key>StandardOutPath</key><string>/Users/username/Library/Logs/Playback/recording.stdout.log</string>
        <key>StandardErrorPath</key><string>/Users/username/Library/Logs/Playback/recording.stderr.log</string>
        <key>EnvironmentVariables</key>
        <dict>
            <key>PLAYBACK_CONFIG</key><string>/Users/username/Library/Application Support/Playback/config.json</string>
        </dict>
        <key>ProcessType</key><string>Interactive</string>
        <key>Nice</key><integer>0</integer>
    </dict>
    </plist>
    ```

- [ ] Configure LaunchAgent logging
  - StandardOutPath: `~/Library/Logs/Playback/recording.stdout.log`
  - StandardErrorPath: `~/Library/Logs/Playback/recording.stderr.log`
  - Create log directory: `~/Library/Logs/Playback/` before loading agent
  - Logs auto-rotate by macOS (no manual rotation needed)
  - stdout: Structured JSON log entries from Python logger
  - stderr: Python tracebacks and unhandled exceptions

- [ ] Configure LaunchAgent environment
  - EnvironmentVariables: `<key>PLAYBACK_CONFIG</key><string>path/to/config.json</string>`
  - ProcessType: `Interactive` (required for GUI access, screencapture, AppleScript)
  - Nice: `0` (normal CPU priority, not background)
  - Load command: `launchctl load ~/Library/LaunchAgents/com.playback.recording.plist`
  - Start command: `launchctl start com.playback.recording`
  - Stop command: `launchctl stop com.playback.recording`
  - Unload command: `launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist`

### Logging System
- [ ] Implement structured JSON logging
  - Location: `~/Library/Logs/Playback/recording.log`
  - Format: One JSON object per line (newline-delimited JSON)
  - Example entry:
    ```json
    {"timestamp": "2025-12-22T14:30:52.123Z", "level": "INFO", "component": "recorder", "message": "Screenshot captured", "display": 1, "app": "com.apple.Safari", "path": "temp/202512/22/20251222-143052-a3f8b29c-com.apple.Safari", "duration_ms": 145}
    ```
  - Python setup: Use `logging.basicConfig()` with `json` formatter
  - Fields: `timestamp` (ISO 8601), `level`, `component`, `message`, plus arbitrary metadata fields

- [ ] Implement log levels
  - INFO: Normal operations (screenshot captured, screen unavailable, config loaded)
  - WARNING: Recoverable errors (app detection failed using fallback, accessibility permission missing)
  - ERROR: Non-critical failures (single screenshot failed, will retry next iteration)
  - CRITICAL: Service-stopping errors (screen recording permission denied, disk full)
  - Python usage: `logger.info()`, `logger.warning()`, `logger.error()`, `logger.critical()`

- [ ] Implement logged events
  - Service started:
    - `{"level": "INFO", "message": "Recording service started", "python_version": "3.11.5", "macos_version": "14.2.1", "pid": 12345}`
  - Screenshot captured:
    - `{"level": "INFO", "message": "Screenshot captured", "display": 1, "app": "com.apple.Safari", "path": "temp/202512/22/20251222-143052-a3f8b29c-com.apple.Safari", "duration_ms": 145, "file_size_kb": 582}`
  - Screenshot skipped:
    - `{"level": "INFO", "message": "Screenshot skipped", "reason": "screensaver active"}`
    - `{"level": "INFO", "message": "Screenshot skipped", "reason": "excluded app frontmost (skip mode)", "app": "com.apple.Messages"}`
  - Screenshot failed:
    - `{"level": "ERROR", "message": "Screenshot capture failed", "error": "screencapture returned exit code 1", "stderr": "...", "consecutive_failures": 1}`
  - Configuration reloaded:
    - `{"level": "INFO", "message": "Configuration reloaded", "recording_enabled": true, "excluded_apps": ["com.apple.Messages"], "exclusion_mode": "skip"}`
  - Service stopped:
    - `{"level": "INFO", "message": "Recording service stopped", "reason": "clean shutdown signal", "uptime_hours": 24.5, "total_captures": 43200}`

- [ ] Implement resource metrics logging
  - Log every 100 captures (~200 seconds, ~3.3 minutes)
  - Metrics to collect:
    - `captures_count`: Total screenshots captured since startup
    - `cpu_percent`: Current CPU usage via `psutil.cpu_percent()`
    - `memory_mb`: Current memory usage via `psutil.Process().memory_info().rss / 1024 / 1024`
    - `disk_free_gb`: Free space on target disk via `shutil.disk_usage().free / 1024**3`
    - `uptime_hours`: Hours since service started
  - Example log entry:
    - `{"level": "INFO", "message": "Resource metrics", "captures": 100, "cpu_percent": 2.1, "memory_mb": 35, "disk_free_gb": 487, "uptime_hours": 0.055}`

### Error Handling
- [ ] Implement permission denied handling
  - Detection: `screencapture` returns exit code 1 with stderr containing "Operation not permitted"
  - Actions:
    1. Log CRITICAL: `{"level": "CRITICAL", "message": "Screen Recording permission denied", "error": "screencapture permission denied"}`
    2. Show notification: `osascript -e 'display notification "Screen Recording permission required" with title "Playback Recording Error"'`
    3. Exit with code 1: `sys.exit(1)`
  - LaunchAgent behavior: Will NOT restart (KeepAlive only restarts on non-zero exit if crash, not clean exit)
  - User action required: Grant permission in System Settings → Privacy & Security → Screen Recording

- [ ] Implement disk full handling
  - Detection: `OSError` with errno 28 (ENOSPC) when writing screenshot file
  - Actions:
    1. Check disk space: `shutil.disk_usage('/').free / 1024**3` for GB remaining
    2. Log CRITICAL: `{"level": "CRITICAL", "message": "Disk full, recording disabled", "disk_free_gb": 0.5, "error": "No space left on device"}`
    3. Show notification: `osascript -e 'display notification "Disk full, recording paused" with title "Playback Recording Error"'`
    4. Update config: `config['recording_enabled'] = False; json.dump(config, open(config_path, 'w'))`
    5. Exit with code 2: `sys.exit(2)`
  - User action required: Free disk space and manually re-enable recording in config

- [ ] Implement accessibility permission handling
  - Detection: AppleScript for frontmost app fails with "System Events got an error: osascript is not allowed assistive access"
  - Actions:
    1. Log WARNING: `{"level": "WARNING", "message": "Accessibility permission denied, using fallback", "error": "AppleScript access denied"}`
    2. Use "unknown" as app ID: `frontmost_app = "unknown"`
    3. Show notification (once per session): `osascript -e 'display notification "Accessibility permission recommended for app tracking" with title "Playback Recording Warning"'`
    4. Continue capturing screenshots normally
  - Degraded mode: Screenshots work but app tracking unavailable (all files named with "unknown")
  - User action: Grant permission in System Settings → Privacy & Security → Accessibility (optional)

- [ ] Implement screencapture failure handling
  - Detection: `subprocess.run()` returns non-zero exit code
  - Actions:
    1. Increment consecutive failure counter
    2. Log ERROR: `{"level": "ERROR", "message": "Screenshot capture failed", "exit_code": return_code, "stderr": stderr_output, "consecutive_failures": failure_count}`
    3. Skip this capture, sleep, continue to next iteration
    4. If 10 consecutive failures:
       - Log CRITICAL: `{"level": "CRITICAL", "message": "Too many consecutive screencapture failures", "consecutive_failures": 10}`
       - Exit with code 3: `sys.exit(3)`
  - Reset counter to 0 after successful capture
  - Common causes: Display disconnected, screencapture binary missing, system resource exhaustion

- [ ] Implement crash recovery
  - LaunchAgent configuration: `<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>`
  - Behavior: Automatically restart on unexpected exit (crash, unhandled exception)
  - Stack trace: Automatically logged to stderr log file (`recording.stderr.log`)
  - Recovery: Service starts fresh, no state carried over
  - Monitoring: Check stderr log for repeated crashes (indicates bug needing fix)
  - Example crash log: Python traceback with full call stack in stderr log

### Dependencies Setup
- [ ] Configure system dependencies
  - macOS 12.0+ (Monterey or later) - Required for modern screencapture and Accessibility APIs
  - Python 3.8+ - Language version with walrus operator, f-strings, type hints
  - `screencapture` - Built-in macOS command at `/usr/sbin/screencapture`
  - Verification: `which screencapture` should return `/usr/sbin/screencapture`

- [ ] Configure Python standard library imports
  - `subprocess` - Execute screencapture command, capture output
  - `time` - Sleep 2 seconds between captures
  - `datetime` - Generate timestamps for filenames and logs
  - `pathlib.Path` - Cross-platform file path handling
  - `uuid` - Generate unique IDs for filenames
  - `re` - Sanitize bundle IDs with regex
  - `ctypes` - Load CoreGraphics.framework for display detection
  - `json` - Parse config.json file
  - `logging` - Structured logging to files
  - `sys` - Exit codes for error handling
  - `os` - File operations (rename, utime)
  - `shutil` - Disk space checking

- [ ] Configure system framework access
  - CoreGraphics.framework: Load via `ctypes.cdll.LoadLibrary('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')`
  - Key functions needed:
    - `CGGetActiveDisplayList(max_displays, display_list, count_ptr)` - Get active displays
    - `CGDisplayBounds(display_id)` - Get display bounds (CGRect)
    - `CGEventGetLocation(None)` - Get mouse cursor position (CGPoint)
  - Structure definitions needed:
    - `CGPoint`: `ctypes.Structure` with `x` and `y` as `ctypes.c_double`
    - `CGRect`: `ctypes.Structure` with `origin` (CGPoint) and `size` (CGSize)

## Core Implementation Details

This section provides all essential technical details needed for implementation. The recording service is fully self-contained with no external specification dependencies.

### Shared Utilities

Recording service uses common functionality from `src/lib/`:

- **Path resolution** (`src/lib/paths.py`) - Environment-aware path resolution for dev/prod
- **Database operations** (`src/lib/database.py`) - SQLite access and schema management
- **macOS integration** (`src/lib/macos.py`) - CoreGraphics, AppleScript utilities for screen capture
- **Timestamp handling** (`src/lib/timestamps.py`) - Filename parsing and generation

These utilities consolidate logic previously duplicated across scripts, providing consistent behavior across recording and processing services.

### Screenshot Capture Command

**Full Command Structure:**
```bash
screencapture -x -t png -D <display_index> <output_path>
```

**Flag Details:**
- `-x`: Silent mode - no camera shutter sound, no UI feedback, no window shadows
- `-t png`: Force PNG format (lossless compression, supports transparency)
- `-D <N>`: Capture specific display by 1-based index (1 = primary, 2 = secondary, etc.)
- `<output_path>`: Full absolute path including `.png` extension (required by screencapture)

**Python Implementation:**
```python
import subprocess

result = subprocess.run(
    ['screencapture', '-x', '-t', 'png', '-D', str(display_index), temp_path],
    capture_output=True,
    text=True
)

if result.returncode != 0:
    # Handle error (see error handling section)
    stderr_output = result.stderr
```

**Post-Capture Processing:**
1. Check return code (0 = success, non-zero = failure)
2. Remove `.png` extension: `os.rename(temp_path, final_path_without_extension)`
3. Set file creation time: `os.utime(final_path, (timestamp, timestamp))`

### Screen Availability Detection Logic

**Three Conditions That Pause Recording:**

1. **Screensaver Active:**
   ```bash
   osascript -e 'tell application "System Events" to get running of screen saver preferences'
   ```
   - Returns: `"true"` (string) if screensaver is running, `"false"` if not
   - Skip recording if result is `"true"`

2. **Display Off:**
   ```python
   import ctypes
   CG = ctypes.cdll.LoadLibrary('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')

   max_displays = 32
   display_list = (ctypes.c_uint32 * max_displays)()
   count = ctypes.c_uint32()

   CG.CGGetActiveDisplayList(max_displays, display_list, ctypes.byref(count))

   if count.value == 0:
       # All displays are off, skip recording
   ```

3. **Playback App Frontmost:**
   - Get frontmost app bundle ID (see Frontmost App Detection below)
   - If bundle ID equals `"com.playback.Playback"`, skip recording
   - Prevents recording the Playback UI itself

**Combined Check Function:**
```python
def is_screen_unavailable() -> bool:
    # Check screensaver
    result = subprocess.run(['osascript', '-e', 'tell application "System Events" to get running of screen saver preferences'],
                          capture_output=True, text=True)
    if result.stdout.strip() == 'true':
        logger.info("Screen unavailable: screensaver active")
        return True

    # Check display state
    count = get_active_display_count()
    if count == 0:
        logger.info("Screen unavailable: display off")
        return True

    # Check Playback app visibility
    frontmost_app = get_frontmost_app()
    if frontmost_app == "com.playback.Playback":
        logger.info("Screen unavailable: Playback app visible")
        return True

    return False
```

### Frontmost App Detection via Accessibility API

**AppleScript Command:**
```bash
osascript -e 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'
```

**Returns:**
- Success: Bundle ID string like `"com.apple.Safari"`, `"com.google.Chrome"`, `"com.microsoft.VSCode"`
- Failure: Empty string or error message if Accessibility permission denied

**Python Implementation:**
```python
import subprocess
import re

def get_frontmost_app() -> str:
    try:
        result = subprocess.run(
            ['osascript', '-e', 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'],
            capture_output=True,
            text=True,
            timeout=2
        )

        if result.returncode == 0 and result.stdout.strip():
            bundle_id = result.stdout.strip()
            # Sanitize for filename safety
            sanitized = re.sub(r'[^a-zA-Z0-9.]', '', bundle_id)
            return sanitized
        else:
            logger.warning("Frontmost app detection failed, using 'unknown'", error=result.stderr)
            return "unknown"

    except Exception as e:
        logger.warning("Frontmost app detection exception", error=str(e))
        return "unknown"
```

**Sanitization Rules:**
- Keep: Letters (a-z, A-Z), digits (0-9), dots (.)
- Remove: Hyphens, underscores, spaces, special characters
- Example: `"com.apple.Safari"` → `"com.apple.Safari"` (unchanged)
- Example: `"com.some-app.Test_App"` → `"com.someapp.TestApp"`

### File Naming Format with Examples

**Pattern:**
```
YYYYMMDD-HHMMSS-<uuid>-<app_id>
```

**Components:**
1. **Date:** 8 digits, YYYYMMDD format
2. **Time:** 6 digits, HHMMSS format (24-hour)
3. **UUID:** 8 hexadecimal characters (first 8 chars of UUID4)
4. **App ID:** Sanitized bundle identifier

**Examples:**
```
20251222-143052-a3f8b29c-com.apple.Safari
20251222-143054-7b4e1a2f-com.google.Chrome
20251222-143056-c9d2e6f8-com.microsoft.VSCode
20251222-143058-5a1b3c4d-unknown
20251222-143100-8e7f2a9b-com.apple.Terminal
```

**Directory Structure:**
```
~/Library/Application Support/com.playback.Playback/temp/
├── 202512/
│   ├── 22/
│   │   ├── 20251222-143052-a3f8b29c-com.apple.Safari
│   │   ├── 20251222-143054-7b4e1a2f-com.google.Chrome
│   │   └── ...
│   └── 23/
│       └── ...
└── 202601/
    ├── 01/
    └── ...
```

**Python Implementation:**
```python
from datetime import datetime
import uuid
from pathlib import Path

def generate_filename(app_id: str) -> str:
    now = datetime.now()
    date_str = now.strftime('%Y%m%d')
    time_str = now.strftime('%H%M%S')
    uuid_str = uuid.uuid4().hex[:8]
    return f"{date_str}-{time_str}-{uuid_str}-{app_id}"

def ensure_chunk_dir(now: datetime) -> Path:
    base = Path.home() / "Library/Application Support/com.playback.Playback/temp"
    month_dir = base / now.strftime('%Y%m')
    day_dir = month_dir / now.strftime('%d')
    day_dir.mkdir(parents=True, exist_ok=True)
    return day_dir
```

### App Exclusion Modes

**Two Modes Available:**

**1. Skip Mode (Simpler, Recommended):**
- Configuration: `{"exclusion_mode": "skip", "excluded_apps": ["com.apple.Messages", "com.apple.FaceTime"]}`
- Behavior: Don't capture screenshot at all when excluded app is frontmost
- Implementation:
  ```python
  if config['exclusion_mode'] == 'skip' and frontmost_app in config['excluded_apps']:
      logger.info("Screenshot skipped: excluded app frontmost (skip mode)", app=frontmost_app)
      return  # Skip this iteration
  ```
- Privacy: Excluded apps never recorded in any form

**2. Invisible Mode (Complex):**
- Configuration: `{"exclusion_mode": "invisible", "excluded_apps": ["com.apple.Messages"]}`
- Behavior: Capture screenshot normally, then black out excluded app windows
- Implementation steps:
  1. Capture screenshot as usual
  2. Get window list: `CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly, kCGNullWindowID)`
  3. Filter windows by owner bundle ID matching excluded app
  4. Get bounds for each window (x, y, width, height)
  5. Load PNG with PIL: `from PIL import Image, ImageDraw`
  6. Draw black rectangles: `ImageDraw.Draw(image).rectangle([(x, y), (x+width, y+height)], fill='black')`
  7. Save modified image
- Complexity: Requires Quartz framework access, image processing library

### LaunchAgent Plist Configuration

**Complete Plist Template:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Service identifier -->
    <key>Label</key>
    <string>com.playback.recording</string>

    <!-- Command to run -->
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>/Users/username/path/to/src/scripts/record_screen.py</string>
    </array>

    <!-- Do NOT start automatically on login -->
    <key>RunAtLoad</key>
    <false/>

    <!-- Restart on crash, NOT on clean exit -->
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>

    <!-- Logging paths -->
    <key>StandardOutPath</key>
    <string>/Users/username/Library/Logs/Playback/recording.stdout.log</string>

    <key>StandardErrorPath</key>
    <string>/Users/username/Library/Logs/Playback/recording.stderr.log</string>

    <!-- Environment variables -->
    <key>EnvironmentVariables</key>
    <dict>
        <key>PLAYBACK_CONFIG</key>
        <string>/Users/username/Library/Application Support/Playback/config.json</string>
    </dict>

    <!-- Process configuration -->
    <key>ProcessType</key>
    <string>Interactive</string>

    <key>Nice</key>
    <integer>0</integer>
</dict>
</plist>
```

**Key Configuration Explanations:**

1. **Label:** Unique identifier for the service (use in launchctl commands)

2. **ProgramArguments:** Array with Python interpreter and script path (must be absolute paths)

3. **RunAtLoad: false**
   - Service does NOT start automatically when user logs in
   - Must be started explicitly with `launchctl start com.playback.recording`
   - Allows user to control when recording begins

4. **KeepAlive: SuccessfulExit = false**
   - If exit code is 0 (clean shutdown): Do NOT restart
   - If exit code is non-zero (crash, unhandled exception): Restart automatically
   - Prevents infinite restart loops on intentional shutdowns

5. **ProcessType: Interactive**
   - Required for GUI access (screencapture needs window server connection)
   - Required for AppleScript (needs System Events access)
   - Background processes cannot capture screen

6. **Nice: 0**
   - Normal CPU priority (not background, not high priority)
   - Ensures timely screenshot capture without starving other processes

**Management Commands:**
```bash
# Load agent (register with launchd, doesn't start yet)
launchctl load ~/Library/LaunchAgents/com.playback.recording.plist

# Start recording (begin capture loop)
launchctl start com.playback.recording

# Stop recording (clean shutdown, won't restart)
launchctl stop com.playback.recording

# Unload agent (deregister from launchd)
launchctl unload ~/Library/LaunchAgents/com.playback.recording.plist

# Check if running
launchctl list | grep com.playback.recording

# View logs
tail -f ~/Library/Logs/Playback/recording.stdout.log
tail -f ~/Library/Logs/Playback/recording.stderr.log
```

### Error Handling for Each Failure Scenario

**1. Screen Recording Permission Denied**

Trigger: `screencapture` returns exit code 1 with stderr "Operation not permitted"

Response:
```python
if 'Operation not permitted' in stderr or 'not permitted to capture' in stderr:
    logger.critical("Screen Recording permission denied", error=stderr)

    # Show notification
    subprocess.run(['osascript', '-e',
                   'display notification "Screen Recording permission required in System Settings" '
                   'with title "Playback Recording Error"'])

    # Exit cleanly (won't restart due to KeepAlive config)
    sys.exit(1)
```

User Resolution: System Settings → Privacy & Security → Screen Recording → Enable for Python/Terminal

---

**2. Accessibility Permission Denied**

Trigger: AppleScript fails with "osascript is not allowed assistive access"

Response:
```python
try:
    frontmost_app = get_frontmost_app_via_applescript()
except AccessibilityError:
    if not accessibility_warning_shown:
        logger.warning("Accessibility permission denied, using fallback")
        subprocess.run(['osascript', '-e',
                       'display notification "Accessibility permission recommended for app tracking" '
                       'with title "Playback Recording Warning"'])
        accessibility_warning_shown = True

    # Use fallback, continue recording
    frontmost_app = "unknown"
```

Degraded Mode: Screenshots captured normally but all files named with "unknown" instead of app bundle ID

User Resolution: System Settings → Privacy & Security → Accessibility → Enable for Python/Terminal (optional)

---

**3. Disk Full**

Trigger: `OSError` with errno 28 (ENOSPC) when writing screenshot file

Response:
```python
import errno
import shutil

try:
    with open(screenshot_path, 'wb') as f:
        f.write(screenshot_data)
except OSError as e:
    if e.errno == errno.ENOSPC:
        # Check remaining space
        disk_usage = shutil.disk_usage(screenshot_path.parent)
        free_gb = disk_usage.free / (1024**3)

        logger.critical("Disk full, recording disabled",
                       disk_free_gb=free_gb,
                       error=str(e))

        # Show notification
        subprocess.run(['osascript', '-e',
                       'display notification "Disk full, recording paused automatically" '
                       'with title "Playback Recording Error"'])

        # Disable recording in config
        config['recording_enabled'] = False
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)

        # Exit cleanly
        sys.exit(2)
```

User Resolution: Free disk space, manually edit config.json to re-enable recording

---

**4. Screencapture Command Failed**

Trigger: `subprocess.run()` returns non-zero exit code (not permission-related)

Response:
```python
consecutive_failures = 0

result = subprocess.run(['screencapture', ...], capture_output=True, text=True)

if result.returncode != 0:
    consecutive_failures += 1

    logger.error("Screenshot capture failed",
                exit_code=result.returncode,
                stderr=result.stderr,
                consecutive_failures=consecutive_failures)

    # Skip this capture, try again next iteration
    if consecutive_failures >= 10:
        logger.critical("Too many consecutive screencapture failures",
                       consecutive_failures=consecutive_failures)
        sys.exit(3)

    return  # Skip this iteration

# Reset counter on success
consecutive_failures = 0
```

Common Causes:
- Display disconnected during capture
- screencapture binary corrupted
- System resources exhausted
- Temporary macOS window server issue

---

**5. Process Crash / Unhandled Exception**

Trigger: Python exception not caught, segmentation fault, system kill

Response:
- LaunchAgent automatically restarts due to `KeepAlive: {SuccessfulExit: false}`
- Stack trace written to stderr log (`recording.stderr.log`)
- Service starts fresh with clean state

Monitoring:
```bash
# Check for crashes
grep -A 20 "Traceback" ~/Library/Logs/Playback/recording.stderr.log

# Check restart count (multiple PIDs = multiple restarts)
launchctl list | grep com.playback.recording
```

If repeated crashes occur: File bug report with stderr log showing traceback

## Testing Checklist

### Unit Tests
- [ ] Test screen availability detection
  - Mock AppleScript for screensaver detection
  - Mock CoreGraphics for display state
  - Mock process list for Playback app visibility
  - Verify correct skip behavior

- [ ] Test active display detection
  - Mock CGGetActiveDisplayList
  - Mock CGEventGetLocation
  - Verify correct display index returned
  - Verify fallback to display 1

- [ ] Test frontmost app detection
  - Mock AppleScript for bundle identifier
  - Verify sanitization of bundle IDs
  - Verify fallback to "unknown"

- [ ] Test filename generation
  - Verify format: YYYYMMDD-HHMMSS-uuid-app_id
  - Verify timestamp accuracy
  - Verify UUID uniqueness
  - Verify app ID sanitization

- [ ] Test configuration loading
  - Test valid config file
  - Test missing config file (use defaults)
  - Test malformed config file (use defaults)
  - Test config reload on each iteration

- [ ] Test app exclusion modes
  - Test "skip" mode with excluded app
  - Test "invisible" mode with excluded app
  - Test with non-excluded app

### Integration Tests
- [ ] Test full capture cycle
  - Mock screencapture command
  - Verify file written to correct location
  - Verify filename format
  - Verify file creation time

- [ ] Test screensaver detection
  - Mock AppleScript response
  - Verify capture is skipped
  - Verify log entry

- [ ] Test permission denied handling
  - Mock screencapture failure (permission)
  - Verify critical error logged
  - Verify notification shown
  - Verify clean exit (code 1)

- [ ] Test disk full handling
  - Mock filesystem full error
  - Verify critical error logged
  - Verify notification shown
  - Verify config updated (recording disabled)
  - Verify clean exit (code 2)

### Manual Testing
- [ ] Run for 24 hours continuously
  - Monitor memory usage (check for leaks)
  - Monitor CPU usage (should be < 1% idle, 3-5% active)
  - Monitor disk space usage (20-50GB per day)
  - Verify no crash-restart cycles

- [ ] Test display handling
  - Disconnect external display during recording
  - Reconnect external display during recording
  - Move mouse between displays
  - Verify correct display is captured

- [ ] Test screen state changes
  - Enable screensaver, verify recording pauses
  - Disable screensaver, verify recording resumes
  - Lock screen, verify recording pauses
  - Unlock screen, verify recording resumes

- [ ] Test Playback app visibility
  - Launch Playback app, verify recording pauses
  - Close Playback app, verify recording resumes
  - Switch to/from Playback app, verify behavior

- [ ] Test permission scenarios
  - Revoke Screen Recording permission, verify error handling
  - Revoke Accessibility permission, verify degraded mode
  - Re-grant permissions, verify recovery

### Performance Tests
- [ ] Verify CPU usage within limits
  - Idle: < 1%
  - Active: 3-5%
  - Peak: 8-10%

- [ ] Verify memory usage within limits
  - Baseline: ~30MB
  - Peak: ~50MB
  - No leaks over 24 hours

- [ ] Verify disk I/O characteristics
  - Write rate: 1 file every 2 seconds
  - File size: 200KB - 2MB per screenshot
  - Daily storage: ~20GB - 50GB per day
