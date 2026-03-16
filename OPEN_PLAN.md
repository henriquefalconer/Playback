# Plan: Add "Open Timeline" to Right-Click Menu on Tray Icon

## Status: COMPLETED

## What was done

Added right-click menu on the tray icon (status bar button) with an "Open Timeline" option. Implementation:

1. **Notification bridge** (`PlaybackApp.swift`): Added `Notification.Name.openTimeline` to bridge from AppKit right-click handler to SwiftUI's `openWindow(id: "timeline")`. The `MenuBarExtra` body listens via `.onReceive`.

2. **Event monitors** (`AppDelegate`): Installed both local and global `NSEvent` monitors for `.rightMouseDown`:
   - Local monitor handles right-clicks when app is active (during MenuBarExtra interaction)
   - Global monitor handles right-clicks when app is in background (normal state for menu bar apps)
   - Both check if the click targets the `NSStatusBarWindow` backing the `MenuBarExtra`

3. **NSMenu**: Single-item menu with "Open Timeline" and `clock.arrow.circlepath` SF Symbol, matching the left-click menu item.

4. **Logging**: All interactions logged via `Log.menuBar` — monitor installation, menu display, and timeline open.

## Files Modified

- `src/Playback/Playback/PlaybackApp.swift` — notification extension, `.onReceive` listener, right-click monitor setup in AppDelegate
