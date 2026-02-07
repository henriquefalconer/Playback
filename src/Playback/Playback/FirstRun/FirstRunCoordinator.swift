// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import Foundation
import SwiftUI

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
        guard let nextRawValue = rawValue + 1,
              nextRawValue < FirstRunStep.allCases.count else {
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
        try Paths.ensureDirectoriesExist()

        var config = Config.defaultConfig
        config.processingIntervalMinutes = processingInterval
        config.tempRetentionPolicy = tempRetentionPolicy
        config.recordingRetentionPolicy = recordingRetentionPolicy

        let configManager = ConfigManager.shared
        configManager.updateConfig(config)

        let agentManager = LaunchAgentManager.shared
        try agentManager.installAgent(.recording)
        try agentManager.installAgent(.processing)
        try agentManager.loadAgent(.recording)
        try agentManager.loadAgent(.processing)

        if startRecordingNow {
            try agentManager.startAgent(.recording)
            try agentManager.startAgent(.processing)
        }

        FirstRunCoordinator.markFirstRunComplete()
    }
}
