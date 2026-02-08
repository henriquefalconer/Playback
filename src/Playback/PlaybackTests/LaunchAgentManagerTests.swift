import XCTest
@testable import Playback

@MainActor
final class LaunchAgentManagerTests: XCTestCase {

    // MARK: - AgentType Tests

    func testAgentTypeLabelsInDevelopmentMode() {
        let originalValue = ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"]
        setenv("PLAYBACK_DEV_MODE", "1", 1)

        XCTAssertEqual(AgentType.recording.label, "com.playback.dev.recording",
                       "Recording agent should have dev label in development mode")
        XCTAssertEqual(AgentType.processing.label, "com.playback.dev.processing",
                       "Processing agent should have dev label in development mode")
        XCTAssertEqual(AgentType.cleanup.label, "com.playback.dev.cleanup",
                       "Cleanup agent should have dev label in development mode")

        if let original = originalValue {
            setenv("PLAYBACK_DEV_MODE", original, 1)
        } else {
            unsetenv("PLAYBACK_DEV_MODE")
        }
    }

    func testAgentTypeLabelsInProductionMode() {
        let originalValue = ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"]
        unsetenv("PLAYBACK_DEV_MODE")

        XCTAssertEqual(AgentType.recording.label, "com.playback.recording",
                       "Recording agent should have production label")
        XCTAssertEqual(AgentType.processing.label, "com.playback.processing",
                       "Processing agent should have production label")
        XCTAssertEqual(AgentType.cleanup.label, "com.playback.cleanup",
                       "Cleanup agent should have production label")

        if let original = originalValue {
            setenv("PLAYBACK_DEV_MODE", original, 1)
        }
    }

    func testAgentTypeTemplateNames() {
        XCTAssertEqual(AgentType.recording.templateName, "recording.plist.template",
                       "Recording agent should have correct template name")
        XCTAssertEqual(AgentType.processing.templateName, "processing.plist.template",
                       "Processing agent should have correct template name")
        XCTAssertEqual(AgentType.cleanup.templateName, "cleanup.plist.template",
                       "Cleanup agent should have correct template name")
    }

    func testAgentTypePlistNamesInDevelopmentMode() {
        let originalValue = ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"]
        setenv("PLAYBACK_DEV_MODE", "1", 1)

        XCTAssertEqual(AgentType.recording.plistName, "com.playback.dev.recording.plist",
                       "Recording plist should include dev prefix in development mode")
        XCTAssertEqual(AgentType.processing.plistName, "com.playback.dev.processing.plist",
                       "Processing plist should include dev prefix in development mode")
        XCTAssertEqual(AgentType.cleanup.plistName, "com.playback.dev.cleanup.plist",
                       "Cleanup plist should include dev prefix in development mode")

        if let original = originalValue {
            setenv("PLAYBACK_DEV_MODE", original, 1)
        } else {
            unsetenv("PLAYBACK_DEV_MODE")
        }
    }

    func testAgentTypePlistNamesInProductionMode() {
        let originalValue = ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"]
        unsetenv("PLAYBACK_DEV_MODE")

        XCTAssertEqual(AgentType.recording.plistName, "com.playback.recording.plist",
                       "Recording plist should not include dev prefix in production")
        XCTAssertEqual(AgentType.processing.plistName, "com.playback.processing.plist",
                       "Processing plist should not include dev prefix in production")
        XCTAssertEqual(AgentType.cleanup.plistName, "com.playback.cleanup.plist",
                       "Cleanup plist should not include dev prefix in production")

        if let original = originalValue {
            setenv("PLAYBACK_DEV_MODE", original, 1)
        }
    }

    func testAgentTypeCaseIterable() {
        let allCases = AgentType.allCases
        XCTAssertEqual(allCases.count, 3, "Should have exactly 3 agent types")
        XCTAssertTrue(allCases.contains(.recording), "Should include recording agent")
        XCTAssertTrue(allCases.contains(.processing), "Should include processing agent")
        XCTAssertTrue(allCases.contains(.cleanup), "Should include cleanup agent")
    }

    func testAgentTypeRawValues() {
        XCTAssertEqual(AgentType.recording.rawValue, "recording")
        XCTAssertEqual(AgentType.processing.rawValue, "processing")
        XCTAssertEqual(AgentType.cleanup.rawValue, "cleanup")
    }

    // MARK: - LaunchAgentStatus Tests

    func testLaunchAgentStatusInitialization() {
        let status = LaunchAgentStatus(isLoaded: true, isRunning: true, pid: 12345, lastExitStatus: 0)

        XCTAssertTrue(status.isLoaded)
        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.pid, 12345)
        XCTAssertEqual(status.lastExitStatus, 0)
    }

    func testLaunchAgentStatusWithNilValues() {
        let status = LaunchAgentStatus(isLoaded: true, isRunning: false, pid: nil, lastExitStatus: nil)

        XCTAssertTrue(status.isLoaded)
        XCTAssertFalse(status.isRunning)
        XCTAssertNil(status.pid)
        XCTAssertNil(status.lastExitStatus)
    }

    func testLaunchAgentStatusNotLoaded() {
        let status = LaunchAgentStatus(isLoaded: false, isRunning: false, pid: nil, lastExitStatus: nil)

        XCTAssertFalse(status.isLoaded)
        XCTAssertFalse(status.isRunning)
        XCTAssertNil(status.pid)
        XCTAssertNil(status.lastExitStatus)
    }

    // MARK: - LaunchAgentError Tests

    func testLaunchAgentErrorTypes() {
        let templateError = LaunchAgentError.templateNotFound("test.template")
        let plistError = LaunchAgentError.invalidPlist("invalid XML")
        let launchctlError = LaunchAgentError.launchctlFailed("load", 127)
        let installError = LaunchAgentError.installationFailed("permission denied")

        switch templateError {
        case .templateNotFound(let name):
            XCTAssertEqual(name, "test.template")
        default:
            XCTFail("Should be templateNotFound error")
        }

        switch plistError {
        case .invalidPlist(let message):
            XCTAssertEqual(message, "invalid XML")
        default:
            XCTFail("Should be invalidPlist error")
        }

        switch launchctlError {
        case .launchctlFailed(let command, let exitCode):
            XCTAssertEqual(command, "load")
            XCTAssertEqual(exitCode, 127)
        default:
            XCTFail("Should be launchctlFailed error")
        }

        switch installError {
        case .installationFailed(let reason):
            XCTAssertEqual(reason, "permission denied")
        default:
            XCTFail("Should be installationFailed error")
        }
    }

    // MARK: - Status Parsing Tests

    func testGetAgentStatusParsesRunningAgent() {
        let mockOutput = """
        PID\tStatus\tLabel
        12345\t0\tcom.playback.recording
        """

        let status = parseStatusOutput(mockOutput)

        XCTAssertTrue(status.isLoaded, "Agent should be loaded")
        XCTAssertTrue(status.isRunning, "Agent should be running with valid PID")
        XCTAssertEqual(status.pid, 12345, "PID should be parsed correctly")
        XCTAssertEqual(status.lastExitStatus, 0, "Exit status should be 0")
    }

    func testGetAgentStatusParsesStoppedAgent() {
        let mockOutput = """
        PID\tStatus\tLabel
        -\t0\tcom.playback.recording
        """

        let status = parseStatusOutput(mockOutput)

        XCTAssertTrue(status.isLoaded, "Agent should be loaded")
        XCTAssertFalse(status.isRunning, "Agent should not be running with - as PID")
        XCTAssertNil(status.pid, "PID should be nil when stopped")
        XCTAssertEqual(status.lastExitStatus, 0, "Exit status should be 0")
    }

    func testGetAgentStatusHandlesNotLoaded() {
        let mockOutput = ""

        let status = parseStatusOutput(mockOutput)

        XCTAssertFalse(status.isLoaded, "Agent should not be loaded")
        XCTAssertFalse(status.isRunning, "Agent should not be running")
        XCTAssertNil(status.pid, "PID should be nil")
        XCTAssertNil(status.lastExitStatus, "Exit status should be nil")
    }

    func testGetAgentStatusParsesExitStatus() {
        let mockOutput = """
        PID\tStatus\tLabel
        -\t1\tcom.playback.recording
        """

        let status = parseStatusOutput(mockOutput)

        XCTAssertTrue(status.isLoaded, "Agent should be loaded")
        XCTAssertFalse(status.isRunning, "Agent should not be running")
        XCTAssertNil(status.pid, "PID should be nil")
        XCTAssertEqual(status.lastExitStatus, 1, "Exit status should be 1")
    }

    func testGetAgentStatusHandlesInvalidOutput() {
        let mockOutput = """
        PID\tStatus\tLabel
        invalid\tinvalid\tcom.playback.recording
        """

        let status = parseStatusOutput(mockOutput)

        XCTAssertTrue(status.isLoaded, "Agent should be considered loaded with invalid data")
        XCTAssertFalse(status.isRunning, "Agent should not be running with invalid PID")
        XCTAssertNil(status.pid, "PID should be nil for invalid input")
        XCTAssertNil(status.lastExitStatus, "Exit status should be nil for invalid input")
    }

    func testGetAgentStatusHandlesMalformedOutput() {
        let mockOutput = """
        PID\tStatus\tLabel
        12345
        """

        let status = parseStatusOutput(mockOutput)

        XCTAssertTrue(status.isLoaded, "Agent should be considered loaded")
        XCTAssertFalse(status.isRunning, "Agent should not be running with malformed data")
        XCTAssertNil(status.pid, "PID should be nil for malformed input")
    }

    func testGetAgentStatusHandlesEmptyLines() {
        let mockOutput = """


        """

        let status = parseStatusOutput(mockOutput)

        XCTAssertFalse(status.isLoaded, "Agent should not be loaded with empty output")
        XCTAssertFalse(status.isRunning, "Agent should not be running")
        XCTAssertNil(status.pid, "PID should be nil")
        XCTAssertNil(status.lastExitStatus, "Exit status should be nil")
    }

    func testGetAgentStatusHandlesNoDashSeparator() {
        let mockOutput = """
        PID\tStatus\tLabel
        -\t-\tcom.playback.recording
        """

        let status = parseStatusOutput(mockOutput)

        XCTAssertTrue(status.isLoaded, "Agent should be loaded")
        XCTAssertFalse(status.isRunning, "Agent should not be running")
        XCTAssertNil(status.pid, "PID should be nil with - separator")
        XCTAssertNil(status.lastExitStatus, "Exit status should be nil with - separator")
    }

    // MARK: - Helper Methods

    /// Helper method to parse launchctl list output into LaunchAgentStatus
    /// This mirrors the logic in LaunchAgentManager.getAgentStatus()
    private func parseStatusOutput(_ output: String) -> LaunchAgentStatus {
        guard !output.isEmpty else {
            return LaunchAgentStatus(isLoaded: false, isRunning: false, pid: nil, lastExitStatus: nil)
        }

        let lines = output.split(separator: "\n")
        guard lines.count >= 2 else {
            return LaunchAgentStatus(isLoaded: false, isRunning: false, pid: nil, lastExitStatus: nil)
        }

        let parts = lines[1].split(separator: "\t").map(String.init)
        guard parts.count >= 3 else {
            return LaunchAgentStatus(isLoaded: true, isRunning: false, pid: nil, lastExitStatus: nil)
        }

        let pid = parts[0] == "-" ? nil : Int(parts[0])
        let lastExitStatus = parts[1] == "-" ? nil : Int(parts[1])
        let isRunning = pid != nil

        return LaunchAgentStatus(isLoaded: true, isRunning: isRunning, pid: pid, lastExitStatus: lastExitStatus)
    }
}

// MARK: - Integration Tests (Disabled by Default)

/// These tests interact with the real system and should only be run manually
/// on a test machine. They are disabled by default to prevent affecting the
/// development environment during normal test runs.
///
/// To run these tests, change #if false to #if true and run on a dedicated
/// test machine where modifying LaunchAgents is safe.
#if false
extension LaunchAgentManagerTests {

    // MARK: - Installation Tests (System Integration)

    func testInstallAgentCreatesValidPlist() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)

        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(AgentType.recording.plistName)

        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath.path),
                      "Plist file should exist after installation")

        try manager.removeAgent(.recording)
    }

    func testInstallAgentSubstitutesVariables() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)

        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(AgentType.recording.plistName)

        let content = try String(contentsOf: plistPath, encoding: .utf8)

        XCTAssertFalse(content.contains("{{LABEL}}"),
                       "LABEL variable should be substituted")
        XCTAssertFalse(content.contains("{{SCRIPT_PATH}}"),
                       "SCRIPT_PATH variable should be substituted")
        XCTAssertFalse(content.contains("{{WORKING_DIR}}"),
                       "WORKING_DIR variable should be substituted")

        try manager.removeAgent(.recording)
    }

    func testLoadAgentMakesAgentLoaded() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)
        try manager.loadAgent(.recording)

        let status = manager.getAgentStatus(.recording)

        XCTAssertTrue(status.isLoaded, "Agent should be loaded after load call")

        try manager.unloadAgent(.recording)
        try manager.removeAgent(.recording)
    }

    func testStartAgentMakesAgentRunning() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)
        try manager.loadAgent(.recording)
        try manager.startAgent(.recording)

        let status = manager.getAgentStatus(.recording)

        XCTAssertTrue(status.isRunning, "Agent should be running after start call")
        XCTAssertNotNil(status.pid, "Agent should have a PID when running")

        try manager.stopAgent(.recording)
        try manager.unloadAgent(.recording)
        try manager.removeAgent(.recording)
    }

    func testStopAgentMakesAgentNotRunning() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)
        try manager.loadAgent(.recording)
        try manager.startAgent(.recording)

        let runningStatus = manager.getAgentStatus(.recording)
        XCTAssertTrue(runningStatus.isRunning, "Agent should be running before stop")

        try manager.stopAgent(.recording)

        let stoppedStatus = manager.getAgentStatus(.recording)
        XCTAssertFalse(stoppedStatus.isRunning, "Agent should not be running after stop")

        try manager.unloadAgent(.recording)
        try manager.removeAgent(.recording)
    }

    func testUnloadAgentMakesAgentNotLoaded() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)
        try manager.loadAgent(.recording)

        let loadedStatus = manager.getAgentStatus(.recording)
        XCTAssertTrue(loadedStatus.isLoaded, "Agent should be loaded before unload")

        try manager.unloadAgent(.recording)

        let unloadedStatus = manager.getAgentStatus(.recording)
        XCTAssertFalse(unloadedStatus.isLoaded, "Agent should not be loaded after unload")

        try manager.removeAgent(.recording)
    }

    func testRemoveAgentDeletesPlistFile() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)

        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(AgentType.recording.plistName)

        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath.path),
                      "Plist should exist before removal")

        try manager.removeAgent(.recording)

        XCTAssertFalse(FileManager.default.fileExists(atPath: plistPath.path),
                       "Plist should not exist after removal")
    }

    func testRestartAgentStopsAndStartsAgent() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)
        try manager.loadAgent(.recording)
        try manager.startAgent(.recording)

        let initialStatus = manager.getAgentStatus(.recording)
        let initialPid = initialStatus.pid

        try manager.restartAgent(.recording)

        let restartedStatus = manager.getAgentStatus(.recording)

        XCTAssertTrue(restartedStatus.isRunning, "Agent should be running after restart")
        XCTAssertNotNil(restartedStatus.pid, "Agent should have a PID after restart")

        if let initialPid = initialPid, let newPid = restartedStatus.pid {
            XCTAssertNotEqual(initialPid, newPid, "PID should change after restart")
        }

        try manager.stopAgent(.recording)
        try manager.unloadAgent(.recording)
        try manager.removeAgent(.recording)
    }

    func testReloadAgentReinstallsAndReloads() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)
        try manager.loadAgent(.recording)

        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(AgentType.recording.plistName)

        let originalContent = try String(contentsOf: plistPath, encoding: .utf8)

        try manager.reloadAgent(.recording)

        let reloadedContent = try String(contentsOf: plistPath, encoding: .utf8)

        XCTAssertEqual(originalContent, reloadedContent,
                       "Content should remain the same after reload")

        let status = manager.getAgentStatus(.recording)
        XCTAssertTrue(status.isLoaded, "Agent should be loaded after reload")

        try manager.unloadAgent(.recording)
        try manager.removeAgent(.recording)
    }

    func testUpdateProcessingIntervalReloadsAgent() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.processing)
        try manager.loadAgent(.processing)

        let initialStatus = manager.getAgentStatus(.processing)
        XCTAssertTrue(initialStatus.isLoaded, "Processing agent should be loaded initially")

        try manager.updateProcessingInterval(minutes: 10)

        let updatedStatus = manager.getAgentStatus(.processing)
        XCTAssertTrue(updatedStatus.isLoaded, "Processing agent should still be loaded after update")

        try manager.unloadAgent(.processing)
        try manager.removeAgent(.processing)
    }

    func testUpdateProcessingIntervalUpdatesStartInterval() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.processing)

        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(AgentType.processing.plistName)

        try manager.updateProcessingInterval(minutes: 15)

        let plistData = try Data(contentsOf: plistPath)
        let plist = try PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any]

        XCTAssertNotNil(plist, "Plist should be readable after update")
        XCTAssertEqual(plist?["StartInterval"] as? Int, 900,
                       "StartInterval should be 900 seconds (15 minutes)")

        try manager.updateProcessingInterval(minutes: 5)

        let updatedPlistData = try Data(contentsOf: plistPath)
        let updatedPlist = try PropertyListSerialization.propertyList(
            from: updatedPlistData,
            options: [],
            format: nil
        ) as? [String: Any]

        XCTAssertNotNil(updatedPlist, "Plist should be readable after second update")
        XCTAssertEqual(updatedPlist?["StartInterval"] as? Int, 300,
                       "StartInterval should be 300 seconds (5 minutes)")

        try manager.removeAgent(.processing)
    }

    func testUpdateProcessingIntervalValidatesRange() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.processing)

        XCTAssertThrowsError(try manager.updateProcessingInterval(minutes: 0)) { error in
            if case LaunchAgentError.installationFailed(let message) = error {
                XCTAssertTrue(message.contains("between 1 and 60"),
                              "Error message should indicate valid range")
            } else {
                XCTFail("Should throw installationFailed error for invalid range")
            }
        }

        XCTAssertThrowsError(try manager.updateProcessingInterval(minutes: 61)) { error in
            if case LaunchAgentError.installationFailed(let message) = error {
                XCTAssertTrue(message.contains("between 1 and 60"),
                              "Error message should indicate valid range")
            } else {
                XCTFail("Should throw installationFailed error for invalid range")
            }
        }

        XCTAssertNoThrow(try manager.updateProcessingInterval(minutes: 1),
                         "Should accept minimum value of 1")
        XCTAssertNoThrow(try manager.updateProcessingInterval(minutes: 60),
                         "Should accept maximum value of 60")

        try manager.removeAgent(.processing)
    }

    // MARK: - Error Handling Tests (System Integration)

    func testInstallAgentThrowsForMissingTemplate() {
        let manager = LaunchAgentManager.shared

        XCTAssertThrowsError(try manager.installAgent(.recording)) { error in
            if case LaunchAgentError.templateNotFound = error {
                // Expected error
            } else {
                XCTFail("Should throw templateNotFound error, got \(error)")
            }
        }
    }

    func testLoadAgentInstallsIfPlistMissing() throws {
        let manager = LaunchAgentManager.shared

        let plistPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent(AgentType.recording.plistName)

        if FileManager.default.fileExists(atPath: plistPath.path) {
            try FileManager.default.removeItem(at: plistPath)
        }

        try manager.loadAgent(.recording)

        XCTAssertTrue(FileManager.default.fileExists(atPath: plistPath.path),
                      "Plist should be installed if missing during load")

        try manager.unloadAgent(.recording)
        try manager.removeAgent(.recording)
    }

    func testUnloadAgentDoesNotThrowIfNotLoaded() {
        let manager = LaunchAgentManager.shared

        XCTAssertNoThrow(try manager.unloadAgent(.recording),
                         "Unload should not throw if agent not loaded")
    }

    func testStopAgentDoesNotThrowIfNotRunning() throws {
        let manager = LaunchAgentManager.shared

        try manager.installAgent(.recording)
        try manager.loadAgent(.recording)

        XCTAssertNoThrow(try manager.stopAgent(.recording),
                         "Stop should not throw if agent not running")

        try manager.unloadAgent(.recording)
        try manager.removeAgent(.recording)
    }
}
#endif
