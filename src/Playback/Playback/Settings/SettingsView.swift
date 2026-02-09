// Copyright (c) 2025 Henrique Falconer. All rights reserved.
// SPDX-License-Identifier: Proprietary

import SwiftUI
import AppKit
import Combine
import CoreGraphics
import UniformTypeIdentifiers

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
                .accessibilityIdentifier("settings.generalTab")

            RecordingSettingsTab()
                .tabItem {
                    Label("Recording", systemImage: "record.circle")
                }
                .tag(1)
                .accessibilityIdentifier("settings.recordingTab")

            ProcessingSettingsTab()
                .tabItem {
                    Label("Processing", systemImage: "gearshape.2")
                }
                .tag(2)
                .accessibilityIdentifier("settings.processingTab")

            StorageSettingsTab()
                .tabItem {
                    Label("Storage", systemImage: "externaldrive")
                }
                .tag(3)
                .accessibilityIdentifier("settings.storageTab")

            PrivacySettingsTab()
                .tabItem {
                    Label("Privacy", systemImage: "hand.raised")
                }
                .tag(4)
                .accessibilityIdentifier("settings.privacyTab")

            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2.fill")
                }
                .tag(5)
                .accessibilityIdentifier("settings.advancedTab")
        }
        .frame(width: 600, height: 500)
    }
}

struct GeneralSettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginError: String?
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false

    var body: some View {
        Form {
            Section("Launch Behavior") {
                Toggle("Launch Playback at login", isOn: $launchAtLoginEnabled)
                    .accessibilityIdentifier("settings.general.launchAtLoginToggle")
                    .onChange(of: launchAtLoginEnabled) { oldValue, newValue in
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

            Section("Required Permissions") {
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
                        Text("Accessibility permission enables global hotkey for timeline viewer.")
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
                            updateGlobalHotkey(newShortcut)
                        }
                    )
                    .accessibilityIdentifier("settings.general.hotkeyRecorder")
                }
            }

            Section("Notifications") {
                Toggle("Processing complete", isOn: binding(\.notifications.processingComplete))
                    .accessibilityIdentifier("settings.general.processingCompleteToggle")
                Toggle("Processing errors", isOn: binding(\.notifications.processingErrors))
                    .help("Recommended")
                    .accessibilityIdentifier("settings.general.processingErrorsToggle")
                Toggle("Disk space warnings", isOn: binding(\.notifications.diskSpaceWarnings))
                    .help("Recommended")
                    .accessibilityIdentifier("settings.general.diskSpaceToggle")
                Toggle("Recording status", isOn: binding(\.notifications.recordingStatus))
                    .accessibilityIdentifier("settings.general.recordingStatusToggle")
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await checkPermissions()
            loadLaunchAtLoginStatus()
        }
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

    private func loadLaunchAtLoginStatus() {
        if let configValue = configManager.config.launchAtLogin {
            launchAtLoginEnabled = configValue

            if LaunchAtLoginManager.shared.isEnabled != configValue {
                try? LaunchAtLoginManager.shared.setEnabled(configValue)
            }
        } else {
            launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLoginManager.shared.setEnabled(enabled)
            launchAtLoginError = nil

            var updatedConfig = configManager.config
            updatedConfig.launchAtLogin = enabled
            configManager.updateConfig(updatedConfig)
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        }
    }

    private func updateGlobalHotkey(_ newShortcut: String) {
        Task {
            await GlobalHotkeyManager.shared.unregister()
        }
    }

    private func parseShortcut(_ shortcut: String) -> (keyCode: Int, modifiers: UInt32)? {
        let components = shortcut.split(separator: "+").map { String($0) }
        guard !components.isEmpty else { return nil }

        let keyString = components.last ?? ""
        let modifierStrings = components.dropLast()

        var modifiers: UInt32 = 0
        for modifier in modifierStrings {
            switch modifier {
            case "Control": modifiers |= UInt32(1 << 12)
            case "Option": modifiers |= UInt32(1 << 11)
            case "Shift": modifiers |= UInt32(1 << 9)
            case "Command": modifiers |= UInt32(1 << 8)
            default: break
            }
        }

        let keyCode: Int
        switch keyString {
        case "Space": keyCode = 49
        case "Return": keyCode = 36
        case "Tab": keyCode = 48
        case "Delete": keyCode = 51
        case "Escape": keyCode = 53
        default:
            if let char = keyString.lowercased().first, char.isLetter {
                let asciiValue = Int(char.asciiValue ?? 0)
                keyCode = asciiValue - 97
            } else {
                return nil
            }
        }

        return (keyCode, modifiers)
    }

    private func checkPermissions() async {
        screenRecordingGranted = checkScreenRecordingPermission()
        accessibilityGranted = checkAccessibilityPermission()
    }

    private func checkScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}

struct RecordingSettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager

    var body: some View {
        Form {
            Section("Recording Interval") {
                HStack {
                    Text("Recording Interval:")
                    Spacer()
                    Text("2 seconds (not configurable)")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("The recording interval is fixed at 2 seconds to balance capture quality with system performance.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }

            Section("Timeline Interaction") {
                Toggle("Pause recording when Timeline window is open", isOn: binding(\.pauseWhenTimelineOpen))
                    .accessibilityIdentifier("settings.recording.pauseWhenTimelineToggle")

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Prevents recording your own timeline browsing activity. When enabled, recording automatically pauses while the Timeline window is open.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }

            Section {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic Pause Behavior")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Recording will automatically pause when the Timeline window is open (if enabled above). The recording service detects the timeline signal file and temporarily stops capturing screenshots until you close the window.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
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

struct ProcessingSettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager

    @State private var lastRunTimestamp: Date?
    @State private var lastRunDuration: TimeInterval?
    @State private var lastRunStatus: ProcessingStatus = .neverRun
    @State private var isProcessing = false

    enum ProcessingStatus {
        case neverRun
        case success
        case failed

        var color: Color {
            switch self {
            case .neverRun: return .gray
            case .success: return .green
            case .failed: return .red
            }
        }

        var text: String {
            switch self {
            case .neverRun: return "Never run"
            case .success: return "Success"
            case .failed: return "Failed"
            }
        }
    }

    var body: some View {
        Form {
            Section("Last Processing Run") {
                HStack {
                    Text("Last run:")
                    Spacer()
                    Text(formatLastRun(lastRunTimestamp))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Duration:")
                    Spacer()
                    Text(formatDuration(lastRunDuration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Status:")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(lastRunStatus.color)
                            .frame(width: 8, height: 8)
                        Text(lastRunStatus.text)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(lastRunStatus.color)
                    }
                }

                Button(action: {
                    Task {
                        await processNow()
                    }
                }) {
                    HStack {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                            Text("Processing...")
                        } else {
                            Text("Process Now")
                        }
                    }
                    .frame(width: 120)
                }
                .disabled(isProcessing)
                .buttonStyle(.borderedProminent)
                .help(isProcessing ? "Processing is already running" : "Manually trigger processing")
                .accessibilityIdentifier("settings.processing.processNowButton")
            }

            Section("Processing Interval") {
                Picker("Process every:", selection: binding(\.processingIntervalMinutes)) {
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("30 minutes").tag(30)
                    Text("60 minutes").tag(60)
                }
                .accessibilityIdentifier("settings.processing.intervalPicker")
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
        .task {
            await loadLastProcessingRun()
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await loadLastProcessingRun()
            }
        }
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

    private func loadLastProcessingRun() async {
        let logPath: String
        if Paths.isDevelopment {
            let projectRoot = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            logPath = projectRoot.appendingPathComponent("dev_logs/processing.log").path
        } else {
            logPath = NSString(string: "~/Library/Logs/Playback/processing.log").expandingTildeInPath
        }

        guard FileManager.default.fileExists(atPath: logPath) else {
            await MainActor.run {
                lastRunStatus = .neverRun
                lastRunTimestamp = nil
                lastRunDuration = nil
            }
            return
        }

        let command = "tail -100 '\(logPath)' 2>/dev/null"
        let output = await runShellCommand(command)

        let (timestamp, duration, status) = parseProcessingLog(output)

        await MainActor.run {
            lastRunTimestamp = timestamp
            lastRunDuration = duration
            lastRunStatus = status
        }
    }

    private func parseProcessingLog(_ logOutput: String) -> (Date?, TimeInterval?, ProcessingStatus) {
        let lines = logOutput.split(separator: "\n").map(String.init)

        var processingStartTime: Date?
        var processingEndTime: Date?
        var processingFailed = false

        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestampStr = json["timestamp"] as? String,
                  let message = json["message"] as? String,
                  let component = json["component"] as? String,
                  component == "processing" else {
                continue
            }

            let timestamp = parseISO8601(timestampStr)

            if message.contains("Processing complete") || message.contains("successfully") {
                if processingEndTime == nil {
                    processingEndTime = timestamp
                }
            }

            if message.contains("Starting processing") || message.contains("Processing day") {
                if processingStartTime == nil {
                    processingStartTime = timestamp
                }
            }

            if let level = json["level"] as? String, level == "ERROR" {
                if message.contains("Processing") || message.contains("Failed") {
                    processingFailed = true
                }
            }

            if processingEndTime != nil && processingStartTime != nil {
                break
            }
        }

        let duration: TimeInterval?
        if let start = processingStartTime, let end = processingEndTime {
            duration = end.timeIntervalSince(start)
        } else {
            duration = nil
        }

        let status: ProcessingStatus
        if processingEndTime == nil && processingStartTime == nil {
            status = .neverRun
        } else if processingFailed {
            status = .failed
        } else if processingEndTime != nil {
            status = .success
        } else {
            status = .neverRun
        }

        return (processingEndTime ?? processingStartTime, duration, status)
    }

    private func parseISO8601(_ isoString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: isoString)
    }

    private func processNow() async {
        await MainActor.run {
            isProcessing = true
        }

        let scriptPath: String
        if Paths.isDevelopment {
            let projectRoot = Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            scriptPath = projectRoot.appendingPathComponent("src/scripts/build_chunks_from_temp.py").path

            let command = "PLAYBACK_DEV_MODE=1 python3 '\(scriptPath)' --auto 2>&1"
            let _ = await runShellCommand(command)
        } else {
            let command = "launchctl kickstart -k gui/\(getuid())/com.playback.processing 2>&1"
            let _ = await runShellCommand(command)
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        await loadLastProcessingRun()

        await MainActor.run {
            isProcessing = false
        }
    }

    private func formatLastRun(_ date: Date?) -> String {
        guard let date = date else {
            return "Never"
        }

        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    private func formatDuration(_ duration: TimeInterval?) -> String {
        guard let duration = duration else {
            return "N/A"
        }

        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        } else if duration < 60 {
            return String(format: "%.1f seconds", duration)
        } else {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }

    private func runShellCommand(_ command: String) async -> String {
        do {
            let result = try await ShellCommand.runAsync("/bin/bash", arguments: ["-c", command])
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }
}

struct StorageSettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager

    @State private var tempBytes: UInt64 = 0
    @State private var chunksBytes: UInt64 = 0
    @State private var databaseBytes: UInt64 = 0
    @State private var totalBytes: UInt64 = 0
    @State private var availableSpace: UInt64 = 0
    @State private var isLoadingUsage = false

    @State private var showCleanupConfirmation = false
    @State private var cleanupPreviewMessage = ""
    @State private var showCleanupResult = false
    @State private var cleanupResultMessage = ""

    var body: some View {
        Form {
            Section("Storage Usage") {
                if isLoadingUsage {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Calculating...")
                            .foregroundColor(.secondary)
                    }
                } else {
                    HStack {
                        Text("Temp Files:")
                        Spacer()
                        Text(formatBytes(tempBytes))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Recordings:")
                        Spacer()
                        Text(formatBytes(chunksBytes))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Database:")
                        Spacer()
                        Text(formatBytes(databaseBytes))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Total:")
                        Spacer()
                        Text(formatBytes(totalBytes))
                            .fontWeight(.semibold)
                    }

                    HStack {
                        Text("Available Space:")
                        Spacer()
                        Text(formatBytes(availableSpace))
                            .foregroundColor(availableSpace < 5_000_000_000 ? .orange : .secondary)
                    }

                    Button("Refresh Usage") {
                        Task {
                            await loadStorageUsage()
                        }
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityIdentifier("settings.storage.refreshButton")
                }
            }

            Section("Retention Policies") {
                Picker("Temp files:", selection: binding(\.tempRetentionPolicy)) {
                    Text("Never delete").tag("never")
                    Text("1 day").tag("1_day")
                    Text("1 week").tag("1_week")
                    Text("1 month").tag("1_month")
                    Text("3 months").tag("3_months")
                    Text("6 months").tag("6_months")
                    Text("1 year").tag("1_year")
                }
                .accessibilityIdentifier("settings.storage.tempRetentionPicker")

                Picker("Recordings:", selection: binding(\.recordingRetentionPolicy)) {
                    Text("Never delete").tag("never")
                    Text("1 day").tag("1_day")
                    Text("1 week").tag("1_week")
                    Text("1 month").tag("1_month")
                    Text("3 months").tag("3_months")
                    Text("6 months").tag("6_months")
                    Text("1 year").tag("1_year")
                }
                .accessibilityIdentifier("settings.storage.recordingRetentionPicker")

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Retention policies are applied automatically during processing. Use manual cleanup to apply immediately.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }

            Section("Manual Cleanup") {
                Button("Clean Up Now") {
                    Task {
                        await previewCleanup()
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.storage.cleanupButton")

                Text("Applies retention policies immediately and removes old files")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadStorageUsage()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await loadStorageUsage()
            }
        }
        .alert("Confirm Cleanup", isPresented: $showCleanupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await performCleanup()
                }
            }
        } message: {
            Text(cleanupPreviewMessage)
        }
        .alert("Cleanup Complete", isPresented: $showCleanupResult) {
            Button("OK") {
                Task {
                    await loadStorageUsage()
                }
            }
        } message: {
            Text(cleanupResultMessage)
        }
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

    private func loadStorageUsage() async {
        await MainActor.run {
            isLoadingUsage = true
        }

        let baseDir = Paths.baseDataDirectory.path
        let tempDir = "\(baseDir)/temp"
        let chunksDir = "\(baseDir)/chunks"
        let dbPath = Paths.databasePath.path

        let tempSize = await calculateDirectorySize(tempDir)
        let chunksSize = await calculateDirectorySize(chunksDir)
        let dbSize = await getFileSize(dbPath)
        let available = await getAvailableSpace(baseDir)

        await MainActor.run {
            tempBytes = tempSize
            chunksBytes = chunksSize
            databaseBytes = dbSize
            totalBytes = tempSize + chunksSize + dbSize
            availableSpace = available
            isLoadingUsage = false
        }
    }

    private func calculateDirectorySize(_ path: String) async -> UInt64 {
        let command = "du -sk '\(path)' 2>/dev/null | awk '{print $1}'"
        let result = await runShellCommand(command)
        if let kilobytes = UInt64(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return kilobytes * 1024
        }
        return 0
    }

    private func getFileSize(_ path: String) async -> UInt64 {
        let command = "stat -f%z '\(path)' 2>/dev/null"
        let result = await runShellCommand(command)
        return UInt64(result.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func getAvailableSpace(_ path: String) async -> UInt64 {
        let command = "df -k '\(path)' | tail -n 1 | awk '{print $4}'"
        let result = await runShellCommand(command)
        if let kilobytes = UInt64(result.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return kilobytes * 1024
        }
        return 0
    }

    private func previewCleanup() async {
        let scriptPath = findProjectRoot().appendingPathComponent("src/scripts/cleanup_old_chunks.py").path
        let command = "python3 '\(scriptPath)' --dry-run 2>&1"
        let result = await runShellCommand(command)

        await MainActor.run {
            if result.contains("Would delete") || result.contains("files to delete") {
                cleanupPreviewMessage = parseCleanupPreview(result)
            } else {
                cleanupPreviewMessage = "No files to clean up based on current retention policies."
            }
            showCleanupConfirmation = true
        }
    }

    private func performCleanup() async {
        let scriptPath = findProjectRoot().appendingPathComponent("src/scripts/cleanup_old_chunks.py").path
        let command = "python3 '\(scriptPath)' 2>&1"
        let result = await runShellCommand(command)

        await MainActor.run {
            if result.contains("Cleanup complete") || result.contains("successfully") {
                cleanupResultMessage = "Cleanup completed successfully.\n\n" + parseCleanupResult(result)
            } else {
                cleanupResultMessage = "Cleanup encountered issues. Check logs for details."
            }
            showCleanupResult = true
        }
    }

    private func parseCleanupPreview(_ output: String) -> String {
        var message = "This will:\n\n"
        let lines = output.components(separatedBy: .newlines)

        var tempCount = 0
        var tempSize: UInt64 = 0
        var chunkCount = 0
        var chunkSize: UInt64 = 0

        for line in lines {
            if line.contains("temp files") {
                if let count = extractNumber(from: line) {
                    tempCount = count
                }
            }
            if line.contains("segment files") || line.contains("recordings") {
                if let count = extractNumber(from: line) {
                    chunkCount = count
                }
            }
        }

        if tempCount > 0 {
            message += "• Delete \(tempCount) temp file(s)\n"
        }
        if chunkCount > 0 {
            message += "• Delete \(chunkCount) recording(s)\n"
        }

        if tempCount == 0 && chunkCount == 0 {
            message += "• No files to delete\n"
        }

        message += "\nProceed with cleanup?"
        return message
    }

    private func parseCleanupResult(_ output: String) -> String {
        let lines = output.components(separatedBy: .newlines)
        var message = ""

        for line in lines {
            if line.contains("Deleted") || line.contains("Cleaned") || line.contains("space freed") {
                message += line + "\n"
            }
        }

        return message.isEmpty ? "Cleanup completed." : message
    }

    private func extractNumber(from text: String) -> Int? {
        let pattern = "\\d+"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let range = Range(match.range, in: text) {
                return Int(text[range])
            }
        }
        return nil
    }

    private func findProjectRoot() -> URL {
        if Paths.isDevelopment {
            return Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        } else {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                fatalError("Application Support directory not available")
            }
            return appSupport.appendingPathComponent("Playback")
        }
    }

    private func runShellCommand(_ command: String) async -> String {
        do {
            let result = try await ShellCommand.runAsync("/bin/bash", arguments: ["-c", command])
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

struct PrivacySettingsTab: View {
    @EnvironmentObject var configManager: ConfigManager

    @State private var newAppId = ""
    @State private var screenRecordingGranted = false
    @State private var accessibilityGranted = false
    @State private var showExportDialog = false
    @State private var exportResult = ""

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
            Section("Permissions") {
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
                        .accessibilityIdentifier("settings.privacy.screenRecordingButton")
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
                        .accessibilityIdentifier("settings.privacy.accessibilityButton")
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Accessibility permission enables global hotkey (Option+Shift+Space) for timeline viewer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
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

            Section("App Exclusion") {
                Picker("Mode:", selection: binding(\.exclusionMode)) {
                    Text("Skip screenshots").tag("skip")
                    Text("Mark as invisible").tag("invisible")
                }
                .accessibilityIdentifier("settings.privacy.exclusionModePicker")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Excluded Apps:")
                        .font(.headline)

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
                        .frame(height: 150)
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

            Section("Data Management") {
                HStack {
                    Text("Data Location:")
                    Spacer()
                    Text(Paths.baseDataDirectory.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Reveal") {
                        revealDataDirectory()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityIdentifier("settings.privacy.revealDataButton")
                }

                Button("Export All Data") {
                    exportAllData()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.privacy.exportDataButton")

                Text("Creates a ZIP archive with all recordings, database, and configuration")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await checkPermissions()
        }
        .onReceive(Timer.publish(every: 10, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await checkPermissions()
            }
        }
        .alert("Export Complete", isPresented: $showExportDialog) {
            Button("OK") { }
        } message: {
            Text(exportResult)
        }
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

    private func checkPermissions() async {
        screenRecordingGranted = checkScreenRecordingPermission()
        accessibilityGranted = checkAccessibilityPermission()
    }

    private func checkScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func checkAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func revealDataDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Paths.baseDataDirectory.path)
    }

    private func exportAllData() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "playback-export-\(formatExportDate(Date())).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await performExport(to: url)
                }
            }
        }
    }

    private func performExport(to destination: URL) async {
        let scriptPath = findProjectRoot().appendingPathComponent("src/scripts/export_data.py").path
        let outputPath = destination.path

        let command = "python3 '\(scriptPath)' '\(outputPath)' 2>&1"
        let result = await runShellCommand(command)

        await MainActor.run {
            if result.contains("Export complete") || result.contains("successfully") {
                exportResult = "Data exported successfully to \(destination.lastPathComponent)"
            } else {
                exportResult = "Export failed. Check logs for details."
            }
            showExportDialog = true
        }
    }

    private func findProjectRoot() -> URL {
        if Paths.isDevelopment {
            return Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        } else {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                fatalError("Application Support directory not available")
            }
            return appSupport.appendingPathComponent("Playback")
        }
    }

    private func runShellCommand(_ command: String) async -> String {
        do {
            let result = try await ShellCommand.runAsync("/bin/bash", arguments: ["-c", command])
            return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    private func formatExportDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func addRecommendedApp(_ bundleId: String) {
        var updatedConfig = configManager.config
        if !updatedConfig.excludedApps.contains(bundleId) {
            updatedConfig.excludedApps.append(bundleId)
            configManager.updateConfig(updatedConfig)
        }
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
    @EnvironmentObject var configManager: ConfigManager

    @State private var macOSVersion = "Loading..."
    @State private var pythonVersion = "Loading..."
    @State private var ffmpegVersion = "Loading..."
    @State private var availableSpace = "Loading..."

    @State private var recordingStatus = LaunchAgentStatus(isLoaded: false, isRunning: false, pid: nil, lastExitStatus: nil)
    @State private var processingStatus = LaunchAgentStatus(isLoaded: false, isRunning: false, pid: nil, lastExitStatus: nil)

    @State private var showResetConfirmation = false
    @State private var showRebuildConfirmation = false
    @State private var showRebuildProgress = false
    @State private var rebuildProgress: Double = 0.0
    @State private var rebuildStatusMessage = ""
    @State private var rebuildError: String? = nil
    @State private var showDiagnosticsResults = false
    @State private var diagnosticsMessage = ""
    @State private var showExportSuccess = false
    @State private var exportedFilePath: URL? = nil
    @State private var showForceRunError = false
    @State private var forceRunError: String? = nil
    @State private var isForceRunning = false

    var body: some View {
        Form {
            Section("Video Encoding Settings") {
                HStack {
                    Text("Codec:")
                    Spacer()
                    Text("H.264 (libx264)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Quality (CRF):")
                    Spacer()
                    Text("\(configManager.config.ffmpegCrf)")
                        .foregroundColor(.secondary)
                }
                .help("Lower values = better quality, larger files (0-51)")

                HStack {
                    Text("Preset:")
                    Spacer()
                    Text("veryfast")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Frame Rate:")
                    Spacer()
                    Text("\(configManager.config.videoFps) fps")
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Video encoding settings are read-only. These values are optimized for screen recording and cannot be changed through the UI.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }

            Section("System Information") {
                HStack {
                    Text("macOS Version:")
                    Spacer()
                    Text(macOSVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Python Version:")
                    Spacer()
                    Text(pythonVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("FFmpeg Version:")
                    Spacer()
                    Text(ffmpegVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Available Disk Space:")
                    Spacer()
                    Text(availableSpace)
                        .foregroundColor(.secondary)
                }
            }

            Section("Service Status") {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(recordingStatus))
                            .frame(width: 8, height: 8)
                        Text("Recording Service:")
                    }
                    Spacer()
                    Text(statusText(recordingStatus))
                        .foregroundColor(.secondary)
                    if !recordingStatus.isRunning && recordingStatus.isLoaded {
                        Button("Restart") {
                            restartService(.recording)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.advanced.restartRecordingButton")
                    }
                }

                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor(processingStatus))
                            .frame(width: 8, height: 8)
                        Text("Processing Service:")
                    }
                    Spacer()
                    Text(statusText(processingStatus))
                        .foregroundColor(.secondary)
                    if !processingStatus.isRunning && processingStatus.isLoaded {
                        Button("Restart") {
                            restartService(.processing)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityIdentifier("settings.advanced.restartProcessingButton")
                    }
                }
            }

            Section("Maintenance") {
                Button("Reset All Settings") {
                    showResetConfirmation = true
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.advanced.resetButton")

                Button("Rebuild Database") {
                    showRebuildConfirmation = true
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.advanced.rebuildDatabaseButton")

                Button("Export Logs") {
                    exportLogs()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.advanced.exportLogsButton")

                Button("Run Diagnostics Check") {
                    runDiagnostics()
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.advanced.diagnosticsButton")

                Button(action: {
                    Task {
                        await forceRunServices()
                    }
                }) {
                    HStack {
                        if isForceRunning {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                            Text("Running Services...")
                        } else {
                            Text("Force Run Services")
                        }
                    }
                }
                .disabled(isForceRunning)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("settings.advanced.forceRunServicesButton")
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            await loadSystemInformation()
            loadServiceStatus()
        }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            Task {
                await loadSystemInformation()
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            loadServiceStatus()
        }
        .alert("Reset All Settings?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetAllSettings()
            }
        } message: {
            Text("This will reset all settings to their default values. This action cannot be undone.")
        }
        .alert("Rebuild Database?", isPresented: $showRebuildConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Rebuild") {
                Task {
                    await performDatabaseRebuild()
                }
            }
        } message: {
            Text("This will scan all video chunks and rebuild the database. This may take several minutes depending on your recording history.")
        }
        .sheet(isPresented: $showRebuildProgress) {
            VStack(spacing: 20) {
                Text("Rebuilding Database")
                    .font(.headline)

                if let error = rebuildError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.red)
                        Text("Rebuild Failed")
                            .font(.title2)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Close") {
                            showRebuildProgress = false
                            rebuildError = nil
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if rebuildProgress >= 1.0 {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.green)
                        Text("Rebuild Complete")
                            .font(.title2)
                        Text(rebuildStatusMessage)
                            .foregroundColor(.secondary)
                        Button("Close") {
                            showRebuildProgress = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    ProgressView(value: rebuildProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                    Text(rebuildStatusMessage)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 400, height: 250)
            .padding()
        }
        .alert("Diagnostics Results", isPresented: $showDiagnosticsResults) {
            Button("OK") { }
        } message: {
            Text(diagnosticsMessage)
        }
        .alert("Logs Exported", isPresented: $showExportSuccess) {
            Button("Show in Finder") {
                if let url = exportedFilePath {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("OK") { }
        } message: {
            if let url = exportedFilePath {
                Text("Logs exported successfully to \(url.lastPathComponent)")
            } else {
                Text("Logs exported successfully")
            }
        }
    }

    private func loadSystemInformation() async {
        macOSVersion = await runShellCommand("sw_vers -productVersion")
        pythonVersion = await runShellCommand("python3 --version")

        let ffmpegPaths = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        var ffmpegFound = false
        for path in ffmpegPaths {
            let version = await runShellCommand("\(path) -version | head -n 1")
            if !version.isEmpty && !version.hasPrefix("Error") {
                ffmpegVersion = version
                ffmpegFound = true
                break
            }
        }
        if !ffmpegFound {
            ffmpegVersion = "Not found"
        }

        let dataDir = Paths.baseDataDirectory.path
        let spaceOutput = await runShellCommand("df -h '\(dataDir)' | tail -n 1 | awk '{print $4}'")
        availableSpace = spaceOutput.isEmpty ? "Unknown" : spaceOutput
    }

    private func loadServiceStatus() {
        recordingStatus = LaunchAgentManager.shared.getAgentStatus(.recording)
        processingStatus = LaunchAgentManager.shared.getAgentStatus(.processing)
    }

    private func statusColor(_ status: LaunchAgentStatus) -> Color {
        if !status.isLoaded {
            return .red
        }
        return status.isRunning ? .green : .yellow
    }

    private func statusText(_ status: LaunchAgentStatus) -> String {
        if !status.isLoaded {
            return "Not Loaded"
        }
        if status.isRunning {
            return "Running (PID: \(status.pid ?? 0))"
        }
        return "Stopped"
    }

    private func restartService(_ type: AgentType) {
        Task {
            do {
                try await LaunchAgentManager.shared.restartAgent(type)
                await MainActor.run {
                    loadServiceStatus()
                }
            } catch {
                print("Failed to restart \(type.rawValue) service: \(error)")
            }
        }
    }

    private func resetAllSettings() {
        configManager.updateConfig(Config.defaultConfig)

        // Restart app after reset to ensure clean state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let appPath = Bundle.main.bundlePath
            let task = Process()
            task.launchPath = "/usr/bin/open"
            task.arguments = [appPath]
            task.launch()
            NSApplication.shared.terminate(nil)
        }
    }

    private func performDatabaseRebuild() async {
        await MainActor.run {
            showRebuildProgress = true
            rebuildProgress = 0.0
            rebuildStatusMessage = "Initializing..."
            rebuildError = nil
        }

        do {
            let result = try await Task.detached {
                try ShellCommand.run(
                    "/usr/bin/python3",
                    arguments: [
                        "-c",
                        """
                        import sys
                        import os
                        from pathlib import Path
                        import sqlite3
                        import json

                        # Add lib directory to path
                        sys.path.insert(0, str(Path('\(Bundle.main.resourcePath ?? "")')/../../..') + '/lib')

                        try:
                            from lib.paths import get_chunks_directory, get_database_path
                            from lib.database import init_database

                            # Get paths
                            chunks_dir = get_chunks_directory()
                            db_path = get_database_path()

                            # Backup existing database
                            if db_path.exists():
                                backup_path = db_path.with_suffix('.backup')
                                import shutil
                                shutil.copy2(db_path, backup_path)

                            # Initialize fresh database
                            conn = init_database()
                            cursor = conn.cursor()

                            # Scan all video chunks
                            video_files = list(chunks_dir.glob('**/*.mp4'))
                            total_files = len(video_files)

                            if total_files == 0:
                                print(json.dumps({'success': True, 'count': 0, 'message': 'No video chunks found to process.'}))
                                sys.exit(0)

                            processed = 0
                            for video_file in video_files:
                                # Extract metadata from path: chunks/YYYYMM/DD/id.mp4
                                parts = video_file.parts
                                if len(parts) < 3:
                                    continue

                                date = parts[-3] + parts[-2]  # YYYYMMDD
                                video_id = video_file.stem

                                # Get video info using ffprobe
                                import subprocess
                                try:
                                    result = subprocess.run(
                                        ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
                                         '-show_entries', 'stream=width,height,duration,nb_frames',
                                         '-show_entries', 'format=size',
                                         '-of', 'json', str(video_file)],
                                        capture_output=True, text=True, timeout=5
                                    )

                                    if result.returncode == 0:
                                        data = json.loads(result.stdout)
                                        stream = data.get('streams', [{}])[0]
                                        format_info = data.get('format', {})

                                        width = stream.get('width', 1920)
                                        height = stream.get('height', 1080)
                                        duration = float(stream.get('duration', format_info.get('duration', 5.0)))
                                        frame_count = int(stream.get('nb_frames', 0))
                                        file_size = int(format_info.get('size', video_file.stat().st_size))

                                        # Calculate timestamps (approximate from video ID if parseable)
                                        # Video IDs are typically timestamps or sequential
                                        start_ts = video_file.stat().st_mtime - duration
                                        end_ts = video_file.stat().st_mtime

                                        # Insert into database
                                        cursor.execute('''
                                            INSERT OR REPLACE INTO segments
                                            (id, date, start_ts, end_ts, frame_count, fps, width, height, file_size_bytes, video_path)
                                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                                        ''', (
                                            video_id, date, start_ts, end_ts, frame_count,
                                            5.0 if frame_count > 0 else 5.0,  # Default FPS
                                            width, height, file_size, str(video_file)
                                        ))

                                        processed += 1

                                        # Report progress every 10 files
                                        if processed % 10 == 0:
                                            conn.commit()
                                            progress = processed / total_files
                                            print(json.dumps({
                                                'progress': progress,
                                                'processed': processed,
                                                'total': total_files
                                            }), flush=True)

                                except Exception as e:
                                    # Skip files that can't be processed
                                    pass

                            conn.commit()
                            conn.close()

                            print(json.dumps({
                                'success': True,
                                'count': processed,
                                'message': f'Processed {processed} video chunks.'
                            }))

                        except Exception as e:
                            print(json.dumps({'success': False, 'error': str(e)}))
                            sys.exit(1)
                        """
                    ]
                )
            }.value

            if result.isSuccess {
                let lines = result.output.components(separatedBy: "\n")
                var finalCount = 0

                for line in lines where !line.isEmpty {
                    if let data = line.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                        if let progress = json["progress"] as? Double,
                           let processed = json["processed"] as? Int,
                           let total = json["total"] as? Int {
                            await MainActor.run {
                                rebuildProgress = progress
                                rebuildStatusMessage = "Processing video \(processed) of \(total)..."
                            }
                        } else if let success = json["success"] as? Bool {
                            if success {
                                if let count = json["count"] as? Int {
                                    finalCount = count
                                }
                            } else if let error = json["error"] as? String {
                                throw NSError(domain: "DatabaseRebuild", code: 1,
                                            userInfo: [NSLocalizedDescriptionKey: error])
                            }
                        }
                    }
                }

                await MainActor.run {
                    rebuildProgress = 1.0
                    if finalCount > 0 {
                        rebuildStatusMessage = "Database rebuilt successfully. Processed \(finalCount) video chunks."
                    } else {
                        rebuildStatusMessage = "No video chunks found to process."
                    }
                }
            } else {
                throw NSError(domain: "DatabaseRebuild", code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "Database rebuild failed: \(result.output)"])
            }
        } catch {
            await MainActor.run {
                rebuildError = "Database rebuild failed: \(error.localizedDescription)"
            }
        }
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "playback-logs-\(formatDate(Date())).zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task {
                    await exportLogsToFile(url)
                }
            }
        }
    }

    private func exportLogsToFile(_ destination: URL) async {
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("playback-logs-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let logsDir = Paths.isDevelopment ? URL(fileURLWithPath: "dev_logs") : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Playback")
            let configPath = Paths.configPath()

            if FileManager.default.fileExists(atPath: logsDir.path) {
                let logFiles = try FileManager.default.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil)
                for logFile in logFiles where logFile.pathExtension == "log" {
                    let destFile = tempDir.appendingPathComponent(logFile.lastPathComponent)
                    try FileManager.default.copyItem(at: logFile, to: destFile)
                }
            }

            if FileManager.default.fileExists(atPath: configPath.path) {
                let destConfig = tempDir.appendingPathComponent("config.json")
                try FileManager.default.copyItem(at: configPath, to: destConfig)
            }

            var systemInfo = """
            Playback System Information
            Generated: \(ISO8601DateFormatter().string(from: Date()))

            System:
            """

            systemInfo += "\n  macOS Version: \(await runShellCommand("sw_vers -productVersion"))"
            systemInfo += "\n  Build: \(await runShellCommand("sw_vers -buildVersion"))"
            systemInfo += "\n  Architecture: \(await runShellCommand("uname -m"))"

            systemInfo += "\n\nDependencies:"
            systemInfo += "\n  Python: \(await runShellCommand("python3 --version 2>&1"))"
            systemInfo += "\n  FFmpeg: \(await runShellCommand("ffmpeg -version 2>&1 | head -n 1"))"

            systemInfo += "\n\nPaths:"
            systemInfo += "\n  Data Directory: \(Paths.baseDataDirectory.path)"
            systemInfo += "\n  Config Path: \(configPath.path)"
            systemInfo += "\n  Database Path: \(Paths.databasePath.path)"
            systemInfo += "\n  Logs Directory: \(logsDir.path)"

            systemInfo += "\n\nServices:"
            systemInfo += "\n  Recording: \(statusText(recordingStatus))"
            systemInfo += "\n  Processing: \(statusText(processingStatus))"

            let dbSize = try? FileManager.default.attributesOfItem(atPath: Paths.databasePath.path)[.size] as? Int64
            if let size = dbSize {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useMB, .useGB]
                formatter.countStyle = .file
                systemInfo += "\n\nDatabase Size: \(formatter.string(fromByteCount: size))"
            }

            try systemInfo.write(to: tempDir.appendingPathComponent("system-info.txt"), atomically: true, encoding: .utf8)

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }

            let result = try await Task.detached {
                try await MainActor.run {
                    try ShellCommand.run("/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", tempDir.path, destination.path])
                }
            }.value

            try FileManager.default.removeItem(at: tempDir)

            if result.isSuccess {
                await MainActor.run {
                    exportedFilePath = destination
                    showExportSuccess = true
                }
            } else {
                throw NSError(domain: "ExportLogs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create zip archive"])
            }
        } catch {
            await MainActor.run {
                diagnosticsMessage = "Export failed: \(error.localizedDescription)"
                showDiagnosticsResults = true
            }
        }
    }

    private func runDiagnostics() {
        Task {
            var diagnostics: [String] = []

            diagnostics.append("macOS: \(await runShellCommand("sw_vers -productVersion"))")
            diagnostics.append("Python: \(await runShellCommand("python3 --version"))")
            diagnostics.append("FFmpeg: \(await runShellCommand("ffmpeg -version | head -n 1"))")

            let dbPath = Paths.databasePath.path
            let dbExists = FileManager.default.fileExists(atPath: dbPath)
            diagnostics.append("Database: \(dbExists ? "Found" : "Missing")")

            let configPath = Paths.configPath().path
            let configExists = FileManager.default.fileExists(atPath: configPath)
            diagnostics.append("Config: \(configExists ? "Found" : "Missing")")

            diagnostics.append("Recording: \(statusText(recordingStatus))")
            diagnostics.append("Processing: \(statusText(processingStatus))")

            await MainActor.run {
                diagnosticsMessage = diagnostics.joined(separator: "\n")
                showDiagnosticsResults = true
            }
        }
    }

    private func forceRunServices() async {
        await MainActor.run {
            isForceRunning = true
            forceRunError = nil
        }

        var diagnostics: [String] = []
        var errors: [String] = []

        // STEP 1: Enable recording in config
        diagnostics.append("=== STEP 1: Enable Recording ===")
        do {
            var updatedConfig = configManager.config
            if !updatedConfig.recordingEnabled {
                updatedConfig.recordingEnabled = true
                configManager.updateConfig(updatedConfig)
                diagnostics.append("✓ Recording enabled in config")
                // Give config a moment to save
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            } else {
                diagnostics.append("✓ Recording already enabled")
            }
        } catch {
            errors.append("Failed to enable recording: \(error.localizedDescription)")
        }

        // STEP 2: Check permissions
        diagnostics.append("\n=== STEP 2: Check Permissions ===")
        let screenRecordingGranted = CGPreflightScreenCaptureAccess()
        diagnostics.append(screenRecordingGranted ? "✓ Screen Recording: Granted" : "✗ Screen Recording: DENIED - Go to System Settings → Privacy & Security → Screen Recording")

        // STEP 3: Check script paths
        diagnostics.append("\n=== STEP 3: Verify Script Paths ===")

        var possibleScriptLocations: [URL] = []

        if Paths.isDevelopment {
            // DEVELOPMENT MODE: SRCROOT is REQUIRED
            guard let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] else {
                diagnostics.append("✗ SRCROOT environment variable NOT SET")
                diagnostics.append("")
                diagnostics.append("REQUIRED: Set SRCROOT in Xcode scheme:")
                diagnostics.append("  1. Edit Scheme → Run → Arguments")
                diagnostics.append("  2. Add Environment Variable:")
                diagnostics.append("     Name: SRCROOT")
                diagnostics.append("     Value: /Users/YOUR_USERNAME/Playback")
                diagnostics.append("           (or ~/Playback works too)")
                errors.append("SRCROOT environment variable not set - cannot locate scripts in development mode")

                // Skip remaining steps
                await MainActor.run {
                    isForceRunning = false
                    loadServiceStatus()
                }

                let finalRecordingStatus = LaunchAgentManager.shared.getAgentStatus(.recording)
                let finalProcessingStatus = LaunchAgentManager.shared.getAgentStatus(.processing)

                diagnostics.append("\n=== STEP 6: Final Service Status ===")
                diagnostics.append("Recording: Not Loaded")
                diagnostics.append("Processing: Not Loaded")

                diagnostics.append("\n=== STEP 7: Environment Info ===")
                diagnostics.append("Development Mode: true")
                diagnostics.append("SRCROOT: NOT SET ✗")
                diagnostics.append("Bundle Path: \(Bundle.main.bundleURL.path)")
                diagnostics.append("Python: \(pythonVersion)")
                diagnostics.append("FFmpeg: \(ffmpegVersion)")

                await showResults(errors: errors, diagnostics: diagnostics, finalRecordingStatus: finalRecordingStatus, finalProcessingStatus: finalProcessingStatus)
                return
            }

            // Expand tilde in path if present
            let expandedPath = NSString(string: srcRoot).expandingTildeInPath
            diagnostics.append("SRCROOT: \(expandedPath)")
            possibleScriptLocations.append(URL(fileURLWithPath: expandedPath).appendingPathComponent("src/scripts"))

        } else {
            // PRODUCTION MODE: Check bundle resources
            diagnostics.append("Production mode - checking bundle resources")
            if let resourceURL = Bundle.main.resourceURL {
                possibleScriptLocations.append(resourceURL.appendingPathComponent("scripts"))
            }
            // Also check Application Support
            possibleScriptLocations.append(findProjectRoot().appendingPathComponent("src/scripts"))
        }

        var recordScriptPath: String?
        var processScriptPath: String?

        for location in possibleScriptLocations {
            let recordPath = location.appendingPathComponent("record_screen.py").path
            let processPath = location.appendingPathComponent("build_chunks_from_temp.py").path

            if FileManager.default.fileExists(atPath: recordPath) && recordScriptPath == nil {
                recordScriptPath = recordPath
            }
            if FileManager.default.fileExists(atPath: processPath) && processScriptPath == nil {
                processScriptPath = processPath
            }

            if recordScriptPath != nil && processScriptPath != nil {
                break
            }
        }

        if let recordPath = recordScriptPath {
            diagnostics.append("✓ Recording script found: \(recordPath)")
        } else {
            diagnostics.append("✗ Recording script MISSING - searched:")
            for loc in possibleScriptLocations {
                diagnostics.append("  - \(loc.appendingPathComponent("record_screen.py").path)")
            }
            errors.append("Recording script not found in any expected location")
        }

        if let processPath = processScriptPath {
            diagnostics.append("✓ Processing script found: \(processPath)")
        } else {
            diagnostics.append("✗ Processing script MISSING - searched:")
            for loc in possibleScriptLocations {
                diagnostics.append("  - \(loc.appendingPathComponent("build_chunks_from_temp.py").path)")
            }
            errors.append("Processing script not found in any expected location")
        }

        // Store paths for later use
        let finalRecordScriptPath = recordScriptPath
        let finalProcessScriptPath = processScriptPath

        // STEP 4: Check/Install LaunchAgents
        diagnostics.append("\n=== STEP 4: Install/Load LaunchAgents ===")

        // Skip if scripts not found
        guard recordScriptPath != nil && processScriptPath != nil else {
            diagnostics.append("✗ Skipping LaunchAgent installation - scripts not found")
            diagnostics.append("RESOLUTION: Ensure you're running from the correct location or scripts are bundled")
            // Jump to final steps
            await MainActor.run {
                isForceRunning = false
                loadServiceStatus()
            }

            let finalRecordingStatus = LaunchAgentManager.shared.getAgentStatus(.recording)
            let finalProcessingStatus = LaunchAgentManager.shared.getAgentStatus(.processing)

            diagnostics.append("\n=== STEP 6: Final Service Status ===")
            diagnostics.append("Recording: \(statusText(finalRecordingStatus)) - Loaded: \(finalRecordingStatus.isLoaded), Running: \(finalRecordingStatus.isRunning), PID: \(finalRecordingStatus.pid?.description ?? "none")")
            diagnostics.append("Processing: \(statusText(finalProcessingStatus)) - Loaded: \(finalProcessingStatus.isLoaded), Running: \(finalProcessingStatus.isRunning), PID: \(finalProcessingStatus.pid?.description ?? "none")")

            diagnostics.append("\n=== STEP 7: Environment Info ===")
            diagnostics.append("Development Mode: \(Paths.isDevelopment)")
            diagnostics.append("Bundle Path: \(Bundle.main.bundleURL.path)")
            diagnostics.append("Config Path: \(Paths.configPath().path)")
            diagnostics.append("Data Directory: \(Paths.baseDataDirectory.path)")
            diagnostics.append("Python: \(pythonVersion)")
            diagnostics.append("FFmpeg: \(ffmpegVersion)")

            await showResults(errors: errors, diagnostics: diagnostics, finalRecordingStatus: finalRecordingStatus, finalProcessingStatus: finalProcessingStatus)
            return
        }

        // Recording agent
        do {
            let recordingStatus = LaunchAgentManager.shared.getAgentStatus(.recording)
            if !recordingStatus.isLoaded {
                diagnostics.append("Installing recording agent...")
                try await LaunchAgentManager.shared.installAgent(.recording)
                diagnostics.append("✓ Recording agent installed")
            } else {
                diagnostics.append("✓ Recording agent already installed")
            }
        } catch {
            let errorMsg = "Failed to install recording agent: \(error.localizedDescription)"
            diagnostics.append("✗ \(errorMsg)")
            errors.append(errorMsg)
        }

        // Processing agent
        do {
            let processingStatus = LaunchAgentManager.shared.getAgentStatus(.processing)
            if !processingStatus.isLoaded {
                diagnostics.append("Installing processing agent...")
                try await LaunchAgentManager.shared.installAgent(.processing)
                diagnostics.append("✓ Processing agent installed")
            } else {
                diagnostics.append("✓ Processing agent already installed")
            }
        } catch {
            let errorMsg = "Failed to install processing agent: \(error.localizedDescription)"
            diagnostics.append("✗ \(errorMsg)")
            errors.append(errorMsg)
        }

        // STEP 5: Start LaunchAgent services
        diagnostics.append("\n=== STEP 5: Start LaunchAgent Services ===")

        // Start recording service
        do {
            try await LaunchAgentManager.shared.startAgent(.recording)
            diagnostics.append("✓ Recording service started")

            // Wait a moment and check status
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            let status = LaunchAgentManager.shared.getAgentStatus(.recording)
            if status.isRunning {
                diagnostics.append("✓ Recording service confirmed running (PID: \(status.pid ?? -1))")
            } else {
                let errorMsg = "Recording service failed to start (exit status: \(status.lastExitStatus ?? -1))"
                diagnostics.append("✗ \(errorMsg)")
                errors.append(errorMsg)

                // Try to get error from logs
                if let logError = await getRecentLogErrors(service: "recording") {
                    diagnostics.append("Recent log error: \(logError)")
                }
            }
        } catch {
            let errorMsg = "Failed to start recording service: \(error.localizedDescription)"
            diagnostics.append("✗ \(errorMsg)")
            errors.append(errorMsg)
        }

        // Start processing service
        do {
            try await LaunchAgentManager.shared.startAgent(.processing)
            diagnostics.append("✓ Processing service started")

            // Wait a moment and check status
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            let status = LaunchAgentManager.shared.getAgentStatus(.processing)
            if status.isRunning {
                diagnostics.append("✓ Processing service confirmed running (PID: \(status.pid ?? -1))")
            } else {
                let errorMsg = "Processing service failed to start (exit status: \(status.lastExitStatus ?? -1))"
                diagnostics.append("✗ \(errorMsg)")
                errors.append(errorMsg)

                // Try to get error from logs
                if let logError = await getRecentLogErrors(service: "processing") {
                    diagnostics.append("Recent log error: \(logError)")
                }
            }
        } catch {
            let errorMsg = "Failed to start processing service: \(error.localizedDescription)"
            diagnostics.append("✗ \(errorMsg)")
            errors.append(errorMsg)
        }

        // STEP 6: Verify final status
        diagnostics.append("\n=== STEP 6: Final Service Status ===")
        await MainActor.run {
            loadServiceStatus()
        }

        // Wait a moment for status to update
        try? await Task.sleep(nanoseconds: 500_000_000)

        let finalRecordingStatus = LaunchAgentManager.shared.getAgentStatus(.recording)
        let finalProcessingStatus = LaunchAgentManager.shared.getAgentStatus(.processing)

        diagnostics.append("Recording: \(statusText(finalRecordingStatus)) - Loaded: \(finalRecordingStatus.isLoaded), Running: \(finalRecordingStatus.isRunning), PID: \(finalRecordingStatus.pid?.description ?? "none")")
        diagnostics.append("Processing: \(statusText(finalProcessingStatus)) - Loaded: \(finalProcessingStatus.isLoaded), Running: \(finalProcessingStatus.isRunning), PID: \(finalProcessingStatus.pid?.description ?? "none")")

        // STEP 7: Environment info
        diagnostics.append("\n=== STEP 7: Environment Info ===")
        diagnostics.append("Development Mode: \(Paths.isDevelopment)")
        diagnostics.append("Config Path: \(Paths.configPath().path)")
        diagnostics.append("Data Directory: \(Paths.baseDataDirectory.path)")
        diagnostics.append("Python: \(pythonVersion)")
        diagnostics.append("FFmpeg: \(ffmpegVersion)")

        await showResults(errors: errors, diagnostics: diagnostics, finalRecordingStatus: finalRecordingStatus, finalProcessingStatus: finalProcessingStatus)
    }

    private func showResults(errors: [String], diagnostics: [String], finalRecordingStatus: LaunchAgentStatus, finalProcessingStatus: LaunchAgentStatus) async {
        await MainActor.run {
            isForceRunning = false
            loadServiceStatus()

            // Store full diagnostic report for export
            var fullReport = ""
            if !errors.isEmpty {
                fullReport = "ERRORS OCCURRED:\n\n"
                fullReport += errors.joined(separator: "\n\n")
                fullReport += "\n\n" + String(repeating: "=", count: 50)
                fullReport += "\n\nFULL DIAGNOSTIC LOG:\n\n"
            }
            fullReport += diagnostics.joined(separator: "\n")
            forceRunError = fullReport

            if !errors.isEmpty {
                // Show concise error summary in alert
                let summary = "Failed to start services. Key issues:\n\n" + errors.prefix(3).joined(separator: "\n\n")
                    + (errors.count > 3 ? "\n\n...and \(errors.count - 3) more issues" : "")
                    + "\n\nClick 'Export Report' to save full diagnostics."

                let alert = NSAlert()
                alert.messageText = "Service Start Failed"
                alert.informativeText = summary
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Export Report")
                alert.addButton(withTitle: "OK")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    exportForceRunError()
                }
            } else {
                // Show success message
                let alert = NSAlert()
                alert.messageText = "Services Started Successfully"
                alert.informativeText = "Recording and processing services are now running.\n\nRecording: PID \(finalRecordingStatus.pid ?? -1)\nProcessing: PID \(finalProcessingStatus.pid ?? -1)\n\nClick 'Export Report' to save full diagnostics."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Export Report")
                alert.addButton(withTitle: "OK")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    exportForceRunError()
                }
            }
        }
    }

    private func getRecentLogErrors(service: String) async -> String? {
        let logPath: String
        if Paths.isDevelopment {
            let projectRoot = findProjectRoot()
            logPath = projectRoot.appendingPathComponent("dev_logs/\(service).log").path
        } else {
            logPath = NSString(string: "~/Library/Logs/Playback/\(service).log").expandingTildeInPath
        }

        guard FileManager.default.fileExists(atPath: logPath) else {
            return "Log file not found: \(logPath)"
        }

        let command = "tail -20 '\(logPath)' | grep -i 'error\\|exception\\|failed\\|traceback' | tail -5"
        let output = await runShellCommand(command)
        return output.isEmpty ? nil : output
    }

    private func findProjectRoot() -> URL {
        if Paths.isDevelopment {
            return Bundle.main.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
        } else {
            guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                fatalError("Application Support directory not available")
            }
            return appSupport.appendingPathComponent("Playback")
        }
    }

    private func exportForceRunError() {
        guard let report = forceRunError else { return }

        let panel = NSSavePanel()
        let timestamp = formatDate(Date())
        let isError = report.contains("ERRORS OCCURRED")
        let filename = isError ? "playback-service-error-\(timestamp).txt" : "playback-service-diagnostics-\(timestamp).txt"
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    // Create detailed report with system info
                    var fullReport = "Playback Service \(isError ? "Error" : "Diagnostic") Report\n"
                    fullReport += String(repeating: "=", count: 60)
                    fullReport += "\n\nGenerated: \(Date())\n"
                    fullReport += "macOS Version: \(self.macOSVersion)\n"
                    fullReport += "Python Version: \(self.pythonVersion)\n"
                    fullReport += "FFmpeg Version: \(self.ffmpegVersion)\n"
                    fullReport += "Available Space: \(self.availableSpace)\n"
                    fullReport += "\n" + String(repeating: "=", count: 60)
                    fullReport += "\n\n"
                    fullReport += report

                    try fullReport.write(to: url, atomically: true, encoding: .utf8)

                    // Show success notification
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } catch {
                    // Show error alert
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = "Could not save report: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    private func runShellCommand(_ command: String) async -> String {
        do {
            let result = try await ShellCommand.runAsync("/bin/bash", arguments: ["-c", command])
            let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? "Not found" : output
        } catch {
            return "Error"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

#Preview {
    SettingsView()
        .environmentObject(ConfigManager.shared)
}
