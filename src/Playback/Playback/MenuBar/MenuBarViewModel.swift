// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Combine
import AppKit
import ApplicationServices
import os

enum RecordingState: Equatable {
    case recording
    case paused
    case error

    var iconName: String {
        switch self {
        case .recording:
            return "record.circle.fill"
        case .paused:
            return "record.circle"
        case .error:
            return "exclamationmark.circle.fill"
        }
    }

    var tooltip: String {
        switch self {
        case .recording:
            return "Playback: Recording"
        case .paused:
            return "Playback: Paused"
        case .error:
            return "Playback: Error"
        }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var recordingState: RecordingState = .paused
    @Published var isRecordingEnabled: Bool = false
    private let configManager: ConfigManager
    private let recordingService: RecordingService
    private var statusTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastUserToggleTime: Date?
    private let launchTime = Date()

    init(configManager: ConfigManager = .shared,
         recordingService: RecordingService = .shared) {
        self.configManager = configManager
        self.recordingService = recordingService

        self.isRecordingEnabled = configManager.config.recordingEnabled

        setupBindings()
    }

    func startMonitoring() {
        startStatusMonitoring()
    }

    private func setupBindings() {
        configManager.$config
            .sink { [weak self] _ in
                self?.updateRecordingState()
            }
            .store(in: &cancellables)
    }

    func toggleRecording() {
        Log.menuBar.debug("toggleRecording() called, isRecordingEnabled=\(self.isRecordingEnabled)")

        // Check permission before enabling
        if isRecordingEnabled {
            let hasPermission = CGPreflightScreenCaptureAccess()

            if !hasPermission {
                Log.menuBar.notice("Permission denied alert shown: Screen Recording permission not granted")
                // Permission denied - revert toggle
                isRecordingEnabled = false

                let alert = NSAlert()
                alert.messageText = "Screen Recording Permission Required"
                alert.informativeText = "Playback needs Screen Recording permission to capture your screen. Please grant permission in System Settings → Privacy & Security → Screen Recording."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Cancel")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                }
                return
            }
        }

        lastUserToggleTime = Date()

        if isRecordingEnabled {
            Log.menuBar.info("Recording toggled ON, excluded_apps=\(self.configManager.config.excludedApps.count, privacy: .public)")
            recordingService.start()
            recordingState = .recording

            var config = configManager.config
            config.recordingEnabled = true
            configManager.updateConfig(config)
        } else {
            Log.menuBar.info("Recording toggled OFF, total_captures=\(self.recordingService.captureCount, privacy: .public)")
            recordingService.stop()
            recordingState = .paused

            var config = configManager.config
            config.recordingEnabled = false
            configManager.updateConfig(config)
        }
    }

    func quitPlayback() {
        performQuit()
    }

    private func performQuit() {
        let uptimeSeconds = Int(Date().timeIntervalSince(launchTime))
        Log.menuBar.info("Quit requested: uptime=\(uptimeSeconds, privacy: .public)s, total_captures=\(self.recordingService.captureCount, privacy: .public)")
        recordingService.stop()
        ProcessingService.shared.stop()
        NSApp.terminate(nil)
    }

    private func startStatusMonitoring() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateRecordingState()
        }
        updateRecordingState()
    }

    private func updateRecordingState() {
        if let lastToggle = lastUserToggleTime, Date().timeIntervalSince(lastToggle) < 10 {
            Log.menuBar.debug("Skipping update - recent user toggle")
            return
        }

        let oldState = recordingState
        Log.menuBar.debug("Updating state - recordingService.isRecording=\(self.recordingService.isRecording), isPausedBySystem=\(self.recordingService.isPausedBySystem)")
        if recordingService.isRecording {
            recordingState = .recording
            isRecordingEnabled = true
        } else if recordingService.isPausedBySystem {
            // System-initiated pause (display sleep / screen saver) — show paused but keep toggle on
            recordingState = .paused
            isRecordingEnabled = true
        } else {
            recordingState = .paused
            isRecordingEnabled = false
        }
        if oldState != recordingState {
            Log.menuBar.info("Menu bar state changed: \(String(describing: oldState), privacy: .public) -> \(String(describing: self.recordingState), privacy: .public)")
        }
    }

    deinit {
        statusTimer?.invalidate()
    }
}
