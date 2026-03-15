// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

struct Config: Codable {
    var version: String
    var excludedApps: [String]
    var timelineShortcut: String
    var recordingEnabled: Bool
    var launchAtLogin: Bool?

    static var defaultConfig: Config {
        Config(
            version: "1.0.0",
            excludedApps: [],
            timelineShortcut: "Option+Shift+Space",
            recordingEnabled: false,
            launchAtLogin: true
        )
    }

    func validated() -> Config {
        var validated = self

        validated.excludedApps = validated.excludedApps
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: "^[a-zA-Z0-9.-]+$", options: .regularExpression) != nil }

        if validated.version.isEmpty {
            validated.version = "1.0.0"
        }

        return validated
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case excludedApps = "excluded_apps"
        case timelineShortcut = "timeline_shortcut"
        case recordingEnabled = "recording_enabled"
        case launchAtLogin = "launch_at_login"
    }
}
