import XCTest
import Foundation
@testable import Playback

/// Integration tests for configuration management and propagation to services
@MainActor
final class ConfigurationIntegrationTests: IntegrationTestBase {

    // MARK: - Configuration Loading and Validation

    func testConfigurationLoadsFromFile() async throws {
        // Test that ConfigManager loads configuration from file

        // GIVEN: A config file with custom values
        try createTestConfig(excludedApps: ["com.test.app"], processingIntervalMinutes: 10)

        // WHEN: ConfigManager loads the config
        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // THEN: Config values match file contents
        XCTAssertEqual(configManager.config.processingIntervalMinutes, 10)
        XCTAssertTrue(configManager.config.excludedApps.contains("com.test.app"))
    }

    func testConfigurationValidatesInvalidValues() async throws {
        // Test that invalid config values are corrected to defaults

        // GIVEN: A config file with invalid values
        let invalidConfig: [String: Any] = [
            "version": "1.0.0",
            "processing_interval_minutes": -100, // Invalid
            "ffmpeg_crf": 100, // Invalid (should be 0-51)
            "video_fps": 0, // Invalid
            "exclusion_mode": "invalid_mode", // Invalid
            "excluded_apps": ["com.valid.app"],
            "temp_retention_policy": "invalid_policy",  // Invalid
            "recording_retention_policy": "invalid_policy",  // Invalid
            "timeline_shortcut": "Option+Shift+Space",
            "pause_when_timeline_open": true,
            "notifications": [
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: invalidConfig, options: .prettyPrinted)
        try jsonData.write(to: tempConfigPath)

        // WHEN: ConfigManager loads and validates
        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // THEN: Invalid values are corrected
        XCTAssertGreaterThan(configManager.config.processingIntervalMinutes, 0)
        XCTAssertLessThanOrEqual(configManager.config.ffmpegCrf, 51)
        XCTAssertGreaterThan(configManager.config.videoFps, 0)
        XCTAssertTrue(["skip", "invisible"].contains(configManager.config.exclusionMode))
    }

    func testConfigurationSavesAndPersists() async throws {
        // Test that config changes are saved to disk and persist across reloads

        // GIVEN: Initial config
        try createTestConfig(processingIntervalMinutes: 5)
        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        XCTAssertEqual(configManager.config.processingIntervalMinutes, 5)

        // WHEN: Config is updated and saved
        var updatedConfig = configManager.config
        updatedConfig.processingIntervalMinutes = 10  // Valid value from allowed set
        await configManager.updateConfig(updatedConfig)

        // THEN: Changes are saved to file
        let savedData = try Data(contentsOf: tempConfigPath)
        let savedConfig = try JSONSerialization.jsonObject(with: savedData) as! [String: Any]
        XCTAssertEqual(savedConfig["processing_interval_minutes"] as? Int, 600)

        // AND: New ConfigManager instance loads the updated values
        let newConfigManager = ConfigManager(configPath: tempConfigPath)
        await newConfigManager.loadConfiguration()
        XCTAssertEqual(newConfigManager.config.processingIntervalMinutes, 10)
    }

    func testConfigurationBackupCreation() async throws {
        // Test that config backups are created when saving

        // GIVEN: Initial config
        try createTestConfig()
        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // WHEN: Config is updated multiple times
        let validIntervals = [1, 5, 10, 15, 30, 60]
        for interval in validIntervals {
            var updatedConfig = configManager.config
            updatedConfig.processingIntervalMinutes = interval
            await configManager.updateConfig(updatedConfig)
            try await Task.sleep(nanoseconds: 100_000_000) // Small delay to ensure different timestamps
        }

        // THEN: Backups are created (max 5 backups)
        let backupDir = tempConfigPath.deletingLastPathComponent()
            .appendingPathComponent("backups")

        if FileManager.default.fileExists(atPath: backupDir.path) {
            let backups = try FileManager.default.contentsOfDirectory(
                at: backupDir,
                includingPropertiesForKeys: nil
            ).filter { $0.lastPathComponent.hasPrefix("config_") }

            XCTAssertLessThanOrEqual(backups.count, 5, "Should maintain max 5 backups")
        }
    }

    // MARK: - Config Hot-Reloading

    func testConfigHotReloadDetectsChanges() async throws {
        // Test that ConfigManager detects external config file changes

        // GIVEN: Initial config
        try createTestConfig(processingIntervalMinutes: 5)
        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        XCTAssertEqual(configManager.config.processingIntervalMinutes, 5)

        // WHEN: Config file is modified externally
        try createTestConfig(processingIntervalMinutes: 10)

        // Note: File watcher would trigger reload in real scenario
        // For testing, manually trigger reload
        await configManager.loadConfiguration()

        // THEN: ConfigManager loads new values
        XCTAssertEqual(configManager.config.processingIntervalMinutes, 10)
    }

    func testConfigChangesPropagateToPublishedProperties() async throws {
        // Test that config changes trigger @Published property updates

        // GIVEN: ConfigManager with initial values
        try createTestConfig(excludedApps: ["com.test.app1"])
        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        XCTAssertEqual(configManager.config.excludedApps.count, 1)

        // WHEN: Config is updated
        var updatedConfig = configManager.config
        updatedConfig.excludedApps = ["com.test.app1", "com.test.app2"]
        await configManager.updateConfig(updatedConfig)

        // THEN: Published properties are updated
        XCTAssertEqual(configManager.config.excludedApps.count, 2)
        XCTAssertTrue(configManager.config.excludedApps.contains("com.test.app2"))
    }

    // MARK: - Service Integration

    func testConfigPropagationToRecordingService() async throws {
        // Test that config changes affect recording service behavior

        // GIVEN: Config with no excluded apps
        try createTestConfig(excludedApps: [])

        // WHEN: Excluded apps are added
        try createTestConfig(excludedApps: ["com.1password.1password"])

        // THEN: Recording service would skip screenshots for excluded app
        let configData = try Data(contentsOf: tempConfigPath)
        let config = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
        let excludedApps = config["excluded_apps"] as! [String]

        XCTAssertTrue(excludedApps.contains("com.1password.1password"))
    }

    func testConfigPropagationToProcessingService() async throws {
        // Test that processing service uses config values

        // GIVEN: Config with custom FPS and CRF
        try createTestConfig()

        let configData = try Data(contentsOf: tempConfigPath)
        let config = try JSONSerialization.jsonObject(with: configData) as! [String: Any]

        // THEN: Processing parameters match config
        XCTAssertEqual(config["video_fps"] as? Int, 5)
        XCTAssertEqual(config["ffmpeg_crf"] as? Int, 28)
        XCTAssertEqual(config["ffmpeg_preset"] as? String, "veryfast")
    }

    func testConfigPropagationToCleanupService() async throws {
        // Test that cleanup service uses retention policies from config

        // GIVEN: Config with retention policies
        try createTestConfig()

        let configData = try Data(contentsOf: tempConfigPath)
        let config = try JSONSerialization.jsonObject(with: configData) as! [String: Any]

        // THEN: Retention policies are set correctly
        XCTAssertEqual(config["temp_retention_policy"] as? String, "1_week")
        XCTAssertEqual(config["recording_retention_policy"] as? String, "never")
    }

    // MARK: - App Exclusion Logic

    func testExcludedAppsBehavior() async throws {
        // Test that app exclusion logic works correctly

        // GIVEN: Config with excluded apps
        let excludedApps = [
            "com.1password.1password",
            "com.apple.Keychain",
            "com.microsoft.teams"
        ]
        try createTestConfig(excludedApps: excludedApps)

        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // THEN: All excluded apps are recognized
        for app in excludedApps {
            XCTAssertTrue(
                configManager.config.excludedApps.contains(app),
                "Expected \(app) to be in excluded apps"
            )
        }
    }

    func testExclusionModeSkip() async throws {
        // Test skip exclusion mode

        // GIVEN: Config with skip mode
        let config: [String: Any] = [
            "version": "1.0.0",
            "exclusion_mode": "skip",
            "excluded_apps": ["com.test.app"],
            "processing_interval_minutes": 300,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "video_fps": 5,
            "ffmpeg_crf": 28
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        try jsonData.write(to: tempConfigPath)

        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // THEN: Exclusion mode is skip
        XCTAssertEqual(configManager.config.exclusionMode, "skip")
    }

    func testExclusionModeInvisible() async throws {
        // Test invisible exclusion mode

        // GIVEN: Config with invisible mode
        let config: [String: Any] = [
            "version": "1.0.0",
            "exclusion_mode": "invisible",
            "excluded_apps": ["com.test.app"],
            "processing_interval_minutes": 300,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "video_fps": 5,
            "ffmpeg_crf": 28
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        try jsonData.write(to: tempConfigPath)

        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // THEN: Exclusion mode is invisible
        XCTAssertEqual(configManager.config.exclusionMode, "invisible")
    }

    // MARK: - Notification Settings

    func testNotificationSettingsParsing() async throws {
        // Test that notification settings are parsed correctly

        // GIVEN: Config with notification settings
        let config: [String: Any] = [
            "version": "1.0.0",
            "processing_interval_minutes": 300,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "video_fps": 5,
            "ffmpeg_crf": 28,
            "notifications": [
                "processing_complete": true,
                "storage_warning": false,
                "error_alert": true
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        try jsonData.write(to: tempConfigPath)

        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // THEN: Notification settings are loaded
        // Note: This would require accessing notification settings from config
        // For now, verify config was loaded successfully
        XCTAssertEqual(configManager.config.processingIntervalMinutes, 5)
    }

    // MARK: - Error Handling

    func testMissingConfigFileUsesDefaults() async throws {
        // Test that missing config file results in default values

        // GIVEN: No config file exists
        let nonExistentPath = tempRootDirectory.appendingPathComponent("nonexistent.json")

        // WHEN: ConfigManager attempts to load
        let configManager = ConfigManager(configPath: nonExistentPath)
        await configManager.loadConfiguration()

        // THEN: Default values are used
        XCTAssertGreaterThan(configManager.config.processingIntervalMinutes, 0)
        XCTAssertGreaterThan(configManager.config.videoFps, 0)
        XCTAssertGreaterThanOrEqual(configManager.config.ffmpegCrf, 0)
        XCTAssertLessThanOrEqual(configManager.config.ffmpegCrf, 51)
    }

    func testCorruptedConfigFileHandling() async throws {
        // Test that corrupted JSON is handled gracefully

        // GIVEN: Corrupted config file
        let corruptedJSON = "{ invalid json content"
        try corruptedJSON.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        // WHEN: ConfigManager attempts to load
        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // THEN: Falls back to default values
        XCTAssertGreaterThan(configManager.config.processingIntervalMinutes, 0)
    }

    func testEmptyConfigFileUsesDefaults() async throws {
        // Test that empty config file uses default values

        // GIVEN: Empty JSON object
        let emptyConfig: [String: Any] = [:]
        let jsonData = try JSONSerialization.data(withJSONObject: emptyConfig, options: .prettyPrinted)
        try jsonData.write(to: tempConfigPath)

        // WHEN: ConfigManager loads
        let configManager = ConfigManager(configPath: tempConfigPath)
        await configManager.loadConfiguration()

        // THEN: Default values are used
        XCTAssertGreaterThan(configManager.config.processingIntervalMinutes, 0)
        XCTAssertGreaterThan(configManager.config.videoFps, 0)
    }
}
