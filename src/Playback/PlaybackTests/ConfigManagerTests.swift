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

    // MARK: - Default Config Tests

    func testDefaultConfigValues() {
        let manager = ConfigManager(configPath: tempDirectory.appendingPathComponent("new.json"))
        let cfg = manager.config

        XCTAssertEqual(cfg.version, "1.0.0")
        XCTAssertTrue(cfg.excludedApps.isEmpty)
        XCTAssertEqual(cfg.timelineShortcut, "Option+Shift+Space")
        XCTAssertTrue(cfg.recordingEnabled, "recording_enabled should default to true per spec")
        XCTAssertEqual(cfg.launchAtLogin, false, "launch_at_login should default to false per spec")
    }

    // MARK: - Load Tests

    func testLoadsExistingConfig() throws {
        let json = """
        {
            "version": "1.0.0",
            "excluded_apps": ["com.apple.keychainaccess"],
            "timeline_shortcut": "Command+Shift+T",
            "recording_enabled": false,
            "launch_at_login": true
        }
        """
        try json.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)
        let cfg = manager.config

        XCTAssertEqual(cfg.excludedApps, ["com.apple.keychainaccess"])
        XCTAssertEqual(cfg.timelineShortcut, "Command+Shift+T")
        XCTAssertFalse(cfg.recordingEnabled)
        XCTAssertEqual(cfg.launchAtLogin, true)
    }

    func testHandlesMissingFileGracefully() {
        let testPath = tempDirectory.appendingPathComponent("nonexistent.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: testPath.path))

        let manager = ConfigManager(configPath: testPath)
        XCTAssertEqual(manager.config.version, "1.0.0", "Should use defaults when file is missing")
    }

    func testHandlesCorruptedJSONGracefully() throws {
        try "{ invalid json".write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)
        XCTAssertEqual(manager.config.version, "1.0.0", "Should fall back to defaults for corrupted JSON")
    }

    // MARK: - Save Tests

    func testSaveCreatesFile() {
        let testPath = tempDirectory.appendingPathComponent("save_test.json")
        let manager = ConfigManager(configPath: testPath)

        XCTAssertFalse(FileManager.default.fileExists(atPath: testPath.path))
        manager.saveConfiguration()
        XCTAssertTrue(FileManager.default.fileExists(atPath: testPath.path))
    }

    func testSaveWritesValidJSON() throws {
        configManager.saveConfiguration()

        let data = try Data(contentsOf: tempConfigPath)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(decoded.version, configManager.config.version)
        XCTAssertEqual(decoded.recordingEnabled, configManager.config.recordingEnabled)
    }

    func testSaveFileHas0644Permissions() throws {
        configManager.saveConfiguration()

        let attrs = try FileManager.default.attributesOfItem(atPath: tempConfigPath.path)
        let perms = attrs[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o644, "Config file should have 0644 permissions per spec")
    }

    // MARK: - Validation Tests

    func testValidationFiltersInvalidBundleIDs() throws {
        let json = """
        {
            "version": "1.0.0",
            "excluded_apps": ["com.valid.app", "Invalid Bundle ID!", "com.another.valid"],
            "timeline_shortcut": "Option+Shift+Space",
            "recording_enabled": true,
            "launch_at_login": false
        }
        """
        try json.write(to: tempConfigPath, atomically: true, encoding: .utf8)

        let manager = ConfigManager(configPath: tempConfigPath)
        XCTAssertEqual(manager.config.excludedApps.count, 2, "Invalid bundle IDs should be filtered")
        XCTAssertTrue(manager.config.excludedApps.contains("com.valid.app"))
        XCTAssertTrue(manager.config.excludedApps.contains("com.another.valid"))
        XCTAssertFalse(manager.config.excludedApps.contains("Invalid Bundle ID!"))
    }

    // MARK: - UpdateConfig Tests

    func testUpdateConfigPersistsChanges() throws {
        var updated = configManager.config
        updated.recordingEnabled = false
        configManager.updateConfig(updated)

        XCTAssertFalse(configManager.config.recordingEnabled)

        // Verify persisted on disk
        let data = try Data(contentsOf: tempConfigPath)
        let saved = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertFalse(saved.recordingEnabled)
    }

    func testUpdateConfigPostsNotification() {
        let expectation = XCTestExpectation(description: "ConfigDidChange notification received")

        let token = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ConfigDidChange"),
            object: nil,
            queue: .main
        ) { _ in
            expectation.fulfill()
        }

        var updated = configManager.config
        updated.recordingEnabled = !updated.recordingEnabled
        configManager.updateConfig(updated)

        wait(for: [expectation], timeout: 1.0)
        NotificationCenter.default.removeObserver(token)
    }
}
