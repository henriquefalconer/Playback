// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

struct MenuBarView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Toggle("Record Screen", isOn: $viewModel.isRecordingEnabled)
                .toggleStyle(.switch)
                .onChange(of: viewModel.isRecordingEnabled) { _, _ in
                    viewModel.toggleRecording()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("menubar.recordToggle")

            Divider()

            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "timeline")
            }) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Open Timeline")
                    Spacer()
                    Text("⌥⇧Space")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("menubar.openTimelineButton")

            Divider()

            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings...")
                    Spacer()
                    Text("⌘,")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("menubar.settingsButton")

            Button(action: {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "diagnostics")
            }) {
                HStack {
                    Image(systemName: "stethoscope")
                    Text("Diagnostics")
                    Spacer()
                    if viewModel.errorCount > 0 {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 16, height: 16)
                            Text("\(viewModel.errorCount)")
                                .font(.caption2)
                                .foregroundColor(.white)
                        }
                        .accessibilityIdentifier("menubar.errorBadge")
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("menubar.diagnosticsButton")

            Divider()

            Button(action: {
                NSApp.orderFrontStandardAboutPanel()
            }) {
                HStack {
                    Text("About Playback")
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("menubar.aboutButton")

            Divider()

            Button(action: viewModel.quitPlayback) {
                HStack {
                    Text("Quit Playback")
                    Spacer()
                    Text("⌘Q")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("menubar.quitButton")
        }
        .frame(minWidth: 220)
    }
}

#Preview {
    MenuBarView(viewModel: MenuBarViewModel())
}
