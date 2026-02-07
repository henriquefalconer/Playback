# macOS Integration Library

Production-quality Python library for macOS system integration, providing CoreGraphics display detection, AppleScript integration, and system state queries.

## Features

- **Display Management**: Detect active displays, get display bounds, find active display based on mouse location
- **Screen State Detection**: Check if screen saver is active, detect if displays are off
- **Application Detection**: Get bundle ID and name of frontmost application
- **User Activity**: Detect user idle time
- **Error Handling**: All functions return `None` on failure, allowing graceful degradation

## Installation

No external dependencies required. Uses only Python standard library and macOS system frameworks.

```bash
# The library is ready to use
python3 -c "from lib import macos"
```

## Usage

### Display Detection

```python
from lib import macos

# Get number of active displays
count = macos.get_active_display_count()
print(f"Active displays: {count}")  # e.g., 2

# Check if any displays are active
if macos.is_display_active():
    print("At least one display is on")
else:
    print("All displays are off")

# Get the index of the display containing the mouse cursor
# (Compatible with screencapture -D flag)
index = macos.get_active_display_index()
print(f"Active display: {index}")  # e.g., 1 for first display
```

### Mouse Location

```python
from lib import macos

# Get current mouse cursor position
mouse = macos.get_mouse_location()
if mouse:
    x, y = mouse
    print(f"Mouse at ({x:.1f}, {y:.1f})")
```

### Screen Availability

```python
from lib import macos

# Check if screen should be recorded
# Returns True if screensaver active or displays off
if macos.is_screen_unavailable():
    print("Skip recording - screen unavailable")
else:
    print("Screen available - proceed with recording")

# Or check individual conditions
if macos.is_screensaver_active():
    print("Screen saver is running")

if not macos.is_display_active():
    print("All displays are off")
```

### Frontmost Application

```python
from lib import macos

# Get bundle ID of focused app
bundle_id = macos.get_frontmost_app_bundle_id()
print(f"Focused app: {bundle_id}")  # e.g., "com.apple.Safari"

# Get localized app name
app_name = macos.get_frontmost_app_name()
print(f"Focused app: {app_name}")  # e.g., "Safari"
```

### User Idle Detection

```python
from lib import macos

# Check if user has been idle for 5 minutes
if macos.is_user_idle(threshold_seconds=300):
    print("User is idle")
else:
    print("User is active")
```

## API Reference

### Display Functions

#### `load_coregraphics() -> ctypes.CDLL`

Load the CoreGraphics framework. Cached after first load.

**Returns**: CDLL object for CoreGraphics framework

**Raises**: `RuntimeError` if CoreGraphics not found

---

#### `get_active_display_count() -> Optional[int]`

Get the number of active (powered on) displays.

**Returns**: Number of displays (0 if all off), or `None` if detection failed

---

#### `is_display_active() -> Optional[bool]`

Check if any displays are currently active.

**Returns**:
- `True` if at least one display is active
- `False` if all displays are off
- `None` if detection failed

---

#### `get_mouse_location() -> Optional[Tuple[float, float]]`

Get current mouse cursor position in screen coordinates.

**Returns**: `(x, y)` tuple, or `None` if detection failed

---

#### `get_display_bounds(display_id: int) -> Optional[Tuple[float, float, float, float]]`

Get the frame of a display in screen coordinates.

**Args**:
- `display_id`: CoreGraphics display ID

**Returns**: `(x, y, width, height)` tuple, or `None` if detection failed

---

#### `get_active_display_index() -> Optional[int]`

Get the 1-based index of the display containing the mouse cursor.

This index is compatible with `screencapture -D <index>`.

**Returns**:
- Display index (1 for first, 2 for second, etc.)
- Falls back to 1 if mouse not on any display
- `None` if detection failed

**Example**:
```python
index = macos.get_active_display_index()
if index:
    subprocess.run(["screencapture", "-D", str(index), "screenshot.png"])
```

---

### Screen State Functions

#### `is_screensaver_active() -> Optional[bool]`

Check if the screen saver is currently running.

Uses AppleScript to query System Events.

**Returns**:
- `True` if screen saver is active
- `False` if screen saver is not active
- `None` if detection failed

---

#### `is_screen_unavailable() -> bool`

Check if the screen should NOT be recorded.

Screen is unavailable if:
- Screen saver is active, OR
- All displays are off

Conservative behavior: returns `False` if detection fails (assumes screen is available).

**Returns**: `True` if screen should not be recorded, `False` otherwise

**Example**:
```python
if not macos.is_screen_unavailable():
    capture_screenshot()
```

---

### Application Detection Functions

#### `get_frontmost_app_bundle_id() -> Optional[str]`

Get the bundle identifier of the currently focused application.

Requires Accessibility permission for the calling process.

**Returns**:
- Bundle ID string (e.g., `"com.apple.Safari"`)
- `"unknown"` if detection failed
- `None` if subprocess execution failed

---

#### `get_frontmost_app_name() -> Optional[str]`

Get the localized name of the currently focused application.

Requires Accessibility permission for the calling process.

**Returns**:
- App name string (e.g., `"Safari"`)
- `"Unknown"` if detection failed
- `None` if subprocess execution failed

---

### User Activity Functions

#### `is_user_idle(threshold_seconds: int = 300) -> Optional[bool]`

Check if the user has been idle (no keyboard/mouse activity).

**Args**:
- `threshold_seconds`: Seconds of inactivity to consider idle (default: 300)

**Returns**:
- `True` if user idle longer than threshold
- `False` if user is active
- `None` if detection failed

**Example**:
```python
# Check if user idle for 10 minutes
if macos.is_user_idle(threshold_seconds=600):
    print("User has been idle for 10+ minutes")
```

---

## Error Handling

All functions follow a consistent error handling pattern:

- **Never raise exceptions** (except `load_coregraphics()` on initialization failure)
- **Return `None`** when detection fails
- **Return sentinel values** (`"unknown"`, `"Unknown"`) for some string functions
- **Conservative defaults**: `is_screen_unavailable()` returns `False` if detection fails

This allows callers to handle failures gracefully:

```python
# Safe pattern - handle None
display_count = macos.get_active_display_count()
if display_count is not None:
    print(f"Found {display_count} displays")
else:
    print("Could not detect displays - using fallback")

# Safe pattern - conservative check
if macos.is_screen_unavailable():
    print("Screen definitely unavailable")
else:
    print("Screen probably available (or detection failed)")
```

## System Requirements

- **macOS 10.13+** (High Sierra or later)
- **Python 3.8+**
- **Permissions**:
  - No permissions required for display/mouse detection
  - **Accessibility** permission required for frontmost app detection
  - No permissions required for screen saver/idle detection

## Testing

Run the test suite:

```bash
python3 src/lib/test_macos.py
```

The test suite validates all functions and provides diagnostic output. Some tests may fail in sandboxed/container environments where CoreGraphics and AppleScript access is restricted.

## Integration with record_screen.py

This library was extracted from `record_screen.py` to provide reusable macOS system integration. To use it:

```python
# Old code in record_screen.py
if is_screen_unavailable():
    continue

# New code using library
from lib import macos

if macos.is_screen_unavailable():
    continue
```

All functions maintain the same behavior as the original implementations.

## Performance

- **Lazy loading**: CoreGraphics framework loaded only when first needed
- **Cached framework**: Framework reference cached after first load
- **Minimal overhead**: Direct ctypes calls to system frameworks
- **Fast queries**: Display/mouse queries complete in <1ms
- **AppleScript timeout**: All AppleScript calls have 5-second timeout

## Troubleshooting

### "CoreGraphics framework not found"
- Ensure running on macOS
- CoreGraphics is a system framework, always present on macOS

### Display detection returns None
- May occur in sandboxed/container environments
- Check system logs for security restrictions
- Fallback: assume single display

### Frontmost app detection returns "unknown"
- Grant Accessibility permission to calling process
- System Settings → Privacy & Security → Accessibility
- Add Terminal, Cursor, or your Python interpreter

### AppleScript queries timeout
- Increase timeout in function calls if needed
- Check if System Events is responding: `osascript -e 'tell application "System Events" to get name'`

## Architecture

The library uses:
- **ctypes** for CoreGraphics framework access (zero-copy, fast)
- **subprocess** for AppleScript execution (simple, reliable)
- **No third-party dependencies** (standard library only)

CoreGraphics functions used:
- `CGGetActiveDisplayList`: Get list of active displays
- `CGEventCreate` / `CGEventGetLocation`: Get mouse position
- `CGDisplayBounds`: Get display frame
- `CGEventSourceSecondsSinceLastEventType`: Get idle time

AppleScript queries:
- Screen saver state: `tell application "System Events" to tell screen saver preferences to get running`
- Frontmost app: `tell application "System Events" to get bundle identifier of (first process whose frontmost is true)`

## Contributing

When adding new functions:

1. **Type hints**: Use proper type hints for parameters and return values
2. **Docstrings**: Include detailed docstring with Args/Returns/Raises
3. **Error handling**: Return `None` on failure, never raise exceptions
4. **Testing**: Add test case to `test_macos.py`
5. **Documentation**: Update this README with API reference

## License

Part of the Playback project. See project root for license information.
