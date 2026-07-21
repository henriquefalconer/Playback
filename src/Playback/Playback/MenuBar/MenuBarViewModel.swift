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
    private var cancellables = Set<AnyCancellable>()
    private let launchTime = Date()

    init(configManager: ConfigManager = .shared,
         recordingService: RecordingService = .shared) {
        self.configManager = configManager
        self.recordingService = recordingService

        self.isRecordingEnabled = configManager.config.recordingEnabled

        setupBindings()
    }

    private func setupBindings() {
        // Drive the menu bar icon directly off the recording service's real state so
        // it can never drift — previously it only updated on config changes, so the
        // icon showed "paused" while recording actually ran.
        recordingService.$isRecording
            .combineLatest(recordingService.$isPausedBySystem, recordingService.$isPausedByTimeline)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.updateRecordingState()
            }
            .store(in: &cancellables)

        configManager.$config
            .receive(on: DispatchQueue.main)
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

        // The icon follows recordingService's published state via setupBindings(), so
        // start()/stop() flipping isRecording updates the menu bar on its own.
        if isRecordingEnabled {
            Log.menuBar.info("Recording toggled ON, excluded_apps=\(self.configManager.config.excludedApps.count, privacy: .public)")
            recordingService.start()

            var config = configManager.config
            config.recordingEnabled = true
            configManager.updateConfig(config)
        } else {
            Log.menuBar.info("Recording toggled OFF, total_captures=\(self.recordingService.captureCount, privacy: .public)")
            recordingService.stop()

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
        AppDelegate.isQuitAuthorized = true
        NSApp.terminate(nil)
    }

    private func updateRecordingState() {
        // The checkmark tracks user intent (config); the icon tracks reality (service).
        isRecordingEnabled = configManager.config.recordingEnabled

        let oldState = recordingState
        recordingState = recordingService.isRecording ? .recording : .paused
        if oldState != recordingState {
            Log.menuBar.info("Menu bar state: \(String(describing: oldState), privacy: .public) -> \(String(describing: self.recordingState), privacy: .public)")
        }
    }

}
