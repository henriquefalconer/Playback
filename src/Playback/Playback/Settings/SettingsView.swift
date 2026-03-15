// Copyright (c) 2026 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import AppKit

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
    @State private var newAppId = ""

    private let recommendedExclusions: [(bundleId: String, name: String)] = [
        ("com.apple.keychainaccess", "Keychain Access"),
        ("com.1password.1password", "1Password 8"),
        ("com.agilebits.onepassword7", "1Password 7"),
        ("com.lastpass.LastPass", "LastPass"),
        ("com.dashlane.Dashlane", "Dashlane"),
        ("com.keepassxc.keepassxc", "KeePassXC"),
        ("com.bitwarden.desktop", "Bitwarden"),
        ("org.keepassx.keepassxc", "KeePassX")
    ]

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
                        Text("Accessibility permission enables the global hotkey (Option+Shift+Space).")
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

            Section("Recommended Exclusions") {
                Text("Password managers and sensitive apps")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(recommendedExclusions, id: \.bundleId) { app in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                            Text(app.bundleId)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        if configManager.config.excludedApps.contains(app.bundleId) {
                            Text("Added")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Button("Add") {
                                addRecommendedApp(app.bundleId)
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section("Excluded Apps") {
                VStack(alignment: .leading, spacing: 8) {
                    if configManager.config.excludedApps.isEmpty {
                        Text("No apps excluded")
                            .foregroundColor(.secondary)
                            .font(.caption)
                            .padding(.vertical, 8)
                    } else {
                        List {
                            ForEach(configManager.config.excludedApps, id: \.self) { appId in
                                Text(appId)
                            }
                            .onDelete(perform: deleteApps)
                        }
                        .frame(height: 120)
                    }

                    HStack {
                        TextField("com.example.app", text: $newAppId)
                            .accessibilityIdentifier("settings.privacy.appIdTextField")
                        Button("Add") {
                            addApp()
                        }
                        .disabled(newAppId.isEmpty)
                        .accessibilityIdentifier("settings.privacy.addAppButton")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            checkPermissions()
            launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
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

    private func addRecommendedApp(_ bundleId: String) {
        var config = configManager.config
        if !config.excludedApps.contains(bundleId) {
            config.excludedApps.append(bundleId)
            configManager.updateConfig(config)
        }
    }

    private func addApp() {
        var config = configManager.config
        if !config.excludedApps.contains(newAppId) {
            config.excludedApps.append(newAppId)
            configManager.updateConfig(config)
            newAppId = ""
        }
    }

    private func deleteApps(at offsets: IndexSet) {
        var config = configManager.config
        config.excludedApps.remove(atOffsets: offsets)
        configManager.updateConfig(config)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ConfigManager.shared)
}
