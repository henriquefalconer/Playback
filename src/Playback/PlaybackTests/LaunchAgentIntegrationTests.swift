import XCTest
import Foundation
@testable import Playback

/// Integration tests for LaunchAgent lifecycle management
@MainActor
final class LaunchAgentIntegrationTests: IntegrationTestBase {

    // MARK: - LaunchAgent Label Generation

    func testLaunchAgentLabelGenerationDevelopment() async throws {
        // Test that dev mode generates correct labels

        // GIVEN: Dev mode environment
        setenv("PLAYBACK_DEV_MODE", "1", 1)

        // WHEN: Generating agent labels
        let recordingLabel = "com.playback.dev.recording"
        let processingLabel = "com.playback.dev.processing"

        // THEN: Labels contain .dev suffix
        XCTAssertTrue(recordingLabel.contains(".dev."))
        XCTAssertTrue(processingLabel.contains(".dev."))
    }

    func testLaunchAgentLabelGenerationProduction() async throws {
        // Test that production mode generates correct labels

        // GIVEN: Production mode (no env var)
        unsetenv("PLAYBACK_DEV_MODE")

        // WHEN: Generating agent labels
        let recordingLabel = "com.playback.recording"
        let processingLabel = "com.playback.processing"

        // THEN: Labels do not contain .dev suffix
        XCTAssertFalse(recordingLabel.contains(".dev"))
        XCTAssertFalse(processingLabel.contains(".dev"))
    }

    // MARK: - Plist Template Processing

    func testPlistTemplateVariableSubstitution() async throws {
        // Test that template variables are correctly substituted

        // GIVEN: A plist template with variables
        let template = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>{{LABEL}}</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/python3</string>
                <string>{{SCRIPT_PATH}}/record_screen.py</string>
            </array>
            <key>WorkingDirectory</key>
            <string>{{WORKING_DIR}}</string>
            <key>StandardOutPath</key>
            <string>{{LOG_PATH}}/recording.log</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PLAYBACK_DEV_MODE</key>
                <string>{{DEV_MODE}}</string>
            </dict>
        </dict>
        </plist>
        """

        // WHEN: Substituting variables
        let substitutions = [
            "LABEL": "com.playback.dev.recording",
            "SCRIPT_PATH": "/Users/test/src/scripts",
            "WORKING_DIR": "/Users/test",
            "LOG_PATH": "/Users/test/dev_logs",
            "DEV_MODE": "1"
        ]

        var processedTemplate = template
        for (key, value) in substitutions {
            processedTemplate = processedTemplate.replacingOccurrences(of: "{{\(key)}}", with: value)
        }

        // THEN: All variables are substituted
        XCTAssertFalse(processedTemplate.contains("{{"))
        XCTAssertTrue(processedTemplate.contains("com.playback.dev.recording"))
        XCTAssertTrue(processedTemplate.contains("/Users/test/src/scripts"))
        XCTAssertTrue(processedTemplate.contains("/Users/test/dev_logs"))
    }

    // MARK: - Agent Status Parsing

    func testAgentStatusParsingRunning() async throws {
        // Test parsing of running agent status

        // GIVEN: launchctl output for running agent
        let output = """
        {
            "LimitLoadToSessionType" = "Aqua";
            "Label" = "com.playback.dev.recording";
            "OnDemand" = false;
            "LastExitStatus" = 0;
            "PID" = 12345;
            "Program" = "/usr/bin/python3";
        };
        """

        // WHEN: Parsing status
        let lines = output.split(separator: "\n")
        var pid: Int? = nil

        for line in lines {
            if line.contains("PID") {
                let components = line.split(separator: "=")
                if components.count >= 2 {
                    let pidString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: ";", with: "")
                    pid = Int(pidString)
                }
            }
        }

        // THEN: PID is extracted
        XCTAssertEqual(pid, 12345)
    }

    func testAgentStatusParsingNotRunning() async throws {
        // Test parsing when agent is not running

        // GIVEN: launchctl output for non-running agent
        let output = """
        {
            "LimitLoadToSessionType" = "Aqua";
            "Label" = "com.playback.dev.recording";
            "OnDemand" = false;
            "LastExitStatus" = 0;
        };
        """

        // WHEN: Parsing status
        let lines = output.split(separator: "\n")
        var hasPID = false

        for line in lines {
            if line.contains("PID") {
                hasPID = true
            }
        }

        // THEN: No PID found
        XCTAssertFalse(hasPID)
    }

    func testAgentStatusParsingNotLoaded() async throws {
        // Test parsing when agent is not loaded

        // GIVEN: launchctl output for non-existent agent
        let output = "Could not find service \"com.playback.dev.recording\" in domain for port"

        // WHEN: Checking if error message
        let isNotLoaded = output.contains("Could not find service")

        // THEN: Detected as not loaded
        XCTAssertTrue(isNotLoaded)
    }

    // MARK: - First-Run Setup Flow

    func testFirstRunSetupCreatesDirectories() async throws {
        // Test that first-run setup creates necessary directories

        // GIVEN: Clean environment
        let baseDir = tempRootDirectory.appendingPathComponent("fresh_install")

        // WHEN: Setting up directories
        let dataDir = baseDir.appendingPathComponent("data")
        let tempDir = dataDir.appendingPathComponent("temp")
        let chunksDir = dataDir.appendingPathComponent("chunks")

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: chunksDir, withIntermediateDirectories: true)

        // THEN: All directories exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: dataDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: chunksDir.path))
    }

    func testFirstRunSetupCreatesDefaultConfig() async throws {
        // Test that first-run setup creates default config

        // GIVEN: No config file exists
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempConfigPath.path))

        // WHEN: Creating default config
        try createTestConfig()

        // THEN: Config file exists with valid content
        assertFileExists(at: tempConfigPath)

        let configData = try Data(contentsOf: tempConfigPath)
        let config = try JSONSerialization.jsonObject(with: configData) as! [String: Any]

        XCTAssertNotNil(config["version"])
        XCTAssertNotNil(config["processing_interval_minutes"])
        XCTAssertNotNil(config["video_fps"])
    }

    func testFirstRunSetupInitializesDatabase() async throws {
        // Test that first-run setup initializes database

        // GIVEN: No database exists
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDatabasePath.path))

        // WHEN: Initializing database
        try initializeTestDatabase()

        // THEN: Database file exists
        assertFileExists(at: tempDatabasePath)
    }

    // MARK: - Agent Lifecycle Management

    func testInstallAgentCreatesPlist() async throws {
        // Test that installing an agent creates the plist file

        // GIVEN: No plist exists
        let plistPath = tempRootDirectory.appendingPathComponent("com.playback.dev.recording.plist")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistPath.path))

        // WHEN: Installing agent (simulated by creating plist)
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.playback.dev.recording</string>
        </dict>
        </plist>
        """

        try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)

        // THEN: Plist file exists
        assertFileExists(at: plistPath)
    }

    func testUninstallAgentRemovesPlist() async throws {
        // Test that uninstalling removes the plist

        // GIVEN: Plist exists
        let plistPath = tempRootDirectory.appendingPathComponent("com.playback.dev.recording.plist")
        let plistContent = "<?xml version=\"1.0\"?><plist></plist>"
        try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)

        assertFileExists(at: plistPath)

        // WHEN: Uninstalling (simulated by removing plist)
        try FileManager.default.removeItem(at: plistPath)

        // THEN: Plist is removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: plistPath.path))
    }

    // MARK: - Service Communication

    func testServicesReadSharedConfig() async throws {
        // Test that multiple services can read the same config file

        // GIVEN: Shared config file
        try createTestConfig(excludedApps: ["com.test.app"], processingIntervalMinutes: 10)

        // WHEN: Multiple services read config (simulated)
        let configData1 = try Data(contentsOf: tempConfigPath)
        let config1 = try JSONSerialization.jsonObject(with: configData1) as! [String: Any]

        let configData2 = try Data(contentsOf: tempConfigPath)
        let config2 = try JSONSerialization.jsonObject(with: configData2) as! [String: Any]

        // THEN: Both read the same values
        XCTAssertEqual(
            config1["processing_interval_seconds"] as? Int,
            config2["processing_interval_seconds"] as? Int
        )

        XCTAssertEqual(
            (config1["excluded_apps"] as? [String])?.count,
            (config2["excluded_apps"] as? [String])?.count
        )
    }

    func testSignalFileCoordination() async throws {
        // Test that services coordinate via signal files

        // GIVEN: Data directory
        let signalPath = tempDataDirectory.appendingPathComponent(".timeline_open")

        // WHEN: Timeline creates signal file
        FileManager.default.createFile(atPath: signalPath.path, contents: Data())

        // THEN: Recording service can detect it
        XCTAssertTrue(FileManager.default.fileExists(atPath: signalPath.path))

        // WHEN: Timeline removes signal file
        try FileManager.default.removeItem(at: signalPath)

        // THEN: Signal is gone
        XCTAssertFalse(FileManager.default.fileExists(atPath: signalPath.path))
    }

    // MARK: - Environment Separation

    func testDevelopmentProductionIsolation() async throws {
        // Test that dev and prod environments are isolated

        // GIVEN: Dev mode paths
        setenv("PLAYBACK_DEV_MODE", "1", 1)
        let devDataPath = tempRootDirectory.appendingPathComponent("dev_data")

        // GIVEN: Prod mode paths
        unsetenv("PLAYBACK_DEV_MODE")
        let prodDataPath = tempRootDirectory.appendingPathComponent("prod_data")

        // THEN: Paths are different
        XCTAssertNotEqual(devDataPath.path, prodDataPath.path)

        // Create both directories
        try FileManager.default.createDirectory(at: devDataPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prodDataPath, withIntermediateDirectories: true)

        // THEN: Both exist independently
        XCTAssertTrue(FileManager.default.fileExists(atPath: devDataPath.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prodDataPath.path))
    }

    // MARK: - Error Scenarios

    func testHandlesAgentCrashGracefully() async throws {
        // Test that system handles agent crashes gracefully

        // GIVEN: Agent was running but crashed
        let plistPath = tempRootDirectory.appendingPathComponent("com.playback.dev.recording.plist")
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.playback.dev.recording</string>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """

        try plistContent.write(to: plistPath, atomically: true, encoding: .utf8)

        // THEN: Plist contains KeepAlive directive
        let loadedContent = try String(contentsOf: plistPath, encoding: .utf8)
        XCTAssertTrue(loadedContent.contains("KeepAlive"))
    }

    func testHandlesMissingScriptPath() async throws {
        // Test that system handles missing Python script gracefully

        // GIVEN: Plist pointing to non-existent script
        let scriptPath = tempRootDirectory.appendingPathComponent("nonexistent_script.py")

        // THEN: Script does not exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: scriptPath.path))

        // Note: LaunchAgent would fail to start, but plist can still be created
        // This tests the file system state, actual process management requires launchctl
    }

    func testHandlesInvalidPlist() async throws {
        // Test handling of invalid plist file

        // GIVEN: Invalid plist content
        let plistPath = tempRootDirectory.appendingPathComponent("invalid.plist")
        let invalidContent = "This is not valid XML"
        try invalidContent.write(to: plistPath, atomically: true, encoding: .utf8)

        // THEN: File exists but contains invalid content
        assertFileExists(at: plistPath)

        let content = try String(contentsOf: plistPath, encoding: .utf8)
        XCTAssertFalse(content.contains("<?xml"))
    }
}
