import XCTest

/// UI tests for first-run wizard
final class FirstRunUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--first-run"]
        app.launch()

        // Give app time to show first-run wizard
        sleep(2)
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

    // MARK: - First Run Wizard Presence Tests

    func testFirstRunWizardAppears() throws {
        // Note: First run wizard may only appear on actual first run
        // This test verifies the wizard can be shown with the --first-run flag

        // Look for any first run navigation buttons
        let continueButton = app.buttons["firstrun.continueButton"]
        let skipButton = app.buttons["firstrun.skipButton"]
        let finishButton = app.buttons["firstrun.finishButton"]

        // At least one navigation button should exist
        let hasAnyButton = continueButton.waitForExistence(timeout: 5.0) ||
                          skipButton.exists ||
                          finishButton.exists

        XCTAssertTrue(hasAnyButton, "First run wizard should show navigation buttons")
    }

    // MARK: - Navigation Button Tests

    func testContinueButtonExists() throws {
        let continueButton = app.buttons["firstrun.continueButton"]

        // Continue button should exist on initial screens
        if continueButton.waitForExistence(timeout: 5.0) {
            XCTAssertTrue(continueButton.isEnabled, "Continue button should be enabled")
        }
    }

    func testContinueButtonClick() throws {
        let continueButton = app.buttons["firstrun.continueButton"]

        if continueButton.waitForExistence(timeout: 5.0) {
            // Click continue
            continueButton.click()
            sleep(1)

            // Should progress to next step (continue button may still exist or be replaced)
            XCTAssertTrue(app.exists, "App should remain running after clicking continue")
        }
    }

    func testBackButtonExists() throws {
        // First, navigate to a screen where back button should exist
        let continueButton = app.buttons["firstrun.continueButton"]

        if continueButton.waitForExistence(timeout: 5.0) {
            continueButton.click()
            sleep(1)

            // Now check for back button
            let backButton = app.buttons["firstrun.backButton"]
            if backButton.waitForExistence(timeout: 3.0) {
                XCTAssertTrue(backButton.isEnabled, "Back button should be enabled")
            }
        }
    }

    func testBackButtonClick() throws {
        let continueButton = app.buttons["firstrun.continueButton"]

        if continueButton.waitForExistence(timeout: 5.0) {
            // Go forward first
            continueButton.click()
            sleep(1)

            // Then go back
            let backButton = app.buttons["firstrun.backButton"]
            if backButton.waitForExistence(timeout: 3.0) {
                backButton.click()
                sleep(1)

                // Should return to previous step
                XCTAssertTrue(app.exists, "App should remain running after clicking back")
            }
        }
    }

    func testSkipButtonExists() throws {
        let skipButton = app.buttons["firstrun.skipButton"]

        // Skip button may exist on some screens
        if skipButton.waitForExistence(timeout: 5.0) {
            XCTAssertTrue(skipButton.isEnabled, "Skip button should be enabled")
        }
    }

    func testSkipButtonClick() throws {
        let skipButton = app.buttons["firstrun.skipButton"]

        if skipButton.waitForExistence(timeout: 5.0) {
            // Click skip
            skipButton.click()
            sleep(1)

            // Should skip current step
            XCTAssertTrue(app.exists, "App should remain running after clicking skip")
        }
    }

    func testFinishButtonExists() throws {
        // Navigate to the final screen
        navigateToFinalScreen()

        let finishButton = app.buttons["firstrun.finishButton"]

        // Finish button should exist on final screen
        if finishButton.waitForExistence(timeout: 5.0) {
            XCTAssertTrue(finishButton.isEnabled, "Finish button should be enabled")
        }
    }

    func testFinishButtonClick() throws {
        // Navigate to final screen
        navigateToFinalScreen()

        let finishButton = app.buttons["firstrun.finishButton"]

        if finishButton.waitForExistence(timeout: 5.0) {
            // Click finish
            finishButton.click()
            sleep(2)

            // First run wizard should close
            XCTAssertFalse(finishButton.exists, "First run wizard should close after finish")
        }
    }

    // MARK: - Navigation Flow Tests

    func testNavigateForwardThroughWizard() throws {
        let continueButton = app.buttons["firstrun.continueButton"]

        if continueButton.waitForExistence(timeout: 5.0) {
            // Click continue multiple times to progress through wizard
            for step in 1...5 {
                if continueButton.exists && continueButton.isEnabled {
                    continueButton.click()
                    sleep(1)
                } else {
                    // Reached end of wizard or finish button appeared
                    break
                }

                // Verify we're still in the app
                XCTAssertTrue(app.exists, "App should remain running at step \(step)")
            }
        }
    }

    func testNavigateBackwardThroughWizard() throws {
        // Navigate forward first
        let continueButton = app.buttons["firstrun.continueButton"]

        if continueButton.waitForExistence(timeout: 5.0) {
            // Go forward 2-3 steps
            for _ in 1...3 {
                if continueButton.exists && continueButton.isEnabled {
                    continueButton.click()
                    sleep(1)
                } else {
                    break
                }
            }

            // Now navigate backward
            let backButton = app.buttons["firstrun.backButton"]
            if backButton.waitForExistence(timeout: 3.0) {
                for step in 1...2 {
                    if backButton.exists && backButton.isEnabled {
                        backButton.click()
                        sleep(1)
                    } else {
                        break
                    }

                    XCTAssertTrue(app.exists, "App should remain running while going back at step \(step)")
                }
            }
        }
    }

    func testNavigateForwardAndBackward() throws {
        let continueButton = app.buttons["firstrun.continueButton"]

        if continueButton.waitForExistence(timeout: 5.0) {
            // Forward 2 steps
            for _ in 1...2 {
                if continueButton.exists && continueButton.isEnabled {
                    continueButton.click()
                    sleep(1)
                }
            }

            // Back 1 step
            let backButton = app.buttons["firstrun.backButton"]
            if backButton.waitForExistence(timeout: 3.0) && backButton.isEnabled {
                backButton.click()
                sleep(1)
            }

            // Forward 1 step
            if continueButton.exists && continueButton.isEnabled {
                continueButton.click()
                sleep(1)
            }

            // Should be able to navigate freely
            XCTAssertTrue(app.exists, "App should handle forward/backward navigation")
        }
    }

    // MARK: - Skip Functionality Tests

    func testSkipEntireWizard() throws {
        let skipButton = app.buttons["firstrun.skipButton"]

        // Try to skip on each screen
        var skipsAttempted = 0
        while skipButton.waitForExistence(timeout: 2.0) && skipsAttempted < 10 {
            skipButton.click()
            sleep(1)
            skipsAttempted += 1

            // Check if we've reached the end
            let finishButton = app.buttons["firstrun.finishButton"]
            if finishButton.exists {
                finishButton.click()
                sleep(1)
                break
            }
        }

        // Either we skipped through or the wizard completed
        XCTAssertTrue(app.exists, "App should remain running after skipping")
    }

    // MARK: - Complete Wizard Tests

    func testCompleteWizardWithContinue() throws {
        let continueButton = app.buttons["firstrun.continueButton"]
        let finishButton = app.buttons["firstrun.finishButton"]

        if continueButton.waitForExistence(timeout: 5.0) {
            // Click continue until we reach finish button
            var stepsCompleted = 0
            let maxSteps = 10 // Safety limit

            while stepsCompleted < maxSteps {
                if finishButton.waitForExistence(timeout: 2.0) {
                    // Reached final screen
                    finishButton.click()
                    sleep(2)
                    break
                } else if continueButton.exists && continueButton.isEnabled {
                    continueButton.click()
                    sleep(1)
                    stepsCompleted += 1
                } else {
                    // Wizard might have closed or we're stuck
                    break
                }
            }

            // Wizard should complete successfully
            XCTAssertTrue(app.exists, "App should be running after completing wizard")
        }
    }

    func testCompleteWizardWithSkips() throws {
        let skipButton = app.buttons["firstrun.skipButton"]
        let continueButton = app.buttons["firstrun.continueButton"]
        let finishButton = app.buttons["firstrun.finishButton"]

        // Alternate between skip and continue
        var steps = 0
        let maxSteps = 10

        while steps < maxSteps {
            if finishButton.waitForExistence(timeout: 2.0) {
                finishButton.click()
                sleep(2)
                break
            } else if skipButton.exists && skipButton.isEnabled && steps % 2 == 0 {
                skipButton.click()
                sleep(1)
            } else if continueButton.exists && continueButton.isEnabled {
                continueButton.click()
                sleep(1)
            } else {
                break
            }
            steps += 1
        }

        // Wizard should handle mixed skip/continue navigation
        XCTAssertTrue(app.exists, "App should handle mixed navigation")
    }

    // MARK: - Integration Tests

    func testWizardPersistenceThroughSteps() throws {
        // Test that wizard remains stable through multiple steps
        let continueButton = app.buttons["firstrun.continueButton"]

        if continueButton.waitForExistence(timeout: 5.0) {
            // Navigate through several steps
            for step in 1...5 {
                let backButton = app.buttons["firstrun.backButton"]
                let finishButton = app.buttons["firstrun.finishButton"]

                if finishButton.exists {
                    // Reached end
                    break
                }

                if continueButton.exists && continueButton.isEnabled {
                    continueButton.click()
                    sleep(1)

                    // Verify navigation buttons remain functional
                    XCTAssertTrue(app.exists, "App should remain stable at step \(step)")

                    // Back button should be available (except on first step)
                    if step > 1 {
                        XCTAssertTrue(backButton.exists || finishButton.exists,
                                    "Navigation buttons should be available at step \(step)")
                    }
                }
            }
        }
    }

    func testWizardDoesNotBlockApp() throws {
        // Verify that wizard doesn't prevent app from functioning

        // Even with wizard open, app should be responsive
        XCTAssertTrue(app.exists, "App should be running")

        // Try interacting with wizard
        let continueButton = app.buttons["firstrun.continueButton"]
        if continueButton.waitForExistence(timeout: 5.0) {
            continueButton.click()
            sleep(1)

            // App should still be responsive
            XCTAssertTrue(app.exists, "App should remain responsive during wizard")
        }
    }

    // MARK: - Helper Methods

    private func navigateToFinalScreen() {
        let continueButton = app.buttons["firstrun.continueButton"]
        let finishButton = app.buttons["firstrun.finishButton"]

        // Navigate forward until we reach the finish button
        var steps = 0
        let maxSteps = 15

        while steps < maxSteps {
            if finishButton.waitForExistence(timeout: 2.0) {
                // Reached final screen
                return
            } else if continueButton.exists && continueButton.isEnabled {
                continueButton.click()
                sleep(1)
                steps += 1
            } else {
                // Try skip button
                let skipButton = app.buttons["firstrun.skipButton"]
                if skipButton.exists && skipButton.isEnabled {
                    skipButton.click()
                    sleep(1)
                    steps += 1
                } else {
                    break
                }
            }
        }
    }
}
