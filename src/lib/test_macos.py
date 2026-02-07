#!/usr/bin/env python3
"""
Test script for macos.py library.

This script demonstrates the usage of all functions in the macos module
and provides basic validation that they work correctly.
"""

import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib import macos


def test_display_functions():
    """Test display detection functions."""
    print("=" * 60)
    print("Testing Display Functions")
    print("=" * 60)

    count = macos.get_active_display_count()
    print(f"Active display count: {count}")
    if count is not None:
        print(f"  ✓ Detected {count} active display(s)")
    else:
        print("  ✗ Could not detect display count (CoreGraphics unavailable)")

    active = macos.is_display_active()
    print(f"\nDisplays active: {active}")
    if active is True:
        print("  ✓ At least one display is active")
    elif active is False:
        print("  ! All displays are off/sleeping")
    else:
        print("  ✗ Could not detect display state")

    index = macos.get_active_display_index()
    print(f"\nActive display index: {index}")
    if index is not None:
        print(f"  ✓ Active display index: {index} (for screencapture -D)")
    else:
        print("  ✗ Could not detect active display index")


def test_mouse_functions():
    """Test mouse location detection."""
    print("\n" + "=" * 60)
    print("Testing Mouse Functions")
    print("=" * 60)

    mouse = macos.get_mouse_location()
    print(f"Mouse location: {mouse}")
    if mouse is not None:
        print(f"  ✓ Mouse at ({mouse[0]:.1f}, {mouse[1]:.1f})")
    else:
        print("  ✗ Could not detect mouse location")


def test_screensaver_functions():
    """Test screensaver detection."""
    print("\n" + "=" * 60)
    print("Testing Screensaver Functions")
    print("=" * 60)

    screensaver = macos.is_screensaver_active()
    print(f"Screensaver active: {screensaver}")
    if screensaver is True:
        print("  ! Screen saver is currently active")
    elif screensaver is False:
        print("  ✓ Screen saver is not active")
    else:
        print("  ✗ Could not detect screensaver state (AppleScript unavailable)")


def test_screen_availability():
    """Test screen availability check."""
    print("\n" + "=" * 60)
    print("Testing Screen Availability")
    print("=" * 60)

    unavailable = macos.is_screen_unavailable()
    print(f"Screen unavailable: {unavailable}")
    if unavailable:
        print("  ! Screen should NOT be recorded (screensaver active or displays off)")
    else:
        print("  ✓ Screen is available for recording")


def test_frontmost_app_functions():
    """Test frontmost app detection."""
    print("\n" + "=" * 60)
    print("Testing Frontmost App Functions")
    print("=" * 60)

    bundle_id = macos.get_frontmost_app_bundle_id()
    print(f"Frontmost app bundle ID: {bundle_id}")
    if bundle_id is not None and bundle_id != "unknown":
        print(f"  ✓ Frontmost app: {bundle_id}")
    elif bundle_id == "unknown":
        print("  ! Could not detect frontmost app (Accessibility permission needed)")
    else:
        print("  ✗ AppleScript execution failed")

    app_name = macos.get_frontmost_app_name()
    print(f"\nFrontmost app name: {app_name}")
    if app_name is not None and app_name != "Unknown":
        print(f"  ✓ Frontmost app: {app_name}")
    elif app_name == "Unknown":
        print("  ! Could not detect frontmost app name")
    else:
        print("  ✗ AppleScript execution failed")


def test_idle_detection():
    """Test user idle detection."""
    print("\n" + "=" * 60)
    print("Testing Idle Detection")
    print("=" * 60)

    for threshold in [60, 300, 600]:
        idle = macos.is_user_idle(threshold_seconds=threshold)
        print(f"User idle (>{threshold}s): {idle}")
        if idle is True:
            print(f"  ! User has been idle for more than {threshold} seconds")
        elif idle is False:
            print(f"  ✓ User is active (idle < {threshold}s)")
        else:
            print(f"  ✗ Could not detect idle time")


def main():
    """Run all tests."""
    print("\n" + "=" * 60)
    print("macOS Library Test Suite")
    print("=" * 60)
    print("\nThis test suite validates the macos.py library functions.")
    print("Some tests may fail in sandboxed/container environments.")
    print()

    try:
        test_display_functions()
        test_mouse_functions()
        test_screensaver_functions()
        test_screen_availability()
        test_frontmost_app_functions()
        test_idle_detection()

        print("\n" + "=" * 60)
        print("Test suite completed")
        print("=" * 60)
        print("\nNote: Functions returning None indicate detection failures,")
        print("which is expected in sandboxed environments or when system")
        print("permissions are not granted.")

    except Exception as e:
        print(f"\n✗ Test suite failed with error: {e}")
        import traceback
        traceback.print_exc()
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
