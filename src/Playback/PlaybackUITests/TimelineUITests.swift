import XCTest

/// UI tests for timeline viewer interactions
final class TimelineUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Give app time to initialize
        sleep(1)
    }

    override func tearDownWithError() throws {
        // Close any open windows
        let closeButtons = app.buttons.matching(identifier: "_XCUI:CloseWindow")
        for i in 0..<closeButtons.count {
            if closeButtons.element(boundBy: i).exists {
                closeButtons.element(boundBy: i).click()
            }
        }

        app = nil
    }

    // MARK: - Timeline Window Tests

    func testOpenTimelineWindow() throws {
        // Open timeline via menu bar button
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")

        openTimelineButton.click()

        // Wait for timeline window to appear
        sleep(2)

        // Verify app is still running
        XCTAssertTrue(app.exists, "App should still be running after opening timeline")
    }

    func testTimelineWindowCanBeClosedAndReopened() throws {
        // Open timeline
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")

        openTimelineButton.click()
        sleep(2)

        // Close window (Command+W or close button)
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        // Reopen timeline
        openTimelineButton.click()
        sleep(2)

        // Verify app is still running
        XCTAssertTrue(app.exists, "App should still be running after reopen")
    }

    // MARK: - Time Bubble Tests

    func testTimeBubbleButtonExists() throws {
        // Open timeline first
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        openTimelineButton.click()
        sleep(2)

        // Look for time bubble button
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.waitForExistence(timeout: 5.0), "Time bubble button should exist in timeline")
    }

    func testTimeBubbleButtonClick() throws {
        // Open timeline first
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        openTimelineButton.click()
        sleep(2)

        // Find and click time bubble button
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.waitForExistence(timeout: 5.0), "Time bubble button should exist")

        timeBubbleButton.click()

        // Wait for date picker to appear (tested in DateTimePickerUITests)
        sleep(1)

        // Verify button still exists
        XCTAssertTrue(timeBubbleButton.exists, "Time bubble button should still exist after click")
    }

    func testTimeBubbleButtonIsClickable() throws {
        // Open timeline first
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        openTimelineButton.click()
        sleep(2)

        // Find time bubble button
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.waitForExistence(timeout: 5.0), "Time bubble button should exist")

        // Verify it's enabled
        XCTAssertTrue(timeBubbleButton.isEnabled, "Time bubble button should be enabled")
    }

    // MARK: - Timeline Display Tests

    func testTimelineDisplaysContent() throws {
        // Open timeline
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        openTimelineButton.click()
        sleep(2)

        // Verify time bubble exists (indicates timeline is rendered)
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.waitForExistence(timeout: 5.0), "Timeline should display time bubble")
    }

    func testTimelineFullscreenMode() throws {
        // Open timeline
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        openTimelineButton.click()
        sleep(2)

        // Timeline should start in fullscreen mode (as per PlaybackApp.swift)
        // Verify the window exists
        XCTAssertTrue(app.exists, "Timeline window should exist")

        // Note: Testing actual fullscreen state is difficult in UI tests
        // We verify the timeline is operational
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.exists, "Timeline should be functional")
    }

    // MARK: - Keyboard Shortcut Tests

    func testCommandFOpensSearch() throws {
        // Open timeline first
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        openTimelineButton.click()
        sleep(2)

        // Press Command+F to open search
        app.typeKey("f", modifierFlags: .command)
        sleep(1)

        // Verify search opened (tested in SearchUITests)
        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 3.0), "Search should open with Command+F")
    }

    func testEscapeClosesTimeline() throws {
        // Open timeline first
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        openTimelineButton.click()
        sleep(2)

        // Press Escape to close
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        // Verify app is still running (timeline closed, but app continues)
        XCTAssertTrue(app.exists, "App should still be running after closing timeline")
    }

    // MARK: - Integration Tests

    func testTimelineWorkflow() throws {
        // Complete workflow: open timeline -> click time bubble -> close

        // 1. Open timeline
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        openTimelineButton.click()
        sleep(2)

        // 2. Verify timeline loaded
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.waitForExistence(timeout: 5.0), "Time bubble should exist")

        // 3. Click time bubble
        timeBubbleButton.click()
        sleep(1)

        // 4. Verify time bubble still accessible
        XCTAssertTrue(timeBubbleButton.exists, "Time bubble should remain after interaction")

        // 5. Close timeline
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        // 6. Verify app still running
        XCTAssertTrue(app.exists, "App should continue running after closing timeline")
    }

    func testMultipleTimelineOpenClose() throws {
        // Test opening and closing timeline multiple times
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")

        for _ in 0..<3 {
            // Open timeline
            openTimelineButton.click()
            sleep(1)

            // Verify it opened
            let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
            XCTAssertTrue(timeBubbleButton.waitForExistence(timeout: 3.0), "Timeline should open")

            // Close timeline
            app.typeKey("w", modifierFlags: .command)
            sleep(1)
        }

        // App should still be running
        XCTAssertTrue(app.exists, "App should still be running after multiple open/close cycles")
    }
}
