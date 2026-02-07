"""
macOS-specific utilities for system integration.

This module provides functions for:
- CoreGraphics display detection and management
- AppleScript integration for system state queries
- Screen availability detection (screensaver, display off)
- Frontmost application detection

All functions include proper error handling and return None on failure
rather than raising exceptions, allowing callers to handle failures gracefully.
"""

import ctypes
import ctypes.util
import subprocess
from typing import Optional, Tuple


# Global CoreGraphics framework reference (lazy-loaded)
_CG = None


def load_coregraphics() -> ctypes.CDLL:
    """
    Load the CoreGraphics framework via ctypes.

    The framework is lazy-loaded and cached for performance.

    Returns:
        CDLL object for CoreGraphics framework

    Raises:
        RuntimeError: If CoreGraphics framework cannot be found
    """
    global _CG
    if _CG is not None:
        return _CG

    path = ctypes.util.find_library("CoreGraphics")
    if not path:
        raise RuntimeError("CoreGraphics framework not found")

    _CG = ctypes.CDLL(path)
    return _CG


def get_active_display_count() -> Optional[int]:
    """
    Get the number of active displays using CoreGraphics.

    An active display is one that is powered on and available for rendering.
    If no displays are active (all displays are off/sleeping), returns 0.

    Returns:
        Number of active displays (0 if all displays off), or None if detection failed
    """
    try:
        cg = load_coregraphics()
    except Exception:
        return None

    # Define function signature for CGGetActiveDisplayList
    CGGetActiveDisplayList = cg.CGGetActiveDisplayList
    CGGetActiveDisplayList.argtypes = [
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_uint32),
    ]
    CGGetActiveDisplayList.restype = ctypes.c_int32

    # Query active displays
    max_displays = 16
    active = (ctypes.c_uint32 * max_displays)()
    count = ctypes.c_uint32(0)
    err = CGGetActiveDisplayList(max_displays, active, ctypes.byref(count))

    if err != 0:
        return None

    return count.value


def is_display_active() -> Optional[bool]:
    """
    Check if any displays are currently active.

    Returns:
        True if at least one display is active
        False if no displays are active (all displays off)
        None if detection failed
    """
    count = get_active_display_count()
    if count is None:
        return None
    return count > 0


def get_mouse_location() -> Optional[Tuple[float, float]]:
    """
    Get the current mouse cursor location in screen coordinates.

    Uses CoreGraphics to query the current event state.

    Returns:
        Tuple of (x, y) coordinates, or None if detection failed
    """
    try:
        cg = load_coregraphics()
    except Exception:
        return None

    # Define CGPoint struct
    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

    # Define function signatures
    CGEventCreate = cg.CGEventCreate
    CGEventCreate.argtypes = [ctypes.c_void_p]
    CGEventCreate.restype = ctypes.c_void_p

    CGEventGetLocation = cg.CGEventGetLocation
    CGEventGetLocation.argtypes = [ctypes.c_void_p]
    CGEventGetLocation.restype = CGPoint

    # Get current mouse location
    event_ref = CGEventCreate(None)
    if not event_ref:
        return None

    loc = CGEventGetLocation(event_ref)
    return (loc.x, loc.y)


def get_display_bounds(display_id: int) -> Optional[Tuple[float, float, float, float]]:
    """
    Get the bounds (frame) of a display in screen coordinates.

    Args:
        display_id: CoreGraphics display ID

    Returns:
        Tuple of (x, y, width, height), or None if detection failed
    """
    try:
        cg = load_coregraphics()
    except Exception:
        return None

    # Define CoreGraphics structs
    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

    class CGSize(ctypes.Structure):
        _fields_ = [("width", ctypes.c_double), ("height", ctypes.c_double)]

    class CGRect(ctypes.Structure):
        _fields_ = [("origin", CGPoint), ("size", CGSize)]

    # Define function signature
    CGDisplayBounds = cg.CGDisplayBounds
    CGDisplayBounds.argtypes = [ctypes.c_uint32]
    CGDisplayBounds.restype = CGRect

    # Get display bounds
    bounds = CGDisplayBounds(display_id)
    return (
        bounds.origin.x,
        bounds.origin.y,
        bounds.size.width,
        bounds.size.height
    )


def get_active_display_index() -> Optional[int]:
    """
    Get the 1-based index of the display currently in use.

    Uses a heuristic: finds which display contains the mouse cursor.
    The returned index is compatible with screencapture -D flag.

    Returns:
        1-based display index (1 for first display, 2 for second, etc.)
        Returns None if detection failed
        Fallback to 1 (first display) if mouse is not on any display
    """
    try:
        cg = load_coregraphics()
    except Exception:
        return None

    # Define CoreGraphics structs
    class CGPoint(ctypes.Structure):
        _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]

    class CGSize(ctypes.Structure):
        _fields_ = [("width", ctypes.c_double), ("height", ctypes.c_double)]

    class CGRect(ctypes.Structure):
        _fields_ = [("origin", CGPoint), ("size", CGSize)]

    # Define function signatures
    CGGetActiveDisplayList = cg.CGGetActiveDisplayList
    CGGetActiveDisplayList.argtypes = [
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32),
        ctypes.POINTER(ctypes.c_uint32),
    ]
    CGGetActiveDisplayList.restype = ctypes.c_int32

    CGEventCreate = cg.CGEventCreate
    CGEventCreate.argtypes = [ctypes.c_void_p]
    CGEventCreate.restype = ctypes.c_void_p

    CGEventGetLocation = cg.CGEventGetLocation
    CGEventGetLocation.argtypes = [ctypes.c_void_p]
    CGEventGetLocation.restype = CGPoint

    CGDisplayBounds = cg.CGDisplayBounds
    CGDisplayBounds.argtypes = [ctypes.c_uint32]
    CGDisplayBounds.restype = CGRect

    # Get list of active displays
    max_displays = 16
    active = (ctypes.c_uint32 * max_displays)()
    count = ctypes.c_uint32(0)
    err = CGGetActiveDisplayList(max_displays, active, ctypes.byref(count))

    if err != 0 or count.value == 0:
        return None

    # Get current mouse location
    event_ref = CGEventCreate(None)
    if not event_ref:
        return None

    loc = CGEventGetLocation(event_ref)
    px, py = loc.x, loc.y

    # Find which display contains the mouse cursor
    for i in range(count.value):
        display_id = active[i]
        bounds = CGDisplayBounds(display_id)
        sx = bounds.origin.x
        sy = bounds.origin.y
        sw = bounds.size.width
        sh = bounds.size.height

        # Check if mouse is within this display's bounds
        if px >= sx and px <= sx + sw and py >= sy and py <= sy + sh:
            return i + 1  # screencapture -D uses 1-based indexing

    # Fallback: return first display if mouse not found on any display
    return 1


def is_screensaver_active() -> Optional[bool]:
    """
    Check if the screen saver is currently running.

    Uses AppleScript to query System Events for screen saver state.

    Returns:
        True if screen saver is active
        False if screen saver is not active
        None if detection failed
    """
    try:
        script = 'tell application "System Events" to tell screen saver preferences to get running'
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )

        if result.returncode == 0:
            output = result.stdout.strip().lower()
            if "true" in output:
                return True
            if "false" in output:
                return False

        return None
    except Exception:
        return None


def is_screen_unavailable() -> bool:
    """
    Check if the screen should NOT be recorded.

    The screen is considered unavailable if:
    - Screen saver is active
    - All displays are off/sleeping

    This function is designed to be conservative: if detection fails,
    it assumes the screen IS available (returns False) to avoid
    missing recordings unnecessarily.

    Returns:
        True if screen should not be recorded
        False if screen is available for recording
    """
    # Check screen saver first
    screensaver_active = is_screensaver_active()
    if screensaver_active is True:
        return True

    # Check if any displays are active
    display_active = is_display_active()
    if display_active is False:
        return True

    # If detection failed or screen is available, return False
    return False


def get_frontmost_app_bundle_id() -> Optional[str]:
    """
    Get the bundle identifier of the currently focused application.

    Uses AppleScript with System Events (requires Accessibility permission).

    Returns:
        Bundle ID string (e.g., "com.apple.Safari")
        Returns "unknown" if detection failed
        Returns None if subprocess execution failed
    """
    script = (
        'tell application "System Events" to get '
        'bundle identifier of (first process whose frontmost is true)'
    )

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
        bundle_id = result.stdout.strip()
        return bundle_id if bundle_id else "unknown"
    except subprocess.TimeoutExpired:
        return "unknown"
    except subprocess.CalledProcessError:
        return "unknown"
    except Exception:
        return None


def get_frontmost_app_name() -> Optional[str]:
    """
    Get the localized name of the currently focused application.

    Uses AppleScript with System Events (requires Accessibility permission).

    Returns:
        Application name string (e.g., "Safari")
        Returns "Unknown" if detection failed
        Returns None if subprocess execution failed
    """
    script = (
        'tell application "System Events" to get '
        'name of (first process whose frontmost is true)'
    )

    try:
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            text=True,
            check=True,
            timeout=5,
        )
        app_name = result.stdout.strip()
        return app_name if app_name else "Unknown"
    except subprocess.TimeoutExpired:
        return "Unknown"
    except subprocess.CalledProcessError:
        return "Unknown"
    except Exception:
        return None


def is_user_idle(threshold_seconds: int = 300) -> Optional[bool]:
    """
    Check if the user has been idle (no keyboard/mouse activity).

    Uses CoreGraphics to query system idle time.

    Args:
        threshold_seconds: Number of seconds of inactivity to consider idle (default: 300 = 5 minutes)

    Returns:
        True if user has been idle longer than threshold
        False if user is active
        None if detection failed
    """
    try:
        cg = load_coregraphics()
    except Exception:
        return None

    # Define function signature
    CGEventSourceSecondsSinceLastEventType = cg.CGEventSourceSecondsSinceLastEventType
    CGEventSourceSecondsSinceLastEventType.argtypes = [ctypes.c_int32, ctypes.c_uint32]
    CGEventSourceSecondsSinceLastEventType.restype = ctypes.c_double

    # Query idle time
    # kCGEventSourceStateHIDSystemState = 1
    # kCGAnyInputEventType = ~0
    idle_time = CGEventSourceSecondsSinceLastEventType(1, ~0)

    if idle_time < 0:
        return None

    return idle_time >= threshold_seconds
