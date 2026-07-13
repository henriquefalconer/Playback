import XCTest

/// UI tests for date/time picker interactions
final class DateTimePickerUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Give app time to initialize
        sleep(1)

        // Open timeline and date picker
        openDatePicker()
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

    // MARK: - Helper Methods

    private func openDatePicker() {
        // Open timeline
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        guard openTimelineButton.waitForExistence(timeout: 5.0) else { return }
        openTimelineButton.click()
        sleep(2)

        // Click time bubble to open date picker
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        guard timeBubbleButton.waitForExistence(timeout: 5.0) else { return }
        timeBubbleButton.click()
        sleep(1)
    }

    // MARK: - Date Picker Presence Tests

    func testDatePickerOpens() throws {
        // Verify date picker elements are present
        let todayButton = app.buttons["datepicker.todayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5.0), "Today button should exist in date picker")
    }

    func testDatePickerHasNavigationButtons() throws {
        let previousButton = app.buttons["datepicker.previousMonthButton"]
        let nextButton = app.buttons["datepicker.nextMonthButton"]

        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous month button should exist")
        XCTAssertTrue(nextButton.exists, "Next month button should exist")
    }

    // MARK: - Today Button Tests

    func testTodayButtonExists() throws {
        let todayButton = app.buttons["datepicker.todayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5.0), "Today button should exist")
        XCTAssertTrue(todayButton.isEnabled, "Today button should be enabled")
    }

    func testTodayButtonClick() throws {
        let todayButton = app.buttons["datepicker.todayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5.0), "Today button should exist")

        // Click today button
        todayButton.click()
        sleep(1)

        // Verify date picker still exists (calendar should update to today)
        XCTAssertTrue(todayButton.exists, "Date picker should remain open after clicking today")
    }

    // MARK: - Month Navigation Tests

    func testPreviousMonthButtonExists() throws {
        let previousButton = app.buttons["datepicker.previousMonthButton"]
        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous month button should exist")
        XCTAssertTrue(previousButton.isEnabled, "Previous month button should be enabled")
    }

    func testPreviousMonthButtonClick() throws {
        let previousButton = app.buttons["datepicker.previousMonthButton"]
        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous month button should exist")

        // Click previous month
        previousButton.click()
        sleep(1)

        // Verify button still exists (month should have changed)
        XCTAssertTrue(previousButton.exists, "Previous month button should still exist")
    }

    func testNextMonthButtonExists() throws {
        let nextButton = app.buttons["datepicker.nextMonthButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5.0), "Next month button should exist")
        XCTAssertTrue(nextButton.isEnabled, "Next month button should be enabled")
    }

    func testNextMonthButtonClick() throws {
        let nextButton = app.buttons["datepicker.nextMonthButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5.0), "Next month button should exist")

        // Click next month
        nextButton.click()
        sleep(1)

        // Verify button still exists (month should have changed)
        XCTAssertTrue(nextButton.exists, "Next month button should still exist")
    }

    func testMonthNavigationSequence() throws {
        let previousButton = app.buttons["datepicker.previousMonthButton"]
        let nextButton = app.buttons["datepicker.nextMonthButton"]

        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous month button should exist")
        XCTAssertTrue(nextButton.exists, "Next month button should exist")

        // Navigate forward
        nextButton.click()
        sleep(1)
        XCTAssertTrue(nextButton.exists, "Should be able to navigate forward")

        // Navigate backward
        previousButton.click()
        sleep(1)
        XCTAssertTrue(previousButton.exists, "Should be able to navigate backward")

        // Navigate back to today
        let todayButton = app.buttons["datepicker.todayButton"]
        todayButton.click()
        sleep(1)
        XCTAssertTrue(todayButton.exists, "Should be able to return to today")
    }

    // MARK: - Day Selection Tests

    func testDayButtonsExist() throws {
        // Day buttons have dynamic identifiers like "datepicker.dayButton.2026-02-08"
        let dayButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.dayButton.'"))

        // Wait a moment for day buttons to appear
        sleep(1)

        // At least some day buttons should exist (current month has days)
        XCTAssertGreaterThan(dayButtonsQuery.count, 0, "Day buttons should exist in calendar")
    }

    func testDayButtonClickJumpsAndStaysOpen() throws {
        // Find first enabled day button (days with recordings)
        let dayButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.dayButton.'"))

        sleep(1)

        let enabledDays = dayButtonsQuery.matching(NSPredicate(format: "isEnabled == true"))
        if enabledDays.count > 0 {
            let firstDayButton = enabledDays.element(boundBy: 0)
            XCTAssertTrue(firstDayButton.exists, "An enabled day button should exist")

            // Clicking a day jumps to its first recording; the picker stays open
            firstDayButton.click()
            sleep(2)

            let todayButton = app.buttons["datepicker.todayButton"]
            XCTAssertTrue(todayButton.exists, "Date picker should stay open after clicking a day")
        }
    }

    // MARK: - Time Slot Tests

    func testTimeSlotButtonsExist() throws {
        // Time slot buttons have identifiers like "datepicker.timeButton.<unix timestamp>"
        let timeButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.timeButton.'"))

        sleep(1)

        // Time slot buttons should exist for a date with recordings
        XCTAssertGreaterThan(timeButtonsQuery.count, 0, "Time slot buttons should exist")
    }

    func testTimeSlotClickJumpsAndStaysOpen() throws {
        let timeButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.timeButton.'"))

        sleep(1)

        if timeButtonsQuery.count > 0 {
            let firstTimeButton = timeButtonsQuery.element(boundBy: 0)
            XCTAssertTrue(firstTimeButton.exists, "First time slot button should exist")

            // Clicking a time slot jumps to it; the picker stays open
            firstTimeButton.click()
            sleep(1)

            let todayButton = app.buttons["datepicker.todayButton"]
            XCTAssertTrue(todayButton.exists, "Date picker should stay open after clicking a time slot")
        }
    }

    func testClickOutsideClosesPicker() throws {
        let todayButton = app.buttons["datepicker.todayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5.0), "Date picker should be open")

        // Click on the dimmed area far from the modal
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.15)).click()
        sleep(1)

        XCTAssertFalse(todayButton.exists, "Date picker should close when clicking outside it")
    }

    // MARK: - Dismissal Tests

    func testEscapeDismissesPickerButKeepsWindow() throws {
        let todayButton = app.buttons["datepicker.todayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5.0), "Date picker should be open")

        // ESC dismisses the modal without closing the timeline window
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        XCTAssertFalse(todayButton.exists, "Date picker should close on ESC")

        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.exists, "Timeline window should remain open after ESC dismisses the picker")
    }

    func testDatePickerCanBeOpenedMultipleTimes() throws {
        // Close current date picker with ESC
        let todayButton = app.buttons["datepicker.todayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5.0), "Date picker should be open")
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        // Reopen date picker
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.waitForExistence(timeout: 5.0), "Time bubble should exist")
        timeBubbleButton.click()
        sleep(1)

        // Verify date picker opened again
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5.0), "Date picker should reopen")
    }

    // MARK: - Integration Tests

    func testDatePickerNavigationAndSelection() throws {
        // Test complete navigation flow

        let previousButton = app.buttons["datepicker.previousMonthButton"]
        let nextButton = app.buttons["datepicker.nextMonthButton"]
        let todayButton = app.buttons["datepicker.todayButton"]

        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous button should exist")

        // Navigate backward 2 months
        for _ in 0..<2 {
            previousButton.click()
            sleep(1)
        }

        // Navigate forward 1 month
        nextButton.click()
        sleep(1)

        // Return to today
        todayButton.click()
        sleep(1)

        // All navigation should work without errors
        XCTAssertTrue(todayButton.exists, "Date picker should remain functional after navigation")
    }
}
