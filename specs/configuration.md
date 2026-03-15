# Configuration Specification

**Component:** Configuration System

## Config File

**Location:**
- Production: `~/Library/Application Support/Playback/config.json`
- Development: `<project>/dev_config.json`

**Schema:**

```json
{
  "version": "1.0.0",
  "excluded_apps": [],
  "timeline_shortcut": "Option+Shift+Space",
  "recording_enabled": true,
  "launch_at_login": false
}
```

## User-Facing Settings (Single Panel)

Only 4 settings are exposed in the UI:

### 1. Launch at Login

- **Config key:** `launch_at_login`
- **Type:** Boolean
- **Default:** false
- **Implementation:** `SMAppService.mainApp` (macOS 13+)

### 2. Permissions Status (Read-Only Display)

- Screen Recording: green/red dot + "Granted"/"Denied" + "Open System Settings" button
- Accessibility: green/yellow dot + "Granted"/"Optional" + "Open System Settings" button
- Not a config value — queried live via `CGPreflightScreenCaptureAccess()` and `AXIsProcessTrustedWithOptions`

### 3. Timeline Hotkey

- **Config key:** `timeline_shortcut`
- **Type:** String
- **Default:** `"Option+Shift+Space"`
- **UI:** HotkeyRecorderView with conflict detection

### 4. Excluded Apps

- **Config key:** `excluded_apps`
- **Type:** Array of bundle ID strings
- **Default:** `[]`
- **UI:** List with add/remove, plus recommended exclusions with quick-add buttons
- **Validation:** Only alphanumeric characters and dots in bundle IDs

## Hardcoded Values (No UI)

| Value | Setting | Rationale |
|---|---|---|
| Recording interval | 2 seconds | Fixed for consistent capture quality |
| Processing interval | 5 minutes | Balanced between freshness and CPU usage |
| Pause when timeline open | Always on | Prevents recording your own timeline browsing |
| Exclusion mode | Skip | Only mode; "invisible" mode removed |
| Video FPS | 30 | Fixed for playback smoothness |
| Video CRF | 28 | Fixed quality/size balance |
| Recording enabled | Via menu bar toggle | Stored in config but controlled by menu bar, not settings |

## Config Management

- **Source:** `ConfigManager.swift` (singleton)
- **Persistence:** JSON file read/write
- **Change notification:** Posts `ConfigDidChange` via NotificationCenter
- **Validation:** `Config.validated()` sanitizes invalid values
- **Hot-reload:** Not needed for 4 simple settings (applied on save)

## Config Struct (Swift)

```swift
struct Config: Codable {
    var version: String = "1.0.0"
    var excludedApps: [String] = []
    var timelineShortcut: String = "Option+Shift+Space"
    var recordingEnabled: Bool = true
    var launchAtLogin: Bool? = false
}
```
