# Configuration System Implementation Plan

**Component:** Configuration System
**Last Updated:** 2026-02-07

## Overview

This document provides a complete, self-contained specification for implementing the Playback configuration system. It covers JSON schema, hot-reloading, validation, migration, and environment variables.

## Configuration System Details

### Complete JSON Schema

The configuration file (`config.json`) uses the following structure:

```json
{
  "version": "1.0.0",
  "processing_interval_minutes": 5,
  "temp_retention_policy": "1_week",
  "recording_retention_policy": "never",
  "exclusion_mode": "skip",
  "excluded_apps": [],
  "ffmpeg_crf": 28,
  "video_fps": 30,
  "timeline_shortcut": "Option+Shift+Space",
  "notifications": {
    "processing_complete": true,
    "processing_errors": true,
    "disk_space_warnings": true,
    "recording_status": false
  }
}
```

#### Field Definitions and Defaults

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `version` | String | `"1.0.0"` | Configuration schema version for migration |
| `processing_interval_minutes` | Integer | `5` | How often to process recordings (1, 5, 10, 15, 30, or 60) |
| `temp_retention_policy` | String | `"1_week"` | When to delete temp recordings ("never", "1_day", "1_week", "1_month") |
| `recording_retention_policy` | String | `"never"` | When to delete processed recordings ("never", "1_day", "1_week", "1_month") |
| `exclusion_mode` | String | `"skip"` | How to handle excluded apps ("invisible" or "skip") |
| `excluded_apps` | Array[String] | `[]` | Bundle IDs of apps to exclude from recording |
| `ffmpeg_crf` | Integer | `28` | FFmpeg quality setting (0-51, lower is better quality) |
| `video_fps` | Integer | `30` | Recording frame rate |
| `timeline_shortcut` | String | `"Option+Shift+Space"` | Keyboard shortcut to open timeline |
| `notifications.processing_complete` | Boolean | `true` | Show notification when processing completes |
| `notifications.processing_errors` | Boolean | `true` | Show notification on processing errors |
| `notifications.disk_space_warnings` | Boolean | `true` | Show notification for low disk space |
| `notifications.recording_status` | Boolean | `false` | Show recording start/stop notifications |

#### Validation Rules for Each Field

**version**
- Type: String in semantic versioning format (e.g., "1.0.0")
- Default: "1.0.0"
- Invalid: Use "1.0.0" and log warning

**processing_interval_minutes**
- Valid values: [1, 5, 10, 15, 30, 60]
- Default on invalid: 5
- Validation: `if value not in [1, 5, 10, 15, 30, 60] then value = 5`

**temp_retention_policy**
- Valid values: ["never", "1_day", "1_week", "1_month"]
- Default on invalid: "1_week"
- Validation: `if value not in valid_values then value = "1_week"`

**recording_retention_policy**
- Valid values: ["never", "1_day", "1_week", "1_month"]
- Default on invalid: "never"
- Validation: `if value not in valid_values then value = "never"`

**exclusion_mode**
- Valid values: ["invisible", "skip"]
- Default on invalid: "skip"
- Validation: `if value not in ["invisible", "skip"] then value = "skip"`

**excluded_apps**
- Type: Array of strings (bundle IDs)
- Format: Each entry must match regex `^[a-z0-9.-]+$`
- Sanitization: Strip whitespace, filter invalid entries
- Default: Empty array `[]`
- Example valid entry: "com.apple.Safari"

**ffmpeg_crf**
- Type: Integer
- Valid range: [0, 51]
- Default on invalid: 28
- Validation: `if value < 0 or value > 51 then value = 28`

**video_fps**
- Type: Integer
- Valid range: > 0
- Default on invalid: 30
- Validation: `if value <= 0 then value = 30`

**timeline_shortcut**
- Type: String
- Format: "[Modifiers+]Key" (e.g., "Option+Shift+Space", "Command+K")
- Valid modifiers: Command, Option, Shift, Control
- Default on invalid: "Option+Shift+Space"
- Validation: Parse shortcut, verify valid key and modifiers

**notifications (all fields)**
- Type: Boolean
- Defaults: See table above
- Validation: `if not boolean then value = default`

### Hot-Reloading Implementation

The configuration system supports hot-reloading using file system watching to detect external changes.

#### FileSystemWatcher Implementation (Swift)

```swift
import Foundation

class ConfigWatcher {
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private let configPath: String
    private let onChange: () -> Void

    init(configPath: String, onChange: @escaping () -> Void) {
        self.configPath = configPath
        self.onChange = onChange
    }

    func startWatching() {
        // Open file descriptor
        fileDescriptor = open(configPath, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("Failed to open config file for watching: \(configPath)")
            return
        }

        // Create dispatch source for file system events
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .delete, .rename],
            queue: DispatchQueue.main
        )

        source?.setEventHandler { [weak self] in
            self?.onChange()
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source?.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
        if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    deinit {
        stopWatching()
    }
}
```

#### Configuration Reload Strategy

**Menu Bar App (Swift)**
- Uses `ConfigWatcher` to monitor config file
- Reloads immediately on file change (< 1 second)
- Updates UI reactively via SwiftUI @Published properties
- Propagates changes to recording service via LaunchAgent environment update

**Recording Service (Python)**
- Checks config file at start of each iteration (every 2 seconds)
- Compares file modification time with last loaded time
- Reloads if file changed
- No file watching needed (polling is sufficient at 2-second interval)

**Processing Service (Python)**
- Reloads config at start of each processing run
- Doesn't need hot-reload during processing (short-lived execution)
- Inherits environment variables from LaunchAgent

#### Configuration Change Propagation

```
User edits config.json
         ↓
FileSystemWatcher detects change (Swift)
         ↓
ConfigManager.reload() called
         ↓
SwiftUI views update (via @Published)
         ↓
LaunchAgent environment updated (if needed)
         ↓
Services pick up changes on next iteration
```

### Migration Strategy Between Versions

The configuration system uses semantic versioning to handle schema changes across app versions.

#### Version Checking

On config load:
1. Read `version` field from config.json
2. Compare with current app version's expected config version
3. If versions match, load normally
4. If config is older, apply migrations
5. If config is newer, log warning and attempt to load (forward compatibility)

#### Migration Framework

```swift
func migrateConfig(from oldVersion: String, to newVersion: String, config: [String: Any]) -> [String: Any] {
    var migratedConfig = config

    // Apply migrations in sequence
    switch (oldVersion, newVersion) {
    case ("1.0.0", "1.1.0"):
        // Example: Add new field with default
        if migratedConfig["new_field"] == nil {
            migratedConfig["new_field"] = defaultValue
        }
        migratedConfig["version"] = "1.1.0"

    case ("1.1.0", "2.0.0"):
        // Example: Rename field
        if let oldValue = migratedConfig["old_field_name"] {
            migratedConfig["new_field_name"] = oldValue
            migratedConfig.removeValue(forKey: "old_field_name")
        }
        migratedConfig["version"] = "2.0.0"

    default:
        print("No migration path from \(oldVersion) to \(newVersion)")
    }

    return migratedConfig
}
```

#### Migration Examples

**Adding a New Field (1.0.0 → 1.1.0)**
```swift
// Before: config.json doesn't have "auto_cleanup_enabled"
// After: Add field with default value
migratedConfig["auto_cleanup_enabled"] = true
```

**Renaming a Field (1.1.0 → 1.2.0)**
```swift
// Before: "processing_interval" (seconds)
// After: "processing_interval_minutes" (minutes)
if let seconds = migratedConfig["processing_interval"] as? Int {
    migratedConfig["processing_interval_minutes"] = seconds / 60
    migratedConfig.removeValue(forKey: "processing_interval")
}
```

**Changing Valid Values (1.2.0 → 1.3.0)**
```swift
// Before: retention_policy = "short", "medium", "long"
// After: retention_policy = "1_day", "1_week", "1_month"
if let oldPolicy = migratedConfig["temp_retention_policy"] as? String {
    let newPolicy = mapOldPolicyToNew(oldPolicy)
    migratedConfig["temp_retention_policy"] = newPolicy
}
```

#### Backward Compatibility

- **Missing fields**: Filled with defaults (Codable handles this automatically)
- **Extra fields**: Ignored (future-proofing for newer configs)
- **Type mismatches**: Fall back to default value and log warning
- **Version field missing**: Assume version "1.0.0" and attempt migration

### Environment Variable Handling

The configuration system supports environment variable overrides for deployment flexibility.

#### Supported Environment Variables

**PLAYBACK_CONFIG**
- Purpose: Override config file path
- Default: `~/Library/Application Support/Playback/config.json` (production)
- Example: `PLAYBACK_CONFIG=/custom/path/config.json`
- Used by: Menu bar app, recording service, processing service

**PLAYBACK_DATA_DIR**
- Purpose: Override data directory path
- Default: `~/Library/Application Support/Playback/data/` (production)
- Example: `PLAYBACK_DATA_DIR=/Volumes/ExternalDrive/playback-data`
- Used by: All components that read/write recordings

**PLAYBACK_DEV_MODE**
- Purpose: Enable development mode with local paths
- Default: Not set (production mode)
- Example: `PLAYBACK_DEV_MODE=1`
- Effect: Uses project directory for config and data instead of Application Support

#### Priority Order

Configuration file location is determined by:
1. `PLAYBACK_CONFIG` environment variable (highest priority)
2. Development mode paths if `PLAYBACK_DEV_MODE=1`
3. Production paths in `~/Library/Application Support/Playback/` (default)

Data directory location is determined by:
1. `PLAYBACK_DATA_DIR` environment variable (highest priority)
2. Development mode paths if `PLAYBACK_DEV_MODE=1`
3. Production paths in `~/Library/Application Support/Playback/data/` (default)

#### Development Mode Paths

When `PLAYBACK_DEV_MODE=1`:
- Config: `<project>/dev_config.json`
- Data: `<project>/dev_data/`
- Logs: `<project>/dev_data/logs/`
- Temp: `<project>/dev_data/temp/`

#### Production Mode Paths

When `PLAYBACK_DEV_MODE` not set:
- Config: `~/Library/Application Support/Playback/config.json`
- Data: `~/Library/Application Support/Playback/data/`
- Logs: `~/Library/Application Support/Playback/data/logs/`
- Temp: `~/Library/Application Support/Playback/data/temp/`

#### Usage in LaunchAgent

Environment variables are set in LaunchAgent plist files:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PLAYBACK_CONFIG</key>
    <string>/Users/username/Library/Application Support/Playback/config.json</string>
    <key>PLAYBACK_DATA_DIR</key>
    <string>/Users/username/Library/Application Support/Playback/data</string>
</dict>
```

Note: `$HOME` must be expanded to actual home directory path in LaunchAgent plists.

## Implementation Checklist

### JSON Configuration File Structure
- [ ] Define Config struct in Swift
  - Source: `src/Playback/Playback/Config/Config.swift`
  - Codable struct with all configuration fields
  - Nested struct for NotificationPreferences
  - **Example:**
    ```swift
    struct Config: Codable {
        let version: String
        let processingIntervalMinutes: Int
        let tempRetentionPolicy: String
        let recordingRetentionPolicy: String
        let exclusionMode: String
        let excludedApps: [String]
        let ffmpegCrf: Int
        let videoFps: Int
        let timelineShortcut: String
        let notifications: NotificationPreferences

        struct NotificationPreferences: Codable {
            let processingComplete: Bool
            let processingErrors: Bool
            let diskSpaceWarnings: Bool
            let recordingStatus: Bool
        }

        static let `default` = Config(
            version: "1.0.0",
            processingIntervalMinutes: 5,
            tempRetentionPolicy: "1_week",
            recordingRetentionPolicy: "never",
            exclusionMode: "skip",
            excludedApps: [],
            ffmpegCrf: 28,
            videoFps: 30,
            timelineShortcut: "Option+Shift+Space",
            notifications: NotificationPreferences(
                processingComplete: true,
                processingErrors: true,
                diskSpaceWarnings: true,
                recordingStatus: false
            )
        )
    }
    ```

- [ ] Define Python config schema
  - Source: `src/scripts/config.py` or embedded in services
  - DEFAULT_CONFIG dictionary with all fields
  - Type hints for configuration values
  - **Example:**
    ```python
    from typing import TypedDict, List

    class NotificationPreferences(TypedDict):
        processing_complete: bool
        processing_errors: bool
        disk_space_warnings: bool
        recording_status: bool

    class Config(TypedDict):
        version: str
        processing_interval_minutes: int
        temp_retention_policy: str
        recording_retention_policy: str
        exclusion_mode: str
        excluded_apps: List[str]
        ffmpeg_crf: int
        video_fps: int
        timeline_shortcut: str
        notifications: NotificationPreferences

    DEFAULT_CONFIG: Config = {
        "version": "1.0.0",
        "processing_interval_minutes": 5,
        "temp_retention_policy": "1_week",
        "recording_retention_policy": "never",
        "exclusion_mode": "skip",
        "excluded_apps": [],
        "ffmpeg_crf": 28,
        "video_fps": 30,
        "timeline_shortcut": "Option+Shift+Space",
        "notifications": {
            "processing_complete": True,
            "processing_errors": True,
            "disk_space_warnings": True,
            "recording_status": False
        }
    }
    ```

- [ ] Implement JSON schema validation (optional)
  - Source: `src/Playback/Playback/Config/ConfigSchema.swift`
  - Validates structure before loading
  - Provides helpful error messages for invalid configs

### Default Configuration
- [ ] Create default configuration constant
  - Source: `src/Playback/Playback/Config/Config.swift`
  - Static property: `Config.default`
  - All fields initialized with defaults from schema
  - **Example:** See Config struct above with `static let default`

- [ ] Implement first-launch initialization
  - Source: `src/Playback/Playback/Config/ConfigManager.swift`
  - Create config.json if it doesn't exist
  - Create parent directory if needed
  - Set file permissions to 0644
  - Log creation event
  - **Example:**
    ```swift
    func initializeConfig() {
        let configPath = getConfigPath()
        let configURL = URL(fileURLWithPath: configPath)

        if !FileManager.default.fileExists(atPath: configPath) {
            // Create parent directory
            let parentDir = configURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o755]
            )

            // Write default config
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(Config.default)
            try data.write(to: configURL)

            // Set permissions
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: configPath
            )

            print("Created default config at \(configPath)")
        }
    }
    ```

### Environment-Specific Configurations
- [ ] Implement development mode detection
  - Check for `PLAYBACK_DEV_MODE=1` environment variable
  - Source: `src/Playback/Playback/Config/ConfigManager.swift`
  - **Example:**
    ```swift
    func isDevelopmentMode() -> Bool {
        return ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"] == "1"
    }
    ```

- [ ] Set up development paths
  - Development config: `<project>/dev_config.json`
  - Development data: `<project>/dev_data/`
  - Use when `PLAYBACK_DEV_MODE=1` is set
  - **Example:**
    ```swift
    func getDevConfigPath() -> String {
        let projectDir = FileManager.default.currentDirectoryPath
        return "\(projectDir)/dev_config.json"
    }
    ```

- [ ] Set up production paths
  - Production config: `~/Library/Application Support/Playback/config.json`
  - Production data: `~/Library/Application Support/Playback/data/`
  - Default when dev mode not enabled
  - **Example:**
    ```swift
    func getProdConfigPath() -> String {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let playbackDir = appSupport.appendingPathComponent("Playback")
        return playbackDir.appendingPathComponent("config.json").path
    }
    ```

- [ ] Implement environment variable overrides
  - `PLAYBACK_CONFIG`: Override config file path
  - `PLAYBACK_DATA_DIR`: Override data directory path
  - Priority: Environment variables > Dev mode > Production defaults
  - **Example:**
    ```swift
    func getConfigPath() -> String {
        // Priority 1: Environment variable
        if let customPath = ProcessInfo.processInfo.environment["PLAYBACK_CONFIG"] {
            return customPath
        }

        // Priority 2: Development mode
        if isDevelopmentMode() {
            return getDevConfigPath()
        }

        // Priority 3: Production default
        return getProdConfigPath()
    }
    ```

### Configuration Loading
- [ ] Implement loadConfig() function
  - Source: `src/Playback/Playback/Config/ConfigManager.swift`
  - Handle missing file → create with defaults
  - Handle malformed JSON → backup and use defaults
  - Handle partial config → merge with defaults
  - **Example:**
    ```swift
    func loadConfig() -> Config {
        let configPath = getConfigPath()

        // Missing file: create with defaults
        if !FileManager.default.fileExists(atPath: configPath) {
            initializeConfig()
            return Config.default
        }

        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var config = try decoder.decode(Config.self, from: data)

            // Validate and clamp values
            config = validateConfig(config)

            return config
        } catch {
            // Malformed JSON: backup and use defaults
            print("Failed to load config: \(error)")
            backupCorruptConfig(configPath)
            return Config.default
        }
    }

    func backupCorruptConfig(_ path: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let backupPath = "\(path).backup.\(timestamp)"
        try? FileManager.default.copyItem(atPath: path, toPath: backupPath)
        print("Backed up corrupt config to \(backupPath)")
    }
    ```

- [ ] Implement Python load_config() function
  - Source: `src/scripts/config.py`
  - Same logic as Swift implementation
  - Used by recording and processing services
  - **Example:**
    ```python
    import json
    import os
    from pathlib import Path
    from typing import Any

    def load_config() -> Config:
        config_path = get_config_path()

        # Missing file: create with defaults
        if not os.path.exists(config_path):
            initialize_config()
            return DEFAULT_CONFIG.copy()

        try:
            with open(config_path, 'r') as f:
                loaded = json.load(f)

            # Merge with defaults (handle partial config)
            config = DEFAULT_CONFIG.copy()
            config.update(loaded)

            # Validate and clamp values
            config = validate_config(config)

            return config
        except (json.JSONDecodeError, IOError) as e:
            # Malformed JSON: backup and use defaults
            print(f"Failed to load config: {e}")
            backup_corrupt_config(config_path)
            return DEFAULT_CONFIG.copy()
    ```

- [ ] Handle corrupt configuration files
  - Backup corrupt file to `config.json.backup.<timestamp>`
  - Log error with details
  - Fall back to default configuration
  - Show notification to user (optional)

### Configuration Saving
- [ ] Implement saveConfig() function
  - Source: `src/Playback/Playback/Config/ConfigManager.swift`
  - Atomic write using temp file + rename
  - Pretty-printed JSON with sorted keys
  - Create parent directory if needed
  - **Example:**
    ```swift
    func saveConfig(_ config: Config) throws {
        let configPath = getConfigPath()
        let configURL = URL(fileURLWithPath: configPath)

        // Rotate backups first
        rotateBackups()

        // Validate before saving
        let validatedConfig = validateConfig(config)

        // Write to temp file
        let tempPath = configPath + ".tmp"
        let tempURL = URL(fileURLWithPath: tempPath)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(validatedConfig)

        try data.write(to: tempURL)

        // Atomic rename
        try FileManager.default.moveItem(at: tempURL, to: configURL)

        // Set permissions
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: configPath
        )

        print("Saved config to \(configPath)")
    }
    ```

- [ ] Implement Python save_config() function
  - Source: `src/scripts/config.py`
  - Same atomic write pattern as Swift
  - Used when processing service updates config
  - **Example:**
    ```python
    def save_config(config: Config) -> None:
        config_path = get_config_path()

        # Rotate backups first
        rotate_backups()

        # Validate before saving
        validated = validate_config(config)

        # Write to temp file
        temp_path = config_path + ".tmp"
        with open(temp_path, 'w') as f:
            json.dump(validated, f, indent=2, sort_keys=True)

        # Atomic rename
        os.rename(temp_path, config_path)

        # Set permissions
        os.chmod(config_path, 0o644)

        print(f"Saved config to {config_path}")
    ```

- [ ] Add pre-save validation
  - Validate all fields before writing
  - Clamp values to valid ranges
  - Log validation errors/warnings

- [ ] Rotate backups before saving
  - Keep last 5 config backups
  - Naming: `config.json.backup.1` through `config.json.backup.5`
  - Rotate before each save: 5→delete, 4→5, 3→4, 2→3, 1→2, current→1
  - **Example:**
    ```swift
    func rotateBackups() {
        let configPath = getConfigPath()

        // Delete oldest backup (5)
        let backup5 = "\(configPath).backup.5"
        try? FileManager.default.removeItem(atPath: backup5)

        // Rotate existing backups
        for i in (1...4).reversed() {
            let oldBackup = "\(configPath).backup.\(i)"
            let newBackup = "\(configPath).backup.\(i + 1)"
            if FileManager.default.fileExists(atPath: oldBackup) {
                try? FileManager.default.moveItem(atPath: oldBackup, toPath: newBackup)
            }
        }

        // Backup current config to .backup.1
        let backup1 = "\(configPath).backup.1"
        try? FileManager.default.copyItem(atPath: configPath, toPath: backup1)
    }
    ```

### Configuration Validation
- [ ] Implement validateConfig() function
  - Source: `src/Playback/Playback/Config/ConfigManager.swift`
  - Validate each field according to rules
  - Clamp invalid values to defaults
  - Return validated config
  - **Example:**
    ```swift
    func validateConfig(_ config: Config) -> Config {
        var validated = config

        // Validate processing_interval_minutes
        let validIntervals = [1, 5, 10, 15, 30, 60]
        if !validIntervals.contains(validated.processingIntervalMinutes) {
            print("Invalid processing_interval_minutes: \(validated.processingIntervalMinutes), using default: 5")
            validated.processingIntervalMinutes = 5
        }

        // Validate retention policies
        let validPolicies = ["never", "1_day", "1_week", "1_month"]
        if !validPolicies.contains(validated.tempRetentionPolicy) {
            print("Invalid temp_retention_policy: \(validated.tempRetentionPolicy), using default: 1_week")
            validated.tempRetentionPolicy = "1_week"
        }
        if !validPolicies.contains(validated.recordingRetentionPolicy) {
            print("Invalid recording_retention_policy: \(validated.recordingRetentionPolicy), using default: never")
            validated.recordingRetentionPolicy = "never"
        }

        // Validate exclusion_mode
        if !["invisible", "skip"].contains(validated.exclusionMode) {
            print("Invalid exclusion_mode: \(validated.exclusionMode), using default: skip")
            validated.exclusionMode = "skip"
        }

        // Validate excluded_apps
        validated.excludedApps = validated.excludedApps
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil }

        // Validate ffmpeg_crf
        if validated.ffmpegCrf < 0 || validated.ffmpegCrf > 51 {
            print("Invalid ffmpeg_crf: \(validated.ffmpegCrf), using default: 28")
            validated.ffmpegCrf = 28
        }

        // Validate video_fps
        if validated.videoFps <= 0 {
            print("Invalid video_fps: \(validated.videoFps), using default: 30")
            validated.videoFps = 30
        }

        // Validate timeline_shortcut
        if !isValidShortcut(validated.timelineShortcut) {
            print("Invalid timeline_shortcut: \(validated.timelineShortcut), using default: Option+Shift+Space")
            validated.timelineShortcut = "Option+Shift+Space"
        }

        return validated
    }
    ```

- [ ] Validate processing_interval_minutes
  - Must be in: [1, 5, 10, 15, 30, 60]
  - Default on invalid: 5

- [ ] Validate retention policies
  - temp_retention_policy: ["never", "1_day", "1_week", "1_month"]
  - recording_retention_policy: ["never", "1_day", "1_week", "1_month"]
  - Defaults: "1_week" for temp, "never" for recording

- [ ] Validate exclusion_mode
  - Must be in: ["invisible", "skip"]
  - Default on invalid: "skip"

- [ ] Validate excluded_apps array
  - Must be array of strings
  - Validate bundle ID format: `[a-z0-9.-]+`
  - Strip whitespace from each entry
  - Filter out invalid entries

- [ ] Validate ffmpeg_crf
  - Must be integer in range [0, 51]
  - Default on invalid: 28

- [ ] Validate video_fps
  - Must be positive integer
  - Default on invalid: 30

- [ ] Validate timeline_shortcut
  - Must be valid keyboard shortcut format
  - Format: "[Modifiers+]Key"
  - Default on invalid: "Option+Shift+Space"

### Hot-Reloading/File Watching
- [ ] Implement ConfigWatcher class
  - Source: `src/Playback/Playback/Config/ConfigWatcher.swift`
  - Use DispatchSourceFileSystemObject for file monitoring
  - Watch for write events on config.json
  - **Example:** See "Hot-Reloading Implementation" section above

- [ ] Add file watching to menu bar app
  - Reload config immediately on file change
  - Update UI to reflect new settings
  - Propagate to other components
  - **Example:**
    ```swift
    class ConfigManager: ObservableObject {
        @Published var config: Config
        private var watcher: ConfigWatcher?

        init() {
            self.config = loadConfig()

            let configPath = getConfigPath()
            self.watcher = ConfigWatcher(configPath: configPath) { [weak self] in
                self?.reloadConfig()
            }
            self.watcher?.startWatching()
        }

        func reloadConfig() {
            self.config = loadConfig()
            print("Config reloaded from file")
        }
    }
    ```

- [ ] Add periodic config checks to services
  - Recording service: Check every iteration (2 seconds)
  - Processing service: Check at start of each run
  - Avoids need for IPC or file watching in Python
  - **Example:**
    ```python
    class RecordingService:
        def __init__(self):
            self.config = load_config()
            self.config_mtime = os.path.getmtime(get_config_path())

        def run(self):
            while True:
                # Check if config changed
                current_mtime = os.path.getmtime(get_config_path())
                if current_mtime > self.config_mtime:
                    self.config = load_config()
                    self.config_mtime = current_mtime
                    print("Config reloaded")

                # Do recording work
                self.capture_frame()
                time.sleep(2)
    ```

### Configuration Migration
- [ ] Implement version checking
  - Source: `src/Playback/Playback/Config/ConfigMigration.swift`
  - Read version field from loaded config
  - Compare against current app version
  - Apply migrations if needed

- [ ] Create migration framework
  - Function: `migrateConfig(from:to:config:)`
  - Switch statement for version pairs
  - Log migration events
  - Update version field after migration
  - **Example:** See "Migration Strategy Between Versions" section above

- [ ] Handle backward compatibility
  - Old configs should work with new app versions
  - Missing fields filled with defaults (Codable handles this)
  - Extra fields ignored (future-proofing)

- [ ] Test migration paths
  - Unit test for each version upgrade path
  - Verify all fields migrated correctly
  - Verify version field updated

### Environment Variables
- [ ] Implement PLAYBACK_CONFIG override
  - Read from environment in ConfigManager
  - Override default config file path
  - Used by LaunchAgents to specify config location
  - **Example:** See "Environment Variable Handling" section above

- [ ] Implement PLAYBACK_DATA_DIR override
  - Read from environment in ConfigManager
  - Override data directory path
  - Pass to recording and processing services

- [ ] Add environment variables to LaunchAgent plists
  - Source: `src/Playback/Playback/Services/LaunchAgentManager.swift`
  - Set in <EnvironmentVariables> section
  - Expand $HOME to actual home directory
  - **Example:** See "Usage in LaunchAgent" section above

### Backup System
- [ ] Implement automatic backup rotation
  - Function: `rotateBackups()`
  - Called before each saveConfig()
  - Keep last 5 backups with numbered suffixes
  - **Example:** See saveConfig() section above

- [ ] Implement manual export
  - Source: `src/Playback/Playback/Settings/AdvancedSettingsView.swift`
  - "Export Settings" button in Advanced tab
  - Save dialog with suggested filename including timestamp
  - Copy current config.json to user-chosen location
  - **Example:**
    ```swift
    func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "playback-config-\(timestamp).json"
        panel.allowedContentTypes = [.json]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                let configPath = getConfigPath()
                try? FileManager.default.copyItem(
                    atPath: configPath,
                    toPath: url.path
                )
            }
        }
    }
    ```

- [ ] Implement manual import
  - Source: `src/Playback/Playback/Settings/AdvancedSettingsView.swift`
  - "Import Settings" button in Advanced tab
  - File picker for config.json file
  - Validate imported config
  - Show confirmation dialog with diff of changes
  - Merge with current config (don't overwrite all fields)
  - **Example:**
    ```swift
    func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let data = try Data(contentsOf: url)
                    let imported = try JSONDecoder().decode(Config.self, from: data)
                    let validated = validateConfig(imported)

                    // Show diff and confirm
                    if showImportConfirmation(current: config, imported: validated) {
                        try saveConfig(validated)
                        reloadConfig()
                    }
                } catch {
                    showError("Failed to import settings: \(error)")
                }
            }
        }
    }
    ```

- [ ] Add restore from backup feature
  - Source: `src/Playback/Playback/Settings/AdvancedSettingsView.swift`
  - List available backups with timestamps
  - Preview backup contents
  - Restore button copies backup to config.json
  - Reload config after restore

### File Permissions and Security
- [ ] Set config file permissions
  - Set to 0644 on creation (user read/write, others read)
  - Verify permissions after saving
  - Log warning if permissions incorrect

- [ ] Set config directory permissions
  - Set to 0755 on creation (standard Application Support)
  - Ensure parent directories created with correct permissions

- [ ] Sanitize sensitive data
  - No passwords or tokens in config (verify this)
  - Excluded apps list is privacy-sensitive but not encrypted
  - Log sanitized config (redact sensitive fields if any added)

### Force Run Services Feature
- [ ] Implement "Force Run Services" button in Advanced settings
  - Source: `src/Playback/Playback/Settings/SettingsView.swift`
  - Location: Advanced Settings Tab → Maintenance Section
  - Button triggers manual execution of recording and processing services
  - Shows progress indicator while running
  - **Example:**
    ```swift
    Button(action: {
        Task {
            await forceRunServices()
        }
    }) {
        HStack {
            if isForceRunning {
                ProgressView()
                    .controlSize(.small)
                Text("Running Services...")
            } else {
                Text("Force Run Services")
            }
        }
    }
    .disabled(isForceRunning)
    ```

- [ ] Implement error handling with alert dialog
  - Display alert if any service fails
  - Show detailed error message with exit codes
  - Include both recording and processing service errors
  - Alert title: "Service Execution Error"
  - Alert provides two actions: "Export Error" and "OK"
  - **Example:**
    ```swift
    .alert("Service Execution Error", isPresented: $showForceRunError) {
        Button("Export Error") {
            exportForceRunError()
        }
        Button("OK") { }
    } message: {
        Text(forceRunError ?? "An unknown error occurred")
    }
    ```

- [ ] Implement error export functionality
  - Export button in error alert saves error details to file
  - Suggested filename format: `playback-service-error-YYYYMMDD-HHMMSS.txt`
  - File type: Plain text (.txt)
  - Export includes comprehensive diagnostic information:
    - Error timestamp
    - macOS version
    - Python version
    - FFmpeg version
    - Full error messages from services
    - Service status (recording and processing)
  - Opens Finder to show exported file after save
  - **Example error report format:**
    ```
    Playback Service Error Report
    Generated: 2026-02-09 14:23:45
    macOS Version: 26.0
    Python Version: Python 3.12.1
    FFmpeg Version: ffmpeg version 7.0.1

    --- Error Details ---

    Recording service failed (exit code 1):
    Traceback (most recent call last):
      ...error details...

    Processing service failed (exit code 2):
    ...error details...

    --- Service Status ---
    Recording Service: Running (PID: 12345)
    Processing Service: Not Running
    ```

- [ ] Service execution implementation
  - Function: `forceRunServices() async`
  - Runs recording service: `python3 record_screen.py`
  - Runs processing service: `python3 build_chunks_from_temp.py --auto`
  - Uses `ShellCommand.runAsync()` for non-blocking execution
  - Handles both development and production script paths
  - Collects errors from both services
  - Shows combined error message if either fails
  - **Script path resolution:**
    - Development: `<project>/src/scripts/`
    - Production: `<bundle>/Resources/`

### Configuration Access API
- [ ] Create ConfigManager singleton
  - Source: `src/Playback/Playback/Config/ConfigManager.swift`
  - Shared instance: `ConfigManager.shared`
  - Thread-safe access to config
  - Observable for SwiftUI views
  - **Example:**
    ```swift
    class ConfigManager: ObservableObject {
        static let shared = ConfigManager()

        @Published var config: Config
        private let queue = DispatchQueue(label: "com.playback.config")

        private init() {
            self.config = loadConfig()
        }

        func update(_ newConfig: Config) {
            queue.async {
                do {
                    try self.saveConfig(newConfig)
                    DispatchQueue.main.async {
                        self.config = newConfig
                    }
                } catch {
                    print("Failed to save config: \(error)")
                }
            }
        }
    }
    ```

- [ ] Implement config field accessors
  - Methods: `get(key:)`, `set(key:value:)`
  - Type-safe accessors for each field
  - Validation on set operations
  - Auto-save after set operations

- [ ] Add SwiftUI integration
  - Conform to ObservableObject
  - @Published properties for reactive updates
  - Use with @EnvironmentObject in views
  - **Example:**
    ```swift
    struct SettingsView: View {
        @EnvironmentObject var configManager: ConfigManager

        var body: some View {
            Form {
                Picker("Processing Interval", selection: $configManager.config.processingIntervalMinutes) {
                    ForEach([1, 5, 10, 15, 30, 60], id: \.self) { interval in
                        Text("\(interval) minutes").tag(interval)
                    }
                }
            }
        }
    }
    ```

## Testing Checklist

### Unit Tests - Configuration Loading
- [ ] Test loading with missing config file
  - Should create file with defaults
  - Should return default configuration
  - File should have correct permissions (0644)

- [ ] Test loading with malformed JSON
  - Should backup corrupt file
  - Should return default configuration
  - Backup filename should include timestamp
  - Should log error message

- [ ] Test loading with partial configuration
  - Missing fields should use defaults
  - Present fields should be preserved
  - Merged config should validate correctly

- [ ] Test loading with extra fields
  - Should ignore unknown fields (forward compatibility)
  - Should preserve known fields
  - Should not error

### Unit Tests - Configuration Validation
- [ ] Test processing_interval_minutes validation
  - Valid values [1, 5, 10, 15, 30, 60] should pass
  - Invalid values should clamp to 5
  - Test boundary values (0, 61, negative)

- [ ] Test retention policy validation
  - Valid policies ["never", "1_day", "1_week", "1_month"] should pass
  - Invalid policies should reset to defaults
  - Test empty string, null, numeric values

- [ ] Test exclusion_mode validation
  - Valid modes ["invisible", "skip"] should pass
  - Invalid modes should reset to "skip"

- [ ] Test excluded_apps validation
  - Valid bundle IDs should pass
  - Invalid formats should be filtered out
  - Whitespace should be stripped
  - Empty array should be valid

- [ ] Test ffmpeg_crf validation
  - Range [0, 51] should pass
  - Out-of-range values should clamp to 28
  - Non-integer values should error/default

- [ ] Test video_fps validation
  - Positive integers should pass
  - Zero and negative should reset to 30

- [ ] Test timeline_shortcut validation
  - Valid keyboard shortcuts should pass
  - Invalid formats should reset to default
  - Test various modifier combinations

### Unit Tests - Configuration Saving
- [ ] Test atomic save operation
  - Should write to temp file first
  - Should rename temp file to target
  - Should not corrupt config if interrupted
  - Should create parent directory if needed

- [ ] Test JSON formatting
  - Output should be pretty-printed
  - Keys should be sorted
  - Should be valid JSON

- [ ] Test backup rotation
  - Should keep last 5 backups
  - Should rotate existing backups correctly
  - Should not fail if no backups exist
  - Oldest backup (5) should be deleted

### Unit Tests - Configuration Migration
- [ ] Test version detection
  - Should correctly read version field
  - Should handle missing version field
  - Should handle invalid version format

- [ ] Test migration execution
  - Should apply correct migration for version pair
  - Should update version field after migration
  - Should preserve unmigrated fields
  - Should log migration events

- [ ] Test no-op migration
  - Current version config should not migrate
  - Should return config unchanged
  - Should not update version field

### Unit Tests - Environment Variables
- [ ] Test PLAYBACK_CONFIG override
  - Should use custom config path when set
  - Should use default when not set
  - Should handle non-existent path

- [ ] Test PLAYBACK_DATA_DIR override
  - Should use custom data directory when set
  - Should use default when not set
  - Should expand ~ to home directory

- [ ] Test development mode
  - Should use dev paths when PLAYBACK_DEV_MODE=1
  - Should use production paths when not set
  - Should log which mode is active

### Integration Tests - File Watching
- [ ] Test hot-reload in menu bar app
  - Modify config file externally
  - Verify app reloads config within 1 second
  - Verify UI updates to reflect new values

- [ ] Test hot-reload in recording service
  - Modify config file during recording
  - Verify service picks up changes within 2 seconds
  - Verify recording behavior changes accordingly

- [ ] Test hot-reload in processing service
  - Modify config file during processing
  - Verify service picks up changes on next run
  - Verify processing parameters change

### Integration Tests - Service Communication
- [ ] Test LaunchAgent environment variables
  - Verify PLAYBACK_CONFIG passed to services
  - Verify PLAYBACK_DATA_DIR passed to services
  - Verify services can read config file

- [ ] Test configuration propagation
  - Change setting in Settings window
  - Verify config.json updated
  - Verify all services see new value
  - Verify LaunchAgent reloaded if needed

### Integration Tests - Backup and Restore
- [ ] Test automatic backup creation
  - Change configuration multiple times
  - Verify backups created and rotated
  - Verify backup contents match previous config

- [ ] Test manual export
  - Export configuration from Settings
  - Verify file saved to chosen location
  - Verify exported file is valid JSON
  - Verify can re-import exported file

- [ ] Test manual import
  - Import configuration from file
  - Verify validation runs on import
  - Verify confirmation dialog shows changes
  - Verify settings updated after import
  - Verify invalid imports are rejected

### Integration Tests - Concurrent Access
- [ ] Test concurrent reads
  - Multiple services reading config simultaneously
  - Should not error or corrupt data

- [ ] Test concurrent writes
  - Settings window and service writing simultaneously
  - Should use atomic writes to prevent corruption
  - Last write should win

- [ ] Test read during write
  - Read config while save in progress
  - Should read either old or new config (not partial)
  - Should not error

### Error Handling Tests
- [ ] Test disk full during save
  - Should fail gracefully
  - Should not corrupt existing config
  - Should log error
  - Should show notification (optional)

- [ ] Test permission denied
  - Cannot read config file
  - Should fall back to defaults
  - Should log error
  - Cannot write config file
  - Should keep settings in memory
  - Should show notification

- [ ] Test config directory missing
  - Should create directory on save
  - Should create parent directories
  - Should set correct permissions

### Performance Tests
- [ ] Test config load time
  - Should load in < 10ms
  - Test with large excluded_apps list (100+ entries)

- [ ] Test config save time
  - Should save in < 50ms
  - Should not block UI thread

- [ ] Test file watching overhead
  - Monitor CPU usage with file watcher active
  - Should be < 0.1% CPU when idle
  - Should respond within 1 second of file change

### Security Tests
- [ ] Verify file permissions
  - Config file should be 0644 after creation
  - Config file should be 0644 after save
  - Config directory should be 0755

- [ ] Verify no sensitive data in logs
  - Log output should not contain passwords/tokens
  - Excluded apps list should be redacted or anonymized in logs (optional)

- [ ] Verify config file location
  - Production config should be in Application Support
  - Dev config should be in project directory
  - Should not be in publicly accessible location

### Integration Tests - Force Run Services
- [ ] Test force run button in UI
  - Button should be enabled when services idle
  - Button should show progress indicator while running
  - Button should be disabled while services running
  - Button should be accessible via identifier

- [ ] Test successful service execution
  - Recording service executes without errors
  - Processing service executes without errors
  - No error alert shown on success
  - Services return to idle state after completion

- [ ] Test error handling for recording service failure
  - Simulate recording service failure
  - Error alert should display
  - Error message should include "Recording service failed"
  - Error message should include exit code
  - Error message should include service output

- [ ] Test error handling for processing service failure
  - Simulate processing service failure
  - Error alert should display
  - Error message should include "Processing service failed"
  - Error message should include exit code
  - Error message should include service output

- [ ] Test error handling for both services failing
  - Simulate both services failing
  - Error alert should display combined errors
  - Both error messages should be separated clearly
  - Alert should remain dismissible

- [ ] Test error export functionality
  - Click "Export Error" button in error alert
  - Save panel should appear with suggested filename
  - Filename format: `playback-service-error-YYYYMMDD-HHMMSS.txt`
  - File type filter: Plain text only
  - Can create new directories in save panel

- [ ] Test exported error file contents
  - File should contain error report header
  - File should include timestamp
  - File should include system information (macOS, Python, FFmpeg)
  - File should include full error details
  - File should include service status
  - File should be valid UTF-8 text

- [ ] Test error export success
  - File should be saved to chosen location
  - Finder should open showing exported file
  - No error dialog on successful export

- [ ] Test error export failure
  - Simulate write permission error
  - Error alert should appear
  - Alert should describe export failure
  - Original error dialog should remain accessible

- [ ] Test script path resolution
  - Development mode: Should use `<project>/src/scripts/`
  - Production mode: Should use `<bundle>/Resources/`
  - Scripts should be found in correct location
  - Missing scripts should generate clear error

- [ ] Test concurrent force run attempts
  - Start force run
  - Attempt second force run while first running
  - Second attempt should be blocked (button disabled)
  - First run should complete normally
  - Button should re-enable after completion
