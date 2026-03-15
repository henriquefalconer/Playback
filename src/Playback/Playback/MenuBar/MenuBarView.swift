// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import os

struct MenuBarView: View {
    @ObservedObject var viewModel: MenuBarViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            Toggle("Record Screen", isOn: $viewModel.isRecordingEnabled)
                .toggleStyle(.switch)
                .onChange(of: viewModel.isRecordingEnabled) { oldValue, newValue in
                    viewModel.toggleRecording()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .accessibilityIdentifier("menubar.recordToggle")

            Divider()

            Button(action: {
                Log.menuBar.info("Open Timeline clicked")
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
                Log.menuBar.info("Settings clicked")
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

            Divider()

            Button(action: {
                Log.menuBar.info("About Playback clicked")
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
        .task {
            viewModel.startMonitoring()
        }
    }
}

#Preview {
    MenuBarView(viewModel: MenuBarViewModel())
}
