# Menu Bar Component Specification

**Component:** Menu Bar (Playback.app component)
**Version:** 2.0
**Last Updated:** 2026-02-07

## Overview

The Menu Bar component is part of the unified Playback.app that provides a persistent menu bar icon for controlling the application. It runs continuously in the background, starts automatically on user login, and provides quick access to recording controls, settings, and diagnostic information. This component is always running as part of Playback.app, even when the timeline viewer is closed.

## Integration with Unified App

**Architecture:**
- Part of single Playback.app (not a separate app)
- Implemented in `Playback/MenuBar/` directory
- Always running when Playback.app is active
- Shares application state with Timeline and Settings components
- Managed by main `PlaybackApp.swift` entry point

**Lifecycle:**
```swift
@main
struct PlaybackApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var menuBarController = MenuBarController()
    @StateObject private var timelineController = TimelineController()

    var body: some Scene {
        // Menu bar is always present
        MenuBarExtra("Playback", systemImage: menuBarController.icon) {
            MenuBarView(controller: menuBarController)
        }
        .menuBarExtraStyle(.menu)

        // Timeline window shown on demand
        Window("Timeline", id: "timeline") {
            TimelineView(controller: timelineController)
        }
        .windowStyle(.plain)
        .defaultPosition(.center)

        // Settings window
        Settings {
            SettingsView()
        }
    }
}
```

## Responsibilities

1. Display menu bar icon with recording status indicator
2. Provide recording toggle (On/Off switch)
3. Open settings window with all configuration options
4. Display diagnostic information (logs and resource metrics)
5. Control Recording and Processing LaunchAgents
6. Show notifications for errors and status changes
7. Launch Timeline viewer on demand
8. Persist user preferences

## User Interface

### Menu Bar Icon

**Location:** macOS menu bar (right side, near system icons)

**Icon States:**

1. **Recording Active**
   - Icon: Red filled circle (SF Symbol: `record.circle.fill`)
   - Tooltip: "Playback: Recording"

2. **Recording Paused**
   - Icon: Gray outlined circle (SF Symbol: `record.circle`)
   - Tooltip: "Playback: Paused"

3. **Error State**
   - Icon: Red circle with exclamation mark (SF Symbol: `exclamationmark.circle.fill`)
   - Tooltip: "Playback: Error (click for details)"

**Click Behavior:** Shows dropdown menu

### Dropdown Menu

**Structure:**

```
┌─────────────────────────────────┐
│ Playback                        │
├─────────────────────────────────┤
│ Record Screen          [On/Off] │  ← Toggle switch
│ Open Timeline          ⌥⇧Space  │  ← Shortcut hint
├─────────────────────────────────┤
│ Settings...                     │
│ Diagnostics...                  │
├─────────────────────────────────┤
│ About Playback                  │
│ Quit Playback                   │
└─────────────────────────────────┘
```

**Menu Items:**

1. **Record Screen** (NSMenuItem with NSSwitch)
   - Toggle switch (On/Off)
   - Action: Enable/disable recording service via LaunchAgent
   - Visual feedback: Icon changes immediately

2. **Open Timeline** (NSMenuItem)
   - Shortcut hint: `⌥⇧Space`
   - Action: Show timeline window
   - Disabled if: No recordings exist yet

3. **Settings...** (NSMenuItem)
   - Shortcut: `⌘,` (standard macOS preference shortcut)
   - Action: Open settings window

4. **Diagnostics...** (NSMenuItem)
   - Action: Open diagnostics window
   - Badge: Shows warning/error count if any

5. **About Playback** (NSMenuItem)
   - Action: Show about panel with version info

6. **Quit Playback** (NSMenuItem)
   - Shortcut: `⌘Q`
   - Action: Stop all services and quit entire app
   - Confirmation dialog: "Stop recording and quit?"

## Settings Window

### Window Properties

- **Title:** "Playback Settings"
- **Size:** 600×500 (fixed, non-resizable)
- **Style:** Standard window with close button
- **Position:** Center of screen on first open
- **Level:** Normal (can be behind other windows)

### Layout

**Sidebar Navigation** (left side, 150px width):
- General
- Recording
- Processing
- Storage
- Privacy
- Advanced

**Content Area** (right side, 450px width):
- Settings for selected category

### General Tab

```
┌────────────────────────────────────────────┐
│                                            │
│  Launch at Login                           │
│  [✓] Start Playback when I log in          │
│                                            │
│  Global Shortcuts                          │
│  Open Timeline:  [⌥⇧Space] [Change...]    │
│                                            │
│  Notifications                             │
│  [✓] Show notifications for errors        │
│  [✓] Show notifications for crashes       │
│  [✓] Show notifications when disk is full │
│  [ ] Show notifications when recording     │
│      starts/stops                          │
│                                            │
│  Permissions                               │
│  Screen Recording:  ✓ Granted             │
│  [Open System Preferences]                │
│                                            │
│  Accessibility:     ✓ Granted             │
│  [Open System Preferences]                │
│                                            │
└────────────────────────────────────────────┘
```

**Fields:**

1. **Launch at Login** (Checkbox)
   - Default: ON
   - Action: Add/remove login item for Playback.app

2. **Open Timeline Shortcut** (Hotkey field)
   - Default: Option+Shift+Space
   - Validation: No conflicts with system shortcuts

3. **Notification Preferences** (Checkboxes)
   - Error notifications: ON (recommended)
   - Crash notifications: ON (recommended)
   - Disk full notifications: ON (recommended)
   - Recording status notifications: OFF (optional)

4. **Permissions Status** (Read-only with action buttons)
   - Screen Recording: Shows checkmark if granted, X if denied
   - Accessibility: Shows checkmark if granted, X if denied
   - Each has "Open System Preferences" button for quick access

### Recording Tab

```
┌────────────────────────────────────────────┐
│                                            │
│  Recording Behavior                        │
│  Interval: 2 seconds (not configurable)   │
│                                            │
│  Pause Recording When:                     │
│  [✓] Timeline viewer is open              │
│  [ ] Screensaver is active (always true)  │
│  [ ] Display is off (always true)         │
│                                            │
│  Note: Playback will always pause          │
│  recording when your screen is locked,     │
│  display is off, or screensaver is         │
│  active.                                   │
│                                            │
└────────────────────────────────────────────┘
```

**Fields:**

1. **Recording Interval** (Read-only label)
   - Value: "2 seconds"
   - Not configurable per requirements

2. **Pause When Timeline Open** (Checkbox)
   - Default: ON
   - Action: Toggle behavior in recording service

### Processing Tab

```
┌────────────────────────────────────────────┐
│                                            │
│  Processing Schedule                       │
│  Run video processing every:               │
│  [5 minutes ▾]                            │
│    1 minute                               │
│    5 minutes (recommended)                │
│   10 minutes                              │
│   15 minutes                              │
│   30 minutes                              │
│   60 minutes                              │
│                                            │
│  Last Processing Run:                      │
│  December 22, 2025 at 2:35 PM             │
│  Duration: 43 seconds                      │
│  Status: ✓ Completed successfully         │
│                                            │
│  [Process Now]  ← Manual trigger button   │
│                                            │
└────────────────────────────────────────────┘
```

**Fields:**

1. **Processing Interval** (Dropdown)
   - Options: 1, 5, 10, 15, 30, 60 minutes
   - Default: 5 minutes
   - Action: Update LaunchAgent plist and reload

2. **Last Run Status** (Read-only labels)
   - Timestamp, duration, status from logs

3. **Process Now Button**
   - Action: Manually trigger processing
   - Disabled while processing is running
   - Shows progress indicator during processing

### Storage Tab

```
┌────────────────────────────────────────────┐
│                                            │
│  Current Usage                             │
│  Screenshots (temp):    2.3 GB            │
│  Videos (chunks):      45.7 GB            │
│  Total:                48.0 GB            │
│                                            │
│  Location:                                 │
│  ~/Library/Application Support/Playback/data │
│  [Open in Finder]                         │
│                                            │
│  Cleanup Policies                          │
│                                            │
│  Delete temporary screenshots older than:  │
│  [1 week ▾]                               │
│    Never                                  │
│    1 day                                  │
│    1 week (recommended)                   │
│    1 month                                │
│                                            │
│  Delete recordings older than:             │
│  [Never ▾]                                │
│    Never (default)                        │
│    1 day                                  │
│    1 week                                 │
│    1 month                                │
│                                            │
│  [Clean Up Now]  ← Manual cleanup button  │
│                                            │
└────────────────────────────────────────────┘
```

**Fields:**

1. **Current Usage** (Read-only labels)
   - Calculated by scanning directories
   - Refreshed on tab open

2. **Storage Location** (Label + button)
   - Shows full path
   - "Open in Finder" button reveals directory

3. **Temp Retention Policy** (Dropdown)
   - Options: Never, 1 day, 1 week, 1 month
   - Default: 1 week
   - Applied during next processing run

4. **Recording Retention Policy** (Dropdown)
   - Options: Never, 1 day, 1 week, 1 month
   - Default: Never
   - Applied during next processing run

5. **Clean Up Now Button**
   - Action: Trigger cleanup immediately
   - Shows confirmation dialog with preview
   - Progress indicator during cleanup

### Privacy Tab

```
┌────────────────────────────────────────────┐
│                                            │
│  App Exclusion                             │
│                                            │
│  When excluded apps are visible:           │
│  [Skip screenshot ▾]                      │
│    Make app invisible                     │
│    Skip screenshot entirely (recommended) │
│                                            │
│  Excluded Apps:                            │
│  ┌──────────────────────────────────────┐ │
│  │ 🔑 1Password                         │ │
│  │ 🔐 Keychain Access                   │ │
│  │                                      │ │
│  │                                      │ │
│  └──────────────────────────────────────┘ │
│  [+ Add App]  [- Remove]                  │
│                                            │
│  Note: Screenshots may still contain       │
│  sensitive information from other apps     │
│  or notifications.                         │
│                                            │
└────────────────────────────────────────────┘
```

**Fields:**

1. **Exclusion Mode** (Dropdown)
   - Option 1: "Make app invisible" - Screenshot taken, app blacked out
   - Option 2: "Skip screenshot entirely" - No screenshot taken (recommended)
   - Default: "Skip screenshot entirely"

2. **Excluded Apps List** (Table view)
   - Shows app name with icon
   - Bundle ID shown on hover
   - Sorted alphabetically

3. **Add App Button**
   - Opens app picker dialog
   - Can drag & drop apps from Finder
   - Can paste bundle ID

4. **Remove Button**
   - Removes selected app(s) from list
   - Confirmation: "Remove X from exclusion list?"

### Advanced Tab

```
┌────────────────────────────────────────────┐
│                                            │
│  Video Encoding (not user-configurable)    │
│  Codec: H.264                             │
│  Quality: CRF 28                          │
│  Preset: veryfast                         │
│  FPS: 30                                   │
│                                            │
│  System Information                        │
│  macOS Version: 13.0 (Ventura)            │
│  Python Version: 3.10.8                   │
│  FFmpeg Version: 5.1.2                    │
│  Available Disk Space: 123.4 GB           │
│                                            │
│  Service Status                            │
│  Recording Service:    ● Running          │
│  Processing Service:   ● Idle             │
│                                            │
│  Maintenance                               │
│  [Reset All Settings]                     │
│  [Rebuild Database]                       │
│  [Export Logs]                            │
│  [Run Diagnostics Check]                  │
│                                            │
└────────────────────────────────────────────┘
```

**Fields:**

1. **Video Encoding** (Read-only labels)
   - Shows current encoding parameters
   - Not configurable per requirements

2. **System Information** (Read-only labels)
   - macOS version
   - Python version (detected from system)
   - FFmpeg version (detected from installation)
   - Available disk space (updated on tab open)

3. **Service Status** (Real-time status indicators)
   - Green dot = running/active
   - Yellow dot = idle/waiting
   - Red dot = stopped/crashed
   - Updates every 5 seconds

4. **Maintenance Buttons**
   - **Reset All Settings:** Restore defaults (confirmation dialog)
   - **Rebuild Database:** Scan chunks/ and regenerate meta.sqlite3
   - **Export Logs:** Save all logs to zip file
   - **Run Diagnostics Check:** Verify all components working correctly

## Diagnostics Window

### Window Properties

- **Title:** "Playback Diagnostics"
- **Size:** 800×600 (resizable)
- **Style:** Standard window
- **Toolbar:** Buttons for refresh, export, clear

### Layout

**Toolbar:**
- [Refresh] - Reload logs and metrics
- [Export] - Save diagnostics to file
- [Clear] - Clear on-screen display (doesn't delete logs)

**Content Area:**

**Tabs:**
1. Overview
2. Recording Logs
3. Processing Logs
4. Resource Usage

### Overview Tab

```
┌────────────────────────────────────────────────────────┐
│                                                        │
│  System Status                  Last Updated: 2:35 PM │
│                                                        │
│  Recording Service:    ● Running                      │
│  Processing Service:   ● Idle (last run: 5m ago)     │
│  Timeline Viewer:      ○ Not open                     │
│                                                        │
│  ────────────────────────────────────────────────────  │
│                                                        │
│  Statistics (Last 24 Hours)                           │
│                                                        │
│  Screenshots Captured:      43,200                    │
│  Video Segments Created:     288                      │
│  Total Recording Time:       23h 58m                  │
│  Disk Space Used:           +4.2 GB                   │
│                                                        │
│  ────────────────────────────────────────────────────  │
│                                                        │
│  Recent Issues                                         │
│                                                        │
│  ⚠️ Processing took longer than usual (2m 15s)       │
│     December 22, 2025 at 2:30 PM                      │
│                                                        │
│  ⚠️ Screenshot skipped (excluded app)                │
│     December 22, 2025 at 1:45 PM                      │
│                                                        │
└────────────────────────────────────────────────────────┘
```

### Recording Logs Tab

Same structure as before, displaying structured logs from recording service.

### Processing Logs Tab

Same structure as before, displaying structured logs from processing service.

### Resource Usage Tab

Real-time charts showing CPU, memory, and disk I/O for recording and processing services.

## Implementation Details

### LaunchAgent Control

**Loading Recording Service:**
```swift
func enableRecording() {
    let task = Process()
    task.launchPath = "/bin/launchctl"
    task.arguments = [
        "load",
        "\(NSHomeDirectory())/Library/LaunchAgents/com.playback.recording.plist"
    ]
    try? task.run()
    task.waitUntilExit()

    // Update config file
    configManager.updateConfig(key: "recording_enabled", value: true)
}
```

**Unloading Recording Service:**
```swift
func disableRecording() {
    let task = Process()
    task.launchPath = "/bin/launchctl"
    task.arguments = [
        "unload",
        "\(NSHomeDirectory())/Library/LaunchAgents/com.playback.recording.plist"
    ]
    try? task.run()
    task.waitUntilExit()

    // Update config file
    configManager.updateConfig(key: "recording_enabled", value: false)
}
```

### Configuration Management

**Shared with Timeline Component:**

All components of Playback.app share the same configuration manager:

```swift
class ConfigManager: ObservableObject {
    @Published var config: Config
    private let configURL: URL

    init() {
        configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Playback/config.json")
        config = loadConfig()
    }

    func loadConfig() -> Config {
        guard let data = try? Data(contentsOf: configURL) else {
            return Config.default
        }
        return (try? JSONDecoder().decode(Config.self, from: data)) ?? Config.default
    }

    func saveConfig() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: configURL)
    }

    func updateConfig<T>(key: WritableKeyPath<Config, T>, value: T) {
        config[keyPath: key] = value
        saveConfig()
    }
}
```

### Notifications

**Sending macOS Notifications with Actions:**
```swift
func showNotification(title: String, body: String, isError: Bool = false, withSettingsButton: Bool = false) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = isError ? .defaultCritical : .default

    if withSettingsButton {
        content.categoryIdentifier = "SETTINGS_ACTION"

        let openSettingsAction = UNNotificationAction(
            identifier: "OPEN_SETTINGS",
            title: "Open Settings",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "SETTINGS_ACTION",
            actions: [openSettingsAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    let request = UNNotificationRequest(
        identifier: UUID().uuidString,
        content: content,
        trigger: nil
    )

    UNUserNotificationCenter.current().add(request)
}

// Handle notification actions
func userNotificationCenter(_ center: UNUserNotificationCenter,
                           didReceive response: UNNotificationResponse,
                           withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.actionIdentifier == "OPEN_SETTINGS" {
        settingsManager.openSettings()
    }
    completionHandler()
}
```

**Examples:**
- "Playback needs Screen Recording permission" (with "Open Settings" button)
- "Recording Service crashed" (with "Open Settings" button)
- "Playback stopped: Disk full" (with "Open Settings" button)

### Launch at Login

**Implementation:**
```swift
import ServiceManagement

func setLaunchAtLogin(_ enabled: Bool) {
    if #available(macOS 13.0, *) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
        }
    } else {
        // Fallback for macOS 12
        SMLoginItemSetEnabled("com.playback.Playback" as CFString, enabled)
    }
}
```

## Component Communication

### Menu Bar → Timeline

**Opening Timeline:**
```swift
// In MenuBarController
func openTimeline() {
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "timeline" }) {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    } else {
        // Window automatically created by SwiftUI Scene
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

### Menu Bar → Settings

**Opening Settings:**
```swift
// In MenuBarController
func openSettings() {
    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
}
```

### Shared State

**Using SwiftUI Environment:**
```swift
@main
struct PlaybackApp: App {
    @StateObject private var configManager = ConfigManager()
    @StateObject private var menuBarController = MenuBarController()
    @StateObject private var timelineController = TimelineController()

    var body: some Scene {
        MenuBarExtra("Playback", systemImage: menuBarController.icon) {
            MenuBarView(controller: menuBarController)
                .environmentObject(configManager)
        }

        Window("Timeline", id: "timeline") {
            TimelineView(controller: timelineController)
                .environmentObject(configManager)
        }

        Settings {
            SettingsView()
                .environmentObject(configManager)
        }
    }
}
```

## Dependencies

- macOS 12.0+ (Monterey or later)
- Swift 5.5+
- SwiftUI 3.0+
- Foundation framework
- AppKit framework
- UserNotifications framework
- ServiceManagement framework (for launch at login)

## Testing

### Unit Tests

- Configuration loading/saving
- LaunchAgent control
- Log file parsing
- Notification scheduling

### UI Tests

- Menu bar icon interaction
- Settings window navigation
- Toggle recording
- App exclusion management

### Integration Tests

- Enable/disable recording (verify LaunchAgent state)
- Change processing interval (verify plist updated)
- Trigger manual processing (verify process starts)
- Open timeline from menu bar

## Future Enhancements

- System tray quick actions (right-click menu)
- Status bar timecode (show current recording time)
- Thumbnail previews in menu
- Usage statistics dashboard
- Export/import settings
