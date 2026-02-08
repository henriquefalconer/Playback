// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import XCTest
@testable import Playback

@MainActor
final class NotificationManagerTests: XCTestCase {
    func testNotificationTypeEnum() {
        let errorType = NotificationType.error
        let warningType = NotificationType.warning
        let infoType = NotificationType.info
        let cleanupType = NotificationType.cleanup

        XCTAssertNotNil(errorType)
        XCTAssertNotNil(warningType)
        XCTAssertNotNil(infoType)
        XCTAssertNotNil(cleanupType)
    }

    func testConvenienceMethodsExist() {
        let manager = NotificationManager.shared

        manager.showRecordingError(message: "Test error")
        manager.showProcessingError(message: "Test processing error")
        manager.showDiskSpaceWarning(freeGB: 5.0)
        manager.showCleanupComplete(freedGB: 10.0)
        manager.showProcessingComplete(segmentCount: 5, date: "2026-02-08")
        manager.showPermissionDenied(permissionType: "Screen Recording")
        manager.showServiceCrashed(serviceName: "Recording Service")
        manager.showDiskFull()
    }
}
