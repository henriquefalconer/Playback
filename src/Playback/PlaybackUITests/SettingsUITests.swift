import XCTest

/// UI tests for settings window
final class SettingsUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()

        // Give app time to initialize
        sleep(1)

        // Open settings window
        openSettings()
    }

    override func tearDownWithError() throws {
        // Close settings window if open
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        app = nil
    }

    // MARK: - Helper Methods

    private func openSettings() {
        let settingsButton = app.buttons["menubar.settingsButton"]
        guard settingsButton.waitForExistence(timeout: 5.0) else { return }
        settingsButton.click()
        sleep(2)
    }

    // MARK: - Settings Window Tests

    func testSettingsWindowOpens() throws {
        // Verify settings window opened by checking for tab buttons
        let generalTab = app.buttons["settings.generalTab"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 5.0), "Settings window should open")
    }

    func testSettingsWindowCanBeClosed() throws {
        // Close window
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        // Reopen to verify it can be reopened
        openSettings()

        let generalTab = app.buttons["settings.generalTab"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 5.0), "Settings window should reopen")
    }

    // MARK: - Tab Navigation Tests

    func testGeneralTabExists() throws {
        let generalTab = app.buttons["settings.generalTab"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 5.0), "General tab should exist")
    }

    func testRecordingTabExists() throws {
        let recordingTab = app.buttons["settings.recordingTab"]
        XCTAssertTrue(recordingTab.waitForExistence(timeout: 5.0), "Recording tab should exist")
    }

    func testProcessingTabExists() throws {
        let processingTab = app.buttons["settings.processingTab"]
        XCTAssertTrue(processingTab.waitForExistence(timeout: 5.0), "Processing tab should exist")
    }

    func testStorageTabExists() throws {
        let storageTab = app.buttons["settings.storageTab"]
        XCTAssertTrue(storageTab.waitForExistence(timeout: 5.0), "Storage tab should exist")
    }

    func testPrivacyTabExists() throws {
        let privacyTab = app.buttons["settings.privacyTab"]
        XCTAssertTrue(privacyTab.waitForExistence(timeout: 5.0), "Privacy tab should exist")
    }

    func testAdvancedTabExists() throws {
        let advancedTab = app.buttons["settings.advancedTab"]
        XCTAssertTrue(advancedTab.waitForExistence(timeout: 5.0), "Advanced tab should exist")
    }

    func testAllTabsAreClickable() throws {
        let generalTab = app.buttons["settings.generalTab"]
        let recordingTab = app.buttons["settings.recordingTab"]
        let processingTab = app.buttons["settings.processingTab"]
        let storageTab = app.buttons["settings.storageTab"]
        let privacyTab = app.buttons["settings.privacyTab"]
        let advancedTab = app.buttons["settings.advancedTab"]

        XCTAssertTrue(generalTab.waitForExistence(timeout: 5.0), "General tab should exist")

        // All tabs should be enabled
        XCTAssertTrue(generalTab.isEnabled, "General tab should be enabled")
        XCTAssertTrue(recordingTab.isEnabled, "Recording tab should be enabled")
        XCTAssertTrue(processingTab.isEnabled, "Processing tab should be enabled")
        XCTAssertTrue(storageTab.isEnabled, "Storage tab should be enabled")
        XCTAssertTrue(privacyTab.isEnabled, "Privacy tab should be enabled")
        XCTAssertTrue(advancedTab.isEnabled, "Advanced tab should be enabled")
    }

    func testNavigateBetweenAllTabs() throws {
        let generalTab = app.buttons["settings.generalTab"]
        let recordingTab = app.buttons["settings.recordingTab"]
        let processingTab = app.buttons["settings.processingTab"]
        let storageTab = app.buttons["settings.storageTab"]
        let privacyTab = app.buttons["settings.privacyTab"]
        let advancedTab = app.buttons["settings.advancedTab"]

        XCTAssertTrue(generalTab.waitForExistence(timeout: 5.0), "General tab should exist")

        // Navigate through all tabs
        recordingTab.click()
        sleep(1)
        XCTAssertTrue(recordingTab.exists, "Recording tab should be accessible")

        processingTab.click()
        sleep(1)
        XCTAssertTrue(processingTab.exists, "Processing tab should be accessible")

        storageTab.click()
        sleep(1)
        XCTAssertTrue(storageTab.exists, "Storage tab should be accessible")

        privacyTab.click()
        sleep(1)
        XCTAssertTrue(privacyTab.exists, "Privacy tab should be accessible")

        advancedTab.click()
        sleep(1)
        XCTAssertTrue(advancedTab.exists, "Advanced tab should be accessible")

        // Return to general
        generalTab.click()
        sleep(1)
        XCTAssertTrue(generalTab.exists, "Should be able to return to General tab")
    }

    // MARK: - General Tab Tests

    func testGeneralTabNotificationToggles() throws {
        let generalTab = app.buttons["settings.generalTab"]
        generalTab.click()
        sleep(1)

        let processingCompleteToggle = app.checkBoxes["settings.general.processingCompleteToggle"]
        let processingErrorsToggle = app.checkBoxes["settings.general.processingErrorsToggle"]
        let diskSpaceToggle = app.checkBoxes["settings.general.diskSpaceToggle"]
        let recordingStatusToggle = app.checkBoxes["settings.general.recordingStatusToggle"]

        // Verify toggles exist
        XCTAssertTrue(processingCompleteToggle.waitForExistence(timeout: 5.0), "Processing complete toggle should exist")
        XCTAssertTrue(processingErrorsToggle.exists, "Processing errors toggle should exist")
        XCTAssertTrue(diskSpaceToggle.exists, "Disk space toggle should exist")
        XCTAssertTrue(recordingStatusToggle.exists, "Recording status toggle should exist")
    }

    func testGeneralTabToggleInteraction() throws {
        let generalTab = app.buttons["settings.generalTab"]
        generalTab.click()
        sleep(1)

        let processingCompleteToggle = app.checkBoxes["settings.general.processingCompleteToggle"]
        XCTAssertTrue(processingCompleteToggle.waitForExistence(timeout: 5.0), "Toggle should exist")

        // Toggle the setting
        let initialValue = processingCompleteToggle.value as? Int
        processingCompleteToggle.click()
        sleep(1)

        // Value should have changed
        let newValue = processingCompleteToggle.value as? Int
        XCTAssertNotEqual(initialValue, newValue, "Toggle value should change when clicked")
    }

    // MARK: - Recording Tab Tests

    func testRecordingTabPauseToggle() throws {
        let recordingTab = app.buttons["settings.recordingTab"]
        recordingTab.click()
        sleep(1)

        let pauseToggle = app.checkBoxes["settings.recording.pauseWhenTimelineToggle"]
        XCTAssertTrue(pauseToggle.waitForExistence(timeout: 5.0), "Pause when timeline toggle should exist")
    }

    func testRecordingTabPauseToggleInteraction() throws {
        let recordingTab = app.buttons["settings.recordingTab"]
        recordingTab.click()
        sleep(1)

        let pauseToggle = app.checkBoxes["settings.recording.pauseWhenTimelineToggle"]
        XCTAssertTrue(pauseToggle.waitForExistence(timeout: 5.0), "Toggle should exist")

        // Toggle the setting
        let initialValue = pauseToggle.value as? Int
        pauseToggle.click()
        sleep(1)

        // Value should have changed
        let newValue = pauseToggle.value as? Int
        XCTAssertNotEqual(initialValue, newValue, "Toggle should change when clicked")
    }

    // MARK: - Processing Tab Tests

    func testProcessingTabIntervalPicker() throws {
        let processingTab = app.buttons["settings.processingTab"]
        processingTab.click()
        sleep(1)

        let intervalPicker = app.popUpButtons["settings.processing.intervalPicker"]
        XCTAssertTrue(intervalPicker.waitForExistence(timeout: 5.0), "Interval picker should exist")
    }

    func testProcessingTabIntervalPickerInteraction() throws {
        let processingTab = app.buttons["settings.processingTab"]
        processingTab.click()
        sleep(1)

        let intervalPicker = app.popUpButtons["settings.processing.intervalPicker"]
        XCTAssertTrue(intervalPicker.waitForExistence(timeout: 5.0), "Interval picker should exist")

        // Click to open picker
        intervalPicker.click()
        sleep(1)

        // Picker should be functional
        XCTAssertTrue(intervalPicker.exists, "Interval picker should remain functional")
    }

    // MARK: - Storage Tab Tests

    func testStorageTabControls() throws {
        let storageTab = app.buttons["settings.storageTab"]
        storageTab.click()
        sleep(1)

        let refreshButton = app.buttons["settings.storage.refreshButton"]
        let tempRetentionPicker = app.popUpButtons["settings.storage.tempRetentionPicker"]
        let recordingRetentionPicker = app.popUpButtons["settings.storage.recordingRetentionPicker"]
        let cleanupButton = app.buttons["settings.storage.cleanupButton"]

        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5.0), "Refresh button should exist")
        XCTAssertTrue(tempRetentionPicker.exists, "Temp retention picker should exist")
        XCTAssertTrue(recordingRetentionPicker.exists, "Recording retention picker should exist")
        XCTAssertTrue(cleanupButton.exists, "Cleanup button should exist")
    }

    func testStorageTabRefreshButton() throws {
        let storageTab = app.buttons["settings.storageTab"]
        storageTab.click()
        sleep(1)

        let refreshButton = app.buttons["settings.storage.refreshButton"]
        XCTAssertTrue(refreshButton.waitForExistence(timeout: 5.0), "Refresh button should exist")

        // Click refresh
        refreshButton.click()
        sleep(1)

        // Button should still exist and be functional
        XCTAssertTrue(refreshButton.exists, "Refresh button should remain functional")
    }

    // MARK: - Privacy Tab Tests

    func testPrivacyTabPermissionButtons() throws {
        let privacyTab = app.buttons["settings.privacyTab"]
        privacyTab.click()
        sleep(1)

        let screenRecordingButton = app.buttons["settings.privacy.screenRecordingButton"]
        let accessibilityButton = app.buttons["settings.privacy.accessibilityButton"]

        XCTAssertTrue(screenRecordingButton.waitForExistence(timeout: 5.0), "Screen recording button should exist")
        XCTAssertTrue(accessibilityButton.exists, "Accessibility button should exist")
    }

    func testPrivacyTabExclusionControls() throws {
        let privacyTab = app.buttons["settings.privacyTab"]
        privacyTab.click()
        sleep(1)

        let exclusionModePicker = app.popUpButtons["settings.privacy.exclusionModePicker"]
        let appIdTextField = app.textFields["settings.privacy.appIdTextField"]
        let addAppButton = app.buttons["settings.privacy.addAppButton"]

        XCTAssertTrue(exclusionModePicker.waitForExistence(timeout: 5.0), "Exclusion mode picker should exist")
        XCTAssertTrue(appIdTextField.exists, "App ID text field should exist")
        XCTAssertTrue(addAppButton.exists, "Add app button should exist")
    }

    func testPrivacyTabDataButtons() throws {
        let privacyTab = app.buttons["settings.privacyTab"]
        privacyTab.click()
        sleep(1)

        let revealDataButton = app.buttons["settings.privacy.revealDataButton"]
        let exportDataButton = app.buttons["settings.privacy.exportDataButton"]

        XCTAssertTrue(revealDataButton.waitForExistence(timeout: 5.0), "Reveal data button should exist")
        XCTAssertTrue(exportDataButton.exists, "Export data button should exist")
    }

    func testPrivacyTabAddAppWorkflow() throws {
        let privacyTab = app.buttons["settings.privacyTab"]
        privacyTab.click()
        sleep(1)

        let appIdTextField = app.textFields["settings.privacy.appIdTextField"]
        let addAppButton = app.buttons["settings.privacy.addAppButton"]

        XCTAssertTrue(appIdTextField.waitForExistence(timeout: 5.0), "App ID text field should exist")

        // Click text field and enter app ID
        appIdTextField.click()
        sleep(1)
        appIdTextField.typeText("com.example.testapp")
        sleep(1)

        // Click add button
        addAppButton.click()
        sleep(1)

        // Controls should still be functional
        XCTAssertTrue(appIdTextField.exists, "Text field should remain functional")
    }

    // MARK: - Advanced Tab Tests

    func testAdvancedTabServiceButtons() throws {
        let advancedTab = app.buttons["settings.advancedTab"]
        advancedTab.click()
        sleep(1)

        let restartRecordingButton = app.buttons["settings.advanced.restartRecordingButton"]
        let restartProcessingButton = app.buttons["settings.advanced.restartProcessingButton"]

        XCTAssertTrue(restartRecordingButton.waitForExistence(timeout: 5.0), "Restart recording button should exist")
        XCTAssertTrue(restartProcessingButton.exists, "Restart processing button should exist")
    }

    func testAdvancedTabDangerousButtons() throws {
        let advancedTab = app.buttons["settings.advancedTab"]
        advancedTab.click()
        sleep(1)

        let resetButton = app.buttons["settings.advanced.resetButton"]
        let rebuildDatabaseButton = app.buttons["settings.advanced.rebuildDatabaseButton"]

        XCTAssertTrue(resetButton.waitForExistence(timeout: 5.0), "Reset button should exist")
        XCTAssertTrue(rebuildDatabaseButton.exists, "Rebuild database button should exist")
    }

    func testAdvancedTabDiagnosticsButtons() throws {
        let advancedTab = app.buttons["settings.advancedTab"]
        advancedTab.click()
        sleep(1)

        let exportLogsButton = app.buttons["settings.advanced.exportLogsButton"]
        let diagnosticsButton = app.buttons["settings.advanced.diagnosticsButton"]

        XCTAssertTrue(exportLogsButton.waitForExistence(timeout: 5.0), "Export logs button should exist")
        XCTAssertTrue(diagnosticsButton.exists, "Diagnostics button should exist")
    }

    func testAdvancedTabExportLogsButton() throws {
        let advancedTab = app.buttons["settings.advancedTab"]
        advancedTab.click()
        sleep(1)

        let exportLogsButton = app.buttons["settings.advanced.exportLogsButton"]
        XCTAssertTrue(exportLogsButton.waitForExistence(timeout: 5.0), "Export logs button should exist")

        // Click button (may open file picker)
        exportLogsButton.click()
        sleep(1)

        // Button should still exist
        XCTAssertTrue(exportLogsButton.exists, "Export logs button should remain functional")
    }

    // MARK: - Integration Tests

    func testCompleteSettingsWorkflow() throws {
        // Complete workflow: navigate all tabs -> change settings -> close

        let generalTab = app.buttons["settings.generalTab"]
        let recordingTab = app.buttons["settings.recordingTab"]
        let processingTab = app.buttons["settings.processingTab"]
        let storageTab = app.buttons["settings.storageTab"]
        let privacyTab = app.buttons["settings.privacyTab"]
        let advancedTab = app.buttons["settings.advancedTab"]

        XCTAssertTrue(generalTab.waitForExistence(timeout: 5.0), "Settings should be open")

        // 1. Navigate through all tabs
        recordingTab.click()
        sleep(1)

        processingTab.click()
        sleep(1)

        storageTab.click()
        sleep(1)

        privacyTab.click()
        sleep(1)

        advancedTab.click()
        sleep(1)

        generalTab.click()
        sleep(1)

        // 2. Change a setting on General tab
        let processingCompleteToggle = app.checkBoxes["settings.general.processingCompleteToggle"]
        XCTAssertTrue(processingCompleteToggle.exists, "Toggle should exist")
        processingCompleteToggle.click()
        sleep(1)

        // 3. Navigate to Recording tab and change setting
        recordingTab.click()
        sleep(1)

        let pauseToggle = app.checkBoxes["settings.recording.pauseWhenTimelineToggle"]
        XCTAssertTrue(pauseToggle.exists, "Pause toggle should exist")
        pauseToggle.click()
        sleep(1)

        // 4. Close settings
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        // Settings should be closed
        XCTAssertFalse(generalTab.exists, "Settings window should close")
    }

    func testSettingsPersistence() throws {
        // Test that settings persist across window close/reopen

        let generalTab = app.buttons["settings.generalTab"]
        XCTAssertTrue(generalTab.waitForExistence(timeout: 5.0), "Settings should be open")

        // Change a setting
        let processingCompleteToggle = app.checkBoxes["settings.general.processingCompleteToggle"]
        XCTAssertTrue(processingCompleteToggle.exists, "Toggle should exist")

        let initialValue = processingCompleteToggle.value as? Int
        processingCompleteToggle.click()
        sleep(1)

        let newValue = processingCompleteToggle.value as? Int
        XCTAssertNotEqual(initialValue, newValue, "Value should change")

        // Close settings
        app.typeKey("w", modifierFlags: .command)
        sleep(1)

        // Reopen settings
        openSettings()
        sleep(1)

        // Verify setting persisted (value should match newValue)
        let persistedValue = processingCompleteToggle.value as? Int
        XCTAssertEqual(persistedValue, newValue, "Setting should persist across close/reopen")
    }

    func testMultipleTabWorkflow() throws {
        // Test rapidly switching between tabs

        let generalTab = app.buttons["settings.generalTab"]
        let recordingTab = app.buttons["settings.recordingTab"]
        let storageTab = app.buttons["settings.storageTab"]
        let advancedTab = app.buttons["settings.advancedTab"]

        XCTAssertTrue(generalTab.waitForExistence(timeout: 5.0), "Settings should be open")

        // Rapidly switch tabs
        for _ in 0..<3 {
            recordingTab.click()
            sleep(1)

            storageTab.click()
            sleep(1)

            advancedTab.click()
            sleep(1)

            generalTab.click()
            sleep(1)
        }

        // All tabs should still be functional
        XCTAssertTrue(generalTab.exists, "General tab should remain functional")
        XCTAssertTrue(recordingTab.exists, "Recording tab should remain functional")
        XCTAssertTrue(storageTab.exists, "Storage tab should remain functional")
        XCTAssertTrue(advancedTab.exists, "Advanced tab should remain functional")
    }
}
