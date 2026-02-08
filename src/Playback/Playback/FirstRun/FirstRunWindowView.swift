// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

struct FirstRunWindowView: View {
    @StateObject private var coordinator = FirstRunCoordinator()
    @State private var isProcessing = false
    @State private var setupError: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ProgressIndicator(currentStep: coordinator.currentStep)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            currentStepView
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            navigationBar
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 600, height: 500)
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch coordinator.currentStep {
        case .welcome:
            WelcomeView(coordinator: coordinator)
        case .permissions:
            PermissionsView(coordinator: coordinator)
        case .storage:
            StorageSetupView(coordinator: coordinator)
        case .dependencies:
            DependencyCheckView(coordinator: coordinator)
        case .config:
            InitialConfigView(coordinator: coordinator)
        }
    }

    @ViewBuilder
    private var navigationBar: some View {
        HStack {
            if isProcessing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Setting up Playback...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let error = setupError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }

            HStack(spacing: 12) {
                if coordinator.currentStep.canGoBack {
                    Button("Back") {
                        coordinator.moveToPreviousStep()
                        setupError = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                    .accessibilityIdentifier("firstrun.backButton")
                }

                if coordinator.currentStep == .config && coordinator.currentStep.canSkip {
                    Button("Skip") {
                        finishSetup()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                    .accessibilityIdentifier("firstrun.skipButton")
                }

                if coordinator.currentStep == FirstRunStep.allCases.last {
                    Button("Finish") {
                        finishSetup()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.canProceed() || isProcessing)
                    .accessibilityIdentifier("firstrun.finishButton")
                } else {
                    Button("Continue") {
                        coordinator.moveToNextStep()
                        setupError = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!coordinator.canProceed() || isProcessing)
                    .accessibilityIdentifier("firstrun.continueButton")
                }
            }
        }
    }

    private func finishSetup() {
        isProcessing = true
        setupError = nil

        Task {
            do {
                try await coordinator.completeSetup()

                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    setupError = "Setup failed: \(error.localizedDescription)"
                    isProcessing = false
                }
            }
        }
    }
}

struct ProgressIndicator: View {
    let currentStep: FirstRunStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(FirstRunStep.allCases.enumerated()), id: \.element) { index, step in
                HStack(spacing: 0) {
                    StepCircle(
                        step: step,
                        isCurrent: step == currentStep,
                        isCompleted: step.rawValue < currentStep.rawValue
                    )

                    if index < FirstRunStep.allCases.count - 1 {
                        Rectangle()
                            .fill(step.rawValue < currentStep.rawValue ? Color.blue : Color.gray.opacity(0.3))
                            .frame(height: 2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct StepCircle: View {
    let step: FirstRunStep
    let isCurrent: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .bold))
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(textColor)
                }
            }

            Text(step.title)
                .font(.caption)
                .foregroundColor(isCurrent ? .primary : .secondary)
                .fontWeight(isCurrent ? .semibold : .regular)
        }
        .frame(minWidth: 80)
    }

    private var backgroundColor: Color {
        if isCompleted {
            return .blue
        } else if isCurrent {
            return .blue.opacity(0.2)
        } else {
            return Color.gray.opacity(0.2)
        }
    }

    private var textColor: Color {
        if isCurrent {
            return .blue
        } else {
            return .secondary
        }
    }
}
