// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation

struct Config: Codable {
    var version: String
    var processingIntervalMinutes: Int
    var tempRetentionPolicy: String
    var recordingRetentionPolicy: String
    var exclusionMode: String
    var excludedApps: [String]
    var ffmpegCrf: Int
    var videoFps: Int
    var timelineShortcut: String
    var pauseWhenTimelineOpen: Bool
    var launchAtLogin: Bool?
    var notifications: Notifications

    struct Notifications: Codable {
        var processingComplete: Bool
        var processingErrors: Bool
        var diskSpaceWarnings: Bool
        var recordingStatus: Bool

        private enum CodingKeys: String, CodingKey {
            case processingComplete = "processing_complete"
            case processingErrors = "processing_errors"
            case diskSpaceWarnings = "disk_space_warnings"
            case recordingStatus = "recording_status"
        }
    }

    static var defaultConfig: Config {
        Config(
            version: "1.0.0",
            processingIntervalMinutes: 5,
            tempRetentionPolicy: "1_week",
            recordingRetentionPolicy: "never",
            exclusionMode: "skip",
            excludedApps: [],
            ffmpegCrf: 28,
            videoFps: 30,
            timelineShortcut: "Option+Shift+Space",
            pauseWhenTimelineOpen: true,
            launchAtLogin: true,
            notifications: Notifications(
                processingComplete: true,
                processingErrors: true,
                diskSpaceWarnings: true,
                recordingStatus: false
            )
        )
    }

    func validated() -> Config {
        var validated = self

        let validIntervals = [1, 5, 10, 15, 30, 60]
        if !validIntervals.contains(validated.processingIntervalMinutes) {
            validated.processingIntervalMinutes = 5
        }

        let validPolicies = ["never", "1_day", "1_week", "1_month"]
        if !validPolicies.contains(validated.tempRetentionPolicy) {
            validated.tempRetentionPolicy = "1_week"
        }
        if !validPolicies.contains(validated.recordingRetentionPolicy) {
            validated.recordingRetentionPolicy = "never"
        }

        if !["invisible", "skip"].contains(validated.exclusionMode) {
            validated.exclusionMode = "skip"
        }

        validated.excludedApps = validated.excludedApps
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: "^[a-zA-Z0-9.-]+$", options: .regularExpression) != nil }

        if validated.ffmpegCrf < 0 || validated.ffmpegCrf > 51 {
            validated.ffmpegCrf = 28
        }

        if validated.videoFps <= 0 {
            validated.videoFps = 30
        }

        if validated.version.isEmpty {
            validated.version = "1.0.0"
        }

        return validated
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case processingIntervalMinutes = "processing_interval_minutes"
        case tempRetentionPolicy = "temp_retention_policy"
        case recordingRetentionPolicy = "recording_retention_policy"
        case exclusionMode = "exclusion_mode"
        case excludedApps = "excluded_apps"
        case ffmpegCrf = "ffmpeg_crf"
        case videoFps = "video_fps"
        case timelineShortcut = "timeline_shortcut"
        case pauseWhenTimelineOpen = "pause_when_timeline_open"
        case launchAtLogin = "launch_at_login"
        case notifications
    }
}
