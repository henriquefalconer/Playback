// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

            RecordingSettingsTab()
                .tabItem {
                    Label("Recording", systemImage: "record.circle")
                }
                .tag(1)

            ProcessingSettingsTab()
                .tabItem {
                    Label("Processing", systemImage: "gearshape.2")
                }
                .tag(2)

            StorageSettingsTab()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(3)

            PrivacySettingsTab()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
                .tag(4)

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2.fill")
                }
                .tag(5)
        }
        .frame(width: 600, height: 500)
    }
}

struct GeneralSettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Processing complete", isOn: binding(\.notifications.processingComplete))
                Toggle("Processing errors", isOn: binding(\.notifications.processingErrors))
                    .help("Recommended")
                Toggle("Disk space warnings", isOn: binding(\.notifications.diskSpaceWarnings))
                    .help("Recommended")
                Toggle("Recording status", isOn: binding(\.notifications.recordingStatus))
            }

            Section("Global Shortcut") {
                HStack {
                    Text("Open Timeline:")
                    Spacer()
                    Text(configManager.config.timelineShortcut)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(
            get: { configManager.config[keyPath: keyPath] },
            set: { newValue in
                var updatedConfig = configManager.config
                updatedConfig[keyPath: keyPath] = newValue
                configManager.updateConfig(updatedConfig)
            }
        )
    }
}

struct RecordingSettingsTab: View {
    var body: some View {
        Form {
            Section("Recording") {
                Text("Recording settings will be added here")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ProcessingSettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager

    var body: some View {
        Form {
            Section("Processing Interval") {
                Picker("Process every:", selection: binding(\.processingIntervalMinutes)) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("60 minutes").tag(60)
                }
            }

            Section("Video Encoding") {
                HStack {
                    Text("Frame rate:")
                    Spacer()
                    Text("\(configManager.config.videoFps) fps")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Quality (CRF):")
                    Spacer()
                    Text("\(configManager.config.ffmpegCrf)")
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(
            get: { configManager.config[keyPath: keyPath] },
            set: { newValue in
                var updatedConfig = configManager.config
                updatedConfig[keyPath: keyPath] = newValue
                configManager.updateConfig(updatedConfig)
            }
        )
    }
}

struct StorageSettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager

    var body: some View {
        Form {
            Section("Retention Policies") {
                Picker("Temp files:", selection: binding(\.tempRetentionPolicy)) {
                    Text("Never delete").tag("never")
                    Text("1 day").tag("1_day")
                    Text("1 week").tag("1_week")
                    Text("1 month").tag("1_month")
                }

                Picker("Recordings:", selection: binding(\.recordingRetentionPolicy)) {
                    Text("Never delete").tag("never")
                    Text("1 day").tag("1_day")
                    Text("1 week").tag("1_week")
                    Text("1 month").tag("1_month")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(
            get: { configManager.config[keyPath: keyPath] },
            set: { newValue in
                var updatedConfig = configManager.config
                updatedConfig[keyPath: keyPath] = newValue
                configManager.updateConfig(updatedConfig)
            }
        )
    }
}

struct PrivacySettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager

    @State private var newAppId = ""

    var body: some View {
        Form {
            Section("App Exclusion") {
                Picker("Mode:", selection: binding(\.exclusionMode)) {
                    Text("Skip screenshots").tag("skip")
                    Text("Mark as invisible").tag("invisible")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Excluded Apps:")
                        .font(.headline)

                    List {
                        ForEach(configManager.config.excludedApps, id: \.self) { appId in
                            Text(appId)
                        }
                        .onDelete(perform: deleteApps)
                    }
                    .frame(height: 150)

                    HStack {
                        TextField("com.example.app", text: $newAppId)
                        Button("Add") {
                            addApp()
                        }
                        .disabled(newAppId.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(
            get: { configManager.config[keyPath: keyPath] },
            set: { newValue in
                var updatedConfig = configManager.config
                updatedConfig[keyPath: keyPath] = newValue
                configManager.updateConfig(updatedConfig)
            }
        )
    }

    private func addApp() {
        var updatedConfig = configManager.config
        if !updatedConfig.excludedApps.contains(newAppId) {
            updatedConfig.excludedApps.append(newAppId)
            configManager.updateConfig(updatedConfig)
            newAppId = ""
        }
    }

    private func deleteApps(at offsets: IndexSet) {
        var updatedConfig = configManager.config
        updatedConfig.excludedApps.remove(atOffsets: offsets)
        configManager.updateConfig(updatedConfig)
    }
}

struct AdvancedSettingsTab: View {
    var body: some View {
        Form {
            Section("Advanced") {
                Text("Advanced settings will be added here")
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    SettingsView()
        .environmentObject(ConfigManager.shared)
}
