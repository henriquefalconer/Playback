import XCTest
import Foundation
@testable import Playback

/// Base class for integration tests that need isolated dev environment and helper methods
@MainActor
class IntegrationTestBase: XCTestCase {
    var tempRootDirectory: URL!
    var tempDataDirectory: URL!
    var tempConfigPath: URL!
    var tempDatabasePath: URL!
    var originalEnvironment: [String: String] = [:]

    override func setUp() async throws {
        try await super.setUp()

        // Save original environment variables
        originalEnvironment = ProcessInfo.processInfo.environment as? [String: String] ?? [:]

        // Create isolated temporary directory structure
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackIntegrationTests")
            .appendingPathComponent(UUID().uuidString)

        tempRootDirectory = tempRoot
        tempDataDirectory = tempRoot.appendingPathComponent("data")
        tempConfigPath = tempRoot.appendingPathComponent("config.json")
        tempDatabasePath = tempDataDirectory.appendingPathComponent("meta.sqlite3")

        // Create directory structure
        try FileManager.default.createDirectory(at: tempDataDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDataDirectory.appendingPathComponent("temp"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempDataDirectory.appendingPathComponent("chunks"), withIntermediateDirectories: true)

        // Set dev mode environment variable
        setenv("PLAYBACK_DEV_MODE", "1", 1)
    }

    override func tearDown() async throws {
        // Clean up temporary directories
        if let tempRoot = tempRootDirectory {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        // Restore original environment variables
        if let devMode = originalEnvironment["PLAYBACK_DEV_MODE"] {
            setenv("PLAYBACK_DEV_MODE", devMode, 1)
        } else {
            unsetenv("PLAYBACK_DEV_MODE")
        }

        try await super.tearDown()
    }

    // MARK: - Test Data Helpers

    /// Create a test configuration file with default values
    func createTestConfig(excludedApps: [String] = [], processingIntervalMinutes: Int = 5) throws {
        let config: [String: Any] = [
            "version": "1.0.0",
            "processing_interval_minutes": processingIntervalMinutes,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "exclusion_mode": "skip",
            "excluded_apps": excludedApps,
            "video_fps": 30,
            "ffmpeg_crf": 28,
            "timeline_shortcut": "Option+Shift+Space",
            "pause_when_timeline_open": true,
            "notifications": [
                "processing_complete": true,
                "processing_errors": true,
                "disk_space_warnings": true,
                "recording_status": false
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        try jsonData.write(to: tempConfigPath)
    }

    /// Initialize test database with schema
    func initializeTestDatabase() throws {
        // This would call the database initialization from Python or Swift
        // For now, we'll create a minimal database file
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: tempDatabasePath.path) {
            fileManager.createFile(atPath: tempDatabasePath.path, contents: nil)
        }
    }

    /// Create a test screenshot file in the temp directory
    func createTestScreenshot(date: String, timestamp: String, appID: String = "com.apple.finder") throws -> URL {
        let dateDir = tempDataDirectory
            .appendingPathComponent("temp")
            .appendingPathComponent(String(date.prefix(6))) // YYYYMM
            .appendingPathComponent(String(date.suffix(2))) // DD

        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let filename = "\(timestamp)_\(appID).png"
        let filePath = dateDir.appendingPathComponent(filename)

        // Create a minimal PNG file (1x1 transparent pixel)
        let pngData = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ])

        try pngData.write(to: filePath)
        return filePath
    }

    /// Create a test video segment file
    func createTestVideoSegment(date: String, startTimestamp: String, duration: Double = 5.0) throws -> URL {
        let dateDir = tempDataDirectory
            .appendingPathComponent("chunks")
            .appendingPathComponent(String(date.prefix(6))) // YYYYMM
            .appendingPathComponent(String(date.suffix(2))) // DD

        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let filename = "\(startTimestamp).mp4"
        let filePath = dateDir.appendingPathComponent(filename)

        // Create a minimal MP4 file (not a valid video, but has non-zero size for tests)
        // MP4 file header bytes for a minimal valid structure
        let mp4Data = Data([
            0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // ftyp box
            0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00,
            0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32,
            0x6D, 0x70, 0x34, 0x31, 0x00, 0x00, 0x00, 0x08,
            0x66, 0x72, 0x65, 0x65 // free box
        ])
        FileManager.default.createFile(atPath: filePath.path, contents: mp4Data)
        return filePath
    }

    // MARK: - Service Helpers

    /// Wait for a condition to be true with timeout
    func waitForCondition(
        timeout: TimeInterval = 5.0,
        pollingInterval: TimeInterval = 0.1,
        condition: () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
        }

        XCTFail("Condition not met within \(timeout) seconds")
    }

    /// Execute a shell command and return output
    func executeShellCommand(_ command: String, arguments: [String] = []) async throws -> String {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Verification Helpers

    /// Verify a file exists and is not empty
    func assertFileExists(at url: URL, message: String? = nil) {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: url.path),
            message ?? "Expected file to exist at \(url.path)"
        )

        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attributes[.size] as? Int64 {
            XCTAssertGreaterThan(
                fileSize,
                0,
                message ?? "Expected file at \(url.path) to have non-zero size"
            )
        }
    }

    /// Verify a directory exists and has specific contents
    func assertDirectoryContains(
        _ directory: URL,
        fileCount: Int? = nil,
        pattern: String? = nil
    ) throws {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: directory.path),
            "Expected directory to exist at \(directory.path)"
        )

        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        if let expectedCount = fileCount {
            XCTAssertEqual(
                contents.count,
                expectedCount,
                "Expected \(expectedCount) files in \(directory.path), found \(contents.count)"
            )
        }

        if let pattern = pattern {
            let matchingFiles = contents.filter { $0.lastPathComponent.contains(pattern) }
            XCTAssertFalse(
                matchingFiles.isEmpty,
                "Expected at least one file matching '\(pattern)' in \(directory.path)"
            )
        }
    }
}
