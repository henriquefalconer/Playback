# Privacy & Security Specification

**Component:** Privacy and Security

## App Exclusion

### Window Filtering Mode (Only Mode)

Excluded apps are filtered out at the ScreenCaptureKit level. Their windows are removed from the capture, revealing whatever is behind them. The screenshot is still taken — only the excluded app's windows are invisible.

```swift
let excludedSCApps = content.applications.filter { app in
    guard let bundleID = app.bundleIdentifier else { return false }
    return excludedApps.contains(bundleID)
}
let filter = SCContentFilter(display: display, excludingApplications: excludedSCApps, exceptingWindows: [])
```

### Excluded Apps List

- Stored in `config.json` as `excluded_apps: [String]`
- User adds/removes via Settings panel
- Recommended exclusions shown in UI (not auto-enabled):
  - `com.apple.keychainaccess` — Keychain Access
  - `com.1password.1password` — 1Password 8
  - `com.agilebits.onepassword7` — 1Password 7
  - `com.lastpass.LastPass` — LastPass
  - `com.dashlane.Dashlane` — Dashlane
  - `com.keepassxc.keepassxc` — KeePassXC
  - `com.bitwarden.desktop` — Bitwarden

## Permissions

### Screen Recording (Required)

- **Purpose:** Screenshot capture via ScreenCaptureKit
- **Check:** `CGPreflightScreenCaptureAccess()`
- **Request:** `CGRequestScreenCaptureAccess()`
- **If denied:** Recording service will not start; settings panel shows status with "Open System Settings" button

### Accessibility (Optional)

- **Purpose:** Global hotkey registration (Option+Shift+Space)
- **Check:** `AXIsProcessTrustedWithOptions`
- **If denied:** Hotkey unavailable; user can still open timeline from menu bar or app icon

### Permission UI

Shown inline in the settings panel (not a separate wizard):
- Green/red dot for each permission
- "Granted" / "Denied" label
- "Open System Settings" button when denied

## Recording Pause

Recording pauses automatically in two scenarios:

### Timeline Open (Signal File)

1. Timeline opens → `SignalFileManager` creates `.timeline_open` file
2. `RecordingService` checks for file before each capture → skips if present
3. Timeline closes → signal file removed → recording resumes

### Display Sleep / Screen Lock / Screen Saver

1. Display sleeps, screen locks, or screen saver starts → `RecordingService.pause()` stops the indicator stream and capture timer
2. This prevents macOS from killing the SCStream (which would quit the app via `didStopWithError`)
3. User logs in (screen unlock) → `RecordingService.resume()` restarts indicator stream and timer
4. Pause observed via `NSWorkspace.screensDidSleepNotification` and `DistributedNotificationCenter` `com.apple.screenIsLocked`; resume observed via `DistributedNotificationCenter` `com.apple.screenIsUnlocked` only (display wake does NOT trigger resume, since it fires before user authentication)

Note: display sleep pause stops the indicator stream entirely to prevent the auto-quit; timeline pause only skips captures.

## File Permissions

| Resource | Permissions |
|---|---|
| Screenshots (temp) | 0600 |
| Videos (chunks) | 0600 |
| Database (meta.sqlite3) | 0600 |
| Data directories | 0700 |
| Config file | 0644 |

## Network Policy

Zero network access. No HTTP clients, no sockets, no telemetry, no update checks. All data stays local.

## Data Security

- SQLite: `PRAGMA secure_delete=ON` (overwrites deleted data)
- SQLite: WAL mode for concurrent access
- All sensitive files are user-readable only (0600)
- Data directories are user-accessible only (0700)
