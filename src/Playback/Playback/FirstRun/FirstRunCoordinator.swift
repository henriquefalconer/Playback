// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import SwiftUI
import Combine

enum FirstRunStep: Int, CaseIterable {
    case welcome = 0
    case permissions = 1
    case storage = 2
    case dependencies = 3
    case config = 4

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .permissions: return "Permissions"
        case .storage: return "Storage"
        case .dependencies: return "Dependencies"
        case .config: return "Configuration"
        }
    }

    var canSkip: Bool {
        switch self {
        case .welcome, .permissions, .storage, .dependencies:
            return false
        case .config:
            return true
        }
    }

    var canGoBack: Bool {
        self != .welcome
    }

    var nextStep: FirstRunStep? {
        let nextRawValue = rawValue + 1
        guard nextRawValue < FirstRunStep.allCases.count else {
            return nil
        }
        return FirstRunStep(rawValue: nextRawValue)
    }

    var previousStep: FirstRunStep? {
        guard rawValue > 0 else { return nil }
        return FirstRunStep(rawValue: rawValue - 1)
    }
}

enum FirstRunValidationState {
    case notStarted
    case checking
    case valid
    case invalid(String)

    var isValid: Bool {
        if case .valid = self {
            return true
        }
        return false
    }
}

@MainActor
final class FirstRunCoordinator: ObservableObject {
    @Published var currentStep: FirstRunStep = .welcome
    @Published var screenRecordingPermission: FirstRunValidationState = .notStarted
    @Published var accessibilityPermission: FirstRunValidationState = .notStarted
    @Published var storageValidation: FirstRunValidationState = .notStarted
    @Published var pythonValidation: FirstRunValidationState = .notStarted
    @Published var ffmpegValidation: FirstRunValidationState = .notStarted

    @Published var availableDiskSpace: UInt64 = 0

    @Published var startRecordingNow: Bool = false
    @Published var processingInterval: Int = 5
    @Published var tempRetentionPolicy: String = "1_week"
    @Published var recordingRetentionPolicy: String = "never"

    private static let hasCompletedFirstRunKey = "hasCompletedFirstRun"

    static var hasCompletedFirstRun: Bool {
        UserDefaults.standard.bool(forKey: hasCompletedFirstRunKey)
    }

    static func markFirstRunComplete() {
        UserDefaults.standard.set(true, forKey: hasCompletedFirstRunKey)
    }

    func moveToNextStep() {
        if let next = currentStep.nextStep {
            currentStep = next
        }
    }

    func moveToPreviousStep() {
        if let previous = currentStep.previousStep {
            currentStep = previous
        }
    }

    func canProceed() -> Bool {
        switch currentStep {
        case .welcome:
            return true
        case .permissions:
            return screenRecordingPermission.isValid
        case .storage:
            return storageValidation.isValid
        case .dependencies:
            return pythonValidation.isValid && ffmpegValidation.isValid
        case .config:
            return true
        }
    }

    func completeSetup() async throws {
        print("[FirstRunCoordinator] Starting setup")
        try Paths.ensureDirectoriesExist()

        var config = Config.defaultConfig
        config.processingIntervalMinutes = processingInterval
        config.tempRetentionPolicy = tempRetentionPolicy
        config.recordingRetentionPolicy = recordingRetentionPolicy
        config.recordingEnabled = startRecordingNow  // Set based on user's choice

        print("[FirstRunCoordinator] Config: recordingEnabled=\(config.recordingEnabled)")

        let configManager = ConfigManager.shared
        configManager.updateConfig(config)

        let agentManager = LaunchAgentManager.shared

        // Install Python processing service (LaunchAgent)
        try agentManager.installAgent(.processing)
        try agentManager.loadAgent(.processing)

        // Install cleanup service (LaunchAgent)
        try agentManager.installAgent(.cleanup)
        try agentManager.loadAgent(.cleanup)

        print("[FirstRunCoordinator] LaunchAgents installed")

        // Start services based on user's choice
        if startRecordingNow {
            print("[FirstRunCoordinator] Starting services")

            // Start Swift recording service (in-app)
            let recordingService = RecordingService.shared
            recordingService.start()

            // Start processing service
            try agentManager.startAgent(.processing)

            print("[FirstRunCoordinator] Services started")
        }

        FirstRunCoordinator.markFirstRunComplete()
        print("[FirstRunCoordinator] Setup complete")

        // Notify AppDelegate to start services (for cases where first-run happens during this session)
        NotificationCenter.default.post(name: NSNotification.Name("FirstRunComplete"), object: nil)
    }
}
