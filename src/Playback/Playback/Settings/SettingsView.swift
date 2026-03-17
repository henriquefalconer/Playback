// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import AppKit
import os
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var configManager: ConfigManager

    var body: some View {
        SettingsPanel()
            .environmentObject(configManager)
            .frame(minWidth: 400, maxWidth: 500)
    }
}

private struct SettingsPanel: View {
    @EnvironmentObject var configManager: ConfigManager

    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var storageInfo: StorageInfo?
    @State private var isCalculatingStorage = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        Form {
            Section("Launch Behavior") {
                Toggle("Launch Playback at login", isOn: $launchAtLoginEnabled)
                    .accessibilityIdentifier("settings.general.launchAtLoginToggle")
                    .onChange(of: launchAtLoginEnabled) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }

                if let error = launchAtLoginError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.top, 4)
                }
            }

            Section("Storage") {
                HStack {
                    if let info = storageInfo {
                        Text(info.totalFormatted)
                    } else if isCalculatingStorage {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("~10–14 GB/month typical usage")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        Log.settings.info("Delete All Recordings button tapped")
                        showDeleteConfirmation = true
                    } label: {
                        if isDeleting {
                            ProgressView()
                                .controlSize(.small)
                            Text("Deleting…")
                        } else {
                            Text("Delete All Recordings")
                        }
                    }
                    .disabled(isDeleting)
                    .confirmationDialog("Delete All Recordings?", isPresented: $showDeleteConfirmation) {
                        Button("Delete All", role: .destructive) {
                            Log.settings.info("Delete All Recordings confirmed by user")
                            isDeleting = true
                            deleteError = nil
                            Task {
                                do {
                                    try DataManager.shared.deleteAllRecordings()
                                    calculateStorage()
                                } catch {
                                    deleteError = error.localizedDescription
                                }
                                isDeleting = false
                            }
                        }
                        Button("Cancel", role: .cancel) {
                            Log.settings.info("Delete All Recordings cancelled by user")
                        }
                    } message: {
                        Text("This will permanently delete all data and metadata. Your settings will be preserved. This cannot be undone.")
                    }
                }

                if let error = deleteError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.top, 4)
                }
            }

            Section("Permissions") {
                VStack(spacing: 12) {
                    HStack {
                        Circle()
                            .fill(screenRecordingGranted ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text("Screen Recording:")
                        Spacer()
                        Text(screenRecordingGranted ? "Granted" : "Denied")
                            .foregroundColor(.secondary)
                        if !screenRecordingGranted {
                            Button("Open Settings") {
                                openScreenRecordingSettings()
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .accessibilityIdentifier("settings.general.screenRecordingButton")
                        }
                    }

                    HStack {
                        Circle()
                            .fill(accessibilityGranted ? Color.green : Color.yellow)
                            .frame(width: 8, height: 8)
                        Text("Accessibility:")
                        Spacer()
                        Text(accessibilityGranted ? "Granted" : "Optional")
                            .foregroundColor(.secondary)
                        if !accessibilityGranted {
                            Button("Open Settings") {
                                openAccessibilitySettings()
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                            .accessibilityIdentifier("settings.general.accessibilityButton")
                        }
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("Accessibility permission enables the global hotkey (\(configManager.config.timelineShortcut)).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background((!screenRecordingGranted || !accessibilityGranted) ? Color.yellow.opacity(0.1) : Color.clear)
                .cornerRadius(6)
            }

            Section("Global Shortcut") {
                HStack {
                    Text("Open Timeline:")
                    Spacer()
                    HotkeyRecorderView(
                        shortcut: binding(\.timelineShortcut),
                        onShortcutChanged: { newShortcut in
                            var config = configManager.config
                            config.timelineShortcut = newShortcut
                            configManager.updateConfig(config)
                        }
                    )
                    .accessibilityIdentifier("settings.general.hotkeyRecorder")
                }
            }

            Section("Excluded Apps") {
                if configManager.config.excludedApps.isEmpty {
                    Text("No apps excluded")
                        .foregroundColor(.secondary)
                        .font(.caption)
                        .padding(.vertical, 8)
                } else {
                    ForEach(configManager.config.excludedApps, id: \.self) { appId in
                        HStack {
                            Text(appId)
                            Spacer()
                            Button {
                                removeApp(appId)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Button {
                    pickApp()
                } label: {
                    HStack {
                        Spacer()
                        Text("Add App")
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("settings.privacy.addAppButton")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkPermissions()
            launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
            calculateStorage()
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(
            get: { configManager.config[keyPath: keyPath] },
            set: { newValue in
                var config = configManager.config
                config[keyPath: keyPath] = newValue
                configManager.updateConfig(config)
            }
        )
    }

    private func checkPermissions() {
        screenRecordingGranted = CGPreflightScreenCaptureAccess()
        accessibilityGranted = AXIsProcessTrusted()
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.shared.setEnabled(enabled)
            launchAtLoginError = nil
            var config = configManager.config
            config.launchAtLogin = enabled
            configManager.updateConfig(config)
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        }
    }

    private func removeApp(_ bundleId: String) {
        var config = configManager.config
        config.excludedApps.removeAll { $0 == bundleId }
        configManager.updateConfig(config)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.title = "Select an App"
        panel.allowedContentTypes = [UTType.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return }

        var config = configManager.config
        if !config.excludedApps.contains(bundleId) {
            config.excludedApps.append(bundleId)
            configManager.updateConfig(config)
        }
    }

    private func calculateStorage() {
        isCalculatingStorage = true
        Task.detached {
            let info = StorageInfo.calculate()
            await MainActor.run {
                storageInfo = info
                isCalculatingStorage = false
            }
        }
    }
}

private struct StorageInfo {
    let totalBytes: Int64

    var totalFormatted: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    static func calculate() -> StorageInfo {
        StorageInfo(totalBytes: directorySize(Paths.baseDataDirectory))
    }

    private static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }
}

#Preview {
    SettingsView()
        .environmentObject(ConfigManager.shared)
}
