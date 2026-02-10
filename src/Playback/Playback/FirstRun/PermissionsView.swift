// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import ApplicationServices

struct PermissionsView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    var body: some View {
        VStack(spacing: 24) {
            Text("Permissions Required")
                .font(.title)
                .fontWeight(.bold)

            Text("Playback needs these permissions to function properly.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 20) {
                PermissionCard(
                    icon: "video.fill",
                    title: "Screen Recording",
                    description: "Required to capture your screen activity",
                    state: coordinator.screenRecordingPermission,
                    required: true,
                    onCheck: { checkScreenRecordingPermission() },
                    onRequest: { requestScreenRecordingPermission() }
                )

                PermissionCard(
                    icon: "command",
                    title: "Accessibility",
                    description: "Optional: Enables global hotkey (Option+Shift+Space) for timeline",
                    state: coordinator.accessibilityPermission,
                    required: false,
                    onCheck: { checkAccessibilityPermission() },
                    onRequest: { requestAccessibilityPermission() }
                )
            }
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            checkScreenRecordingPermission()
            checkAccessibilityPermission()

            // Auto-refresh permission status when app becomes active
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                checkScreenRecordingPermission()
                checkAccessibilityPermission()
            }
        }
        .onDisappear {
            // Remove observer when view disappears
            NotificationCenter.default.removeObserver(
                self,
                name: NSApplication.didBecomeActiveNotification,
                object: nil
            )
        }
    }

    private func checkScreenRecordingPermission() {
        coordinator.screenRecordingPermission = .checking

        DispatchQueue.global(qos: .userInitiated).async {
            let hasPermission = CGPreflightScreenCaptureAccess()

            DispatchQueue.main.async {
                if hasPermission {
                    coordinator.screenRecordingPermission = .valid
                } else {
                    coordinator.screenRecordingPermission = .invalid("Permission not granted")
                }
            }
        }
    }

    private func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            checkScreenRecordingPermission()
        }
    }

    private func checkAccessibilityPermission() {
        coordinator.accessibilityPermission = .checking

        DispatchQueue.global(qos: .userInitiated).async {
            let promptKey = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
            let options = [promptKey: false] as CFDictionary
            let hasPermission = AXIsProcessTrustedWithOptions(options)

            DispatchQueue.main.async {
                if hasPermission {
                    coordinator.accessibilityPermission = .valid
                } else {
                    coordinator.accessibilityPermission = .invalid("Permission not granted")
                }
            }
        }
    }

    private func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeRetainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let _ = AXIsProcessTrustedWithOptions(options)

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            checkAccessibilityPermission()
        }
    }
}

struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let state: FirstRunValidationState
    let required: Bool
    let onCheck: () -> Void
    let onRequest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                        if !required {
                            Text("Optional")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusIcon
            }

            HStack(spacing: 8) {
                Button("Check Status") {
                    onCheck()
                }
                .buttonStyle(.bordered)

                if case .invalid = state {
                    Button("Grant Permission") {
                        onRequest()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch state {
        case .notStarted:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        case .checking:
            ProgressView()
                .controlSize(.small)
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
}
