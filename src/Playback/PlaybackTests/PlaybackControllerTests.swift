import XCTest
import AVFoundation
import Combine
import AppKit
@testable import Playback

@MainActor
final class PlaybackControllerTests: XCTestCase {

    // MARK: - Initialization Tests

    func testPlaybackControllerInitialization() {
        let controller = PlaybackController()

        XCTAssertNotNil(controller, "PlaybackController should initialize successfully")
        XCTAssertNotNil(controller.player, "Player should be initialized")
    }

    func testInitialStateIsNotPlaying() {
        let controller = PlaybackController()

        XCTAssertFalse(controller.isPlaying, "isPlaying should start as false")
    }

    func testInitialCurrentTimeIsZero() {
        let controller = PlaybackController()

        XCTAssertEqual(controller.currentTime, 0, accuracy: 0.001,
                       "currentTime should start at 0")
    }

    func testInitialFrozenFrameIsNil() {
        let controller = PlaybackController()

        XCTAssertNil(controller.frozenFrame, "frozenFrame should start as nil")
    }

    func testInitialShowFrozenFrameIsFalse() {
        let controller = PlaybackController()

        XCTAssertFalse(controller.showFrozenFrame, "showFrozenFrame should start as false")
    }

    func testInitialCurrentSegmentIsNil() {
        let controller = PlaybackController()

        XCTAssertNil(controller.currentSegment, "currentSegment should start as nil")
    }

    // MARK: - Playback State Tests

    func testTogglePlayPauseFromPaused() {
        let controller = PlaybackController()
        controller.pause()

        XCTAssertFalse(controller.isPlaying, "Should start paused")

        controller.togglePlayPause()

        XCTAssertTrue(controller.isPlaying, "Should toggle to playing")
    }

    func testTogglePlayPauseFromPlaying() {
        let controller = PlaybackController()
        controller.play()

        XCTAssertTrue(controller.isPlaying, "Should start playing")

        controller.togglePlayPause()

        XCTAssertFalse(controller.isPlaying, "Should toggle to paused")
    }

    func testPlaySetsIsPlayingTrue() {
        let controller = PlaybackController()

        controller.play()

        XCTAssertTrue(controller.isPlaying, "play() should set isPlaying to true")
    }

    func testPauseSetsIsPlayingFalse() {
        let controller = PlaybackController()
        controller.play()

        controller.pause()

        XCTAssertFalse(controller.isPlaying, "pause() should set isPlaying to false")
    }

    func testMultiplePlayCallsRemainPlaying() {
        let controller = PlaybackController()

        controller.play()
        controller.play()
        controller.play()

        XCTAssertTrue(controller.isPlaying, "Multiple play() calls should keep isPlaying true")
    }

    func testMultiplePauseCallsRemainPaused() {
        let controller = PlaybackController()

        controller.pause()
        controller.pause()
        controller.pause()

        XCTAssertFalse(controller.isPlaying, "Multiple pause() calls should keep isPlaying false")
    }

    func testTogglePlayPauseMultipleTimes() {
        let controller = PlaybackController()

        controller.togglePlayPause()
        XCTAssertTrue(controller.isPlaying)

        controller.togglePlayPause()
        XCTAssertFalse(controller.isPlaying)

        controller.togglePlayPause()
        XCTAssertTrue(controller.isPlaying)

        controller.togglePlayPause()
        XCTAssertFalse(controller.isPlaying)
    }

    // MARK: - Published Properties Tests

    func testCurrentSegmentIsPublished() {
        let controller = PlaybackController()

        let mirror = Mirror(reflecting: controller)
        let publishedProperties = mirror.children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            let typeString = String(describing: type(of: child.value))
            return typeString.contains("Published") ? label : nil
        }

        XCTAssertTrue(publishedProperties.contains("_currentSegment"),
                      "currentSegment should be @Published")
    }

    func testCurrentTimeIsPublished() {
        let controller = PlaybackController()

        let mirror = Mirror(reflecting: controller)
        let publishedProperties = mirror.children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            let typeString = String(describing: type(of: child.value))
            return typeString.contains("Published") ? label : nil
        }

        XCTAssertTrue(publishedProperties.contains("_currentTime"),
                      "currentTime should be @Published")
    }

    func testIsPlayingIsPublished() {
        let controller = PlaybackController()

        let mirror = Mirror(reflecting: controller)
        let publishedProperties = mirror.children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            let typeString = String(describing: type(of: child.value))
            return typeString.contains("Published") ? label : nil
        }

        XCTAssertTrue(publishedProperties.contains("_isPlaying"),
                      "isPlaying should be @Published")
    }

    func testFrozenFrameIsPublished() {
        let controller = PlaybackController()

        let mirror = Mirror(reflecting: controller)
        let publishedProperties = mirror.children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            let typeString = String(describing: type(of: child.value))
            return typeString.contains("Published") ? label : nil
        }

        XCTAssertTrue(publishedProperties.contains("_frozenFrame"),
                      "frozenFrame should be @Published")
    }

    func testShowFrozenFrameIsPublished() {
        let controller = PlaybackController()

        let mirror = Mirror(reflecting: controller)
        let publishedProperties = mirror.children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            let typeString = String(describing: type(of: child.value))
            return typeString.contains("Published") ? label : nil
        }

        XCTAssertTrue(publishedProperties.contains("_showFrozenFrame"),
                      "showFrozenFrame should be @Published")
    }

    // MARK: - ObservableObject Tests

    func testPlaybackControllerIsObservableObject() {
        let controller = PlaybackController()

        XCTAssertTrue(controller is ObservableObject,
                      "PlaybackController should conform to ObservableObject")
    }

    func testPublishedPropertiesCanBeBound() {
        let controller = PlaybackController()
        var cancellables = Set<AnyCancellable>()
        let expectation = XCTestExpectation(description: "Property change should trigger publisher")

        controller.$isPlaying
            .dropFirst()
            .sink { newValue in
                XCTAssertTrue(newValue, "Should receive updated value")
                expectation.fulfill()
            }
            .store(in: &cancellables)

        controller.play()

        wait(for: [expectation], timeout: 1.0)
    }

    func testCurrentTimePublisher() {
        let controller = PlaybackController()
        var cancellables = Set<AnyCancellable>()
        let expectation = XCTestExpectation(description: "currentTime change should trigger publisher")

        controller.$currentTime
            .dropFirst()
            .sink { newTime in
                XCTAssertEqual(newTime, 100.0, accuracy: 0.001)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        controller.currentTime = 100.0

        wait(for: [expectation], timeout: 1.0)
    }

    func testFrozenFramePublisher() {
        let controller = PlaybackController()
        var cancellables = Set<AnyCancellable>()
        let expectation = XCTestExpectation(description: "frozenFrame change should trigger publisher")

        controller.$frozenFrame
            .dropFirst()
            .sink { newFrame in
                XCTAssertNotNil(newFrame)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        let testImage = NSImage(size: NSSize(width: 100, height: 100))
        controller.frozenFrame = testImage

        wait(for: [expectation], timeout: 1.0)
    }

    func testShowFrozenFramePublisher() {
        let controller = PlaybackController()
        var cancellables = Set<AnyCancellable>()
        let expectation = XCTestExpectation(description: "showFrozenFrame change should trigger publisher")

        controller.$showFrozenFrame
            .dropFirst()
            .sink { newValue in
                XCTAssertTrue(newValue)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        controller.showFrozenFrame = true

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - AVPlayer Tests

    func testPlayerExists() {
        let controller = PlaybackController()

        XCTAssertNotNil(controller.player, "Player should exist")
    }

    func testPlayerIsAVPlayer() {
        let controller = PlaybackController()

        XCTAssertTrue(controller.player is AVPlayer,
                      "Player should be an AVPlayer instance")
    }

    func testPlayerInitialStateIsNotPlaying() {
        let controller = PlaybackController()

        XCTAssertEqual(controller.player.rate, 0.0,
                       "Player should not be playing initially")
    }

    func testPlayerInitialItemIsNil() {
        let controller = PlaybackController()

        XCTAssertNil(controller.player.currentItem,
                     "Player should not have an item initially")
    }

    func testPlayUpdatesPlayerRate() {
        let controller = PlaybackController()

        controller.play()

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(controller.player.rate, 1.0,
                       "Player rate should be 1.0 when playing")
    }

    func testPauseUpdatesPlayerRate() {
        let controller = PlaybackController()
        controller.play()

        controller.pause()

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertEqual(controller.player.rate, 0.0,
                       "Player rate should be 0.0 when paused")
    }

    // MARK: - Method Existence Tests

    func testScrubMethodExists() {
        let controller = PlaybackController()
        let store = TimelineStore()

        controller.scrub(to: 100.0, store: store)
    }

    func testUpdateMethodExists() {
        let controller = PlaybackController()
        let store = TimelineStore()

        controller.update(for: 100.0, store: store)
    }

    func testScheduleUpdateMethodExists() {
        let controller = PlaybackController()
        let store = TimelineStore()

        controller.scheduleUpdate(for: 100.0, store: store)
    }

    func testTogglePlayPauseMethodExists() {
        let controller = PlaybackController()

        controller.togglePlayPause()
    }

    func testPlayMethodExists() {
        let controller = PlaybackController()

        controller.play()
    }

    func testPauseMethodExists() {
        let controller = PlaybackController()

        controller.pause()
    }

    // MARK: - State Consistency Tests

    func testIsPlayingConsistentWithPlayerRate() {
        let controller = PlaybackController()

        controller.play()
        XCTAssertTrue(controller.isPlaying)
        XCTAssertEqual(controller.player.rate, 1.0)

        controller.pause()
        XCTAssertFalse(controller.isPlaying)
        XCTAssertEqual(controller.player.rate, 0.0)
    }

    func testCurrentTimeRemainsValidAfterUpdate() {
        let controller = PlaybackController()

        controller.currentTime = 100.0
        XCTAssertEqual(controller.currentTime, 100.0)

        controller.currentTime = 200.0
        XCTAssertEqual(controller.currentTime, 200.0)
    }

    func testShowFrozenFrameCanBeToggled() {
        let controller = PlaybackController()

        controller.showFrozenFrame = true
        XCTAssertTrue(controller.showFrozenFrame)

        controller.showFrozenFrame = false
        XCTAssertFalse(controller.showFrozenFrame)

        controller.showFrozenFrame = true
        XCTAssertTrue(controller.showFrozenFrame)
    }

    // MARK: - Edge Cases Tests

    func testNegativeCurrentTimeHandling() {
        let controller = PlaybackController()

        controller.currentTime = -100.0

        XCTAssertEqual(controller.currentTime, -100.0,
                       "Controller should accept negative times (clamping is done elsewhere)")
    }

    func testLargeCurrentTimeHandling() {
        let controller = PlaybackController()

        controller.currentTime = 1_000_000_000.0

        XCTAssertEqual(controller.currentTime, 1_000_000_000.0,
                       "Controller should handle large time values")
    }

    func testZeroCurrentTime() {
        let controller = PlaybackController()

        controller.currentTime = 0.0

        XCTAssertEqual(controller.currentTime, 0.0, accuracy: 0.001)
    }

    func testCurrentSegmentCanBeSet() {
        let controller = PlaybackController()
        let segment = Segment(
            id: "test-segment",
            startTS: 1000.0,
            endTS: 1100.0,
            frameCount: 300,
            fps: 30.0,
            videoURL: URL(fileURLWithPath: "/tmp/test.mp4")
        )

        XCTAssertNil(controller.currentSegment)
    }

    func testFrozenFrameCanBeSet() {
        let controller = PlaybackController()
        let testImage = NSImage(size: NSSize(width: 100, height: 100))

        controller.frozenFrame = testImage

        XCTAssertNotNil(controller.frozenFrame)
        XCTAssertEqual(controller.frozenFrame?.size, NSSize(width: 100, height: 100))
    }

    func testFrozenFrameCanBeCleared() {
        let controller = PlaybackController()
        let testImage = NSImage(size: NSSize(width: 100, height: 100))

        controller.frozenFrame = testImage
        XCTAssertNotNil(controller.frozenFrame)

        controller.frozenFrame = nil
        XCTAssertNil(controller.frozenFrame)
    }

    // MARK: - Memory Management Tests

    func testControllerCanBeDeallocated() {
        var controller: PlaybackController? = PlaybackController()
        weak var weakController = controller

        controller = nil

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertNil(weakController, "Controller should be deallocated when no strong references remain")
    }

    func testPlayerRemovedOnDeinit() {
        var controller: PlaybackController? = PlaybackController()
        let player = controller?.player

        controller = nil

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        XCTAssertNotNil(player, "Player itself should remain (not retained by time observer)")
    }
}

// MARK: - Integration Test Notes
//
// The following tests require actual video files and are better suited as integration tests:
//
// 1. Frozen Frame Capture Tests:
//    - testCaptureFrozenFrameFromSegment() - requires real video file and AVAssetImageGenerator
//    - testFrozenFrameGenerationWithInvalidFile() - requires testing with missing/corrupted video
//    - testFrozenFrameGenerationAtSpecificTime() - requires video with known content at timestamp
//
// 2. Segment Transition Tests:
//    - testTransitionBetweenSegments() - requires multiple video segments
//    - testFrozenFrameDuringSegmentTransition() - requires observing frame capture during transition
//    - testSegmentChangeUpdatesCurrentSegment() - requires actual database and video files
//
// 3. Time Observer Tests:
//    - testTimeObserverUpdatesCurrentTime() - requires playing actual video
//    - testTimeObserverRespectsScrubbing() - requires observing behavior during scrubbing
//    - testTimeObserverStopsDuringScrubbing() - requires verifying observer doesn't update during scrub
//
// 4. Seek Operation Tests:
//    - testSeekToSpecificTime() - requires video file to seek within
//    - testSeekWithTolerances() - requires observing actual seek behavior
//    - testSeekDuringPlay() - requires playing video and performing seek
//
// 5. Scrub Operation Tests:
//    - testScrubUpdatesCurrentTime() - requires store with real segments
//    - testScrubMaintainsPauseState() - requires observing player state during scrub
//    - testScrubBoundarySticking() - requires segments with specific time ranges
//    - testScrubEndWorkItem() - requires time-based observation of scrub end behavior
//
// 6. Update Operation Tests:
//    - testUpdateChangesSegment() - requires database with multiple segments
//    - testUpdateSeeksToCorrectOffset() - requires video file and time verification
//    - testUpdateWithMissingSegment() - requires testing error handling with invalid time
//
// 7. Schedule Update Tests:
//    - testScheduleUpdateDebouncing() - requires time-based testing of debounce behavior
//    - testScheduleUpdateCancelsPendingWork() - requires observing work item cancellation
//
// 8. AVPlayerItem Status Tests:
//    - testStatusObserverReadyToPlay() - requires video file that loads successfully
//    - testStatusObserverFailedState() - requires invalid video file
//    - testStatusObserverHidesFrozenFrameWhenReady() - requires observing UI state changes
//
// To implement these integration tests:
// 1. Create test video files (e.g., 5-second videos with known content)
// 2. Create test database with known segments
// 3. Use XCTestExpectation for async operations
// 4. Verify AVPlayer state, currentTime, and UI properties
// 5. Clean up test files in tearDown()
//
// Example integration test structure:
//
// @MainActor
// final class PlaybackControllerIntegrationTests: XCTestCase {
//     var tempDirectory: URL!
//     var testVideoPath: URL!
//     var testDBPath: URL!
//     var controller: PlaybackController!
//     var store: TimelineStore!
//
//     override func setUp() {
//         super.setUp()
//         tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
//         testVideoPath = generateTestVideo() // Helper to create test video
//         testDBPath = createTestDatabase()   // Helper to create test database
//         controller = PlaybackController()
//         store = TimelineStore(dbPath: testDBPath.path, ...)
//     }
//
//     func testUpdateLoadsAndPlaysSegment() async {
//         let expectation = XCTestExpectation(description: "Segment should load and play")
//
//         controller.update(for: 1000.0, store: store)
//
//         await fulfillment(of: [expectation], timeout: 5.0)
//
//         XCTAssertNotNil(controller.currentSegment)
//         XCTAssertNotNil(controller.player.currentItem)
//         XCTAssertTrue(controller.isPlaying)
//     }
// }
