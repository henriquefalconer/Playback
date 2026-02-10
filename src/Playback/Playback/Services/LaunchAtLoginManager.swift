// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }

        do {
            return SMAppService.mainApp.status == .enabled
        } catch {
            return false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                if SMAppService.mainApp.status == .enabled {
                    return
                }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered {
                    return
                }
                try SMAppService.mainApp.unregister()
            }
        } else {
            throw LaunchAtLoginError.unsupportedOS
        }
    }

    enum LaunchAtLoginError: LocalizedError {
        case unsupportedOS
        case registrationFailed
        case unregistrationFailed

        var errorDescription: String? {
            switch self {
            case .unsupportedOS:
                return "Launch at login requires macOS 13.0 or later"
            case .registrationFailed:
                return "Failed to enable launch at login"
            case .unregistrationFailed:
                return "Failed to disable launch at login"
            }
        }
    }
}
