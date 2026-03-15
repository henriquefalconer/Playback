// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import os
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
                    Log.system.debug("Launch at login already enabled, skipping")
                    return
                }
                try SMAppService.mainApp.register()
                Log.system.info("Launch at login enabled")
            } else {
                if SMAppService.mainApp.status == .notRegistered {
                    Log.system.debug("Launch at login already disabled, skipping")
                    return
                }
                try SMAppService.mainApp.unregister()
                Log.system.info("Launch at login disabled")
            }
        } else {
            Log.system.error("Launch at login requires macOS 13.0+")
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
