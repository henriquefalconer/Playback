import XCTest

/// Base UI test case for Playback UI tests
final class PlaybackUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.exists, "App should launch successfully")
    }
}
