import XCTest
@testable import Playback

@MainActor
final class ConfigManagerTests: XCTestCase {
    var tempDirectory: URL!
    var tempConfigPath: URL!
    var configManager: ConfigManager!

    override func setUp() {
        super.setUp()

        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        tempConfigPath = tempDirectory.appendingPathComponent("config.json")

        try! FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        configManager = ConfigManager(configPath: tempConfigPath)
    }

    override func tearDown() {
        configManager = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Initialization Tests

    func testInitializationCreatesDefaultConfig() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempConfigPath.path),
                       "Config file should not exist before initialization")

        let defaultConfig = configManager.config

        XCTAssertEqual(defaultConfig.version, "1.0.0")
        XCTAssertEqual(defaultConfig.processingIntervalMinutes, 5)
        XCTAssertEqual(defaultConfig.tempRetentionPolicy, "1_week")
        XCTAssertEqual(defaultConfig.recordingRetentionPolicy, "never")
        XCTAssertEqual(defaultConfig.exclusionMode, "skip")
        XCTAssertTrue(defaultConfig.excludedApps.isEmpty)
        XCTAssertEqual(defaultConfig.ffmpegCrf, 28)
        XCTAssertEqual(defaultConfig.videoFps, 30)
    }

    func testInitializationLoadsExistingConfig() throws {
        let customConfig = """
        {
            "version": "1.0.0",
            "processing_interval_minutes": 10,
            "temp_retention_policy": "1_day",
            "recording_retention_policy": "1_week",
            "exclusion_mode": "invisible",
            "excluded_apps": ["com.1password.1password"],
            "ffmpeg_crf": 23,
            "video_fps": 60,
            "timeline_shortcut": "Command+Shift+T",
            "pause_when_timeline_open": false,
            "notifications": {
                "processing_complete": false,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": true
            }
        }
        """

        try customConfig.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)
        let config = manager.config

        XCTAssertEqual(config.version, "1.0.0")
        XCTAssertEqual(config.processingIntervalMinutes, 10)
        XCTAssertEqual(config.tempRetentionPolicy, "1_day")
        XCTAssertEqual(config.recordingRetentionPolicy, "1_week")
        XCTAssertEqual(config.exclusionMode, "invisible")
        XCTAssertEqual(config.excludedApps, ["com.1password.1password"])
        XCTAssertEqual(config.ffmpegCrf, 23)
        XCTAssertEqual(config.videoFps, 60)
        XCTAssertEqual(config.timelineShortcut, "Command+Shift+T")
        XCTAssertFalse(config.pauseWhenTimelineOpen)
    }

    // MARK: - Saving Tests

    func testSaveConfigurationWritesFile() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempConfigPath.path))

        configManager.saveConfiguration()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempConfigPath.path),
                      "Config file should exist after save")
    }

    func testSaveConfigurationWritesValidJSON() throws {
        configManager.saveConfiguration()

        let data = try Data(contentsOf: tempConfigPath)
        let decoded = try JSONDecoder().decode(Config.self, from: data)

        XCTAssertEqual(decoded.version, configManager.config.version)
        XCTAssertEqual(decoded.processingIntervalMinutes, configManager.config.processingIntervalMinutes)
    }

    func testSaveConfigurationCreatesBackup() throws {
        configManager.saveConfiguration()

        var modifiedConfig = configManager.config
        modifiedConfig.processingIntervalMinutes = 15
        configManager.updateConfig(modifiedConfig)

        configManager.saveConfiguration()

        let backupDir = tempDirectory.appendingPathComponent("backups")
        let backups = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)

        XCTAssertTrue(backups.count >= 1, "At least one backup should exist")
        XCTAssertTrue(backups.first?.lastPathComponent.hasPrefix("config_") ?? false,
                      "Backup should have timestamp prefix")
    }

    func testSaveConfigurationMaintainsMaxFiveBackups() throws {
        for i in 1...7 {
            var modifiedConfig = configManager.config
            let newInterval = (i * 5) % 60
            modifiedConfig.processingIntervalMinutes = newInterval > 0 ? newInterval : 5
            configManager.updateConfig(modifiedConfig)
            Thread.sleep(forTimeInterval: 0.1)
        }

        let backupDir = tempDirectory.appendingPathComponent("backups")
        let backups = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)

        XCTAssertEqual(backups.count, 5, "Should maintain exactly 5 backups")
    }

    // MARK: - Validation Tests

    func testValidationCorrectsInvalidProcessingInterval() throws {
        let invalidConfig = """
        {
            "version": "1.0.0",
            "processing_interval_minutes": 3,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "exclusion_mode": "skip",
            "excluded_apps": [],
            "ffmpeg_crf": 28,
            "video_fps": 30,
            "timeline_shortcut": "Option+Shift+Space",
            "pause_when_timeline_open": true,
            "notifications": {
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            }
        }
        """

        try invalidConfig.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.processingIntervalMinutes, 5,
                       "Invalid interval should be corrected to default")
    }

    func testValidationCorrectsInvalidRetentionPolicy() throws {
        let invalidConfig = """
        {
            "version": "1.0.0",
            "processing_interval_minutes": 5,
            "temp_retention_policy": "invalid_policy",
            "recording_retention_policy": "never",
            "exclusion_mode": "skip",
            "excluded_apps": [],
            "ffmpeg_crf": 28,
            "video_fps": 30,
            "timeline_shortcut": "Option+Shift+Space",
            "pause_when_timeline_open": true,
            "notifications": {
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            }
        }
        """

        try invalidConfig.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.tempRetentionPolicy, "1_week",
                       "Invalid retention policy should be corrected to default")
    }

    func testValidationCorrectsInvalidExclusionMode() throws {
        let invalidConfig = """
        {
            "version": "1.0.0",
            "processing_interval_minutes": 5,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "exclusion_mode": "invalid_mode",
            "excluded_apps": [],
            "ffmpeg_crf": 28,
            "video_fps": 30,
            "timeline_shortcut": "Option+Shift+Space",
            "pause_when_timeline_open": true,
            "notifications": {
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            }
        }
        """

        try invalidConfig.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.exclusionMode, "skip",
                       "Invalid exclusion mode should be corrected to default")
    }

    func testValidationFiltersInvalidBundleIDs() throws {
        let invalidConfig = """
        {
            "version": "1.0.0",
            "processing_interval_minutes": 5,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "exclusion_mode": "skip",
            "excluded_apps": ["com.valid.app", "Invalid Bundle ID!", "com.another.valid"],
            "ffmpeg_crf": 28,
            "video_fps": 30,
            "timeline_shortcut": "Option+Shift+Space",
            "pause_when_timeline_open": true,
            "notifications": {
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            }
        }
        """

        try invalidConfig.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.excludedApps.count, 2,
                       "Invalid bundle IDs should be filtered out")
        XCTAssertTrue(manager.config.excludedApps.contains("com.valid.app"))
        XCTAssertTrue(manager.config.excludedApps.contains("com.another.valid"))
        XCTAssertFalse(manager.config.excludedApps.contains("Invalid Bundle ID!"))
    }

    func testValidationCorrectsCRFOutOfRange() throws {
        let invalidConfig = """
        {
            "version": "1.0.0",
            "processing_interval_minutes": 5,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "exclusion_mode": "skip",
            "excluded_apps": [],
            "ffmpeg_crf": 100,
            "video_fps": 30,
            "timeline_shortcut": "Option+Shift+Space",
            "pause_when_timeline_open": true,
            "notifications": {
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            }
        }
        """

        try invalidConfig.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.ffmpegCrf, 28,
                       "CRF out of range should be corrected to default")
    }

    func testValidationCorrectsInvalidFPS() throws {
        let invalidConfig = """
        {
            "version": "1.0.0",
            "processing_interval_minutes": 5,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "exclusion_mode": "skip",
            "excluded_apps": [],
            "ffmpeg_crf": 28,
            "video_fps": 0,
            "timeline_shortcut": "Option+Shift+Space",
            "pause_when_timeline_open": true,
            "notifications": {
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            }
        }
        """

        try invalidConfig.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.videoFps, 30,
                       "Invalid FPS should be corrected to default")
    }

    // MARK: - Update Tests

    func testUpdateConfigSavesImmediately() throws {
        var newConfig = configManager.config
        newConfig.processingIntervalMinutes = 15

        configManager.updateConfig(newConfig)

        XCTAssertEqual(configManager.config.processingIntervalMinutes, 15)

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempConfigPath.path),
                      "Config should be saved after update")

        let data = try Data(contentsOf: tempConfigPath)
        let savedConfig = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(savedConfig.processingIntervalMinutes, 15)
    }

    func testUpdateConfigValidatesInput() throws {
        var invalidConfig = configManager.config
        invalidConfig.processingIntervalMinutes = 3
        invalidConfig.ffmpegCrf = 100

        configManager.updateConfig(invalidConfig)

        XCTAssertEqual(configManager.config.processingIntervalMinutes, 5,
                       "Invalid values should be corrected during update")
        XCTAssertEqual(configManager.config.ffmpegCrf, 28)
    }

    // MARK: - Migration Tests

    func testMigrationHandlesVersion1_0_0() throws {
        let v1Config = """
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
            "pause_when_timeline_open": true,
            "notifications": {
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            }
        }
        """

        try v1Config.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.version, "1.0.0",
                       "Version 1.0.0 should load without migration")
    }

    // MARK: - Error Handling Tests

    func testHandlesCorruptedJSONGracefully() throws {
        let corruptedJSON = """
        {
            "version": "1.0.0",
            "processing_interval_minutes": not_a_number
        """

        try corruptedJSON.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.version, "1.0.0",
                       "Should fall back to defaults when JSON is corrupted")
        XCTAssertEqual(manager.config.processingIntervalMinutes, 5)
    }

    func testHandlesMissingFileGracefully() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempConfigPath.path))

        let manager = ConfigManager(configPath: tempConfigPath)

        XCTAssertEqual(manager.config.version, "1.0.0",
                       "Should use defaults when file is missing")
    }
}
