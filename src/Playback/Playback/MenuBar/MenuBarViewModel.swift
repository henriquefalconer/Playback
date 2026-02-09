// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Combine
import AppKit
import ApplicationServices

enum RecordingState {
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
            return "Playback: Error (click for details)"
        }
    }
}

@MainActor
final class MenuBarViewModel: ObservableObject {
    @Published var recordingState: RecordingState = .paused
    @Published var isRecordingEnabled: Bool = false {
        willSet {
            print("[MenuBarViewModel] isRecordingEnabled will change: \(isRecordingEnabled) → \(newValue)")
        }
        didSet {
            print("[MenuBarViewModel] isRecordingEnabled did change to: \(isRecordingEnabled)")
        }
    }
    @Published var showSettings = false
    @Published var showDiagnostics = false
    @Published var errorCount: Int = 0

    private let configManager: ConfigManager
    private let launchAgentManager: LaunchAgentManager
    private let recordingService: RecordingService
    private var statusTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lastUserToggleTime: Date?

    init(configManager: ConfigManager = .shared,
         launchAgentManager: LaunchAgentManager = .shared,
         recordingService: RecordingService = .shared) {
        self.configManager = configManager
        self.launchAgentManager = launchAgentManager
        self.recordingService = recordingService

        self.isRecordingEnabled = configManager.config.recordingEnabled
        print("[MenuBarViewModel] Initialized with recordingEnabled=\(self.isRecordingEnabled)")

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
        print("[MenuBarViewModel] toggleRecording() called, isRecordingEnabled=\(isRecordingEnabled)")

        // Check permission before enabling
        if isRecordingEnabled {
            let hasPermission = CGPreflightScreenCaptureAccess()
            print("[MenuBarViewModel] Permission check: \(hasPermission)")

            if !hasPermission {
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

        // Use Swift RecordingService (no LaunchAgent needed)
        if isRecordingEnabled {
            print("[MenuBarViewModel] Enabling recording")
            recordingService.start()
            recordingState = .recording

            var config = configManager.config
            config.recordingEnabled = true
            configManager.updateConfig(config)
        } else {
            print("[MenuBarViewModel] Disabling recording")
            recordingService.stop()
            recordingState = .paused

            var config = configManager.config
            config.recordingEnabled = false
            configManager.updateConfig(config)
        }
    }

    func quitPlayback() {
        let alert = NSAlert()
        alert.messageText = "Stop recording and quit Playback?"
        alert.informativeText = "This will stop all Playback services:\n• Recording service will stop\n• Processing service will stop\n• Timeline viewer will close\n• Menu bar icon will disappear\n\nUnprocessed screenshots will remain for later processing."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            performQuit()
        }
    }

    private func performQuit() {
        // Stop Swift RecordingService
        recordingService.stop()

        // Stop Python processing service
        try? launchAgentManager.stopAgent(.processing)

        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == "com.falconer.Playback" }
            .forEach { $0.terminate() }

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
            print("[MenuBarViewModel] Skipping update - recent user toggle")
            return
        }

        // Check Swift RecordingService status
        print("[MenuBarViewModel] Updating state - recordingService.isRecording=\(recordingService.isRecording)")
        if recordingService.isRecording {
            recordingState = .recording
            isRecordingEnabled = true
        } else {
            recordingState = .paused
            isRecordingEnabled = false
        }
    }

    deinit {
        statusTimer?.invalidate()
    }
}
