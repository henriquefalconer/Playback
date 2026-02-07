// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import Combine

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
    @Published var isRecordingEnabled: Bool = false
    @Published var showSettings = false
    @Published var showDiagnostics = false
    @Published var errorCount: Int = 0

    private let configManager: ConfigManager
    private let launchAgentManager: LaunchAgentManager
    private var statusTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(configManager: ConfigManager = .shared, launchAgentManager: LaunchAgentManager = .shared) {
        self.configManager = configManager
        self.launchAgentManager = launchAgentManager

        setupBindings()
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
        isRecordingEnabled.toggle()

        Task {
            do {
                if isRecordingEnabled {
                    try launchAgentManager.startAgent(.recording)
                    recordingState = .recording
                } else {
                    try launchAgentManager.stopAgent(.recording)
                    recordingState = .paused
                }
            } catch {
                print("[MenuBar] Error toggling recording: \(error)")
                recordingState = .error
                isRecordingEnabled.toggle()
            }
        }
    }

    func openTimeline() {
        NSApp.activate(ignoringOtherApps: true)
        if NSApp.windows.contains(where: { $0.identifier?.rawValue == "timeline" }) {
            NSApp.windows.first(where: { $0.identifier?.rawValue == "timeline" })?.makeKeyAndOrderFront(nil)
        } else {
            NSApp.sendAction(#selector(NSResponder.newDocument(_:)), to: nil, from: nil)
        }
    }

    func openSettings() {
        if let url = URL(string: "playback://settings") {
            NSWorkspace.shared.open(url)
        }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "settings" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func openDiagnostics() {
        showDiagnostics = true
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
        Task {
            do {
                try? launchAgentManager.stopAgent(.recording)
                try? launchAgentManager.stopAgent(.processing)

                NSWorkspace.shared.runningApplications
                    .filter { $0.bundleIdentifier == "com.playback.timeline" }
                    .forEach { $0.terminate() }

                NSApp.terminate(nil)
            }
        }
    }

    private func startStatusMonitoring() {
        statusTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.updateRecordingState()
        }
        updateRecordingState()
    }

    private func updateRecordingState() {
        let status = launchAgentManager.getAgentStatus(.recording)

        if status.isRunning {
            recordingState = .recording
            isRecordingEnabled = true
        } else if let exitStatus = status.lastExitStatus, exitStatus != 0 {
            recordingState = .error
            isRecordingEnabled = false
        } else {
            recordingState = .paused
            isRecordingEnabled = false
        }
    }

    deinit {
        statusTimer?.invalidate()
    }
}
