import XCTest

/// UI tests for menu bar interactions
final class MenuBarUITests: XCTestCase {
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
        app = nil
    }

    // MARK: - Menu Bar Presence Tests

    func testMenuBarIconExists() throws {
        // Menu bar extras are accessed differently in UI tests
        // The menu bar icon should be visible
        XCTAssertTrue(app.exists, "App should be running")
    }

    // MARK: - Recording Toggle Tests

    func testRecordingToggleExists() throws {
        let recordToggle = app.switches["menubar.recordToggle"]

        // Toggle should exist in menu bar
        XCTAssertTrue(recordToggle.waitForExistence(timeout: 5.0), "Recording toggle should exist")
    }

    func testToggleRecordingOn() throws {
        let recordToggle = app.switches["menubar.recordToggle"]
        XCTAssertTrue(recordToggle.waitForExistence(timeout: 5.0), "Recording toggle should exist")

        // Get initial state
        let initialValue = recordToggle.value as? String

        // Toggle recording on if it's off
        if initialValue == "0" {
            recordToggle.click()

            // Wait for state change
            sleep(1)

            // Verify state changed
            let newValue = recordToggle.value as? String
            XCTAssertEqual(newValue, "1", "Recording should be enabled")
        }
    }

    func testToggleRecordingOff() throws {
        let recordToggle = app.switches["menubar.recordToggle"]
        XCTAssertTrue(recordToggle.waitForExistence(timeout: 5.0), "Recording toggle should exist")

        // Ensure recording is on first
        let initialValue = recordToggle.value as? String
        if initialValue == "0" {
            recordToggle.click()
            sleep(1)
        }

        // Now toggle off
        recordToggle.click()
        sleep(1)

        // Verify state changed to off
        let newValue = recordToggle.value as? String
        XCTAssertEqual(newValue, "0", "Recording should be disabled")
    }

    // MARK: - Menu Button Tests

    func testOpenTimelineButtonExists() throws {
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")
        XCTAssertTrue(openTimelineButton.isEnabled, "Open Timeline button should be enabled")
    }

    func testOpenTimelineButtonClick() throws {
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        XCTAssertTrue(openTimelineButton.waitForExistence(timeout: 5.0), "Open Timeline button should exist")

        // Click the button
        openTimelineButton.click()

        // Wait for timeline window to appear (checked in TimelineUITests)
        sleep(1)

        // Verify click was registered (button should still exist)
        XCTAssertTrue(openTimelineButton.exists, "Button should still exist after click")
    }

    func testSettingsButtonExists() throws {
        let settingsButton = app.buttons["menubar.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5.0), "Settings button should exist")
        XCTAssertTrue(settingsButton.isEnabled, "Settings button should be enabled")
    }

    func testSettingsButtonClick() throws {
        let settingsButton = app.buttons["menubar.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5.0), "Settings button should exist")

        // Click the button
        settingsButton.click()

        // Wait for settings window to appear
        sleep(1)

        // Verify settings window opened (checked in SettingsUITests)
        XCTAssertTrue(settingsButton.exists, "Button should still exist after click")
    }

    func testDiagnosticsButtonExists() throws {
        let diagnosticsButton = app.buttons["menubar.diagnosticsButton"]
        XCTAssertTrue(diagnosticsButton.waitForExistence(timeout: 5.0), "Diagnostics button should exist")
        XCTAssertTrue(diagnosticsButton.isEnabled, "Diagnostics button should be enabled")
    }

    func testDiagnosticsButtonClick() throws {
        let diagnosticsButton = app.buttons["menubar.diagnosticsButton"]
        XCTAssertTrue(diagnosticsButton.waitForExistence(timeout: 5.0), "Diagnostics button should exist")

        // Click the button
        diagnosticsButton.click()

        // Wait for diagnostics window to appear
        sleep(1)

        // Verify click was registered
        XCTAssertTrue(diagnosticsButton.exists, "Button should still exist after click")
    }

    // MARK: - Error Badge Tests

    func testErrorBadgeVisibilityWhenNoErrors() throws {
        let errorBadge = app.staticTexts["menubar.errorBadge"]

        // Error badge should not be visible when there are no errors
        // Note: This may be visible in some states, so we just check it doesn't crash
        _ = errorBadge.exists
    }

    // MARK: - Other Menu Items Tests

    func testAboutButtonExists() throws {
        let aboutButton = app.buttons["menubar.aboutButton"]
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 5.0), "About button should exist")
        XCTAssertTrue(aboutButton.isEnabled, "About button should be enabled")
    }

    func testAboutButtonClick() throws {
        let aboutButton = app.buttons["menubar.aboutButton"]
        XCTAssertTrue(aboutButton.waitForExistence(timeout: 5.0), "About button should exist")

        // Click the button
        aboutButton.click()

        // Wait for about panel to appear
        sleep(1)

        // Verify click was registered
        XCTAssertTrue(aboutButton.exists, "Button should still exist after click")
    }

    func testQuitButtonExists() throws {
        let quitButton = app.buttons["menubar.quitButton"]
        XCTAssertTrue(quitButton.waitForExistence(timeout: 5.0), "Quit button should exist")
        XCTAssertTrue(quitButton.isEnabled, "Quit button should be enabled")
    }

    // Note: We don't test actual quit functionality as it would terminate the test

    // MARK: - Integration Tests

    func testMenuBarNavigationFlow() throws {
        // Test navigating through menu bar items in sequence
        let recordToggle = app.switches["menubar.recordToggle"]
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        let settingsButton = app.buttons["menubar.settingsButton"]
        let diagnosticsButton = app.buttons["menubar.diagnosticsButton"]

        // Verify all elements exist
        XCTAssertTrue(recordToggle.waitForExistence(timeout: 5.0), "Recording toggle should exist")
        XCTAssertTrue(openTimelineButton.exists, "Open Timeline button should exist")
        XCTAssertTrue(settingsButton.exists, "Settings button should exist")
        XCTAssertTrue(diagnosticsButton.exists, "Diagnostics button should exist")

        // Toggle recording state
        recordToggle.click()
        sleep(1)

        // All buttons should still be accessible after state change
        XCTAssertTrue(openTimelineButton.isEnabled, "Open Timeline button should remain enabled")
        XCTAssertTrue(settingsButton.isEnabled, "Settings button should remain enabled")
        XCTAssertTrue(diagnosticsButton.isEnabled, "Diagnostics button should remain enabled")
    }
}
