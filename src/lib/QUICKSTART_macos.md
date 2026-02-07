# Quick Start: macos.py Library

## Installation

No installation needed - just import:

```python
from lib import macos
```

## Common Use Cases

### 1. Skip Recording When Screen Unavailable

```python
from lib import macos

if macos.is_screen_unavailable():
    # Screen saver active or displays off - skip recording
    continue
```

### 2. Capture Specific Display

```python
from lib import macos
import subprocess

# Get the display containing the mouse cursor
display_index = macos.get_active_display_index()

if display_index:
    # Capture that specific display
    subprocess.run([
        "screencapture",
        "-D", str(display_index),
        "-x",
        "screenshot.png"
    ])
```

### 3. Tag Files with Frontmost App

```python
from lib import macos
from datetime import datetime

# Get current app
bundle_id = macos.get_frontmost_app_bundle_id()

# Generate filename with app info
timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
filename = f"{timestamp}-{bundle_id}.png"
```

### 4. Detect User Idle Time

```python
from lib import macos

# Check if user idle for 5 minutes
if macos.is_user_idle(threshold_seconds=300):
    print("User has been away for 5+ minutes")
    # Maybe pause recording, reduce frequency, etc.
```

### 5. Multi-Display Support

```python
from lib import macos

# Get display count
count = macos.get_active_display_count()
print(f"Found {count} active displays")

# Capture each display separately
for i in range(1, count + 1):
    subprocess.run([
        "screencapture",
        "-D", str(i),
        f"display_{i}.png"
    ])
```

## Function Quick Reference

### Display Functions

```python
count = macos.get_active_display_count()         # int or None
active = macos.is_display_active()               # bool or None
index = macos.get_active_display_index()         # int or None (1-based)
x, y = macos.get_mouse_location()                # tuple or None
x, y, w, h = macos.get_display_bounds(id)        # tuple or None
```

### Screen State Functions

```python
unavailable = macos.is_screen_unavailable()      # bool (never None)
screensaver = macos.is_screensaver_active()      # bool or None
```

### App Detection Functions

```python
bundle_id = macos.get_frontmost_app_bundle_id()  # str or None
app_name = macos.get_frontmost_app_name()        # str or None
```

### Activity Functions

```python
idle = macos.is_user_idle(threshold_seconds=300) # bool or None
```

## Error Handling Pattern

All functions return `None` on failure (except `is_screen_unavailable()` which returns `bool`):

```python
from lib import macos

# Pattern 1: Check for None
display_index = macos.get_active_display_index()
if display_index is not None:
    use_display(display_index)
else:
    use_fallback_display()

# Pattern 2: Provide default
bundle_id = macos.get_frontmost_app_bundle_id() or "unknown"

# Pattern 3: Conservative check (is_screen_unavailable never returns None)
if macos.is_screen_unavailable():
    # Definitely unavailable
    skip_recording()
else:
    # Available or detection failed (conservative: assume available)
    proceed_with_recording()
```

## Common Patterns

### Recording Loop with Screen Checks

```python
from lib import macos
import time

while True:
    # Check if screen available
    if macos.is_screen_unavailable():
        print("Screen unavailable - skipping")
        time.sleep(2)
        continue

    # Get display and app info
    display_index = macos.get_active_display_index()
    bundle_id = macos.get_frontmost_app_bundle_id()

    # Capture screenshot with metadata
    capture_screenshot(
        display=display_index,
        app=bundle_id
    )

    time.sleep(2)
```

### Smart Recording (Skip When Idle)

```python
from lib import macos

# Different strategies based on user activity
if macos.is_user_idle(threshold_seconds=300):
    # User idle for 5+ minutes - reduce frequency
    interval = 10  # seconds
elif macos.is_user_idle(threshold_seconds=60):
    # User idle for 1+ minute - normal frequency
    interval = 2
else:
    # User active - high frequency
    interval = 1

time.sleep(interval)
```

### Multi-Display Recording

```python
from lib import macos

# Get all displays
count = macos.get_active_display_count()

if count is None or count == 0:
    print("No displays available")
else:
    # Capture active display (with mouse)
    active = macos.get_active_display_index()
    capture_display(active)

    # Optionally capture all displays
    for i in range(1, count + 1):
        if i != active:
            capture_display(i)  # Capture secondary displays
```

## Debugging

### Enable Verbose Mode

```python
from lib import macos

# Test each function
print("Display count:", macos.get_active_display_count())
print("Display active:", macos.is_display_active())
print("Display index:", macos.get_active_display_index())
print("Mouse location:", macos.get_mouse_location())
print("Screensaver:", macos.is_screensaver_active())
print("Screen unavailable:", macos.is_screen_unavailable())
print("Frontmost app:", macos.get_frontmost_app_bundle_id())
print("User idle:", macos.is_user_idle(60))
```

### Run Test Suite

```bash
python3 src/lib/test_macos.py
```

### Check Permissions

```python
from lib import macos

# Test if Accessibility permission is granted
bundle_id = macos.get_frontmost_app_bundle_id()

if bundle_id is None:
    print("ERROR: AppleScript failed")
elif bundle_id == "unknown":
    print("WARNING: Accessibility permission needed")
    print("Grant in: System Settings → Privacy & Security → Accessibility")
else:
    print(f"SUCCESS: Detected app {bundle_id}")
```

## Performance Tips

1. **Cache CoreGraphics**: The framework is automatically cached after first use
2. **Avoid repeated AppleScript**: Cache app bundle ID if it doesn't need to change every iteration
3. **Batch display queries**: If checking multiple displays, query count once
4. **Use timeouts**: All AppleScript calls have 5s timeout built-in

```python
# Good: Cache frontmost app for multiple uses
bundle_id = macos.get_frontmost_app_bundle_id()
use_bundle_id_multiple_times(bundle_id)

# Bad: Query multiple times unnecessarily
subprocess.run(["do_something", macos.get_frontmost_app_bundle_id()])
subprocess.run(["do_another", macos.get_frontmost_app_bundle_id()])
```

## System Requirements

- macOS 10.13+ (High Sierra or later)
- Python 3.8+
- **Permissions**: Accessibility for frontmost app detection

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Functions return `None` | Expected in sandboxed/container environments |
| Frontmost app returns "unknown" | Grant Accessibility permission |
| AppleScript timeout | System Events not responding, restart Mac |
| Import error | Ensure running from project root: `PYTHONPATH=src python3 script.py` |

## Full Documentation

- **API Reference**: `src/lib/README_macos.md`
- **Migration Guide**: `src/lib/MIGRATION_GUIDE.md`
- **Extraction Details**: `src/lib/EXTRACTION_SUMMARY.md`

## Examples in Code

See these files for usage examples:
- `src/lib/test_macos.py` - Test suite with all functions
- `src/scripts/record_screen.py` - Original implementation (lines 40-291)

## Quick Test

```bash
# Test import
python3 -c "from lib import macos; print('✓ Import works')"

# Test basic function
python3 -c "from lib import macos; print('Screen unavailable:', macos.is_screen_unavailable())"

# Run full test suite
python3 src/lib/test_macos.py
```

## One-Liner Examples

```bash
# Check if screen available
python3 -c "from lib import macos; import sys; sys.exit(0 if not macos.is_screen_unavailable() else 1)"

# Get frontmost app
python3 -c "from lib import macos; print(macos.get_frontmost_app_bundle_id())"

# Get display count
python3 -c "from lib import macos; print(macos.get_active_display_count() or 0)"

# Check if user idle
python3 -c "from lib import macos; print('Idle' if macos.is_user_idle(60) else 'Active')"
```

## Next Steps

1. Read full API docs: `src/lib/README_macos.md`
2. Run test suite: `python3 src/lib/test_macos.py`
3. Integrate into `record_screen.py`: See `src/lib/MIGRATION_GUIDE.md`
4. Use in your scripts: Import and start using!
