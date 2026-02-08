import XCTest
@testable import Playback

final class PathsTests: XCTestCase {

    // MARK: - Environment Detection Tests

    func testIsDevelopmentReturnsTrueWhenEnvVarSet() {
        let originalValue = ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"]
        setenv("PLAYBACK_DEV_MODE", "1", 1)

        XCTAssertTrue(Paths.isDevelopment, "Should detect development mode when PLAYBACK_DEV_MODE=1")

        if let original = originalValue {
            setenv("PLAYBACK_DEV_MODE", original, 1)
        } else {
            unsetenv("PLAYBACK_DEV_MODE")
        }
    }

    func testIsDevelopmentReturnsFalseWhenEnvVarNotSet() {
        let originalValue = ProcessInfo.processInfo.environment["PLAYBACK_DEV_MODE"]
        unsetenv("PLAYBACK_DEV_MODE")

        XCTAssertFalse(Paths.isDevelopment, "Should not detect development mode when env var not set")

        if let original = originalValue {
            setenv("PLAYBACK_DEV_MODE", original, 1)
        }
    }

    // MARK: - Path Resolution Tests

    func testBaseDataDirectoryReturnsNonEmptyPath() {
        let path = Paths.baseDataDirectory
        XCTAssertFalse(path.path.isEmpty, "Base data directory path should not be empty")
    }

    func testDatabasePathContainsMetaSqlite() {
        let dbPath = Paths.databasePath
        XCTAssertTrue(dbPath.path.contains("meta.sqlite3"), "Database path should contain meta.sqlite3")
        XCTAssertTrue(dbPath.path.hasSuffix("meta.sqlite3"), "Database path should end with meta.sqlite3")
    }

    func testTimelineOpenSignalPathContainsSignalFile() {
        let signalPath = Paths.timelineOpenSignalPath
        XCTAssertTrue(signalPath.path.contains(".timeline_open"), "Signal path should contain .timeline_open")
    }

    func testChunksDirectoryPathContainsChunks() {
        let chunksPath = Paths.chunksDirectory
        XCTAssertTrue(chunksPath.path.contains("chunks"), "Chunks directory path should contain 'chunks'")
    }

    func testConfigPathReturnsValidURL() {
        let configPath = Paths.configPath()
        XCTAssertFalse(configPath.path.isEmpty, "Config path should not be empty")
        XCTAssertTrue(configPath.path.hasSuffix(".json"), "Config path should end with .json")
    }

    // MARK: - Directory Creation Tests

    func testEnsureDirectoriesExistCreatesDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        // Temporarily override paths to use temp directory (would need refactoring for true isolation)
        // For now, just test that the method doesn't throw
        do {
            try Paths.ensureDirectoriesExist()
        } catch {
            XCTFail("ensureDirectoriesExist should not throw: \(error)")
        }

        // Verify base directory exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: Paths.baseDataDirectory.path),
                      "Base data directory should exist after calling ensureDirectoriesExist")

        // Verify chunks directory exists
        XCTAssertTrue(FileManager.default.fileExists(atPath: Paths.chunksDirectory.path),
                      "Chunks directory should exist after calling ensureDirectoriesExist")
    }

    // MARK: - Path Consistency Tests

    func testAllPathsAreConsistent() {
        let baseDir = Paths.baseDataDirectory
        let dbPath = Paths.databasePath
        let signalPath = Paths.timelineOpenSignalPath
        let chunksPath = Paths.chunksDirectory

        // All paths should be children of base directory
        XCTAssertTrue(dbPath.path.hasPrefix(baseDir.path),
                      "Database path should be under base directory")
        XCTAssertTrue(signalPath.path.hasPrefix(baseDir.path),
                      "Signal path should be under base directory")
        XCTAssertTrue(chunksPath.path.hasPrefix(baseDir.path),
                      "Chunks path should be under base directory")
    }
}

// MARK: - SignalFileManager Tests

final class SignalFileManagerTests: XCTestCase {
    var tempDirectory: URL!
    var tempSignalPath: URL!
    var signalManager: SignalFileManager!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        tempSignalPath = tempDirectory.appendingPathComponent(".timeline_open")
        signalManager = SignalFileManager(signalPath: tempSignalPath)
    }

    override func tearDown() {
        signalManager = nil
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    // MARK: - Signal File Creation Tests

    func testCreateSignalFileCreatesFile() throws {
        try signalManager.createSignalFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempSignalPath.path),
                      "Signal file should exist after creation")
    }

    func testCreateSignalFileCreatesParentDirectory() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.path),
                       "Temp directory should not exist before creating signal file")

        try signalManager.createSignalFile()

        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.path),
                      "Parent directory should be created when creating signal file")
    }

    func testCreateSignalFileWritesTimestamp() throws {
        try signalManager.createSignalFile()

        let content = try String(contentsOf: tempSignalPath, encoding: .utf8)
        XCTAssertTrue(content.contains("Timeline viewer opened at"),
                      "Signal file should contain timestamp message")
    }

    // MARK: - Signal File Removal Tests

    func testRemoveSignalFileRemovesFile() throws {
        try signalManager.createSignalFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempSignalPath.path))

        signalManager.removeSignalFile()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempSignalPath.path),
                       "Signal file should not exist after removal")
    }

    func testRemoveSignalFileDoesNotThrowWhenFileDoesNotExist() {
        signalManager.removeSignalFile()
    }

    // MARK: - Signal File Existence Tests

    func testExistsReturnsTrueWhenFileExists() throws {
        XCTAssertFalse(signalManager.exists, "Signal should not exist initially")

        try signalManager.createSignalFile()
        XCTAssertTrue(signalManager.exists, "Signal should exist after creation")
    }

    func testExistsReturnsFalseWhenFileDoesNotExist() {
        XCTAssertFalse(signalManager.exists, "Signal should not exist initially")
    }

    // MARK: - Lifecycle Tests

    func testDeinitRemovesSignalFile() throws {
        try signalManager.createSignalFile()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempSignalPath.path))

        // Release the manager
        signalManager = nil

        // Give deinit a moment to execute
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertFalse(FileManager.default.fileExists(atPath: tempSignalPath.path),
                       "Signal file should be removed when manager is deallocated")
    }

    // MARK: - Multiple Operations Tests

    func testMultipleCreateCallsOverwriteFile() throws {
        try signalManager.createSignalFile()
        let firstContent = try String(contentsOf: tempSignalPath, encoding: .utf8)

        // Wait a tiny bit to ensure timestamp changes
        Thread.sleep(forTimeInterval: 0.01)

        try signalManager.createSignalFile()
        let secondContent = try String(contentsOf: tempSignalPath, encoding: .utf8)

        XCTAssertNotEqual(firstContent, secondContent,
                          "Second creation should overwrite with new timestamp")
    }
}
