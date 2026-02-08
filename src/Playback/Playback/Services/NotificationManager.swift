// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import AppKit
import UserNotifications

enum NotificationType {
    case error
    case warning
    case info
    case cleanup
}

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private let notificationCenter = UNUserNotificationCenter.current()
    private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private override init() {
        super.init()
        notificationCenter.delegate = self
        setupNotificationCategories()
        Task {
            await checkAuthorizationStatus()
        }
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            return granted
        } catch {
            if Paths.isDevelopment {
                print("Failed to request notification permission: \(error)")
            }
            return false
        }
    }

    private func checkAuthorizationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func setupNotificationCategories() {
        let settingsAction = UNNotificationAction(
            identifier: "OPEN_SETTINGS",
            title: "Open Settings",
            options: [.foreground]
        )

        let settingsCategory = UNNotificationCategory(
            identifier: "SETTINGS_ACTION",
            actions: [settingsAction],
            intentIdentifiers: [],
            options: []
        )

        notificationCenter.setNotificationCategories([settingsCategory])
    }

    func showNotification(
        title: String,
        body: String,
        type: NotificationType,
        withSettingsButton: Bool = false
    ) {
        Task {
            await checkAuthorizationStatus()

            guard authorizationStatus == .authorized else {
                if Paths.isDevelopment {
                    print("Notification not shown - authorization status: \(authorizationStatus)")
                }
                return
            }

            guard shouldShowNotification(for: type) else {
                if Paths.isDevelopment {
                    print("Notification suppressed by config settings: \(type)")
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = type == .error ? .defaultCritical : .default

            if withSettingsButton {
                content.categoryIdentifier = "SETTINGS_ACTION"
            }

            let identifier = UUID().uuidString
            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: nil
            )

            do {
                try await notificationCenter.add(request)
                if Paths.isDevelopment {
                    print("Notification sent: \(title)")
                }
            } catch {
                if Paths.isDevelopment {
                    print("Failed to send notification: \(error)")
                }
            }
        }
    }

    private func shouldShowNotification(for type: NotificationType) -> Bool {
        let config = ConfigManager.shared.config.notifications

        switch type {
        case .error:
            return config.processingErrors || config.recordingStatus
        case .warning:
            return config.diskSpaceWarnings
        case .info:
            return config.processingComplete
        case .cleanup:
            return config.processingComplete
        }
    }

    func showRecordingError(message: String) {
        showNotification(
            title: "Recording Error",
            body: message,
            type: .error,
            withSettingsButton: true
        )
    }

    func showProcessingError(message: String) {
        showNotification(
            title: "Processing Failed",
            body: message,
            type: .error,
            withSettingsButton: true
        )
    }

    func showDiskSpaceWarning(freeGB: Double) {
        showNotification(
            title: "Low Disk Space",
            body: String(format: "Only %.1f GB free. Recording may stop soon.", freeGB),
            type: .warning,
            withSettingsButton: true
        )
    }

    func showCleanupComplete(freedGB: Double) {
        showNotification(
            title: "Cleanup Complete",
            body: String(format: "Freed %.2f GB of disk space", freedGB),
            type: .cleanup
        )
    }

    func showProcessingComplete(segmentCount: Int, date: String) {
        showNotification(
            title: "Processing Complete",
            body: "Created \(segmentCount) video segments for \(date)",
            type: .info
        )
    }

    func showPermissionDenied(permissionType: String) {
        showNotification(
            title: "Permission Required",
            body: "Playback needs \(permissionType) permission to function properly",
            type: .error,
            withSettingsButton: true
        )
    }

    func showServiceCrashed(serviceName: String) {
        showNotification(
            title: "Service Crashed",
            body: "\(serviceName) has stopped unexpectedly",
            type: .error,
            withSettingsButton: true
        )
    }

    func showDiskFull() {
        showNotification(
            title: "Disk Full",
            body: "Recording stopped: No disk space available",
            type: .error,
            withSettingsButton: true
        )
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "OPEN_SETTINGS" {
            Task { @MainActor in
                NSApp.activate(ignoringOtherApps: true)

                if let settingsURL = URL(string: "playback://settings") {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
        }

        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }
}
