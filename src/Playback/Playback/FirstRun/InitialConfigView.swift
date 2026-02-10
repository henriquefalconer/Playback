// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

struct InitialConfigView: View {
    @ObservedObject var coordinator: FirstRunCoordinator

    private let processingIntervals = [1, 5, 10, 15, 30, 60]
    private let retentionPolicies = [
        ("never", "Never delete"),
        ("1_day", "1 day"),
        ("1_week", "1 week"),
        ("1_month", "1 month")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Text("Initial Configuration")
                .font(.title)
                .fontWeight(.bold)

            Text("Configure your recording preferences. You can change these later in Settings.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 20) {
                ConfigCard(icon: "record.circle.fill", title: "Recording") {
                    Toggle("Start recording now", isOn: $coordinator.startRecordingNow)
                        .toggleStyle(.switch)

                    Text("If disabled, you can start recording later from the menu bar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ConfigCard(icon: "clock.fill", title: "Processing Interval") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How often should recordings be processed into video segments?")
                            .font(.callout)
                            .foregroundColor(.secondary)

                        Picker("Processing Interval", selection: $coordinator.processingInterval) {
                            ForEach(processingIntervals, id: \.self) { interval in
                                Text(formatInterval(interval)).tag(interval)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                ConfigCard(icon: "trash.fill", title: "Retention Policies") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Temporary Files")
                                .font(.callout)
                            Text("Raw screenshots before processing")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Temp Retention", selection: $coordinator.tempRetentionPolicy) {
                                ForEach(retentionPolicies, id: \.0) { policy in
                                    Text(policy.1).tag(policy.0)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Processed Recordings")
                                .font(.callout)
                            Text("Final video segments")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Picker("Recording Retention", selection: $coordinator.recordingRetentionPolicy) {
                                ForEach(retentionPolicies, id: \.0) { policy in
                                    Text(policy.1).tag(policy.0)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Default settings work well for most users. You can adjust these anytime.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.top, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func formatInterval(_ minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes)m"
        } else {
            return "\(minutes / 60)h"
        }
    }
}

struct ConfigCard<Content: View>: View {
    let icon: String
    let title: String
    let content: Content

    init(icon: String, title: String, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 24)

                Text(title)
                    .font(.headline)
            }

            content
                .padding(.leading, 36)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
