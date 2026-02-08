import XCTest
import SQLite3
@testable import Playback

// SQLite constant for SQLITE_TRANSIENT
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Performance test suite for key Playback operations
///
/// Target Performance Metrics:
/// - Database queries: <100ms for typical queries
/// - Timeline rendering: <16ms for 60fps operations
/// - Configuration loading: <50ms
/// - Path resolution: <10ms
/// - Search queries: <200ms
@MainActor
final class PerformanceTests: XCTestCase {
    var tempDirectory: URL!
    var tempDatabasePath: URL!
    var tempConfigPath: URL!
    var tempBaseDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create isolated test environment
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlaybackPerformanceTests")
            .appendingPathComponent(UUID().uuidString)

        tempDatabasePath = tempDirectory.appendingPathComponent("meta.sqlite3")
        tempConfigPath = tempDirectory.appendingPathComponent("config.json")
        tempBaseDir = tempDirectory.appendingPathComponent("data")

        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tempBaseDir, withIntermediateDirectories: true)

        // Initialize database with sample data
        try createTestDatabase()

        // Create test config
        try createTestConfig()
    }

    override func tearDown() async throws {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Test Data Setup

    /// Create a test database with sample segments for performance testing
    private func createTestDatabase() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", """
            import sqlite3
            import random

            conn = sqlite3.connect('\(tempDatabasePath.path)')
            conn.execute('PRAGMA journal_mode=WAL')
            conn.execute('PRAGMA secure_delete=ON')

            # Create segments table
            conn.execute('''CREATE TABLE IF NOT EXISTS segments (
                id TEXT PRIMARY KEY,
                date TEXT NOT NULL,
                start_ts REAL NOT NULL,
                end_ts REAL NOT NULL,
                frame_count INTEGER NOT NULL,
                file_size_bytes INTEGER NOT NULL,
                fps REAL,
                video_path TEXT NOT NULL
            )''')

            # Create index for timestamp queries
            conn.execute('CREATE INDEX IF NOT EXISTS idx_segments_start_ts ON segments(start_ts)')
            conn.execute('CREATE INDEX IF NOT EXISTS idx_segments_date ON segments(date)')

            # Create OCR tables
            conn.execute('''CREATE TABLE IF NOT EXISTS ocr_text (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                segment_id TEXT NOT NULL,
                timestamp REAL NOT NULL,
                text_content TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 0.9
            )''')

            conn.execute('''CREATE VIRTUAL TABLE IF NOT EXISTS ocr_search USING fts5(
                text_content, segment_id, timestamp, content=ocr_text
            )''')

            # Insert sample segments (100 segments over ~3 hours)
            base_ts = 1704067200.0  # 2024-01-01 00:00:00
            for i in range(100):
                seg_id = f"seg_{i:04d}"
                start_ts = base_ts + (i * 120.0)  # 2-minute intervals
                end_ts = start_ts + 120.0
                frame_count = 300
                fps = 5.0
                date = "20240101"
                video_path = f"chunks/202401/01/{int(start_ts)}.mp4"
                file_size = 512000

                conn.execute('''INSERT INTO segments
                    (id, date, start_ts, end_ts, frame_count, file_size_bytes, fps, video_path)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)''',
                    (seg_id, date, start_ts, end_ts, frame_count, file_size, fps, video_path))

            # Insert sample OCR text entries (500 entries for search testing)
            sample_texts = [
                "Important meeting notes about project",
                "Code review feedback from team",
                "Database performance optimization",
                "User interface design mockup",
                "API documentation update",
                "Bug fix for timeline rendering",
                "Configuration management system",
                "Search functionality improvements",
                "Performance benchmarking results",
                "Integration test coverage"
            ]

            for i in range(500):
                seg_idx = i % 100
                seg_id = f"seg_{seg_idx:04d}"
                timestamp = base_ts + (seg_idx * 120.0) + (i % 120)
                text = sample_texts[i % len(sample_texts)]
                confidence = 0.85 + (random.random() * 0.14)  # 0.85-0.99

                conn.execute('''INSERT INTO ocr_text
                    (segment_id, timestamp, text_content, confidence)
                    VALUES (?, ?, ?, ?)''',
                    (seg_id, timestamp, text, confidence))

            # Populate FTS5 index
            conn.execute('''INSERT INTO ocr_search(rowid, segment_id, timestamp, text_content)
                SELECT id, segment_id, timestamp, text_content FROM ocr_text''')

            conn.commit()
            conn.close()
            """]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(domain: "PerformanceTest", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create test database"])
        }
    }

    /// Create a test configuration file
    private func createTestConfig() throws {
        let config: [String: Any] = [
            "version": "1.0.0",
            "processing_interval_minutes": 5,
            "temp_retention_policy": "1_week",
            "recording_retention_policy": "never",
            "exclusion_mode": "skip",
            "excluded_apps": ["com.1password.1password", "com.apple.Keychain"],
            "video_fps": 5,
            "ffmpeg_crf": 28,
            "ffmpeg_preset": "veryfast",
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

    // MARK: - Database Query Performance Tests

    /// Test: Recent segments query performance
    /// Target: <100ms for fetching recent segments
    func testRecentSegmentsQueryPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            var db: OpaquePointer?
            guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
                XCTFail("Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            let query = """
                SELECT id, start_ts, end_ts, frame_count, fps, video_path
                FROM segments
                ORDER BY start_ts DESC
                LIMIT 50
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                XCTFail("Failed to prepare statement")
                return
            }
            defer { sqlite3_finalize(statement) }

            var count = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                count += 1
            }

            XCTAssertEqual(count, 50, "Should retrieve 50 recent segments")
        }
    }

    /// Test: Date range query performance
    /// Target: <100ms for date range queries
    func testDateRangeQueryPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            var db: OpaquePointer?
            guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
                XCTFail("Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            let startTime = 1704067200.0
            let endTime = startTime + 7200.0  // 2 hours

            let query = """
                SELECT id, start_ts, end_ts, frame_count
                FROM segments
                WHERE start_ts >= ? AND end_ts <= ?
                ORDER BY start_ts ASC
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                XCTFail("Failed to prepare statement")
                return
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_double(statement, 1, startTime)
            sqlite3_bind_double(statement, 2, endTime)

            var count = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                count += 1
            }

            XCTAssertGreaterThan(count, 0, "Should find segments in date range")
        }
    }

    /// Test: Timeline query for specific date performance
    /// Target: <100ms for fetching all segments for a specific date
    func testTimelineQueryPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            var db: OpaquePointer?
            guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
                XCTFail("Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            let query = """
                SELECT id, start_ts, end_ts, frame_count, fps, video_path
                FROM segments
                WHERE date = ?
                ORDER BY start_ts ASC
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                XCTFail("Failed to prepare statement")
                return
            }
            defer { sqlite3_finalize(statement) }

            let date = "20240101"
            sqlite3_bind_text(statement, 1, (date as NSString).utf8String, -1, SQLITE_TRANSIENT)

            var count = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                count += 1
            }

            XCTAssertEqual(count, 100, "Should retrieve all 100 segments for the date")
        }
    }

    /// Test: FTS5 full-text search query performance
    /// Target: <200ms for search queries
    func testFTS5SearchQueryPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            var db: OpaquePointer?
            guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
                XCTFail("Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            let query = """
                SELECT o.id, o.text_content, o.timestamp, o.segment_id, o.confidence
                FROM ocr_text o
                JOIN ocr_search s ON o.id = s.rowid
                WHERE s.text_content MATCH ?
                AND o.confidence >= 0.5
                ORDER BY o.timestamp DESC
                LIMIT 100
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                XCTFail("Failed to prepare statement")
                return
            }
            defer { sqlite3_finalize(statement) }

            let searchQuery = "performance"
            sqlite3_bind_text(statement, 1, (searchQuery as NSString).utf8String, -1, SQLITE_TRANSIENT)

            var count = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                count += 1
            }

            XCTAssertGreaterThan(count, 0, "Should find search results")
        }
    }

    // MARK: - Timeline Rendering Performance Tests

    /// Test: TimelineStore segment loading performance
    /// Target: <50ms for loading 100 segments
    func testTimelineStoreLoadingPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let store = TimelineStore(dbPath: tempDatabasePath.path, baseDir: tempBaseDir, autoRefresh: false)

            // Wait for async loading to complete
            let expectation = XCTestExpectation(description: "Segments loaded")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                XCTAssertEqual(store.segments.count, 100, "Should load all 100 segments")
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }
    }

    /// Test: Time-to-segment mapping performance
    /// Target: <16ms for 60fps operations (should be much faster, aim for <1ms)
    func testTimeToSegmentMappingPerformance() {
        let store = TimelineStore(dbPath: tempDatabasePath.path, baseDir: tempBaseDir, autoRefresh: false)

        // Wait for segments to load
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        measure(metrics: [XCTClockMetric()]) {
            // Perform multiple lookups to simulate timeline scrubbing
            for _ in 0..<100 {
                let randomTime = 1704067200.0 + Double.random(in: 0...12000)
                let _ = store.segment(for: randomTime)
            }
        }
    }

    /// Test: Segment video offset calculation performance
    /// Target: <1ms per calculation for smooth scrubbing
    func testSegmentVideoOffsetCalculationPerformance() {
        let segment = Segment(
            id: "test",
            startTS: 1704067200.0,
            endTS: 1704067320.0,
            frameCount: 300,
            fps: 5.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        measure(metrics: [XCTClockMetric()]) {
            // Perform many offset calculations to simulate scrubbing
            for i in 0..<1000 {
                let time = segment.startTS + Double(i) * 0.12
                let _ = segment.videoOffset(forAbsoluteTime: time)
            }
        }
    }

    /// Test: Segment absolute time calculation performance
    /// Target: <1ms per calculation for timeline updates
    func testSegmentAbsoluteTimeCalculationPerformance() {
        let segment = Segment(
            id: "test",
            startTS: 1704067200.0,
            endTS: 1704067320.0,
            frameCount: 300,
            fps: 5.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        measure(metrics: [XCTClockMetric()]) {
            // Perform many absolute time calculations
            for i in 0..<1000 {
                let offset = Double(i) * 0.06
                let _ = segment.absoluteTime(forVideoOffset: offset)
            }
        }
    }

    // MARK: - Configuration Loading Performance Tests

    /// Test: ConfigManager initialization performance
    /// Target: <50ms for config load
    func testConfigManagerInitializationPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let manager = ConfigManager(configPath: tempConfigPath, enableWatcher: false)
            XCTAssertNotNil(manager.config, "Config should be loaded")
        }
    }

    /// Test: Config file parsing performance
    /// Target: <30ms for JSON parsing
    func testConfigFileParsingPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            do {
                let data = try Data(contentsOf: tempConfigPath)
                let decoder = JSONDecoder()
                let config = try decoder.decode(Config.self, from: data)
                XCTAssertNotNil(config, "Config should be parsed")
            } catch {
                XCTFail("Config parsing failed: \(error)")
            }
        }
    }

    /// Test: Config validation performance
    /// Target: <10ms for validation
    func testConfigValidationPerformance() {
        let manager = ConfigManager(configPath: tempConfigPath, enableWatcher: false)
        let config = manager.config

        measure(metrics: [XCTClockMetric()]) {
            let _ = config.validated()
        }
    }

    // MARK: - Path Resolution Performance Tests

    /// Test: Environment-aware path resolution performance
    /// Target: <10ms for path operations
    func testPathResolutionPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            // Perform multiple path resolutions
            for _ in 0..<100 {
                let _ = Paths.baseDataDirectory
                let _ = Paths.databasePath
                let _ = Paths.chunksDirectory
                let _ = Paths.configPath()
                let _ = Paths.timelineOpenSignalPath
            }
        }
    }

    /// Test: Directory creation performance
    /// Target: <50ms for creating directory structure
    func testDirectoryCreationPerformance() {
        let tempTestDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathPerformanceTest")
            .appendingPathComponent(UUID().uuidString)

        measure(metrics: [XCTClockMetric(), XCTStorageMetric()]) {
            do {
                try FileManager.default.createDirectory(
                    at: tempTestDir.appendingPathComponent("data/chunks"),
                    withIntermediateDirectories: true
                )
                try FileManager.default.createDirectory(
                    at: tempTestDir.appendingPathComponent("data/temp"),
                    withIntermediateDirectories: true
                )
            } catch {
                XCTFail("Directory creation failed: \(error)")
            }
        }

        try? FileManager.default.removeItem(at: tempTestDir.deletingLastPathComponent())
    }

    /// Test: File existence checks performance
    /// Target: <5ms for batch file checks
    func testFileExistenceChecksPerformance() {
        let fileManager = FileManager.default
        let paths = [
            tempDatabasePath,
            tempConfigPath,
            tempBaseDir,
            tempDirectory
        ]

        measure(metrics: [XCTClockMetric()]) {
            for _ in 0..<100 {
                for path in paths {
                    let _ = fileManager.fileExists(atPath: path?.path ?? "")
                }
            }
        }
    }

    // MARK: - Search Performance Tests

    /// Test: Search query execution performance (direct SQL)
    /// Target: <200ms for search queries
    func testSearchControllerQueryPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            var db: OpaquePointer?
            guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
                XCTFail("Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            let query = """
                SELECT o.id, o.text_content, o.timestamp, o.segment_id, o.confidence
                FROM ocr_text o
                JOIN ocr_search s ON o.id = s.rowid
                WHERE s.text_content MATCH ?
                AND o.confidence >= ?
                ORDER BY o.timestamp DESC
                LIMIT 100
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                XCTFail("Failed to prepare statement")
                return
            }
            defer { sqlite3_finalize(statement) }

            let searchQuery = "performance"
            sqlite3_bind_text(statement, 1, (searchQuery as NSString).utf8String, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 2, 0.5)

            var count = 0
            while sqlite3_step(statement) == SQLITE_ROW {
                count += 1
            }

            XCTAssertGreaterThan(count, 0, "Should find search results")
        }
    }

    /// Test: Search result caching performance (simulated with repeated queries)
    /// Target: <50ms for repeated identical queries (SQLite query cache)
    func testSearchResultCachingPerformance() {
        measure(metrics: [XCTClockMetric()]) {
            var db: OpaquePointer?
            guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
                XCTFail("Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            let query = """
                SELECT o.id, o.text_content, o.timestamp, o.segment_id
                FROM ocr_text o
                JOIN ocr_search s ON o.id = s.rowid
                WHERE s.text_content MATCH ?
                LIMIT 50
            """

            // Execute the same query multiple times to test SQLite caching
            for _ in 0..<5 {
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                    continue
                }

                let searchQuery = "documentation"
                sqlite3_bind_text(statement, 1, (searchQuery as NSString).utf8String, -1, SQLITE_TRANSIENT)

                var count = 0
                while sqlite3_step(statement) == SQLITE_ROW {
                    count += 1
                }
                sqlite3_finalize(statement)
            }
        }
    }

    /// Test: Search result navigation performance (array indexing)
    /// Target: <5ms for result navigation
    func testSearchResultNavigationPerformance() {
        var db: OpaquePointer?
        guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
            XCTFail("Failed to open database")
            return
        }
        defer { sqlite3_close(db) }

        // Fetch results once
        let query = """
            SELECT o.id, o.timestamp FROM ocr_text o
            JOIN ocr_search s ON o.id = s.rowid
            WHERE s.text_content MATCH 'performance'
            LIMIT 100
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            XCTFail("Failed to prepare statement")
            return
        }
        defer { sqlite3_finalize(statement) }

        var results: [(Int, Double)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(statement, 0))
            let timestamp = sqlite3_column_double(statement, 1)
            results.append((id, timestamp))
        }

        // Measure navigation through results
        measure(metrics: [XCTClockMetric()]) {
            var currentIndex = 0
            for _ in 0..<100 {
                currentIndex = (currentIndex + 1) % results.count
                let _ = results[currentIndex]
            }
            for _ in 0..<100 {
                currentIndex = (currentIndex - 1 + results.count) % results.count
                let _ = results[currentIndex]
            }
        }
    }

    // MARK: - Composite Performance Tests

    /// Test: Full timeline initialization performance
    /// Target: <200ms for complete timeline setup
    func testFullTimelineInitializationPerformance() {
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()]) {
            let store = TimelineStore(dbPath: tempDatabasePath.path, baseDir: tempBaseDir, autoRefresh: false)

            // Wait for loading
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

            XCTAssertGreaterThan(store.segments.count, 0, "Timeline should have segments")
            XCTAssertNotNil(store.timelineStart, "Timeline should have start time")
            XCTAssertNotNil(store.timelineEnd, "Timeline should have end time")
        }
    }

    /// Test: Search with timeline integration performance
    /// Target: <250ms for search + navigation
    func testSearchWithTimelineIntegrationPerformance() {
        let store = TimelineStore(dbPath: tempDatabasePath.path, baseDir: tempBaseDir, autoRefresh: false)

        // Wait for segments to load
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

        measure(metrics: [XCTClockMetric()]) {
            var db: OpaquePointer?
            guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
                XCTFail("Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            // Perform search
            let query = """
                SELECT o.timestamp FROM ocr_text o
                JOIN ocr_search s ON o.id = s.rowid
                WHERE s.text_content MATCH ?
                LIMIT 1
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                XCTFail("Failed to prepare statement")
                return
            }
            defer { sqlite3_finalize(statement) }

            let searchQuery = "optimization"
            sqlite3_bind_text(statement, 1, (searchQuery as NSString).utf8String, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_ROW {
                let timestamp = sqlite3_column_double(statement, 0)
                // Navigate to segment containing this timestamp
                let _ = store.segment(for: timestamp)
            }
        }
    }

    // MARK: - Memory Performance Tests

    /// Test: Memory usage for large segment loads
    /// Target: <50MB for 100 segments
    func testLargeSegmentLoadMemoryUsage() {
        measure(metrics: [XCTMemoryMetric()]) {
            let store = TimelineStore(dbPath: tempDatabasePath.path, baseDir: tempBaseDir, autoRefresh: false)

            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

            XCTAssertEqual(store.segments.count, 100, "Should load all segments")
        }
    }

    /// Test: Memory usage for search results
    /// Target: <10MB for 100 search results
    func testSearchResultsMemoryUsage() {
        measure(metrics: [XCTMemoryMetric()]) {
            var db: OpaquePointer?
            guard sqlite3_open(tempDatabasePath.path, &db) == SQLITE_OK else {
                XCTFail("Failed to open database")
                return
            }
            defer { sqlite3_close(db) }

            let query = """
                SELECT o.id, o.text_content, o.timestamp, o.segment_id, o.confidence
                FROM ocr_text o
                JOIN ocr_search s ON o.id = s.rowid
                WHERE s.text_content MATCH ?
                LIMIT 100
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
                XCTFail("Failed to prepare statement")
                return
            }
            defer { sqlite3_finalize(statement) }

            let searchQuery = "test"
            sqlite3_bind_text(statement, 1, (searchQuery as NSString).utf8String, -1, SQLITE_TRANSIENT)

            var results: [(Int, String, Double, String?, Double)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = Int(sqlite3_column_int64(statement, 0))
                let text = String(cString: sqlite3_column_text(statement, 1))
                let timestamp = sqlite3_column_double(statement, 2)
                let segmentIdPtr = sqlite3_column_text(statement, 3)
                let segmentId = segmentIdPtr != nil ? String(cString: segmentIdPtr!) : nil
                let confidence = sqlite3_column_double(statement, 4)
                results.append((id, text, timestamp, segmentId, confidence))
            }

            XCTAssertGreaterThan(results.count, 0, "Should have results")
        }
    }

}
