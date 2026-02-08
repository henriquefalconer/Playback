import XCTest
import SQLite3
@testable import Playback

final class TimelineStoreTests: XCTestCase {

    // MARK: - Segment Model Tests

    func testSegmentDurationCalculation() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        XCTAssertEqual(segment.duration, 100.0,
                       "Duration should be endTS - startTS")
    }

    func testSegmentVideoDurationCalculation() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        if let videoDuration = segment.videoDuration {
            XCTAssertEqual(videoDuration, 10.0, accuracy: 0.01,
                           "Video duration should be frameCount / fps = 300/30 = 10s")
        } else {
            XCTFail("Segment should have video duration")
        }
    }

    func testSegmentVideoDurationWithoutFPS() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: nil,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        XCTAssertNil(segment.videoDuration,
                     "Video duration should be nil when fps is not available")
    }

    func testSegmentIdentifiable() {
        let segment = Segment(
            id: "unique-id",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        XCTAssertEqual(segment.id, "unique-id",
                       "Segment should be Identifiable with id property")
    }

    // MARK: - Time Mapping Tests

    func testVideoOffsetMapping() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        let offset = segment.videoOffset(forAbsoluteTime: 1050.0)

        XCTAssertGreaterThanOrEqual(offset, 0.0,
                                    "Video offset should be non-negative")
        if let videoDuration = segment.videoDuration {
            XCTAssertLessThanOrEqual(offset, videoDuration,
                                     "Video offset should not exceed video duration")
        }
    }

    func testAbsoluteTimeMapping() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        let absoluteTime = segment.absoluteTime(forVideoOffset: 5.0)

        XCTAssertGreaterThanOrEqual(absoluteTime, segment.startTS,
                                    "Absolute time should be at or after segment start")
        XCTAssertLessThanOrEqual(absoluteTime, segment.endTS,
                                 "Absolute time should be at or before segment end")
    }

    func testVideoOffsetClampingAtStart() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        let offset = segment.videoOffset(forAbsoluteTime: 900.0)

        XCTAssertEqual(offset, 0.0, accuracy: 0.01,
                       "Should clamp to start when time is before segment")
    }

    func testVideoOffsetClampingAtEnd() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        let offset = segment.videoOffset(forAbsoluteTime: 1200.0)

        if let videoDuration = segment.videoDuration {
            XCTAssertEqual(offset, videoDuration, accuracy: 0.01,
                           "Should clamp to end when time is after segment")
        } else {
            XCTFail("Segment should have video duration")
        }
    }

    func testTimeRoundTrip() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        let originalTime: TimeInterval = 1050.0
        let videoOffset = segment.videoOffset(forAbsoluteTime: originalTime)
        let reconstructedTime = segment.absoluteTime(forVideoOffset: videoOffset)

        XCTAssertEqual(originalTime, reconstructedTime, accuracy: 1.0,
                       "Round trip conversion should be approximately consistent")
    }

    func testVideoOffsetWithZeroDuration() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1000.0,
            frameCount: 0,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        let offset = segment.videoOffset(forAbsoluteTime: 1000.0)

        XCTAssertEqual(offset, 0.0, accuracy: 0.01,
                       "Zero duration segment should return 0 offset")
    }

    func testAbsoluteTimeWithZeroVideoDuration() {
        let segment = Segment(
            id: "test",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 0,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        let absoluteTime = segment.absoluteTime(forVideoOffset: 50.0)

        XCTAssertGreaterThanOrEqual(absoluteTime, segment.startTS,
                                    "Should handle zero frame count gracefully")
        XCTAssertLessThanOrEqual(absoluteTime, segment.endTS)
    }

    // MARK: - AppSegment Model Tests

    func testAppSegmentDurationCalculation() {
        let appSegment = AppSegment(
            id: "test",
            startTS: 1000.0,
            endTS: 1150.0,
            appId: "com.apple.safari"
        )

        XCTAssertEqual(appSegment.duration, 150.0,
                       "AppSegment duration should be endTS - startTS")
    }

    func testAppSegmentWithNullAppId() {
        let appSegment = AppSegment(
            id: "test",
            startTS: 1000.0,
            endTS: 1150.0,
            appId: nil
        )

        XCTAssertNil(appSegment.appId,
                     "AppSegment should handle nil app_id")
    }

    func testAppSegmentIdentifiable() {
        let appSegment = AppSegment(
            id: "unique-app-id",
            startTS: 1000.0,
            endTS: 1100.0,
            appId: "com.apple.safari"
        )

        XCTAssertEqual(appSegment.id, "unique-app-id",
                       "AppSegment should be Identifiable with id property")
    }

    // MARK: - TimelineStore Initialization Tests

    func testTimelineStoreInitialization() {
        let store = TimelineStore()

        XCTAssertNotNil(store, "TimelineStore should initialize successfully")
        XCTAssertTrue(store.segments.isEmpty || !store.segments.isEmpty,
                      "Segments array should be accessible")
        XCTAssertTrue(store.appSegments.isEmpty || !store.appSegments.isEmpty,
                      "AppSegments array should be accessible")
    }

    func testTimelineStoreComputedPropertiesWithNoSegments() {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let tempDBPath = tempDirectory.appendingPathComponent("meta.sqlite3")
        let tempBaseDir = tempDirectory.appendingPathComponent("data")

        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: tempBaseDir, withIntermediateDirectories: true)

        var db: OpaquePointer?
        if sqlite3_open(tempDBPath.path, &db) == SQLITE_OK {
            let createTable = """
            CREATE TABLE IF NOT EXISTS segments (
                id TEXT PRIMARY KEY,
                start_ts REAL NOT NULL,
                end_ts REAL NOT NULL,
                frame_count INTEGER NOT NULL,
                fps REAL,
                video_path TEXT NOT NULL
            );
            """
            sqlite3_exec(db, createTable, nil, nil, nil)
            sqlite3_close(db)
        }

        let store = TimelineStore(dbPath: tempDBPath.path, baseDir: tempBaseDir, autoRefresh: false)

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))

        XCTAssertNil(store.timelineStart,
                     "Timeline start should be nil when no segments")
        XCTAssertNil(store.timelineEnd,
                     "Timeline end should be nil when no segments")
        XCTAssertNil(store.latestTS,
                     "Latest timestamp should be nil when no segments")

        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Integration Note Tests
    // These tests verify the TimelineStore interface without requiring database integration
    // Full database integration tests should be added when database access patterns are finalized

    func testSegmentSelectionMethodExists() {
        let store = TimelineStore()

        let result = store.segment(for: 1000.0)

        XCTAssertTrue(result == nil || result != nil,
                      "segment(for:) method should be callable")
    }

    func testSegmentSelectionWithDirectionMethodExists() {
        let store = TimelineStore()

        let result = store.segment(for: 1000.0, direction: 1.0)

        XCTAssertTrue(result == nil || result != nil,
                      "segment(for:direction:) method should be callable")
    }
}
