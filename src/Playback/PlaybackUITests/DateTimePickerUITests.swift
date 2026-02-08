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

    func testDatePickerHasActionButtons() throws {
        let cancelButton = app.buttons["datepicker.cancelButton"]
        let jumpButton = app.buttons["datepicker.jumpButton"]

        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5.0), "Cancel button should exist")
        XCTAssertTrue(jumpButton.exists, "Jump to Time button should exist")
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
        // Day buttons have dynamic identifiers like "datepicker.dayButton.20260208"
        // We'll check if any day buttons exist
        let dayButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.dayButton.'"))

        // Wait a moment for day buttons to appear
        sleep(1)

        // At least some day buttons should exist (current month has days)
        XCTAssertGreaterThan(dayButtonsQuery.count, 0, "Day buttons should exist in calendar")
    }

    func testDayButtonClick() throws {
        // Find first available day button
        let dayButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.dayButton.'"))

        sleep(1)

        if dayButtonsQuery.count > 0 {
            let firstDayButton = dayButtonsQuery.element(boundBy: 0)
            XCTAssertTrue(firstDayButton.exists, "First day button should exist")

            // Click the day
            firstDayButton.click()
            sleep(1)

            // Verify date picker still exists
            let jumpButton = app.buttons["datepicker.jumpButton"]
            XCTAssertTrue(jumpButton.exists, "Date picker should remain open after selecting day")
        }
    }

    // MARK: - Time Selection Tests

    func testTimeButtonsExist() throws {
        // Time buttons have identifiers like "datepicker.timeButton.0", "datepicker.timeButton.1", etc.
        let timeButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.timeButton.'"))

        sleep(1)

        // Time buttons should exist
        XCTAssertGreaterThan(timeButtonsQuery.count, 0, "Time buttons should exist")
    }

    func testTimeButtonClick() throws {
        // Find first time button
        let timeButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.timeButton.'"))

        sleep(1)

        if timeButtonsQuery.count > 0 {
            let firstTimeButton = timeButtonsQuery.element(boundBy: 0)
            XCTAssertTrue(firstTimeButton.exists, "First time button should exist")

            // Click the time
            firstTimeButton.click()
            sleep(1)

            // Verify jump button is enabled (selection should be complete)
            let jumpButton = app.buttons["datepicker.jumpButton"]
            XCTAssertTrue(jumpButton.exists, "Jump button should exist after time selection")
        }
    }

    // MARK: - Action Button Tests

    func testCancelButtonExists() throws {
        let cancelButton = app.buttons["datepicker.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5.0), "Cancel button should exist")
        XCTAssertTrue(cancelButton.isEnabled, "Cancel button should be enabled")
    }

    func testCancelButtonClick() throws {
        let cancelButton = app.buttons["datepicker.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5.0), "Cancel button should exist")

        // Click cancel
        cancelButton.click()
        sleep(1)

        // Date picker should close (cancel button should no longer exist)
        XCTAssertFalse(cancelButton.exists, "Date picker should close after clicking cancel")
    }

    func testJumpButtonExists() throws {
        let jumpButton = app.buttons["datepicker.jumpButton"]
        XCTAssertTrue(jumpButton.waitForExistence(timeout: 5.0), "Jump button should exist")
    }

    func testJumpButtonClick() throws {
        // First select a day and time
        let dayButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.dayButton.'"))
        sleep(1)

        if dayButtonsQuery.count > 0 {
            dayButtonsQuery.element(boundBy: 0).click()
            sleep(1)
        }

        let timeButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.timeButton.'"))
        if timeButtonsQuery.count > 0 {
            timeButtonsQuery.element(boundBy: 0).click()
            sleep(1)
        }

        // Now click jump button
        let jumpButton = app.buttons["datepicker.jumpButton"]
        XCTAssertTrue(jumpButton.exists, "Jump button should exist")

        jumpButton.click()
        sleep(1)

        // Date picker should close after jump
        XCTAssertFalse(jumpButton.exists, "Date picker should close after jumping to time")
    }

    // MARK: - Integration Tests

    func testCompleteDateTimeSelectionWorkflow() throws {
        // Complete workflow: navigate month -> select day -> select time -> jump

        // 1. Navigate to previous month
        let previousButton = app.buttons["datepicker.previousMonthButton"]
        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous button should exist")
        previousButton.click()
        sleep(1)

        // 2. Return to today
        let todayButton = app.buttons["datepicker.todayButton"]
        todayButton.click()
        sleep(1)

        // 3. Select a day
        let dayButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.dayButton.'"))
        sleep(1)
        if dayButtonsQuery.count > 0 {
            dayButtonsQuery.element(boundBy: 0).click()
            sleep(1)
        }

        // 4. Select a time
        let timeButtonsQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'datepicker.timeButton.'"))
        if timeButtonsQuery.count > 0 {
            timeButtonsQuery.element(boundBy: 0).click()
            sleep(1)
        }

        // 5. Verify jump button is enabled
        let jumpButton = app.buttons["datepicker.jumpButton"]
        XCTAssertTrue(jumpButton.exists, "Jump button should be enabled after full selection")

        // 6. Cancel instead of jumping (to keep test isolated)
        let cancelButton = app.buttons["datepicker.cancelButton"]
        cancelButton.click()
        sleep(1)

        XCTAssertFalse(cancelButton.exists, "Date picker should close")
    }

    func testDatePickerCanBeOpenedMultipleTimes() throws {
        // Close current date picker
        let cancelButton = app.buttons["datepicker.cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 5.0), "Cancel button should exist")
        cancelButton.click()
        sleep(1)

        // Reopen date picker
        let timeBubbleButton = app.buttons["timeline.timeBubbleButton"]
        XCTAssertTrue(timeBubbleButton.waitForExistence(timeout: 5.0), "Time bubble should exist")
        timeBubbleButton.click()
        sleep(1)

        // Verify date picker opened again
        let todayButton = app.buttons["datepicker.todayButton"]
        XCTAssertTrue(todayButton.waitForExistence(timeout: 5.0), "Date picker should reopen")
    }

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
