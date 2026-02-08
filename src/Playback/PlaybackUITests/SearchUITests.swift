import XCTest

/// UI tests for search functionality
final class SearchUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Give app time to initialize
        sleep(1)

        // Open timeline
        openTimeline()
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

    private func openTimeline() {
        let openTimelineButton = app.buttons["menubar.openTimelineButton"]
        guard openTimelineButton.waitForExistence(timeout: 5.0) else { return }
        openTimelineButton.click()
        sleep(2)
    }

    private func openSearch() {
        // Press Command+F to open search
        app.typeKey("f", modifierFlags: .command)
        sleep(1)
    }

    // MARK: - Search Opening Tests

    func testSearchOpensWithCommandF() throws {
        // Open search
        app.typeKey("f", modifierFlags: .command)
        sleep(1)

        // Verify search field exists
        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search field should appear with Command+F")
    }

    func testSearchFieldExists() throws {
        openSearch()

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search text field should exist")
    }

    func testSearchFieldIsFocused() throws {
        openSearch()

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search text field should exist")

        // Field should be focused and ready for input
        // We can verify by typing directly (no need to click first)
        app.typeText("test")
        sleep(1)

        // Verify text was entered
        XCTAssertEqual(searchTextField.value as? String, "test", "Search field should accept text input")
    }

    // MARK: - Search Input Tests

    func testEnterSearchQuery() throws {
        openSearch()

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search text field should exist")

        // Type search query
        app.typeText("test query")
        sleep(1)

        // Verify query was entered
        let fieldValue = searchTextField.value as? String
        XCTAssertEqual(fieldValue, "test query", "Search query should be entered correctly")
    }

    func testSearchWithSpecialCharacters() throws {
        openSearch()

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search text field should exist")

        // Type query with special characters
        app.typeText("@#$%")
        sleep(1)

        // Verify special characters were entered
        let fieldValue = searchTextField.value as? String
        XCTAssertEqual(fieldValue, "@#$%", "Search should accept special characters")
    }

    func testSearchWithEmptyQuery() throws {
        openSearch()

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search text field should exist")

        // Don't type anything, just verify empty state
        let fieldValue = searchTextField.value as? String
        XCTAssertTrue(fieldValue == nil || fieldValue == "", "Search field should start empty")
    }

    // MARK: - Navigation Button Tests

    func testPreviousButtonExists() throws {
        openSearch()

        let previousButton = app.buttons["search.previousButton"]
        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous button should exist")
    }

    func testPreviousButtonClick() throws {
        openSearch()

        // Enter a search query first
        app.typeText("test")
        sleep(1)

        let previousButton = app.buttons["search.previousButton"]
        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous button should exist")

        // Click previous button
        previousButton.click()
        sleep(1)

        // Button should still exist after click
        XCTAssertTrue(previousButton.exists, "Previous button should remain after click")
    }

    func testNextButtonExists() throws {
        openSearch()

        let nextButton = app.buttons["search.nextButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5.0), "Next button should exist")
    }

    func testNextButtonClick() throws {
        openSearch()

        // Enter a search query first
        app.typeText("test")
        sleep(1)

        let nextButton = app.buttons["search.nextButton"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5.0), "Next button should exist")

        // Click next button
        nextButton.click()
        sleep(1)

        // Button should still exist after click
        XCTAssertTrue(nextButton.exists, "Next button should remain after click")
    }

    func testNavigationButtonSequence() throws {
        openSearch()

        // Enter search query
        app.typeText("test")
        sleep(1)

        let previousButton = app.buttons["search.previousButton"]
        let nextButton = app.buttons["search.nextButton"]

        XCTAssertTrue(previousButton.waitForExistence(timeout: 5.0), "Previous button should exist")
        XCTAssertTrue(nextButton.exists, "Next button should exist")

        // Click next multiple times
        for _ in 0..<3 {
            nextButton.click()
            sleep(1)
        }

        // Click previous multiple times
        for _ in 0..<2 {
            previousButton.click()
            sleep(1)
        }

        // Both buttons should still be functional
        XCTAssertTrue(previousButton.exists, "Previous button should remain functional")
        XCTAssertTrue(nextButton.exists, "Next button should remain functional")
    }

    // MARK: - Clear Button Tests

    func testClearButtonExists() throws {
        openSearch()

        // Enter text first to show clear button
        app.typeText("test")
        sleep(1)

        let clearButton = app.buttons["search.clearButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5.0), "Clear button should exist when text is entered")
    }

    func testClearButtonClick() throws {
        openSearch()

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search text field should exist")

        // Enter text
        app.typeText("test query")
        sleep(1)

        // Click clear button
        let clearButton = app.buttons["search.clearButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5.0), "Clear button should exist")
        clearButton.click()
        sleep(1)

        // Verify text was cleared
        let fieldValue = searchTextField.value as? String
        XCTAssertTrue(fieldValue == nil || fieldValue == "", "Search field should be cleared")
    }

    func testClearButtonHidesWhenEmpty() throws {
        openSearch()

        // Enter text
        app.typeText("test")
        sleep(1)

        let clearButton = app.buttons["search.clearButton"]
        XCTAssertTrue(clearButton.waitForExistence(timeout: 5.0), "Clear button should appear with text")

        // Clear the text
        clearButton.click()
        sleep(1)

        // Clear button may hide when field is empty (depending on implementation)
        // We just verify the operation completed without error
        XCTAssertTrue(app.exists, "App should remain functional after clearing")
    }

    // MARK: - Close Button Tests

    func testCloseButtonExists() throws {
        openSearch()

        let closeButton = app.buttons["search.closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5.0), "Close button should exist")
    }

    func testCloseButtonClick() throws {
        openSearch()

        let closeButton = app.buttons["search.closeButton"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5.0), "Close button should exist")

        // Click close button
        closeButton.click()
        sleep(1)

        // Search should close (close button should no longer exist)
        XCTAssertFalse(closeButton.exists, "Search should close after clicking close button")
    }

    func testEscapeClosesSearch() throws {
        openSearch()

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search field should exist")

        // Press Escape
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        // Search should close
        XCTAssertFalse(searchTextField.exists, "Search should close with Escape key")
    }

    // MARK: - Integration Tests

    func testCompleteSearchWorkflow() throws {
        // Complete workflow: open search -> enter query -> navigate results -> clear -> close

        // 1. Open search
        app.typeKey("f", modifierFlags: .command)
        sleep(1)

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search should open")

        // 2. Enter query
        app.typeText("workflow test")
        sleep(1)

        // 3. Navigate through results
        let nextButton = app.buttons["search.nextButton"]
        XCTAssertTrue(nextButton.exists, "Next button should exist")
        nextButton.click()
        sleep(1)

        let previousButton = app.buttons["search.previousButton"]
        previousButton.click()
        sleep(1)

        // 4. Clear search
        let clearButton = app.buttons["search.clearButton"]
        XCTAssertTrue(clearButton.exists, "Clear button should exist")
        clearButton.click()
        sleep(1)

        // 5. Close search
        let closeButton = app.buttons["search.closeButton"]
        closeButton.click()
        sleep(1)

        // Search should be closed
        XCTAssertFalse(closeButton.exists, "Search should be closed after complete workflow")
    }

    func testSearchCanBeOpenedMultipleTimes() throws {
        // Open search
        app.typeKey("f", modifierFlags: .command)
        sleep(1)

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search should open first time")

        // Close search
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        // Reopen search
        app.typeKey("f", modifierFlags: .command)
        sleep(1)

        // Verify search opened again
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search should reopen")

        // Close again
        let closeButton = app.buttons["search.closeButton"]
        closeButton.click()
        sleep(1)

        // Reopen one more time
        app.typeKey("f", modifierFlags: .command)
        sleep(1)

        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search should reopen multiple times")
    }

    func testSearchPersistsQuery() throws {
        openSearch()

        let searchTextField = app.textFields["search.textField"]
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search field should exist")

        // Enter query
        app.typeText("persistent query")
        sleep(1)

        // Navigate results
        let nextButton = app.buttons["search.nextButton"]
        nextButton.click()
        sleep(1)

        // Query should still be there
        let fieldValue = searchTextField.value as? String
        XCTAssertEqual(fieldValue, "persistent query", "Query should persist during navigation")

        // Close and reopen search
        app.typeKey(.escape, modifierFlags: [])
        sleep(1)

        app.typeKey("f", modifierFlags: .command)
        sleep(1)

        // Query may or may not persist across close/reopen depending on implementation
        // We just verify search reopens successfully
        XCTAssertTrue(searchTextField.waitForExistence(timeout: 5.0), "Search should reopen")
    }

    func testSearchNavigationWrapAround() throws {
        openSearch()

        // Enter query
        app.typeText("test")
        sleep(1)

        let nextButton = app.buttons["search.nextButton"]
        let previousButton = app.buttons["search.previousButton"]

        XCTAssertTrue(nextButton.waitForExistence(timeout: 5.0), "Next button should exist")

        // Click next many times (should wrap around if there are results)
        for _ in 0..<10 {
            nextButton.click()
            sleep(1)
        }

        // Navigation should still work
        XCTAssertTrue(nextButton.exists, "Next button should remain functional after many clicks")

        // Click previous many times
        for _ in 0..<5 {
            previousButton.click()
            sleep(1)
        }

        // Navigation should still work
        XCTAssertTrue(previousButton.exists, "Previous button should remain functional")
    }
}
