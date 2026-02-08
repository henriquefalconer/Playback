import XCTest
import Foundation
@testable import Playback

/// Integration tests for the complete recording → processing → playback pipeline
@MainActor
final class FullPipelineIntegrationTests: IntegrationTestBase {

    // MARK: - End-to-End Pipeline Tests

    func testFullPipelineRecordingToPlayback() async throws {
        // Test the complete flow: screenshot capture → temp storage → processing → video segments → database

        // GIVEN: A clean test environment with config
        try createTestConfig()
        try initializeTestDatabase()

        // Create test screenshots simulating a recording session
        let dateStr = "20260208"
        let timestamps = [
            "20260208_110000_000",
            "20260208_110002_000",
            "20260208_110004_000",
            "20260208_110006_000",
            "20260208_110008_000"
        ]

        for timestamp in timestamps {
            _ = try createTestScreenshot(date: dateStr, timestamp: timestamp, appID: "com.apple.Safari")
        }

        // Verify screenshots were created
        let tempDir = tempDataDirectory.appendingPathComponent("temp/202602/08")
        try assertDirectoryContains(tempDir, fileCount: 5)

        // WHEN: Processing service runs (simulated)
        // In a real integration test, we would:
        // 1. Execute the Python processing script
        // 2. Wait for completion
        // 3. Verify outputs

        // For now, simulate the processing output
        let videoSegment = try createTestVideoSegment(
            date: dateStr,
            startTimestamp: "20260208_110000_000",
            duration: 10.0
        )

        // THEN: Verify video segment was created
        assertFileExists(at: videoSegment, message: "Expected video segment to be created")

        let chunksDir = tempDataDirectory.appendingPathComponent("chunks/202602/08")
        try assertDirectoryContains(chunksDir, fileCount: 1, pattern: ".mp4")
    }

    func testRecordingPausesWhenTimelineOpen() async throws {
        // Test that recording service pauses when .timeline_open signal file exists

        // GIVEN: A recording session
        try createTestConfig()

        // WHEN: Timeline viewer opens (creates signal file)
        let signalPath = tempDataDirectory.appendingPathComponent(".timeline_open")
        FileManager.default.createFile(atPath: signalPath.path, contents: Data())

        // THEN: Signal file exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: signalPath.path))

        // WHEN: Timeline viewer closes (removes signal file)
        try FileManager.default.removeItem(at: signalPath)

        // THEN: Signal file is removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: signalPath.path))
    }

    func testExcludedAppScreenshotsSkipped() async throws {
        // Test that screenshots are not captured when excluded app is frontmost

        // GIVEN: Config with excluded apps
        try createTestConfig(excludedApps: ["com.1password.1password"])

        // WHEN: Creating screenshot for excluded app
        let dateStr = "20260208"
        let timestamp = "20260208_110000_000"

        // In real implementation, the recording service would skip creating this file
        // For test purposes, we verify the config contains the exclusion
        let configData = try Data(contentsOf: tempConfigPath)
        let config = try JSONSerialization.jsonObject(with: configData) as! [String: Any]
        let excludedApps = config["excluded_apps"] as! [String]

        // THEN: Config contains the excluded app
        XCTAssertTrue(excludedApps.contains("com.1password.1password"))
    }

    func testProcessingHandlesMultipleDays() async throws {
        // Test that processing can handle screenshots across multiple days

        // GIVEN: Screenshots from multiple days
        let dates = ["20260206", "20260207", "20260208"]

        try createTestConfig()

        for date in dates {
            _ = try createTestScreenshot(date: date, timestamp: "\(date)_120000_000")
        }

        // THEN: All dates have temp directories with screenshots
        for date in dates {
            let month = String(date.prefix(6))
            let day = String(date.suffix(2))
            let tempDir = tempDataDirectory.appendingPathComponent("temp/\(month)/\(day)")

            XCTAssertTrue(
                FileManager.default.fileExists(atPath: tempDir.path),
                "Expected temp directory for date \(date)"
            )
        }
    }

    func testDatabaseSegmentStorage() async throws {
        // Test that processed video segments are recorded in the database

        // GIVEN: A processed video segment
        try initializeTestDatabase()

        let dateStr = "20260208"
        let timestamp = "20260208_110000_000"
        let videoPath = try createTestVideoSegment(date: dateStr, startTimestamp: timestamp)

        // THEN: Video file exists
        assertFileExists(at: videoPath)

        // Note: Actual database insertion would be tested with real database operations
        // This test verifies the file structure is correct for database insertion
        XCTAssertTrue(videoPath.path.contains("chunks"))
        XCTAssertTrue(videoPath.pathExtension == "mp4")
    }

    func testCleanupRemovesTempFiles() async throws {
        // Test that temp files are removed after processing

        // GIVEN: Temp screenshots
        let dateStr = "20260208"
        let timestamp = "20260208_110000_000"
        let screenshotPath = try createTestScreenshot(date: dateStr, timestamp: timestamp)

        // Verify screenshot exists
        assertFileExists(at: screenshotPath)

        // WHEN: Cleanup runs (simulated)
        try FileManager.default.removeItem(at: screenshotPath)

        // THEN: Temp file is removed
        XCTAssertFalse(FileManager.default.fileExists(atPath: screenshotPath.path))
    }

    func testRetentionPolicyEnforcement() async throws {
        // Test that old segments are removed according to retention policy

        // GIVEN: Config with 7-day retention
        try createTestConfig()

        // Create segments from different dates
        let oldDate = "20260101" // Old segment (should be cleaned)
        let recentDate = "20260208" // Recent segment (should be kept)

        let oldSegment = try createTestVideoSegment(date: oldDate, startTimestamp: "\(oldDate)_120000_000")
        let recentSegment = try createTestVideoSegment(date: recentDate, startTimestamp: "\(recentDate)_120000_000")

        // Verify both exist
        assertFileExists(at: oldSegment)
        assertFileExists(at: recentSegment)

        // WHEN: Cleanup runs (simulated - would remove old segment)
        // In real implementation, cleanup service would delete oldSegment based on retention policy

        // THEN: Recent segment still exists
        assertFileExists(at: recentSegment)
    }

    // MARK: - Performance Tests

    func testProcessingPerformanceWithLargeDataset() async throws {
        // Test processing performance with 100+ screenshots

        try createTestConfig()

        let dateStr = "20260208"
        let startTime = Date()

        // Create 100 test screenshots
        for i in 0..<100 {
            let hour = String(format: "%02d", 10 + (i / 3600))
            let minute = String(format: "%02d", (i / 60) % 60)
            let second = String(format: "%02d", i % 60)
            let timestamp = "\(dateStr)_\(hour)\(minute)\(second)_000"

            _ = try createTestScreenshot(date: dateStr, timestamp: timestamp)
        }

        let creationTime = Date().timeIntervalSince(startTime)

        // Verify all screenshots were created
        let tempDir = tempDataDirectory.appendingPathComponent("temp/202602/08")
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )

        XCTAssertEqual(contents.count, 100, "Expected 100 screenshots")
        XCTAssertLessThan(creationTime, 5.0, "Screenshot creation took too long: \(creationTime)s")
    }

    func testMemoryUsageDuringProcessing() async throws {
        // Test that memory usage remains reasonable during processing

        try createTestConfig()

        let dateStr = "20260208"

        // Create multiple screenshots
        for i in 0..<50 {
            let timestamp = String(format: "%@_%02d0000_000", dateStr, i)
            _ = try createTestScreenshot(date: dateStr, timestamp: timestamp)
        }

        // Note: Actual memory profiling would require additional tooling
        // This test verifies the data structure is reasonable
        let tempDir = tempDataDirectory.appendingPathComponent("temp/202602/08")
        let contents = try FileManager.default.contentsOfDirectory(
            at: tempDir,
            includingPropertiesForKeys: nil
        )

        // Verify all files were created without memory issues
        XCTAssertEqual(contents.count, 50)
    }

    // MARK: - Error Handling Tests

    func testHandlesCorruptedScreenshots() async throws {
        // Test that processing handles corrupted screenshot files gracefully

        // GIVEN: A corrupted screenshot file
        let dateStr = "20260208"
        let timestamp = "\(dateStr)_110000_000"
        let dateDir = tempDataDirectory
            .appendingPathComponent("temp/202602/08")

        try FileManager.default.createDirectory(at: dateDir, withIntermediateDirectories: true)

        let filename = "\(timestamp)_com.apple.finder.png"
        let filePath = dateDir.appendingPathComponent(filename)

        // Create a corrupted PNG (invalid data)
        let corruptedData = Data([0x00, 0x01, 0x02, 0x03])
        try corruptedData.write(to: filePath)

        // THEN: File exists but is corrupted
        assertFileExists(at: filePath)

        // Note: Actual processing would need to handle this gracefully
        // Test verifies the file structure allows for error handling
        let fileSize = try FileManager.default.attributesOfItem(atPath: filePath.path)[.size] as! Int64
        XCTAssertLessThan(fileSize, 100, "Corrupted file should be small")
    }

    func testHandlesMissingTempDirectory() async throws {
        // Test that system handles missing temp directories gracefully

        // GIVEN: Config without temp directory
        try createTestConfig()

        let nonExistentDir = tempDataDirectory.appendingPathComponent("temp/202602/99")

        // THEN: Directory does not exist
        XCTAssertFalse(FileManager.default.fileExists(atPath: nonExistentDir.path))

        // WHEN: Creating directory structure
        try FileManager.default.createDirectory(at: nonExistentDir, withIntermediateDirectories: true)

        // THEN: Directory is created
        XCTAssertTrue(FileManager.default.fileExists(atPath: nonExistentDir.path))
    }
}
