# Configuration Specification

**Component:** Configuration System
**Version:** 1.0
**Last Updated:** 2026-02-07

## Overview

Playback uses a JSON-based configuration system stored in the user's Application Support directory. All components read from this single source of truth, ensuring consistent behavior across the system.

## Configuration File

### Location

**Path:** `~/Library/Application Support/Playback/config.json`

**Creation:** Automatically created on first launch with default values

**Permissions:** 0644 (user read/write, others read-only)

### Schema

**Version:** 1.0

**Full Structure:**

```json
{
  "version": "1.0",
  "recording_enabled": true,
  "processing_interval_minutes": 5,
  "temp_retention_policy": "1_week",
  "recording_retention_policy": "never",
  "excluded_apps": [
    "com.apple.Keychain",
    "com.1password.1password"
  ],
  "exclusion_mode": "skip",
  "pause_on_timeline_open": true,
  "notifications": {
    "errors": true,
    "disk_full": true,
    "recording_status": false
  },
  "launch_at_login": true,
  "timeline_shortcut": "Option+Shift+Space",
  "ffmpeg_preset": "veryfast",
  "ffmpeg_crf": 28,
  "video_fps": 30,
  "segment_duration_seconds": 5
}
```

## Configuration Fields

### Recording Settings

**`recording_enabled`** (boolean)
- **Default:** `true`
- **Description:** Master switch for screenshot capture
- **Modified by:** Menu bar app toggle
- **Read by:** Recording service, menu bar app

**`pause_on_timeline_open`** (boolean)
- **Default:** `true`
- **Description:** Whether to pause recording when playback app is visible
- **Modified by:** Settings window
- **Read by:** Recording service

**`excluded_apps`** (array of strings)
- **Default:** `[]`
- **Description:** List of bundle IDs to exclude from recording
- **Format:** Array of bundle identifier strings (e.g., "com.apple.Safari")
- **Modified by:** Settings window (Privacy tab)
- **Read by:** Recording service

**`exclusion_mode`** (string enum)
- **Default:** `"skip"`
- **Options:**
  - `"invisible"` - Take screenshot but black out excluded app
  - `"skip"` - Don't take screenshot at all
- **Description:** How to handle excluded apps
- **Modified by:** Settings window (Privacy tab)
- **Read by:** Recording service

### Processing Settings

**`processing_interval_minutes`** (integer)
- **Default:** `5`
- **Options:** 1, 5, 10, 15, 30, 60
- **Description:** How often to run video processing (minutes)
- **Modified by:** Settings window (Processing tab)
- **Read by:** Menu bar app (to update LaunchAgent plist)

**`ffmpeg_preset`** (string)
- **Default:** `"veryfast"`
- **Options:** `"ultrafast"`, `"veryfast"`, `"fast"`, `"medium"`, `"slow"`
- **Description:** FFmpeg encoding speed preset
- **Modified by:** Not user-configurable (fixed per requirements)
- **Read by:** Processing service

**`ffmpeg_crf`** (integer)
- **Default:** `28`
- **Range:** 0-51 (lower = better quality, larger file)
- **Description:** FFmpeg Constant Rate Factor for video quality
- **Modified by:** Not user-configurable (fixed per requirements)
- **Read by:** Processing service

**`video_fps`** (integer)
- **Default:** `30`
- **Description:** Output video framerate
- **Modified by:** Not user-configurable (fixed per requirements)
- **Read by:** Processing service

**`segment_duration_seconds`** (integer)
- **Default:** `5`
- **Description:** Target duration for each video segment
- **Modified by:** Not user-configurable (fixed per requirements)
- **Read by:** Processing service

### Storage Settings

**`temp_retention_policy`** (string enum)
- **Default:** `"1_week"`
- **Options:** `"never"`, `"1_day"`, `"1_week"`, `"1_month"`
- **Description:** Delete temp screenshots older than this duration
- **Modified by:** Settings window (Storage tab)
- **Read by:** Processing service

**`recording_retention_policy`** (string enum)
- **Default:** `"never"`
- **Options:** `"never"`, `"1_day"`, `"1_week"`, `"1_month"`
- **Description:** Delete video recordings older than this duration
- **Modified by:** Settings window (Storage tab)
- **Read by:** Processing service

### User Interface Settings

**`launch_at_login`** (boolean)
- **Default:** `true`
- **Description:** Start menu bar app automatically on user login
- **Modified by:** Settings window (General tab)
- **Read by:** Menu bar app (to manage login item)

**`timeline_shortcut`** (string)
- **Default:** `"Option+Shift+Space"`
- **Description:** Global keyboard shortcut to open playback app
- **Format:** Modifier keys + Key (e.g., "Command+Option+S")
- **Modified by:** Settings window (General tab)
- **Read by:** Playback app

**`notifications`** (object)
- **Default:** `{"errors": true, "disk_full": true, "recording_status": false}`
- **Description:** Which notifications to show
- **Fields:**
  - `errors` (boolean) - Show error notifications
  - `disk_full` (boolean) - Show disk full notifications
  - `recording_status` (boolean) - Show start/stop notifications
- **Modified by:** Settings window (General tab)
- **Read by:** All services

### Metadata

**`version`** (string)
- **Default:** `"1.0"`
- **Description:** Configuration schema version
- **Modified by:** System (during migrations)
- **Read by:** All components (for compatibility checks)

## Configuration Management

### Loading Configuration

**Priority:**
1. Read from config file
2. If file doesn't exist: Create with defaults
3. If file is malformed: Log error, use defaults, back up corrupt file
4. If missing fields: Merge with defaults (partial config)

**Implementation (Swift):**
```swift
struct Config: Codable {
    let version: String
    var recordingEnabled: Bool
    var processingIntervalMinutes: Int
    var tempRetentionPolicy: String
    var recordingRetentionPolicy: String
    var excludedApps: [String]
    var exclusionMode: String
    var pauseOnTimelineOpen: Bool
    var notifications: NotificationPreferences
    var launchAtLogin: Bool
    var timelineShortcut: String
    let ffmpegPreset: String
    let ffmpegCrf: Int
    let videoFps: Int
    let segmentDurationSeconds: Int

    struct NotificationPreferences: Codable {
        var errors: Bool
        var diskFull: Bool
        var recordingStatus: Bool
    }

    static let `default` = Config(
        version: "1.0",
        recordingEnabled: true,
        processingIntervalMinutes: 5,
        tempRetentionPolicy: "1_week",
        recordingRetentionPolicy: "never",
        excludedApps: [],
        exclusionMode: "skip",
        pauseOnTimelineOpen: true,
        notifications: NotificationPreferences(errors: true, diskFull: true, recordingStatus: false),
        launchAtLogin: true,
        timelineShortcut: "Option+Shift+Space",
        ffmpegPreset: "veryfast",
        ffmpegCrf: 28,
        videoFps: 30,
        segmentDurationSeconds: 5
    )
}

func loadConfig() -> Config {
    let url = configFileURL()

    guard FileManager.default.fileExists(atPath: url.path) else {
        let defaultConfig = Config.default
        saveConfig(defaultConfig)
        return defaultConfig
    }

    do {
        let data = try Data(contentsOf: url)
        var config = try JSONDecoder().decode(Config.self, from: data)

        // Validate and clamp values
        config = validateConfig(config)

        return config
    } catch {
        print("[Config] Failed to load config: \(error)")

        // Back up corrupt file
        let backupURL = url.appendingPathExtension("backup.\(Date().timeIntervalSince1970)")
        try? FileManager.default.copyItem(at: url, to: backupURL)

        return Config.default
    }
}
```

**Implementation (Python):**
```python
import json
from pathlib import Path
from typing import Any, Dict

DEFAULT_CONFIG = {
    "version": "1.0",
    "recording_enabled": True,
    "processing_interval_minutes": 5,
    "temp_retention_policy": "1_week",
    "recording_retention_policy": "never",
    "excluded_apps": [],
    "exclusion_mode": "skip",
    "pause_on_timeline_open": True,
    "notifications": {
        "errors": True,
        "disk_full": True,
        "recording_status": False
    },
    "launch_at_login": True,
    "timeline_shortcut": "Option+Shift+Space",
    "ffmpeg_preset": "veryfast",
    "ffmpeg_crf": 28,
    "video_fps": 30,
    "segment_duration_seconds": 5
}

def get_config_path() -> Path:
    return Path.home() / "Library/Application Support/Playback/config.json"

def load_config() -> Dict[str, Any]:
    path = get_config_path()

    if not path.exists():
        save_config(DEFAULT_CONFIG)
        return DEFAULT_CONFIG.copy()

    try:
        with open(path, 'r') as f:
            config = json.load(f)

        # Merge with defaults (in case new fields added)
        merged = DEFAULT_CONFIG.copy()
        merged.update(config)

        # Validate values
        merged = validate_config(merged)

        return merged
    except Exception as e:
        print(f"[Config] Failed to load config: {e}")
        return DEFAULT_CONFIG.copy()

def validate_config(config: Dict[str, Any]) -> Dict[str, Any]:
    # Clamp processing interval to valid values
    valid_intervals = [1, 5, 10, 15, 30, 60]
    if config["processing_interval_minutes"] not in valid_intervals:
        config["processing_interval_minutes"] = 5

    # Validate retention policies
    valid_policies = ["never", "1_day", "1_week", "1_month"]
    if config["temp_retention_policy"] not in valid_policies:
        config["temp_retention_policy"] = "1_week"
    if config["recording_retention_policy"] not in valid_policies:
        config["recording_retention_policy"] = "never"

    # Validate exclusion mode
    valid_modes = ["invisible", "skip"]
    if config["exclusion_mode"] not in valid_modes:
        config["exclusion_mode"] = "skip"

    return config
```

### Saving Configuration

**Process:**
1. Validate all fields
2. Serialize to JSON with pretty formatting
3. Write to temp file atomically
4. Rename temp file to target (atomic replace)
5. Log configuration change

**Implementation (Swift):**
```swift
func saveConfig(_ config: Config) {
    let url = configFileURL()
    let tempURL = url.appendingPathExtension("tmp")

    do {
        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)

        // Write to temp file
        try data.write(to: tempURL)

        // Atomic replace
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)

        print("[Config] Configuration saved successfully")
    } catch {
        print("[Config] Failed to save config: \(error)")
    }
}
```

**Implementation (Python):**
```python
def save_config(config: Dict[str, Any]) -> None:
    path = get_config_path()
    temp_path = path.with_suffix('.tmp')

    try:
        # Ensure directory exists
        path.parent.mkdir(parents=True, exist_ok=True)

        # Write to temp file
        with open(temp_path, 'w') as f:
            json.dump(config, f, indent=2, sort_keys=True)

        # Atomic replace
        temp_path.replace(path)

        print("[Config] Configuration saved successfully")
    except Exception as e:
        print(f"[Config] Failed to save config: {e}")
```

### Configuration Changes

**Propagation:**
- Menu bar app: Immediate (watches file for changes)
- Recording service: Next iteration (every 2 seconds)
- Processing service: Next run (every N minutes)
- Playback app: On launch

**Change Notification (Optional):**
- Use FSEvents to watch config file
- Notify components to reload when changed
- Reduces latency for settings changes

**Implementation (Swift):**
```swift
class ConfigWatcher {
    private var monitor: DispatchSourceFileSystemObject?

    func startWatching(onChange: @escaping () -> Void) {
        let url = configFileURL()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let queue = DispatchQueue(label: "com.playback.config.watcher")
        monitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: queue
        )

        monitor?.setEventHandler {
            onChange()
        }

        monitor?.setCancelHandler {
            close(fd)
        }

        monitor?.resume()
    }

    func stopWatching() {
        monitor?.cancel()
        monitor = nil
    }
}
```

## Configuration Validation

### Field Validation Rules

**`processing_interval_minutes`:**
- Must be in: [1, 5, 10, 15, 30, 60]
- If invalid: Reset to 5

**`temp_retention_policy`:**
- Must be in: ["never", "1_day", "1_week", "1_month"]
- If invalid: Reset to "1_week"

**`recording_retention_policy`:**
- Must be in: ["never", "1_day", "1_week", "1_month"]
- If invalid: Reset to "never"

**`exclusion_mode`:**
- Must be in: ["invisible", "skip"]
- If invalid: Reset to "skip"

**`excluded_apps`:**
- Must be array of strings
- Each string should be valid bundle ID format
- If invalid: Filter out invalid entries

**`ffmpeg_crf`:**
- Must be integer in range [0, 51]
- If invalid: Reset to 28

**`video_fps`:**
- Must be positive integer
- Recommended: 24, 30, 60
- If invalid: Reset to 30

**`timeline_shortcut`:**
- Must be valid keyboard shortcut string
- Format: "[Modifiers+]Key"
- If invalid: Reset to "Option+Shift+Space"

### Sanitization

**Bundle IDs:**
- Strip whitespace
- Convert to lowercase (optional)
- Validate format: `[a-z0-9.-]+`

**File Paths:**
- Expand ~ to home directory
- Resolve symlinks
- Validate directory exists (for storage locations)

## Configuration Migration

### Version Compatibility

**Current Version:** 1.0

**Future Versions:** 1.1, 2.0, etc.

**Migration Strategy:**
1. Read config file
2. Check version field
3. If older version: Apply migration transformations
4. Write updated config with new version

### Migration Example (1.0 → 1.1)

```swift
func migrateConfig(from oldVersion: String, to newVersion: String, config: inout Config) {
    switch (oldVersion, newVersion) {
    case ("1.0", "1.1"):
        // Example: Add new field with default value
        // (In practice, Codable handles this via default values)
        print("[Config] Migrating from 1.0 to 1.1")
        config.version = "1.1"

    default:
        print("[Config] No migration needed")
    }
}
```

## Environment Variables

### Runtime Overrides

**`PLAYBACK_CONFIG`** (optional)
- Override config file path
- Used by LaunchAgents to specify config location
- Example: `PLAYBACK_CONFIG=$HOME/Library/Application Support/Playback/config.json`

**`PLAYBACK_DATA_DIR`** (optional)
- Override data directory (temp/, chunks/, meta.sqlite3)
- Default: `~/Library/Application Support/Playback/data/`
- Example: `PLAYBACK_DATA_DIR=/Volumes/External/Playback/`

### Usage in LaunchAgent

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PLAYBACK_CONFIG</key>
    <string>$HOME/Library/Application Support/Playback/config.json</string>
    <key>PLAYBACK_DATA_DIR</key>
    <string>$HOME/Library/Application Support/Playback/data</string>
</dict>
```

## Configuration Backup

### Automatic Backups

**Trigger:** Before saving changes

**Location:** `~/Library/Application Support/Playback/config.json.backup`

**Retention:** Keep last 5 backups

**Naming:**
- `config.json.backup.1` (most recent)
- `config.json.backup.2`
- ...
- `config.json.backup.5` (oldest)

**Implementation:**
```swift
func rotateBackups() {
    let baseURL = configFileURL()
    let backupURLs = (1...5).map { baseURL.appendingPathExtension("backup.\($0)") }

    // Rotate existing backups (5 → delete, 4 → 5, 3 → 4, ...)
    for i in stride(from: 4, through: 1, by: -1) {
        let src = backupURLs[i-1]
        let dst = backupURLs[i]
        try? FileManager.default.removeItem(at: dst)
        try? FileManager.default.moveItem(at: src, to: dst)
    }

    // Copy current config to backup.1
    try? FileManager.default.copyItem(at: baseURL, to: backupURLs[0])
}
```

### Manual Export/Import

**Export:**
- Settings window → Advanced → "Export Settings"
- Saves config.json to user-chosen location
- Includes version and timestamp in filename

**Import:**
- Settings window → Advanced → "Import Settings"
- Loads config from user-chosen file
- Validates and merges with current config
- Confirmation dialog showing changes

## Security Considerations

### Sensitive Data

**Excluded Apps List:**
- May reveal user's security/privacy concerns
- File permissions: 0644 (user-readable only)
- No encryption (not highly sensitive)

**No Passwords/Tokens:**
- Config file does not store credentials
- No API keys or authentication tokens

### File Permissions

**Config File:** `0644` (user read/write, others read)
- Prevents other users from modifying settings
- Allows system services to read settings

**Config Directory:** `0755` (standard Application Support permissions)

## Testing

### Unit Tests

- Config loading with missing file
- Config loading with malformed JSON
- Config validation (invalid values)
- Config migration (version upgrade)
- Field clamping (out-of-range values)

### Integration Tests

- Settings change → LaunchAgent update
- Settings change → Service picks up new value
- Config file corruption → Fallback to defaults
- Concurrent writes (race conditions)

## Future Enhancements

### Potential Features

1. **Per-Display Settings** - Different recording intervals per monitor
2. **Time-Based Profiles** - Different settings for work hours vs. personal time
3. **App-Specific Settings** - Custom recording intervals per app
4. **Cloud Sync** - Sync settings across devices (iCloud)
5. **Configuration Presets** - Quick switch between preset configurations
6. **CLI Configuration Tool** - Manage settings from terminal

### Advanced Validation

1. **Schema Validation** - JSON Schema for strict validation
2. **Type Safety** - Ensure types are correct at runtime
3. **Dependency Validation** - Check for conflicting settings
4. **Resource Checks** - Validate FFmpeg available, disk space sufficient
